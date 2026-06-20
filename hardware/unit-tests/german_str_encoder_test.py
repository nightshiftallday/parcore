from coyote_test import fpga_test_case, fpga_register
from random import randint, seed
from typing import List
from unit_test.fpga_stream import Stream, StreamType
from unit_test.simulation_time import SimulationTime, SimulationTimeUnit, FixedSimulationTime

import numpy as np

REG_OFFSET      = 4
REG_BUFFER_ADDR = 5

BEAT_SIZE  = 64
INLINE_LEN = 12

DEFAULT_BUFFER_ADDR = 0x1000


# ---------------------------------------------------------------------------
# Encoding helpers
# ---------------------------------------------------------------------------

def _encode_data(strings: List[bytes]) -> bytearray:
    buf = bytearray()
    for s in strings:
        buf += s
    return buf


def _encode_lengths(strings: List[bytes]) -> bytearray:
    buf = bytearray()
    for s in strings:
        buf += len(s).to_bytes(4, 'little')
    return buf


def _expected_strings(strings: List[bytes], buffer_addr: int) -> List[int]:
    """The german_str_t records, serialised LSB-first as the hardware emits them.

    Canonical Umbra/German layout of each 16-byte record (byte 0 first):
      bytes  0..3  : length   - 4-byte LE string length
      bytes  4..7  : prefix   - first 4 string bytes (zero-padded)
      bytes  8..15 : payload  - inline bytes 4..11 (short) OR 8-byte LE buffer
                                address (long, len > 12)

    The buffer address advances by every string's length (all bytes are written
    to the buffer), so a long string at logical offset `cum` stores
    buffer_addr + cum.
    """
    out = bytearray()
    cum = 0
    for s in strings:
        n = len(s)
        rec = bytearray(16)
        rec[0:4] = n.to_bytes(4, 'little')
        rec[4:8] = (s[:4]).ljust(4, b'\x00')
        if n <= INLINE_LEN:
            rec[8:16] = (s[4:12]).ljust(8, b'\x00')
        else:
            rec[8:16] = (buffer_addr + cum).to_bytes(8, 'little')
        out += rec
        cum += n
    return list(out)


def _expected_data(strings: List[bytes]) -> List[int]:
    return [b for s in strings for b in s]


# ---------------------------------------------------------------------------
# Test case
# ---------------------------------------------------------------------------

class GermanStringEncoderTest(fpga_test_case.FPGATestCase):
    """
    Tests for GermanStringEncoder.

    The vfpga top wires:
      - axis_host_recv[0] -> AXIToNData            -> in_data    (string bytes)
      - axis_host_recv[1] -> AXIToNData -> repack  -> in_lens    (4-byte lengths)
      - out_strings -> bytes -> NDataWidthConverter
                    -> NDataToAXI -> axis_host_send[0]           (german_str_t)
      - out_data    -> NDataToAXI -> axis_host_send[1]           (forwarded bytes)

    NOTE: the byte offset of the first string is left at 0.  As with the
    PlainStringDecoder test, a non-zero offset would surface the leading bytes
    verbatim through the DMA test interface (which delivers keep=1), so it is
    not exercised here.

    NOTE: every test keeps the data stream non-empty (at least one byte total),
    since the encoder only accepts its config once the first data beat is
    available.
    """

    alternative_vfpga_top_file = "vfpga_tops/german_str_encoder_test.sv"
    debug_mode = True

    def setUp(self):
        ret = super().setUp()
        self._simulation_time: SimulationTime = SimulationTime.fixed_time(
            100, SimulationTimeUnit.MICROSECONDS
        )
        return ret

    # ------------------------------------------------------------------
    # Shared driver
    # ------------------------------------------------------------------

    def _run(self, strings: List[bytes], buffer_addr: int = DEFAULT_BUFFER_ADDR) -> None:
        self.write_register(fpga_register.vFPGARegister(
            REG_OFFSET, bytearray((0).to_bytes(4, 'little'))))
        self.write_register(fpga_register.vFPGARegister(
            REG_BUFFER_ADDR, bytearray(buffer_addr.to_bytes(8, 'little'))))

        self.set_stream_input(0, _encode_data(strings))
        self.set_stream_input(1, _encode_lengths(strings))

        self.set_expected_output(
            0, Stream(StreamType.UNSIGNED_INT_8, _expected_strings(strings, buffer_addr)))
        self.set_expected_output(
            1, Stream(StreamType.UNSIGNED_INT_8, _expected_data(strings)))

        self.simulate_fpga()
        self.assert_simulation_output()

    # ------------------------------------------------------------------
    # Short strings (inline payload)
    # ------------------------------------------------------------------

    def test_single_short_string(self):
        """One short string: prefix + inline payload, no address."""
        self._run([b"hello"])

    def test_string_shorter_than_prefix(self):
        """Length < 4: prefix is partially filled and zero-padded, payload empty."""
        self._run([b"ab"])

    def test_string_exactly_prefix_len(self):
        """Length == 4: prefix full, inline payload all zero."""
        self._run([b"abcd"])

    def test_string_fills_inline(self):
        """Length == 12: the maximum inline string (4 prefix + 8 payload)."""
        self._run([b"abcdefghijkl"])

    def test_multiple_short_one_beat(self):
        """Several short strings whose bytes fit in a single data beat.
        Exercises Path A (stay on the beat) repeatedly."""
        self._run([b"foo", b"bar", b"baz"])

    def test_empty_among_nonempty(self):
        """Zero-length strings interleaved with real ones (data stays non-empty)."""
        self._run([b"", b"abc", b"", b"de"])

    # ------------------------------------------------------------------
    # Long strings (address payload)
    # ------------------------------------------------------------------

    def test_single_long_string(self):
        """Length 13 (> 12): payload is the buffer address, not inline bytes."""
        self._run([b"abcdefghijklm"])

    def test_long_string_spans_two_beats(self):
        """A 65-byte string spans two data beats: Path B then a continuation
        flush. Its view stores buffer_addr + 0."""
        self._run([b"a" * 65])

    def test_long_string_spans_many_beats(self):
        """A 200-byte string spans four beats, stressing the continuation path."""
        self._run([b"b" * 200])

    def test_mixed_short_and_long(self):
        """Mix of inline and address strings; checks the running buffer address
        advances by every string's length."""
        self._run([b"hi", b"x" * 20, b"yo", b"z" * 30, b"end"])

    # ------------------------------------------------------------------
    # Lookahead / beat-boundary behaviour
    # ------------------------------------------------------------------

    def test_short_string_uses_preview_bytes(self):
        """A short string that starts near the end of a beat, so its inline
        bytes are read from the Lookahead preview window of the next beat.
        String 1 (60 bytes, long) leaves string 2 starting at byte 60."""
        self._run([b"x" * 60, b"abcdefghij"])

    def test_string_ends_on_beat_boundary(self):
        """A string whose bytes end exactly on the 64-byte boundary (Path B with
        next_offset == STREAM_WIDTH), followed by another string."""
        self._run([b"a" * 64, b"tail"])

    # ------------------------------------------------------------------
    # Scale / throughput
    # ------------------------------------------------------------------

    def test_16_strings_fill_length_beat(self):
        self._run([b"ab"] * 16)

    def test_many_short_strings(self):
        strings = [bytes([(i + 1) % 256, (i * 3) % 256, (i * 7) % 256])
                   for i in range(50)]
        self._run(strings)

    def test_many_mixed_strings(self):
        """A larger page mixing every category to cover all FSM paths together."""
        self._run([
            b"a",
            b"hello world",            # 11, inline
            b"abcdefghijkl",           # 12, inline boundary
            b"abcdefghijklm",          # 13, address
            b"q" * 70,                 # long, multi-beat
            b"short",
            b"",
            b"the quick brown fox jumps over the lazy dog",
        ])

    def test_many_mixed_strings_2(self):
        """A larger page mixing every category to cover all FSM paths together."""
        self._run([
            b"a",
            b"hello world",            # 11, inline
            b"abcdefghijkl",           # 12, inline boundary
            b"abcdefghijklm",          # 13, address
            b"q" * 70,                 # long, multi-beat
            b"short",
            b"",
            b"the quick brown fox jumps over the lazy dog",
            b"a",
            b"hello world",            # 11, inline
            b"abcdefghijkl",           # 12, inline boundary
            b"abcdefghijklm",          # 13, address
            b"q" * 70,                 # long, multi-beat
            b"short",
            b"",
            b"the quick brown fox jumps over the lazy dog",
            b"a",
            b"hello world",            # 11, inline
            b"abcdefghijkl",           # 12, inline boundary
            b"abcdefghijklm",          # 13, address
            b"q" * 70,                 # long, multi-beat
            b"short",
            b"",
            b"the quick brown fox jumps over the lazy dog",
            b"a",
            b"hello world",            # 11, inline
            b"abcdefghijkl",           # 12, inline boundary
            b"abcdefghijklm",          # 13, address
            b"q" * 70,                 # long, multi-beat
            b"short",
            b"",
            b"the quick brown fox jumps over the lazy dog",
            b"a",
            b"hello world",            # 11, inline
            b"abcdefghijkl",           # 12, inline boundary
            b"abcdefghijklm",          # 13, address
            b"q" * 70,                 # long, multi-beat
            b"short",
            b"",
            b"the quick brown fox jumps over the lazy dog",
        ])

    def test_random_input(self):
        """A larger page mixing every category to cover all FSM paths together."""
        RAND_SEED = 0xDEADBEEF
        NUM_STRINGS = 128
        STR_MIN_LEN = 0
        STR_MAX_LEN = 4096
        seed(RAND_SEED)
        input = []
        for _ in range(NUM_STRINGS):
            str_len = randint(STR_MIN_LEN, STR_MAX_LEN)
            input.append(np.random.bytes(str_len))
        
        self._run(input)
