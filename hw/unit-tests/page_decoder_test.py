from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join

@dataclass
class _Data:
    dictionary: bytearray
    hybrid: bytearray

def read_data(filename: str) -> _Data:
    files = [filename + '_dict_compressed.bin', filename + '_chunk_compressed.bin']
    data: list[bytearray] = []
    for filename in files:
        dir = dirname(realpath(__file__))
        with open(join(dir, 'data', filename), 'rb') as f:
            data.append(bytearray(f.read()))

    return _Data(dictionary=data[0], hybrid=data[1])

@dataclass
class _TestCase:
    inputs: list[_Data]
    outputs: list[list[int]]

_rle_input = read_data('rle_data_rg0_col0')
_rle_output =  [i for i in range(10, 20) for _ in range(i)]

_bpe_input = read_data('bpe_data_rg0_col0')
_bpe_output = list(range(10, 20)) * 15

_test_cases = (
    _TestCase(
        inputs=[_rle_input],
        outputs=[_rle_output],
    ),
    _TestCase(
        inputs=[_bpe_input],
        outputs=[_bpe_output],
    ),
    # _TestCase(
    #     inputs=[custom_page_header(_rle_input, 64+59)],
    #     outputs=[_rle_output],
    # ),
    # _TestCase(
    #     inputs=[_rle_input, _bpe_input],
    #     outputs=[_rle_output, _bpe_output],
    # ),
    # _TestCase(
    #     inputs=[_rle_input, _bpe_input, read_data('mixed_data_rg0_col0_chunk_decompressed.bin')],
    #     outputs=[_rle_output, _bpe_output,
    #             [i-10 for i in range(10, 20) for _ in range(i)] +
    #             list(range(128-118, 256-118)) * 2 +
    #             [i-10 for i in range(10, 20) for _ in range(i)] +
    #             list(range(128-118, 256-118)) * 2
    #     ]
    # ),
)

class PageDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "page_decoder_test.sv"
    debug_mode = True
    # verbose_logging = True

    def test_one_rle_page(self):
        test_case = _test_cases[0]
        self.set_stream_input(0, test_case.inputs[0].dictionary)
        self.set_stream_input(0, test_case.inputs[0].hybrid)
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, test_case.outputs[0]))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_bpe_page(self):
        test_case = _test_cases[1]
        self.set_stream_input(0, test_case.inputs[0].dictionary)
        self.set_stream_input(0, test_case.inputs[0].hybrid)
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, test_case.outputs[0]))

        test_case = _test_cases[0]
        self.set_stream_input(0, test_case.inputs[0].dictionary)
        self.set_stream_input(0, test_case.inputs[0].hybrid)
        self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, test_case.outputs[0]))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
