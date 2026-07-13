from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream, fpga_register, simulation_time
from os.path import dirname, realpath, join

import pyarrow.parquet as pq

from page_header_parser_test import (
    _make_data_page_header,
    _make_dict_page_header,
    _extract_parquet_column_chunks,
)

from libstf_utils.common import stream_type_to_libstf_type_t


_GERMAN_STR_T = 5  # libstf type_t enum value
_INLINE_LEN = 12


@dataclass
class _ColumnChunk:
    compression: bool
    num_values: int
    chunk_bytes: bytearray   # full column-chunk: thrift headers + payloads concatenated
    stream_type: "fpga_stream.StreamType" = fpga_stream.StreamType.SIGNED_INT_64
    type_t_override: int = None  # e.g. _GERMAN_STR_T for string chunks
    heap_base_addr: int = 0

    def _registers(self) -> list:
        if self.type_t_override is not None:
            type_t = self.type_t_override
        else:
            type_t = stream_type_to_libstf_type_t(self.stream_type)
        # Two config registers per decoder: register 2*d takes the 48-bit heap
        # base address, register 2*d+1 the conf word whose write enqueues the
        # config. The conf word packs (MSB -> LSB) as:
        #   compression_t [1 bit] | num_values [32 bits] | type_t [3 bits]
        assert self.heap_base_addr < (1 << 48)
        compression = 1 if self.compression else 0
        packed = (compression << 35) | ((self.num_values & 0xFFFFFFFF) << 3) | (type_t & 0x7)
        return [bytearray(self.heap_base_addr.to_bytes(8, 'little')),
                bytearray(packed.to_bytes(8, 'little'))]


def read_bytes(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        return bytearray(f.read())


# -- Parquet-backed cases ----------------------------------------------------
#
# For the parquet-backed workloads we lift the full thrift-wrapped column chunk
# (headers + SNAPPY-compressed payloads) directly from the parquet file. The
# pre-stripped *_chunk_compressed.bin / *_dict_compressed.bin fixtures are no
# longer needed.
def _parquet_chunk(parquet_filename: str, col_idx: int = 0) -> _ColumnChunk:
    path = join(dirname(realpath(__file__)), 'data', parquet_filename)
    pf = pq.ParquetFile(path)
    col_meta = pf.metadata.row_group(0).column(col_idx)
    cases = _extract_parquet_column_chunks(path)
    case = cases[col_idx]

    return _ColumnChunk(
        compression=True,  # all generated parquet fixtures use SNAPPY
        num_values=col_meta.num_values,
        chunk_bytes=case.chunk_bytes,
    )


# -- Synthetic PLAIN-only chunk ---------------------------------------------

def _make_def_levels(num_values: int) -> bytes:
    # RLE/bit-packing hybrid, bit_width=1, all values = 1 (all present)
    # RLE run header: (num_values << 1) | 0 encoded as varint, then value byte 0x01
    header = num_values << 1
    varint = []
    v = header
    while True:
        b = v & 0x7f
        v >>= 7
        if v:
            varint.append(b | 0x80)
        else:
            varint.append(b)
            break
    rle_body = bytes(varint) + bytes([0x01])
    return len(rle_body).to_bytes(4, 'little') + rle_body


def make_plain_data(items: list[int]) -> _ColumnChunk:
    stream = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, items)
    values = stream.data_to_bytearray()
    def_levels = _make_def_levels(len(items))
    payload = bytearray(def_levels) + bytearray(values)
    hdr = _make_data_page_header(
        num_values=len(items),
        uncompressed_size=len(payload),
        compressed_size=len(payload),
        encoding=0,  # PLAIN
    )
    chunk = bytearray(hdr) + payload
    return _ColumnChunk(
        compression=False,
        num_values=len(items),
        chunk_bytes=chunk,
    )


# -- Synthetic "tricky" chunk: dict + repeated decompressed-hybrid pages [+ plain]
#
# The dictionary body holds the actual values at the column's width, so it is
# synthesised at the column's width. The HYBRID body, by contrast, encodes
# dictionary *indices* and is therefore width-independent — we reuse the on-disk
# fixture for both 32- and 64-bit chunks. `dict_values` must match the values the
# fixture's indices point at (the `*_dict_decompressed.bin` fixtures store
# range(10, 20), i.e. 10 distinct values).
def make_tricky(
    filename: str,
    num_values: int,
    items: list[int],
    factor: int,
    stream_type: "fpga_stream.StreamType" = fpga_stream.StreamType.SIGNED_INT_64,
    dict_values: list[int] = list(range(10, 20)),
    trailing_plain: bool = True,
) -> _ColumnChunk:
    hybrid_body = read_bytes(filename + '_chunk_decompressed.bin')

    chunk = bytearray()

    # Dictionary page: encoding=PLAIN, values at the column's width.
    dict_body = bytearray(fpga_stream.Stream(stream_type, dict_values).data_to_bytearray())
    chunk += _make_dict_page_header(
        num_values=len(dict_values),
        uncompressed_size=len(dict_body),
        compressed_size=len(dict_body),
    )
    chunk += dict_body

    # `factor` HYBRID pages. Each body already carries its 4-byte def_levels
    # length prefix + def_levels + RLE/BPE-encoded payload — PageHeaderParser's
    # SKIP_DEF_LEVELS state will strip the def_levels prefix at runtime.
    for _ in range(factor):
        chunk += _make_data_page_header(
            num_values=num_values,
            uncompressed_size=len(hybrid_body),
            compressed_size=len(hybrid_body),
            encoding=8,  # RLE_DICTIONARY
        )
        chunk += hybrid_body

    total_num_values = num_values * factor

    # Optional trailing PLAIN page. Its presence is what forces the dictionary
    # path to be reset via the injected dummy beat (see ColumnChunkDecoder).
    if trailing_plain:
        plain_values = fpga_stream.Stream(stream_type, items).data_to_bytearray()
        plain_def_levels = _make_def_levels(len(items))
        plain_body = bytearray(plain_def_levels) + bytearray(plain_values)
        chunk += _make_data_page_header(
            num_values=len(items),
            uncompressed_size=len(plain_body),
            compressed_size=len(plain_body),
            encoding=0,  # PLAIN
        )
        chunk += plain_body
        total_num_values += len(items)

    return _ColumnChunk(
        compression=False,
        num_values=total_num_values,
        chunk_bytes=chunk,
        stream_type=stream_type,
    )


# -- Synthetic string chunks --------------------------------------------------

def _plain_string_body(strings: list[bytes]) -> bytearray:
    """Parquet PLAIN BYTE_ARRAY encoding: 4-byte LE length prefix + bytes."""
    body = bytearray()
    for s in strings:
        body += len(s).to_bytes(4, 'little') + s
    return body


def _german_views(strings: list[bytes], base_addr: int, cum: int = 0) -> tuple[bytearray, int]:
    """german_str_t records as the hardware emits them (LSB-first: length,
    prefix, inline-or-address). The heap holds each page's raw PLAIN bytes
    verbatim — 4-byte length prefixes included — so `cum` (the running heap
    offset, carried across pages) advances by 4 + len per string and a long
    string's address points just past its prefix."""
    out = bytearray()
    for s in strings:
        n = len(s)
        rec = bytearray(16)
        rec[0:4] = n.to_bytes(4, 'little')
        rec[4:8] = s[:4].ljust(4, b'\x00')
        if n <= _INLINE_LEN:
            rec[8:16] = s[4:12].ljust(8, b'\x00')
        else:
            rec[8:16] = (base_addr + cum + 4).to_bytes(8, 'little')
        out += rec
        cum += 4 + n
    return out, cum


def make_string_plain_chunk(pages: list[list[bytes]], heap_base: int) -> _ColumnChunk:
    """A string chunk of PLAIN-encoded pages (def levels + length-prefixed strings)."""
    chunk = bytearray()
    total = 0
    for strings in pages:
        body = bytearray(_make_def_levels(len(strings))) + _plain_string_body(strings)
        chunk += _make_data_page_header(
            num_values=len(strings),
            uncompressed_size=len(body),
            compressed_size=len(body),
            encoding=0,  # PLAIN
        )
        chunk += body
        total += len(strings)
    return _ColumnChunk(
        compression=False,
        num_values=total,
        chunk_bytes=chunk,
        type_t_override=_GERMAN_STR_T,
        heap_base_addr=heap_base,
    )


def make_string_dict_chunk(
    dict_strings: list[bytes],
    hybrid_filename: str,
    hybrid_num_values: int,
    factor: int,
    heap_base: int,
    trailing_plain: list[bytes] = None,
) -> _ColumnChunk:
    """A string chunk: PLAIN dictionary page + `factor` HYBRID pages (reusing
    the fixed-width RLE index fixture) + optional trailing PLAIN fallback page."""
    dict_body = _plain_string_body(dict_strings)
    chunk = bytearray()
    chunk += _make_dict_page_header(
        num_values=len(dict_strings),
        uncompressed_size=len(dict_body),
        compressed_size=len(dict_body),
    )
    chunk += dict_body

    hybrid_body = read_bytes(hybrid_filename + '_chunk_decompressed.bin')
    for _ in range(factor):
        chunk += _make_data_page_header(
            num_values=hybrid_num_values,
            uncompressed_size=len(hybrid_body),
            compressed_size=len(hybrid_body),
            encoding=8,  # RLE_DICTIONARY
        )
        chunk += hybrid_body
    total = hybrid_num_values * factor

    if trailing_plain is not None:
        body = bytearray(_make_def_levels(len(trailing_plain))) + _plain_string_body(trailing_plain)
        chunk += _make_data_page_header(
            num_values=len(trailing_plain),
            uncompressed_size=len(body),
            compressed_size=len(body),
            encoding=0,  # PLAIN
        )
        chunk += body
        total += len(trailing_plain)

    return _ColumnChunk(
        compression=False,
        num_values=total,
        chunk_bytes=chunk,
        type_t_override=_GERMAN_STR_T,
        heap_base_addr=heap_base,
    )


# Reference outputs shared across cases.
_RLE_OUTPUT = [i for i in range(10, 20) for _ in range(i)]
_PLAIN_OUTPUT = list(range(0, 256))

# Ten dictionary strings matching the RLE index fixture (values 10..19 map to
# indices 0..9), mixing inline (<=12 B) and heap-addressed (>12 B) strings.
# 218 raw heap bytes total (178 payload + 40 prefix) — deliberately not
# beat-aligned so the carried residue is flushed by the chunk-final heap
# segment.
_DICT_STRINGS = [
    b"alpha",
    b"b" * 20,
    b"gamma!",
    b"d" * 13,
    b"e",
    b"zeta-zeta",
    b"g" * 40,
    b"hi",
    b"abcdefghijkl",
    b"j" * 70,
]


class ColumnChunkDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "vfpga_tops/column_chunk_decoder_test.sv"
    debug_mode = True

    def __init__(self, a) -> None:
        super().__init__(a)

    def setUp(self):
        return super().setUp()

    def run_chunks(self, inputs: list[_ColumnChunk], outputs: list[list[int]]):
        """Drive the decoder with one or more column chunks and assert outputs."""
        # Chunk-level registers only — page-level configuration is now produced
        # inside ColumnChunkDecoder by PageHeaderParser. GlobalConfig occupies
        # regs 0..2; decoder 0's register pair follows: reg 3 = heap base
        # address, reg 4 = conf word (whose write enqueues the config).
        for input in inputs:
            heap_reg, conf_reg = input._registers()
            self.write_register(fpga_register.vFPGARegister(3, heap_reg))
            self.write_register(fpga_register.vFPGARegister(4, conf_reg))

        # One stream input per column chunk (full thrift-wrapped bytes).
        for input in inputs:
            self.set_stream_input(0, input.chunk_bytes)

        # The output value width follows each chunk's declared type_t.
        for input, output in zip(inputs, outputs):
            self.set_expected_output(0, fpga_stream.Stream(input.stream_type, output))

        self.simulate_fpga()
        self.assert_simulation_output()

    def test_one_rle_page(self):
        self.run_chunks([_parquet_chunk('rle_data.parquet')], [_RLE_OUTPUT])

    def test_one_bpe_page(self):
        self.run_chunks([_parquet_chunk('bpe_data.parquet')], [list(range(10, 20)) * 15])

    def test_one_mixed_page(self):
        output = ([i**8 for i in range(10, 20) for _ in range(i)] +
                  list(range(128, 256)) * 2) * 2
        self.run_chunks([_parquet_chunk('mixed_data.parquet')], [output])

    def test_one_big_bpe_page(self):
        self.run_chunks([_parquet_chunk('big_bpe_data.parquet')], [list(range(10, 100)) * 5])

    def test_plain_page(self):
        self.run_chunks([make_plain_data(_PLAIN_OUTPUT)], [_PLAIN_OUTPUT])

    def test_tricky_page(self):
        factor = 3
        tricky = make_tricky('rle_data_rg0_col0', len(_RLE_OUTPUT), _PLAIN_OUTPUT, factor)
        self.run_chunks(
            [tricky, _parquet_chunk('rle_data.parquet')],
            [_RLE_OUTPUT * factor + _PLAIN_OUTPUT, _RLE_OUTPUT],
        )

    def test_many_hybrid_pages(self):
        self.overwrite_simulation_time(simulation_time.SimulationTime.till_finished())
        mixed_output = ([i**8 for i in range(10, 20) for _ in range(i)] +
                        list(range(128, 256)) * 2) * 2
        self.run_chunks(
            [
                _parquet_chunk('rle_data.parquet'),
                _parquet_chunk('bpe_data.parquet'),
                _parquet_chunk('mixed_data.parquet'),
                _parquet_chunk('big_bpe_data.parquet'),
            ],
            [
                _RLE_OUTPUT,
                list(range(10, 20)) * 15,
                mixed_output,
                list(range(10, 100)) * 5,
            ],
        )

    def test_plain_after_hybrid(self):
        chunk = make_tricky('rle_data_rg0_col0', len(_RLE_OUTPUT), _PLAIN_OUTPUT, 1)
        self.run_chunks([chunk], [_RLE_OUTPUT + _PLAIN_OUTPUT])

    # -- String chunks ---------------------------------------------------------

    def run_string_chunks(
        self,
        inputs: list[_ColumnChunk],
        expected_values: list[bytearray],
        expected_heaps: list[bytearray],
    ):
        """Drive string chunks and assert the german-view stream (send[0]) and
        the heap byte stream (send[1])."""
        self.overwrite_simulation_time(simulation_time.SimulationTime.till_finished())
        for input in inputs:
            heap_reg, conf_reg = input._registers()
            self.write_register(fpga_register.vFPGARegister(3, heap_reg))
            self.write_register(fpga_register.vFPGARegister(4, conf_reg))
        for input in inputs:
            self.set_stream_input(0, input.chunk_bytes)
        for views in expected_values:
            self.set_expected_output(0, views)
        for heap in expected_heaps:
            self.set_expected_output(1, heap)

        self.simulate_fpga()
        self.assert_simulation_output()

    def test_string_single_plain_page(self):
        heap_base = 0x40000
        strings = [b"hello", b"x" * 20, b"yo", b"abcdefghijklm", b"s"]
        views, _ = _german_views(strings, heap_base)
        heap = _plain_string_body(strings)
        self.run_string_chunks(
            [make_string_plain_chunk([strings], heap_base)], [views], [heap])

    def test_string_plain_pages(self):
        # Multi-page PLAIN string chunk: each page's german records stream
        # straight to the value output while its heap streams out. Pages end
        # mid-beat so both output normalizers carry overflow across pages, and
        # heap addresses must keep accumulating across pages.
        heap_base = 0x41000
        pages = [
            [b"hello", b"x" * 20, b"yo"],
            [b"abcdefghijklm", b"q" * 70, b"s"],
            [b"tail-string", b"z" * 30],
        ]
        views = bytearray()
        cum = 0
        for p in pages:
            v, cum = _german_views(p, heap_base, cum)
            views += v
        heap = bytearray(b"".join(bytes(_plain_string_body(p)) for p in pages))
        self.run_string_chunks(
            [make_string_plain_chunk(pages, heap_base)], [views], [heap])

    def test_string_dict_hybrid(self):
        # DICT string page + one HYBRID page. The chunk ends on the hybrid
        # page, so the dictionary page's carried heap residue is flushed by
        # the injected final heap segment.
        heap_base = 0x80000
        dict_views, _ = _german_views(_DICT_STRINGS, heap_base)
        views = bytearray()
        for v in _RLE_OUTPUT:
            i = v - 10
            views += dict_views[16 * i:16 * (i + 1)]
        heap = _plain_string_body(_DICT_STRINGS)
        chunk = make_string_dict_chunk(
            _DICT_STRINGS, 'rle_data_rg0_col0', len(_RLE_OUTPUT), 1, heap_base)
        self.run_string_chunks([chunk], [views], [heap])

    def test_string_dict_then_plain(self):
        # Dict->plain fallback: a trailing PLAIN string page overwrites the
        # dictionary scratch after the HYBRID page consumed it, and its heap
        # lands contiguously after the dictionary page's heap.
        heap_base = 0x100000
        dict_views, dict_heap_bytes = _german_views(_DICT_STRINGS, heap_base)
        plain_strings = [b"plain-one", b"w" * 25, b"pp"]

        views = bytearray()
        for v in _RLE_OUTPUT:
            i = v - 10
            views += dict_views[16 * i:16 * (i + 1)]
        plain_views, _ = _german_views(plain_strings, heap_base, dict_heap_bytes)
        views += plain_views

        heap = _plain_string_body(_DICT_STRINGS) + _plain_string_body(plain_strings)
        chunk = make_string_dict_chunk(
            _DICT_STRINGS, 'rle_data_rg0_col0', len(_RLE_OUTPUT), 1, heap_base,
            trailing_plain=plain_strings)
        self.run_string_chunks([chunk], [views], [heap])

    def test_string_two_chunks(self):
        # Back-to-back string chunks: heap_base_addr reloads per chunk and the
        # dictionary scratch is reused from index 0.
        base_a, base_b = 0x200000, 0x300000
        pages_a = [[b"first-chunk-string", b"aa"], [b"m" * 30, b"nn", b"o" * 13]]
        pages_b = [[b"second", b"chunk", b"y" * 44]]

        views_a = bytearray()
        cum = 0
        for p in pages_a:
            v, cum = _german_views(p, base_a, cum)
            views_a += v
        views_b, _ = _german_views(pages_b[0], base_b)

        self.run_string_chunks(
            [make_string_plain_chunk(pages_a, base_a),
             make_string_plain_chunk(pages_b, base_b)],
            [views_a, views_b],
            [bytearray(b"".join(bytes(_plain_string_body(p)) for p in pages_a)),
             _plain_string_body(pages_b[0])],
        )

    def test_string_multi_hybrid_pages(self):
        # Several HYBRID pages read the same stored dictionary: the string
        # read group spans all of them (ids `last` only on the chunk-final
        # page), so the dictionary content must survive from page to page.
        heap_base = 0x180000
        factor = 3
        dict_views, _ = _german_views(_DICT_STRINGS, heap_base)
        page_views = bytearray()
        for v in _RLE_OUTPUT:
            i = v - 10
            page_views += dict_views[16 * i:16 * (i + 1)]
        heap = _plain_string_body(_DICT_STRINGS)
        chunk = make_string_dict_chunk(
            _DICT_STRINGS, 'rle_data_rg0_col0', len(_RLE_OUTPUT), factor, heap_base)
        self.run_string_chunks([chunk], [bytearray(page_views * factor)], [heap])

    def test_string_dict_never_read(self):
        # A chunk whose dictionary page is stored but never referenced (no
        # HYBRID page): the chunk-final PLAIN page injects the dummy ids beat
        # that closes the never-opened read group, so the next chunk's store
        # does not deadlock. The unread dictionary strings still occupy heap,
        # so the PLAIN page's records point past them.
        base_a, base_b = 0x200000, 0x300000
        plain_strings = [b"orphaned-dict", b"v" * 21, b"end"]
        dict_heap = bytes(_plain_string_body(_DICT_STRINGS))
        views_a, _ = _german_views(plain_strings, base_a, len(dict_heap))
        heap_a = bytearray(dict_heap) + _plain_string_body(plain_strings)

        dict_views, _ = _german_views(_DICT_STRINGS, base_b)
        views_b = bytearray()
        for v in _RLE_OUTPUT:
            i = v - 10
            views_b += dict_views[16 * i:16 * (i + 1)]
        heap_b = bytearray(dict_heap)

        chunk_a = make_string_dict_chunk(
            _DICT_STRINGS, 'rle_data_rg0_col0', len(_RLE_OUTPUT), 0, base_a,
            trailing_plain=plain_strings)
        chunk_b = make_string_dict_chunk(
            _DICT_STRINGS, 'rle_data_rg0_col0', len(_RLE_OUTPUT), 1, base_b)
        self.run_string_chunks(
            [chunk_a, chunk_b], [views_a, views_b], [heap_a, heap_b])

    def test_different_types(self):
        # Back-to-back chunks exercising the TypedDictionary reset across a chunk
        # boundary AND a width switch:
        #   Chunk A: 32-bit, dict + HYBRID + trailing PLAIN. The trailing PLAIN
        #            page (with a dict page seen) triggers the injected dummy
        #            reset beat that flushes the internal Dictionary cache.
        #   Chunk B: 64-bit, dict + HYBRID (no PLAIN). It reloads the dictionary
        #            from scratch. If chunk A's reset did not fully clear the
        #            dictionary state, chunk B would either materialise stale
        #            32-bit values or mis-size its 64-bit output, so a correct
        #            chunk B output proves the reset.
        self.overwrite_simulation_time(simulation_time.SimulationTime.till_finished())
        chunk_a = make_tricky(
            'rle_data_rg0_col0', len(_RLE_OUTPUT), _PLAIN_OUTPUT, 1,
            stream_type=fpga_stream.StreamType.SIGNED_INT_32,
        )
        chunk_b = make_tricky(
            'rle_data_rg0_col0', len(_RLE_OUTPUT), [], 1,
            stream_type=fpga_stream.StreamType.SIGNED_INT_64,
            trailing_plain=False,
        )
        self.run_chunks(
            [chunk_a, chunk_b],
            [_RLE_OUTPUT + _PLAIN_OUTPUT, _RLE_OUTPUT],
        )
