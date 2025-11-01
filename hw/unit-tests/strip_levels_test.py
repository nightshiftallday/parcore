from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join
from random import randint

def read_data(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        data = bytearray(f.read())

    return data

@dataclass
class _TestCase:
    data: bytearray

    @property
    def input(self) -> bytearray:
        return self.data

    @property
    def output(self) -> bytearray:
        strip_len = int.from_bytes(self.data[0:4], 'little')
        return self.data[4+strip_len:]

_test_cases = (
    _TestCase(data=read_data('rle_data_rg0_col0_chunk_decompressed.bin')),
    _TestCase(data=read_data('bpe_data_rg0_col0_chunk_decompressed.bin')),
    _TestCase(data=read_data('data_rg0_col0_chunk_decompressed.bin')),
)

class StripLevelsTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "strip_levels_test.sv"
    debug_mode = True
    # verbose_logging = True

    def test_one_strip(self):
        test_case = _test_cases[0]
        self.set_stream_input(0, test_case.input)
        self.set_expected_output(0, test_case.output)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_two_strips(self):
        for i in (0,1):
            test_case = _test_cases[i]
            self.set_stream_input(0, test_case.input)
            self.set_expected_output(0, test_case.output)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_many_strips(self):
        for i in range(24):
            test_case = _test_cases[i % len(_test_cases)]
            self.set_stream_input(0, test_case.input)
            self.set_expected_output(0, test_case.output)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
