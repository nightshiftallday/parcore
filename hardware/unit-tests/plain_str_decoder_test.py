from typing import List

from coyote_test import fpga_test_case, fpga_register
from unit_test.fpga_stream import Stream, StreamType

# GlobalConfig with NUM_CONFIGS=2, ADDR_SPACE_SIZES={1,1}:
#   NUM_GLOBAL_REGS = 2 + 2 = 4
#   Write config addresses start at 4.
REG_OFFSET     = 4  # conf_config[0] -> latched_offset  -> conf.data.offset
REG_NUM_VALUES = 5  # conf_config[1] -> latched_num_values -> conf.data.num_values

BEAT_SIZE = 64  # STREAM_WIDTH in bytes


# ---------------------------------------------------------------------------
# Encoding helpers
# ---------------------------------------------------------------------------

def _encode(strings: List[bytes]) -> bytearray:
    """Serialize strings in PLAIN format: 4-byte LE length prefix + payload."""
    buf = bytearray()
    for s in strings:
        buf += len(s).to_bytes(4, 'little')
        buf += s
    return buf


def _expected_values(strings: List[bytes]) -> List[int]:
    """Payload bytes from all strings concatenated (prefix-stripped, compacted)."""
    return [b for s in strings for b in s]


def _expected_lengths(strings: List[bytes]) -> List[int]:
    """Each string length as 4-byte LE, flattened — matches the lengths output stream."""
    out = []
    for s in strings:
        out += list(len(s).to_bytes(4, 'little'))
    return out


# ---------------------------------------------------------------------------
# Test case
# ---------------------------------------------------------------------------

class PlainStringDecoderTest(fpga_test_case.FPGATestCase):
    """
    Tests for PlainStringDecoder.

    The vfpga top wires:
      - axis_host_recv[0]  -> AXIToNData -> in        (PLAIN-encoded page bytes)
      - out_data -> DataNormalizer -> NDataToAXI -> axis_host_send[0]  (string bytes)
      - out_lens -> lengths_as_bytes -> NDataWidthConverter
                 -> NDataToAXI -> axis_host_send[1]               (lengths)

    NOTE: Non-zero `offset` tests are omitted.  In real use, the upstream
    PageHeaderParser sets keep=0 for the pre-offset header bytes, so they
    are invisible to the DataNormalizer.  Through the DMA test interface, all
    transmitted bytes arrive with keep=1, so those header bytes would appear
    verbatim in the output — testing that would verify DMA behaviour, not the
    decoder.  The offset register is exercised indirectly by the beat-straddling
    tests, which rely on correct prefix_offset arithmetic.
    """

    alternative_vfpga_top_file = "vfpga_tops/plain_string_decoder_test.sv"
    debug_mode = True

    # ------------------------------------------------------------------
    # Shared driver
    # ------------------------------------------------------------------

    def _run(self, strings: List[bytes], offset: int = 0) -> None:
        """
        Encode `strings` in PLAIN format, write config registers, drive the
        simulation, and assert both output streams.

        :param strings: Payload bytes for each string (no length prefix).
        :param offset:  Byte offset within the first beat at which the first
                        length prefix begins.  Prepend that many zero bytes to
                        the input so the prefix lands at the right position.
        """
        encoded = _encode(strings)
        input_data = bytearray(offset) + encoded

        self.write_register(fpga_register.vFPGARegister(
            REG_OFFSET, bytearray(offset.to_bytes(4, 'little'))))
        self.write_register(fpga_register.vFPGARegister(
            REG_NUM_VALUES, bytearray(len(strings).to_bytes(4, 'little'))))

        self.set_stream_input(0, input_data)
        self.set_expected_output(
            0, Stream(StreamType.UNSIGNED_INT_8, _expected_values(strings)))
        self.set_expected_output(
            1, Stream(StreamType.UNSIGNED_INT_8, _expected_lengths(strings)))

        self.simulate_fpga()
        self.assert_simulation_output()

    # ------------------------------------------------------------------
    # Basic single-beat correctness
    # ------------------------------------------------------------------

    def test_single_string(self):
        """One short string well within a single 64-byte beat."""
        self._run([b"hello"])

    def test_single_empty_string(self):
        """Zero-length string: 4-byte prefix of 0 with no payload bytes."""
        self._run([b""])

    def test_multiple_empty_strings(self):
        """Several consecutive zero-length strings to exercise Path A in a loop."""
        self._run([b"", b"", b"", b""])

    def test_multiple_strings_one_beat(self):
        """Several short strings whose combined encoding fits in one beat.
        3 x (4 + 3) = 21 bytes < 64 bytes."""
        self._run([b"foo", b"bar", b"baz"])

    def test_interleaved_empty_and_nonempty(self):
        """Alternating empty and non-empty strings; exercises Path A for each
        zero-length entry (next_offset = current + 4, no crossing)."""
        self._run([b"", b"abc", b"", b"de", b"", b"f"])

    def test_string_fills_most_of_beat(self):
        """Single string that almost fills a beat: 4 + 55 = 59 bytes."""
        self._run([b"x" * 55])

    # ------------------------------------------------------------------
    # Multi-beat / crossing paths
    # ------------------------------------------------------------------

    def test_string_spanning_two_beats(self):
        """A string whose encoding spans exactly two beats (4 + 65 = 69 bytes).
        Exercises Path B (have_len && crossing) and the barrel-shift/merge path
        inside the DataNormalizer for the spilled bytes."""
        self._run([b"a" * 65])

    def test_string_spanning_many_beats(self):
        """A very long string spanning four beats to stress the word_only (C/D)
        FSM paths and multi-beat DataBeatMerge accumulation."""
        self._run([b"b" * 300])

    def test_multiple_strings_spanning_beats(self):
        """Multiple strings that together span several beats, mixing Path A
        (short strings) and Path B (crossing strings)."""
        self._run([b"x" * 30, b"y" * 50, b"z" * 20])

    # ------------------------------------------------------------------
    # Length prefix straddling a beat boundary
    # ------------------------------------------------------------------

    def test_prefix_straddles_boundary_split_3_1(self):
        """Second length prefix starts at byte 61 of the encoded stream (split 3/1).
        Achieved naturally: string 1 is 57 bytes (4+57=61 bytes encoded)."""
        self._run([b"a" * 57, b"end"])

    def test_prefix_straddles_boundary_split_2_2(self):
        """Second length prefix starts at byte 62 (split 2/2 across beat boundary).
        String 1 is 58 bytes (4+58=62 bytes encoded)."""
        self._run([b"b" * 58, b"world"])

    def test_prefix_straddles_boundary_split_1_3(self):
        """Second length prefix starts at byte 63 (split 1/3 across beat boundary).
        String 1 is 59 bytes (4+59=63 bytes encoded)."""
        self._run([b"c" * 59, b"hi"])

    def test_two_prefixes_straddle_boundary(self):
        """Back-to-back beat-boundary straddles: string 1 pushes the second prefix
        to byte 62, and string 2 is long enough to push the third into beat 2."""
        self._run([b"d" * 58, b"e" * 65, b"tail"])

    # ------------------------------------------------------------------
    # Scale / throughput
    # ------------------------------------------------------------------

    def test_16_strings_exact_lengths_beat(self):
        """16 strings of length 0 so out_lens fills exactly one 64-byte beat
        (16 x 4 bytes = 64 bytes)."""
        self._run([b""] * 16)

    def test_many_short_strings(self):
        """128 three-byte strings to exercise sustained throughput across many
        beats of both the data and lengths output streams."""
        strings = [bytes([i % 256, (i * 3) % 256, (i * 7) % 256])
                   for i in range(128)]
        self._run(strings)

    def test_mixed_length_strings(self):
        """Mix of empty, single-byte, medium and long strings to exercise all
        FSM paths (A, B, C/D, E) in a single page."""
        self._run([
            b"",
            b"a",
            b"hello world",
            b"",
            b"the quick brown fox jumps over the lazy dog",
            b"z" * 70,
            b"short",
            b"",
        ])
