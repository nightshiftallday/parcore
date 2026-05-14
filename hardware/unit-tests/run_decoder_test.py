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
    inputs: list[bytearray]
    outputs: list[list[int]]

_test_cases = (
    _TestCase(
        inputs=[read_data('rle_data_rg0_col0_chunk_decompressed.bin')],
        outputs=[[i-10] * i for i in range(10, 20)],
    ),
    _TestCase(
        inputs=[
            read_data('rle_data_rg0_col0_chunk_decompressed.bin'),
            read_data('bpe_data_rg0_col0_chunk_decompressed.bin')
        ],
        outputs=[[i-10] * i for i in range(10, 20)]
                + [list(range(10-10, 20-10)) * 15],
    ),
    _TestCase(
        inputs=[
            read_data('rle_data_rg0_col0_chunk_decompressed.bin'),
            read_data('bpe_data_rg0_col0_chunk_decompressed.bin'),
            read_data('mixed_data_rg0_col0_chunk_decompressed.bin')
        ],
        outputs=[[i-10] * i for i in range(10, 20)]
                + [list(range(10-10, 20-10)) * 15]
                # the run_decoder module will be reset at this point after producing
                # 145+150 values, and will load the next configuration for the mixed
                # data input.
                + [[i-10] * i for i in range(10, 20)]
                + [list(range(128-118, 256-118)) * 2]
                + [[i-10] * i for i in range(10, 20)]
                + [list(range(128-118, 256-118)) * 2]
        ,
    ),
)

class RunDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "vfpga_tops/run_decoder_test.sv"
    debug_mode = True
    # verbose_logging = True

    def test_one_rle_strip(self):
        test_case = _test_cases[0]
        self.set_stream_input(0, test_case.inputs[0])
        for lst in test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, lst))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_bpe_strip(self):
        test_case = _test_cases[1]
        for byt in test_case.inputs:
            self.set_stream_input(0, byt)
        for lst in test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, lst))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_mixed_strips(self):
        test_case = _test_cases[2]
        for byt in test_case.inputs:
            self.set_stream_input(0, byt)

        for lst in test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, lst))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
