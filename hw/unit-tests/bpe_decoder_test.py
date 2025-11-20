from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join
from random import randint

def bitpack(values, bit_width) -> bytearray:
    bit_buffer = 0
    total_bits = 0
    out = bytearray()

    for v in values:
        # Mask value to bit_width bits
        v &= (1 << bit_width) - 1
        # Append bits to buffer (on the *low* side)
        bit_buffer |= v << total_bits
        total_bits += bit_width

        # Flush full bytes to output
        while total_bits >= 8:
            out.append(bit_buffer & 0xFF)
            bit_buffer >>= 8
            total_bits -= 8

    # Handle remaining bits (if any)
    if total_bits > 0:
        out.append(bit_buffer & 0xFF)

    return out

def pad_to_512_bits(bytearr, bit_width) -> bytearray:
    """Pad output so every 16 values produce exactly 512 bits"""
    group_bits = 16 * bit_width
    group_bytes = (group_bits + 7) // 8
    padded = bytearray()

    i = 0
    while i < len(bytearr):
        block = bytearr[i:i+group_bytes]
        padded.extend(block)
        # pad each block to 64 bytes
        if len(block) < 64:
            padded.extend(b'\x00' * (64 - len(block)))
        i += group_bytes

    return padded

@dataclass
class _TestCase:
    elements: list[int]
    bit_width: int

    @property
    def input(self) -> bytearray:
        assert len(self.elements) == 55
        assert self.bit_width == 7

        packed = bitpack(self.elements, self.bit_width)
        return pad_to_512_bits(packed, self.bit_width)

    @property
    def output(self) -> fpga_stream.Stream:
        return fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, self.elements)

_test_cases = (
    _TestCase(elements=list(range(55)), bit_width=7),
    _TestCase(elements=[randint(0, 32) for _ in range(55)], bit_width=7),
    _TestCase(elements=[randint(0, 64) for _ in range(55)], bit_width=7),
    _TestCase(elements=[randint(0, 128) for _ in range(55)], bit_width=7),
)

class BPEDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "bpe_decoder_test.sv"
    debug_mode = True
    # verbose_logging = True

    def test_one_bpe_decoding(self):
        self.set_stream_input(0, _test_cases[0].input)
        self.set_expected_output(0, _test_cases[0].output)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_two_bpe_decoding(self):
        for test_case in _test_cases[:2]:
            self.set_stream_input(0, test_case.input)
            self.set_expected_output(0, test_case.output)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_three_bpe_decoding(self):
        for test_case in _test_cases[:3]:
            self.set_stream_input(0, test_case.input)
            self.set_expected_output(0, test_case.output)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_many_bpe_decoding(self):
        for test_case in _test_cases:
            self.set_stream_input(0, test_case.input)
            self.set_expected_output(0, test_case.output)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
