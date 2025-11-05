from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join
from random import randint

def read_data(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        data = bytearray(f.read())

    return data

def custom_page_header(data: bytearray, size: int) -> bytearray:
    skip = int.from_bytes(data[:4], 'little')
    bit_width = data[skip+4]
    data = data[skip+5:]

    new_header = bytearray(size+5)
    new_header[0:4] = size.to_bytes(4, 'little')
    new_header[size+4] = bit_width.to_bytes(1, 'little')[0]
    return new_header + data

@dataclass
class _TestCase:
    inputs: list[bytearray]
    outputs: list[list[int]]

_rle_input = read_data('rle_data_rg0_col0_chunk_decompressed.bin')
_rle_output =  [i-10 for i in range(10, 20) for _ in range(i)]

_bpe_input = read_data('bpe_data_rg0_col0_chunk_decompressed.bin')
_bpe_output = list(range(10-10, 20-10)) * 15

_test_cases = (
    _TestCase(
        inputs=[_rle_input],
        outputs=[_rle_output],
    ),
    _TestCase(
        inputs=[custom_page_header(_rle_input, 75)],
        outputs=[_rle_output],
    ),
    _TestCase(
        inputs=[custom_page_header(_rle_input, 64+59)],
        outputs=[_rle_output],
    ),
    _TestCase(
        inputs=[_rle_input, _bpe_input],
        outputs=[_rle_output, _bpe_output],
    ),
    _TestCase(
        inputs=[_rle_input, _bpe_input, read_data('mixed_data_rg0_col0_chunk_decompressed.bin')],
        outputs=[_rle_output, _bpe_output,
                [i-10 for i in range(10, 20) for _ in range(i)] +
                list(range(128-118, 256-118)) * 2 +
                [i-10 for i in range(10, 20) for _ in range(i)] +
                list(range(128-118, 256-118)) * 2
        ]
    ),
)

class PageDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "page_decoder_test.sv"
    debug_mode = True
    # verbose_logging = True

    def test_one_rle_page(self):
        test_case = _test_cases[0]
        self.set_stream_input(0, test_case.inputs[0])
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, test_case.outputs[0]))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_custom_header_length(self):
        test_case = _test_cases[1]
        self.set_stream_input(0, test_case.inputs[0])
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, test_case.outputs[0]))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_tricky_header_length(self):
        test_case = _test_cases[2]
        self.set_stream_input(0, test_case.inputs[0])
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, test_case.outputs[0]))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_bpe_page(self):
        test_case = _test_cases[3]
        for lst in test_case.inputs:
            self.set_stream_input(0, lst)
        for lst in test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, lst))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_mixed_page(self):
        test_case = _test_cases[4]
        for lst in test_case.inputs:
            self.set_stream_input(0, lst)
        for lst in test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, lst))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
