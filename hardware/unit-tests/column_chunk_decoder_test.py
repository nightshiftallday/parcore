from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream, fpga_register, simulation_time
from os.path import dirname, realpath, join

import pyarrow.parquet as pq

from page_header_parser_test import (
    _make_data_page_header,
    _make_dict_page_header,
    _extract_parquet_column_chunks,
    _PageType as _PHPageType,
)


@dataclass
class _ColumnChunk:
    compression: bool
    num_values: int
    hybrid_num_values: int
    chunk_bytes: bytearray   # full column-chunk: thrift headers + payloads concatenated

    def _registers(self) -> dict[int, bytearray]:
        return {
            0: bytearray(int(1 if self.compression else 0).to_bytes(1, 'big')), # compression_t
            1: bytearray(self.num_values.to_bytes(4, 'little')),                # num_values
            2: bytearray(self.hybrid_num_values.to_bytes(4, 'little')),         # hybrid_num_values
            3: bytearray(int(2).to_bytes(1, 'big')),                            # type_t = int64_t
        }


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

    # Sum num_values across non-dict pages -> hybrid_num_values when those
    # pages are HYBRID. ColumnChunkDecoder uses hybrid_num_values to size the
    # output normalizer for the dictionary path.
    hybrid_num_values = sum(
        p.num_values for p in case.pages if p.page_type == _PHPageType.HYBRID
    )

    return _ColumnChunk(
        compression=True,  # all generated parquet fixtures use SNAPPY
        num_values=col_meta.num_values,
        hybrid_num_values=hybrid_num_values,
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
        hybrid_num_values=0,
        chunk_bytes=chunk,
    )


# -- Synthetic "tricky" chunk: dict + repeated decompressed-hybrid pages + plain
def make_tricky(filename: str, num_values: int, items: list[int], factor: int) -> _ColumnChunk:
    dict_body  = read_bytes(filename + '_dict_decompressed.bin')
    hybrid_body = read_bytes(filename + '_chunk_decompressed.bin')

    chunk = bytearray()

    # Dictionary page: encoding=PLAIN.
    chunk += _make_dict_page_header(
        num_values=num_values,
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

    # Trailing PLAIN page.
    plain_stream = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, items)
    plain_values = plain_stream.data_to_bytearray()
    plain_def_levels = _make_def_levels(len(items))
    plain_body = bytearray(plain_def_levels) + bytearray(plain_values)
    chunk += _make_data_page_header(
        num_values=len(items),
        uncompressed_size=len(plain_body),
        compressed_size=len(plain_body),
        encoding=0,  # PLAIN
    )
    chunk += plain_body

    total_num_values = num_values * factor + len(items)
    hybrid_num_values = num_values * factor
    return _ColumnChunk(
        compression=False,
        num_values=total_num_values,
        hybrid_num_values=hybrid_num_values,
        chunk_bytes=chunk,
    )


@dataclass
class _TestCase:
    inputs: list[_ColumnChunk]
    outputs: list[list[int]]


_rle_output =  [i for i in range(10, 20) for _ in range(i)]
_rle_input = _parquet_chunk('rle_data.parquet')

_bpe_output = list(range(10, 20)) * 15
_bpe_input = _parquet_chunk('bpe_data.parquet')

_mixed_output = ([i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2 +
                [i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2)
_mixed_input = _parquet_chunk('mixed_data.parquet')

_big_bpe_output = list(range(10, 100)) * 5
_big_bpe_input = _parquet_chunk('big_bpe_data.parquet')

_mixed_output_plain = list(range(0, 256))
_mixed_input_plain = make_plain_data(_mixed_output_plain)

_tricky_factor = 3
_tricky_output_plain = list(range(0, 256))
_tricky_output = _rle_output * _tricky_factor + _tricky_output_plain
_tricky_input = make_tricky('rle_data_rg0_col0', len(_rle_output), _tricky_output_plain, _tricky_factor)

# Minimal "PLAIN page directly after a HYBRID page" case: a single dictionary
# page, a single HYBRID (RLE_DICTIONARY) page, then a trailing PLAIN page. The
# dict page is required scaffolding because the HYBRID page references it.
_hybrid_then_plain_output_plain = list(range(0, 256))
_hybrid_then_plain_output = _rle_output + _hybrid_then_plain_output_plain
_hybrid_then_plain_input = make_tricky(
    'rle_data_rg0_col0', len(_rle_output), _hybrid_then_plain_output_plain, 1
)

_test_cases = (
    _TestCase(inputs=[_rle_input],       outputs=[_rle_output]),
    _TestCase(inputs=[_bpe_input],       outputs=[_bpe_output]),
    _TestCase(inputs=[_mixed_input],     outputs=[_mixed_output]),
    _TestCase(inputs=[_big_bpe_input],   outputs=[_big_bpe_output]),
    _TestCase(
        inputs=[_rle_input, _bpe_input, _mixed_input, _big_bpe_input],
        outputs=[_rle_output, _bpe_output, _mixed_output, _big_bpe_output],
    ),
    _TestCase(inputs=[_mixed_input_plain], outputs=[_mixed_output_plain]),
    _TestCase(
        inputs=[_tricky_input, _rle_input],
        outputs=[_tricky_output, _rle_output],
    ),
    _TestCase(
        inputs=[_hybrid_then_plain_input],
        outputs=[_hybrid_then_plain_output],
    ),
)

class ColumnChunkDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "vfpga_tops/column_chunk_decoder_test.sv"
    debug_mode = True

    def __init__(self, a) -> None:
        super().__init__(a)

    def setUp(self):
        return super().setUp()

    def simulate_fpga(self):
        assert self.test_case is not None, (
            "Cannot have host test with empty test case!"
        )

        # Chunk-level registers only — page-level configuration is now produced
        # inside ColumnChunkDecoder by PageHeaderParser. Offset 3 mirrors
        # page_header_parser_test.py (GlobalConfig occupies regs 0..2).
        for input in self.test_case.inputs:
            for i, value in input._registers().items():
                self.write_register(fpga_register.vFPGARegister(3 + i, value))

        # One stream input per column chunk (full thrift-wrapped bytes).
        for input in self.test_case.inputs:
            self.set_stream_input(0, input.chunk_bytes)

        for output in self.test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, output))

        return super().simulate_fpga()

    def test_one_rle_page(self):
        self.test_case = _test_cases[0]
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_one_bpe_page(self):
        self.test_case = _test_cases[1]
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_one_mixed_page(self):
        self.test_case = _test_cases[2]
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_one_big_bpe_page(self):
        self.test_case = _test_cases[3]
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_plain_page(self):
        self.test_case = _test_cases[5]
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_tricky_page(self):
        self.test_case = _test_cases[6]
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_many_hybrid_pages(self):
        self.test_case = _test_cases[4]
        self.overwrite_simulation_time(simulation_time.SimulationTime.till_finished())
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_plain_after_hybrid(self):
        self.test_case = _test_cases[7]
        self.simulate_fpga()
        self.assert_simulation_output()
