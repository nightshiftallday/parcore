from dataclasses import dataclass
from enum import IntEnum
from coyote_test import fpga_test_case, fpga_register

import pyarrow.parquet as pq


class _PageType(IntEnum):
    HYBRID = 0
    DICT   = 1
    PLAIN  = 2


@dataclass
class _ExpectedPage:
    page_type:  _PageType
    num_values: int
    last:       bool
    payload:    bytearray   # raw compressed payload bytes (header stripped)


@dataclass
class _TestCase:
    chunk_num_values: int
    chunk_bytes:      bytearray         # raw column-chunk bytes (headers + payloads)
    pages:            list[_ExpectedPage]


# ---------------------------------------------------------------------------
# Thrift compact-protocol header builders
# ---------------------------------------------------------------------------

def _zigzag_encode(n: int) -> int:
    return (n << 1) ^ (n >> 31)

def _encode_varint(n: int) -> bytearray:
    n = _zigzag_encode(n)
    out = bytearray()
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            b |= 0x80
        out.append(b)
        if not n:
            break
    return out

def _make_data_page_header(
    num_values: int,
    uncompressed_size: int,
    compressed_size: int,
    encoding: int,
) -> bytearray:
    """Minimal Thrift compact DataPageHeader (no CRC, no statistics)."""
    h = bytearray()
    h += b'\x15' + _encode_varint(0)               # fid1: page_type=DATA_PAGE(0)
    h += b'\x15' + _encode_varint(uncompressed_size)
    h += b'\x15' + _encode_varint(compressed_size)
    h += b'\x2c'                                    # fid5: data_page_header STRUCT
    h += b'\x15' + _encode_varint(num_values)       # inner fid1
    h += b'\x15' + _encode_varint(encoding)         # inner fid2: encoding
    h += b'\x15' + _encode_varint(0)                # inner fid3: def_level_enc=PLAIN
    h += b'\x15' + _encode_varint(0)                # inner fid4: rep_level_enc=PLAIN
    h += b'\x00'                                    # inner STOP
    h += b'\x00'                                    # outer STOP
    return h

def _encode_binary(data: bytes) -> bytearray:
    """Thrift compact binary field value: length (unsigned varint) + bytes."""
    out = bytearray()
    n = len(data)
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            b |= 0x80
        out.append(b)
        if not n:
            break
    out += data
    return out

def _make_data_page_header_full(
    num_values: int,
    uncompressed_size: int,
    compressed_size: int,
    encoding: int,
    def_level_encoding: int,
    rep_level_encoding: int,
    crc: int,
    stats_max: bytes,
    stats_min: bytes,
    stats_null_count: int,
    stats_distinct_count: int,
    stats_max_value: bytes,
    stats_min_value: bytes,
    stats_is_max_exact: bool,
    stats_is_min_exact: bool,
) -> bytearray:
    """Thrift compact DataPageHeader with all optional fields including full Statistics."""
    # Build Statistics struct body (all 8 fields, each with delta_fid=1)
    stats = bytearray()
    stats += b'\x18' + _encode_binary(stats_max)           # fid1: max (binary)
    stats += b'\x18' + _encode_binary(stats_min)           # fid2: min (binary)
    stats += b'\x15' + _encode_varint(stats_null_count)    # fid3: null_count (i64)
    stats += b'\x15' + _encode_varint(stats_distinct_count)# fid4: distinct_count (i64)
    stats += b'\x18' + _encode_binary(stats_max_value)     # fid5: max_value (binary)
    stats += b'\x18' + _encode_binary(stats_min_value)     # fid6: min_value (binary)
    stats += bytes([0x11 if stats_is_max_exact else 0x12]) # fid7: is_max_value_exact (bool)
    stats += bytes([0x11 if stats_is_min_exact else 0x12]) # fid8: is_min_value_exact (bool)
    stats += b'\x00'                                        # STOP

    h = bytearray()
    h += b'\x15' + _encode_varint(0)                  # fid1: page_type=DATA_PAGE(0)
    h += b'\x15' + _encode_varint(uncompressed_size)  # fid2: uncompressed_page_size
    h += b'\x15' + _encode_varint(compressed_size)    # fid3: compressed_page_size
    h += b'\x15' + _encode_varint(crc)                # fid4: crc (optional i32)
    h += b'\x1c'                                       # fid5: data_page_header STRUCT (delta=1)
    h += b'\x15' + _encode_varint(num_values)          # inner fid1: num_values
    h += b'\x15' + _encode_varint(encoding)            # inner fid2: encoding
    h += b'\x15' + _encode_varint(def_level_encoding)  # inner fid3: definition_level_encoding
    h += b'\x15' + _encode_varint(rep_level_encoding)  # inner fid4: repetition_level_encoding
    h += b'\x1c'                                       # inner fid5: statistics STRUCT (delta=1)
    h += stats
    h += b'\x00'                                       # inner STOP (DataPageHeader)
    h += b'\x00'                                       # outer STOP (PageHeader)
    return h


def _make_data_page_header_sparse_stats(
    num_values: int,
    uncompressed_size: int,
    compressed_size: int,
    encoding: int,
    def_level_encoding: int,
    rep_level_encoding: int,
    crc: int,
    stats_max: bytes,
    stats_max_value: bytes,
    stats_is_min_exact: bool,
) -> bytearray:
    """DataPageHeader where Statistics writes only fids 1, 5, 8 (deltas 1, 4, 3).

    Forces tag bytes 0x48 and 0x31, exercising high-nibble (delta>1) dispatch.
    """
    stats = bytearray()
    stats += b'\x18' + _encode_binary(stats_max)           # fid1: max (binary), delta 1
    stats += b'\x48' + _encode_binary(stats_max_value)     # fid5: max_value (binary), delta 4
    stats += bytes([0x31 if stats_is_min_exact else 0x32]) # fid8: is_min_value_exact (bool), delta 3
    stats += b'\x00'                                        # STOP

    h = bytearray()
    h += b'\x15' + _encode_varint(0)                  # fid1: page_type=DATA_PAGE(0)
    h += b'\x15' + _encode_varint(uncompressed_size)  # fid2: uncompressed_page_size
    h += b'\x15' + _encode_varint(compressed_size)    # fid3: compressed_page_size
    h += b'\x15' + _encode_varint(crc)                # fid4: crc (optional i32)
    h += b'\x1c'                                       # fid5: data_page_header STRUCT (delta=1)
    h += b'\x15' + _encode_varint(num_values)          # inner fid1: num_values
    h += b'\x15' + _encode_varint(encoding)            # inner fid2: encoding
    h += b'\x15' + _encode_varint(def_level_encoding)  # inner fid3: definition_level_encoding
    h += b'\x15' + _encode_varint(rep_level_encoding)  # inner fid4: repetition_level_encoding
    h += b'\x1c'                                       # inner fid5: statistics STRUCT (delta=1)
    h += stats
    h += b'\x00'                                       # inner STOP (DataPageHeader)
    h += b'\x00'                                       # outer STOP (PageHeader)
    return h


def _make_dict_page_header(
    num_values: int,
    uncompressed_size: int,
    compressed_size: int,
) -> bytearray:
    """Minimal Thrift compact DictionaryPageHeader."""
    h = bytearray()
    h += b'\x15' + _encode_varint(2)               # fid1: page_type=DICTIONARY_PAGE(2)
    h += b'\x15' + _encode_varint(uncompressed_size)
    h += b'\x15' + _encode_varint(compressed_size)
    h += b'\x4c'                                    # fid7: dictionary_page_header STRUCT
    h += b'\x15' + _encode_varint(num_values)       # inner fid1
    h += b'\x15' + _encode_varint(0)                # inner fid2: encoding=PLAIN
    h += b'\x00'                                    # inner STOP
    h += b'\x00'                                    # outer STOP
    return h

def _hw_page_type(thrift_page_type: int, encoding: int) -> _PageType:
    if thrift_page_type == 2:
        return _PageType.DICT
    elif encoding == 0:
        return _PageType.PLAIN
    else:
        return _PageType.HYBRID


# ---------------------------------------------------------------------------
# Build test cases from synthetic headers
# ---------------------------------------------------------------------------

def _make_synthetic_plain(num_values: int, payload_size: int, last: bool) -> tuple[bytearray, _ExpectedPage]:
    payload = bytearray(range(payload_size % 256)) * (payload_size // 256 + 1)
    payload = payload[:payload_size]
    hdr = _make_data_page_header(num_values, payload_size, payload_size, 0)
    chunk = hdr + payload
    page = _ExpectedPage(
        page_type=_PageType.PLAIN,
        num_values=num_values,
        last=last,
        payload=bytearray(payload),
    )
    return chunk, page

def _make_synthetic_hybrid(num_values: int, payload_size: int, last: bool) -> tuple[bytearray, _ExpectedPage]:
    # Hybrid page payload layout: 4-byte def_levels length (LE) | def_levels bytes | encoded data.
    # The hardware passes the full compressed body through unchanged.
    def_levels_len = 8
    def_levels = bytearray(b'\x55' * def_levels_len)
    encoded = bytearray(b'\xab' * payload_size)
    body = bytearray(def_levels_len.to_bytes(4, 'little')) + def_levels + encoded
    hdr = _make_data_page_header(num_values, len(body), len(body), 8)  # RLE_DICT=8
    chunk = hdr + body
    page = _ExpectedPage(
        page_type=_PageType.HYBRID,
        num_values=num_values,
        last=last,
        payload=bytearray(body),
    )
    return chunk, page

def _make_synthetic_dict(num_values: int, payload_size: int) -> tuple[bytearray, _ExpectedPage]:
    payload = bytearray(b'\xcd' * payload_size)
    hdr = _make_dict_page_header(num_values, payload_size, payload_size)
    chunk = hdr + payload
    page = _ExpectedPage(
        page_type=_PageType.DICT,
        num_values=num_values,
        last=False,
        payload=bytearray(payload),
    )
    return chunk, page


def _single_plain_page_case() -> _TestCase:
    num_values = 20
    payload_size = 64
    chunk, page = _make_synthetic_plain(num_values, payload_size, last=True)
    page.last = True
    return _TestCase(
        chunk_num_values=num_values,
        chunk_bytes=bytearray(chunk),
        pages=[page],
    )

def _single_hybrid_page_case() -> _TestCase:
    num_values = 100
    payload_size = 128
    chunk, page = _make_synthetic_hybrid(num_values, payload_size, last=True)
    return _TestCase(
        chunk_num_values=num_values,
        chunk_bytes=bytearray(chunk),
        pages=[page],
    )

def _dict_plus_hybrid_case() -> _TestCase:
    """Dict page followed by a hybrid data page.

    Payload sizes are chosen to exercise two specific paths (NUM_BYTES = 64):

    1. PAYLOAD_DRAIN_BUF Case A for the dict page:
       The dict header is ~13 bytes. After LATCH_FIRST strips the fid1 tag,
       ~51 bytes of the first AXI beat remain in the buffer, which is more
       than dict_ps=20. So remaining_bytes(~51) > remaining_comp_size(20) and
       Case A fires: skip_bytes is set to 20+1=21 and the FSM jumps directly
       to PARSE_TYPE for the data page header.

    2. PAYLOAD_BYPASS final-beat path (RTL line 349) with skip_bytes != 0 at
       entry (the TODO on line 339): after Case A sets skip_bytes=21 the
       parser consumes the data page header with the skip counter running down.
       By the time PAYLOAD_BYPASS is entered skip_bytes is 0, so the
       `n_skip_bytes = '0` assignment on line 367 is a no-op — but the branch
       itself is reached because data_ps=100 leaves a 36-byte final beat
       (remaining_comp_size=36 < NUM_BYTES=64).
    """
    dict_nv, dict_ps = 8, 20
    data_nv, data_ps = 50, 100
    dict_chunk, dict_page = _make_synthetic_dict(dict_nv, dict_ps)
    data_chunk, data_page = _make_synthetic_hybrid(data_nv, data_ps, last=True)
    data_page.last = True
    chunk = bytearray(dict_chunk) + bytearray(data_chunk)
    return _TestCase(
        chunk_num_values=data_nv,
        chunk_bytes=chunk,
        pages=[dict_page, data_page],
    )

def _large_plain_case() -> _TestCase:
    """Payload spanning multiple 64-byte AXI beats."""
    num_values = 1000
    payload_size = 8000
    chunk, page = _make_synthetic_plain(num_values, payload_size, last=True)
    return _TestCase(
        chunk_num_values=num_values,
        chunk_bytes=bytearray(chunk),
        pages=[page],
    )

def _data_page_all_optional_fields_case() -> _TestCase:
    """DataPageHeader with CRC and all 8 Statistics fields populated.

    The header is 73 bytes and spans two 64-byte AXI beats.
    """
    num_values   = 42
    payload_size = 80
    encoding     = 0  # PLAIN

    payload = bytearray(range(payload_size % 256)) * (payload_size // 256 + 1)
    payload = payload[:payload_size]

    hdr = _make_data_page_header_full(
        num_values           = num_values,
        uncompressed_size    = payload_size,
        compressed_size      = payload_size,
        encoding             = encoding,
        def_level_encoding   = 0,   # PLAIN
        rep_level_encoding   = 0,   # PLAIN
        crc                  = 0x12345678,
        stats_max            = b'\xff\xff\xff\xff\xff\xff\xff\x7f',  # INT64 max
        stats_min            = b'\x00\x00\x00\x00\x00\x00\x00\x80',  # INT64 min
        stats_null_count     = 3,
        stats_distinct_count = 39,
        stats_max_value      = b'\xff\xff\xff\xff\xff\xff\xff\x7f',
        stats_min_value      = b'\x00\x00\x00\x00\x00\x00\x00\x80',
        stats_is_max_exact   = True,
        stats_is_min_exact   = True,
    )
    chunk = hdr + payload
    page = _ExpectedPage(
        page_type  = _PageType.PLAIN,
        num_values = num_values,
        last       = True,
        payload    = bytearray(payload),
    )
    return _TestCase(
        chunk_num_values = num_values,
        chunk_bytes      = bytearray(chunk),
        pages            = [page],
    )


def _deep_header_small_payload_case() -> _TestCase:
    """Synthetic page whose header is long enough that the final buffer refill
    in IS_END leaves remaining_bytes > NUM_BYTES when PAYLOAD_DRAIN_BUF is
    entered.  This exercises the TODO path on line 311 of page_header_parser.sv
    where the buffer holds more than one full AXI beat of payload residue.

    We achieve a long header by including CRC + full Statistics with two binary
    fields (8 bytes each), which pushes the header past two 64-byte AXI beats.
    The payload is kept small (3 bytes) so it fits entirely inside the residue
    that was already loaded during header parsing.
    """
    num_values   = 5
    payload_size = 73
    encoding     = 0  # PLAIN

    payload = bytearray(b'\xDE\xAD\xBE' + bytes(range(70)))

    hdr = _make_data_page_header_full(
        num_values           = num_values,
        uncompressed_size    = payload_size,
        compressed_size      = payload_size,
        encoding             = encoding,
        def_level_encoding   = 0,
        rep_level_encoding   = 0,
        crc                  = 0x00FEBABE,
        stats_max            = b'\xff\xff\xff\xff\xff\xff',
        stats_min            = b'\x00\x00\x00\x00\x00\x80',
        stats_null_count     = 0,
        stats_distinct_count = 5,
        stats_max_value      = b'\xff\xff\xff\xff\xff',
        stats_min_value      = b'\x00\x00\x00\x00\x80',
        stats_is_max_exact   = True,
        stats_is_min_exact   = False,
    )
    chunk = hdr + payload
    page = _ExpectedPage(
        page_type  = _PageType.PLAIN,
        num_values = num_values,
        last       = True,
        payload    = bytearray(payload),
    )
    return _TestCase(
        chunk_num_values = num_values,
        chunk_bytes      = bytearray(chunk),
        pages            = [page],
    )


def _data_page_sparse_stats_case() -> _TestCase:
    """DataPageHeader whose Statistics writes only fids 1, 5, 8 — deltas 1, 4, 3.

    Forces the parser to dispatch on tag bytes 0x48 (binary, delta 4) and
    0x31 (bool-true, delta 3), not just the delta-1 forms 0x18 / 0x11.
    """
    num_values   = 42
    payload_size = 80
    encoding     = 0  # PLAIN

    payload = bytearray(range(payload_size % 256)) * (payload_size // 256 + 1)
    payload = payload[:payload_size]

    hdr = _make_data_page_header_sparse_stats(
        num_values         = num_values,
        uncompressed_size  = payload_size,
        compressed_size    = payload_size,
        encoding           = encoding,
        def_level_encoding = 0,
        rep_level_encoding = 0,
        crc                = 0x12345678,
        stats_max          = b'\xff\xff\xff\xff\xff\xff\xff\x7f',
        stats_max_value    = b'\xff\xff\xff\xff\xff\xff\xff\x7f',
        stats_is_min_exact = True,
    )
    chunk = hdr + payload
    page = _ExpectedPage(
        page_type  = _PageType.PLAIN,
        num_values = num_values,
        last       = True,
        payload    = bytearray(payload),
    )
    return _TestCase(
        chunk_num_values = num_values,
        chunk_bytes      = bytearray(chunk),
        pages            = [page],
    )


# ---------------------------------------------------------------------------
# Build test cases from nation.parquet
# ---------------------------------------------------------------------------

def _decode_leb128(data: bytes, pos: int) -> tuple[int, int]:
    result, shift = 0, 0
    while True:
        b = data[pos]
        result |= (b & 0x7F) << shift
        pos += 1
        shift += 7
        if not (b & 0x80):
            break
    return result, pos

def _zigzag_decode(n: int) -> int:
    return (n >> 1) ^ (-(n & 1))

def _skip_varint(data: bytes, pos: int) -> int:
    while data[pos] & 0x80:
        pos += 1
    return pos + 1

def _skip_field(data: bytes, pos: int) -> int:
    ctype = data[pos] & 0xF
    pos += 1
    if ctype in (4, 5, 6):
        pos = _skip_varint(data, pos)
    elif ctype == 0xC:
        while data[pos] != 0x00:
            pos = _skip_field(data, pos)
        pos += 1  # nested STOP
    return pos

def _parse_inner_struct(data: bytes, pos: int) -> tuple[dict, int]:
    fields: dict[int, object] = {}
    prev_fid = 0
    while pos < len(data):
        tag = data[pos]
        if tag == 0x00:
            pos += 1
            break
        delta_fid = (tag >> 4) & 0xF
        ctype = tag & 0xF
        if delta_fid == 0:
            raw, pos = _decode_leb128(data, pos + 1)
            fid = _zigzag_decode(raw)
        else:
            fid = prev_fid + delta_fid
            pos += 1
        prev_fid = fid
        if ctype in (4, 5, 6):
            val, pos = _decode_leb128(data, pos)
            fields[fid] = _zigzag_decode(val)
        elif ctype in (1, 2):
            fields[fid] = (ctype == 1)
        elif ctype == 0xC:
            while data[pos] != 0x00:
                pos = _skip_field(data, pos)
            pos += 1
            fields[fid] = 'struct'
        else:
            break
    return fields, pos

def _parse_page_header(data: bytes, offset: int) -> tuple[dict, int]:
    pos = offset
    outer: dict[int, object] = {}
    prev_fid = 0
    while pos < len(data):
        tag = data[pos]
        if tag == 0x00:
            pos += 1
            break
        delta_fid = (tag >> 4) & 0xF
        ctype = tag & 0xF
        if delta_fid == 0:
            raw, pos = _decode_leb128(data, pos + 1)
            fid = _zigzag_decode(raw)
        else:
            fid = prev_fid + delta_fid
            pos += 1
        prev_fid = fid
        if ctype in (4, 5, 6):
            val, pos = _decode_leb128(data, pos)
            outer[fid] = _zigzag_decode(val)
        elif ctype == 0xC:
            inner, pos = _parse_inner_struct(data, pos)
            outer[fid] = inner
        elif ctype in (1, 2):
            outer[fid] = (ctype == 1)
    return outer, pos

def _extract_parquet_column_chunks(parquet_path: str) -> list[_TestCase]:
    with open(parquet_path, 'rb') as fh:
        raw = bytearray(fh.read())

    pf = pq.ParquetFile(parquet_path)
    meta = pf.metadata
    cases: list[_TestCase] = []

    for col_idx in range(meta.num_columns):
        col = meta.row_group(0).column(col_idx)
        start = (
            col.dictionary_page_offset
            if col.dictionary_page_offset is not None
            else col.data_page_offset
        )
        size  = col.total_compressed_size
        chunk = bytes(raw[start : start + size])

        pages: list[_ExpectedPage] = []
        pos = 0
        total_num_values = 0

        while pos < size:
            outer, hdr_end = _parse_page_header(chunk, pos)
            if not outer:
                break
            thrift_type  = outer.get(1, 0)
            comp_size    = outer.get(3, 0)
            inner_key    = 7 if thrift_type == 2 else 5
            inner        = outer.get(inner_key, {})
            num_values   = inner.get(1, 0) if isinstance(inner, dict) else 0
            encoding     = inner.get(2, 0) if isinstance(inner, dict) else 0

            hw_type = _hw_page_type(thrift_type, encoding)
            payload_start = hdr_end
            payload_end   = pos + (hdr_end - pos) + comp_size
            payload       = bytearray(chunk[payload_start : payload_end])

            pages.append(_ExpectedPage(
                page_type  = hw_type,
                num_values = num_values,
                last       = False,
                payload    = payload,
            ))

            if hw_type != _PageType.DICT:
                total_num_values += num_values

            pos = payload_end

        if pages:
            pages[-1].last = True
            cases.append(_TestCase(
                chunk_num_values = total_num_values,
                chunk_bytes      = bytearray(chunk),
                pages            = pages,
            ))

    return cases


# ---------------------------------------------------------------------------
# Serialisation helpers
# ---------------------------------------------------------------------------

def _page_conf_record(page: _ExpectedPage) -> bytearray:
    """6-byte record matching the hardware serialiser: type(1) | num_values(4 LE) | last(1)."""
    rec = bytearray(6)
    rec[0] = int(page.page_type)
    rec[1:5] = page.num_values.to_bytes(4, 'little')
    rec[5] = 1 if page.last else 0
    return rec

def _chunk_conf_registers(num_values: int) -> dict[int, bytearray]:
    """ColumnChunkDecoderConfig register values (3 regs at offset 0)."""
    return {
        0: bytearray(int(0).to_bytes(1, 'big')),          # compression=RAW
        1: bytearray(num_values.to_bytes(4, 'little')),   # num_values
        2: bytearray(int(2).to_bytes(1, 'big')),          # type=INT64 (unused here)
    }


# ---------------------------------------------------------------------------
# Test case instances
# ---------------------------------------------------------------------------

_PARQUET_PATH = '/local/home/jodann/parcore/hardware/unit-tests/data/lineitem.parquet'

_SYNTHETIC_CASES = [
    _single_plain_page_case(),
    _single_hybrid_page_case(),
    _dict_plus_hybrid_case(),
    _large_plain_case(),
    _data_page_all_optional_fields_case(),
    _data_page_sparse_stats_case(),
    _deep_header_small_payload_case(),
]

_PARQUET_CASES = _extract_parquet_column_chunks(_PARQUET_PATH)


# ---------------------------------------------------------------------------
# Test class
# ---------------------------------------------------------------------------

class PageHeaderParserTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "vfpga_tops/page_header_parser_test.sv"
    debug_mode = True

    def _run_sequential(self, tcs: list[_TestCase]) -> None:
        """Drive multiple column chunks back-to-back in a single simulation run."""
        for tc in tcs:
            for reg_idx, value in _chunk_conf_registers(tc.chunk_num_values).items():
                self.write_register(fpga_register.vFPGARegister(3 + reg_idx, value))
            self.set_stream_input(0, tc.chunk_bytes)
            for page in tc.pages:
                self.set_expected_output(0, page.payload)
                self.set_expected_output(1, _page_conf_record(page))

        self.simulate_fpga()
        self.assert_simulation_output()

    def _run(self, tc: _TestCase) -> None:
        # Write chunk_conf registers
        for reg_idx, value in _chunk_conf_registers(tc.chunk_num_values).items():
            self.write_register(fpga_register.vFPGARegister(3 + reg_idx, value))

        # Input: raw column-chunk bytes
        self.set_stream_input(0, tc.chunk_bytes)

        # Expected output stream 0: one transfer per page (each ends with last=1)
        # Expected output stream 1: one 6-byte page_conf record per page
        for page in tc.pages:
            self.set_expected_output(0, page.payload)
            self.set_expected_output(1, _page_conf_record(page))

        self.simulate_fpga()
        self.assert_simulation_output()

    # -- Synthetic tests -----------------------------------------------------

    def test_single_plain_page(self):
        self._run(_SYNTHETIC_CASES[0])

    def test_single_hybrid_page(self):
        self._run(_SYNTHETIC_CASES[1])

    def test_dict_plus_hybrid(self):
        self._run(_SYNTHETIC_CASES[2])

    def test_large_plain_page(self):
        self._run(_SYNTHETIC_CASES[3])

    def test_data_page_all_optional_fields(self):
        """DataPageHeader with CRC and all 8 Statistics fields populated."""
        self._run(_SYNTHETIC_CASES[4])

    def test_data_page_sparse_statistics(self):
        """Statistics with non-sequential fids (deltas 1, 4, 3) — exercises
        high-nibble dispatch in IS_END."""
        self._run(_SYNTHETIC_CASES[5])

    def test_overfull_header_buffer(self):
        """Long header (CRC + full Statistics with binary fields) forces a buffer
        refill inside IS_END, leaving remaining_bytes > NUM_BYTES when
        PAYLOAD_DRAIN_BUF is entered."""
        self._run(_SYNTHETIC_CASES[6])

    # -- lineitem.parquet tests ----------------------------------------------

    def test_parquet_l_orderkey(self):
        """Plain data page: INT64, no dictionary."""
        self._run(_PARQUET_CASES[0])

    def test_parquet_l_discount(self):
        """Dictionary page + RLE_DICT data page: INT64."""
        self._run(_PARQUET_CASES[6])

    def test_parquet_l_extendedprice(self):
        """Plain data page: INT64, no dictionary (large payload)."""
        self._run(_PARQUET_CASES[5])

    def test_parquet_l_shipdate(self):
        """Plain data page: INT32, no dictionary."""
        self._run(_PARQUET_CASES[10])

    def test_sequential_column_chunks(self):
        """Two different column chunks driven back-to-back in one simulation.
        Verifies that IDLE fully resets internal state between chunks so the
        second chunk is parsed correctly after the first completes."""
        self._run_sequential([_PARQUET_CASES[0], _PARQUET_CASES[6]])
