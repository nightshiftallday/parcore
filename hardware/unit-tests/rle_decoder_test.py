from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join
from random import randint

@dataclass
class _TestCase:
    element: int
    count: int

    @property
    def data(self) -> list[int]:
        return [self.element] * self.count

_test_cases = (
    _TestCase(element=1024, count=64),
    _TestCase(element=1337, count=7),
    _TestCase(element=11, count=54),
    _TestCase(element=98412, count=127),
)

class RLEDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "rle_decoder_test.sv"
    debug_mode = True
    # verbose_logging = True

    def test_one_rle_decoding(self):
        decoded = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, _test_cases[0].data)
        self.set_expected_output(0, decoded)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_two_rle_decoding(self):
        decoded1 = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, _test_cases[0].data)
        decoded2 = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, _test_cases[1].data)
        self.set_expected_output(0, decoded1)
        self.set_expected_output(0, decoded2)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_many_rle_decoding(self):
        for i in range(24):
            decoded = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, _test_cases[i % len(_test_cases)].data)
            self.set_expected_output(0, decoded)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
