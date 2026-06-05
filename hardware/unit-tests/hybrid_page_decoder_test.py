from coyote_test import fpga_test_case, fpga_stream, fpga_register
from os.path import dirname, realpath, join


def read_data(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        return bytearray(f.read())


def custom_page_header(data: bytearray, size: int) -> bytearray:
    skip = int.from_bytes(data[:4], 'little')
    bit_width = data[skip+4]
    data = data[skip+5:]

    new_header = bytearray(size+5)
    new_header[0:4] = size.to_bytes(4, 'little')
    new_header[size+4] = bit_width.to_bytes(1, 'little')[0]
    return new_header + data


# Reference outputs shared across cases.
_RLE_OUTPUT = [i - 10 for i in range(10, 20) for _ in range(i)]
_BPE_OUTPUT = list(range(10 - 10, 20 - 10)) * 15

# Ensure the `custom_page_header` function is correct
_rle_input = read_data('rle_data_rg0_col0_chunk_decompressed.bin')
assert custom_page_header(_rle_input, 13) == custom_page_header(custom_page_header(_rle_input, 75), 13)


class HybridPageDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "vfpga_tops/hybrid_page_decoder_test.sv"
    debug_mode = True
    # verbose_logging = True

    def run_pages(self, inputs: list[bytearray], outputs: list[list[int]]):
        """Drive the decoder with one or more pages and assert their outputs.

        Each page is streamed in and its num_values is written to the
        per-page config register (offset 3); the expected outputs are asserted.
        """
        for input in inputs:
            self.set_stream_input(0, input)
        for output in outputs:
            self.set_expected_output(
                0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, output)
            )
            self.write_register(
                fpga_register.vFPGARegister(3, bytearray(len(output).to_bytes(8, 'little')))
            )

        self.simulate_fpga()
        self.assert_simulation_output()

    def test_one_rle_page(self):
        self.run_pages(
            [read_data('rle_data_rg0_col0_chunk_decompressed.bin')],
            [_RLE_OUTPUT],
        )

    def test_custom_header_length(self):
        self.run_pages(
            [custom_page_header(read_data('rle_data_rg0_col0_chunk_decompressed.bin'), 64 + 15)],
            [_RLE_OUTPUT],
        )

    def test_tricky_header_length(self):
        self.run_pages(
            [custom_page_header(read_data('rle_data_rg0_col0_chunk_decompressed.bin'), 64 + 59)],
            [_RLE_OUTPUT],
        )

    def test_rle_and_bpe_page(self):
        self.run_pages(
            [read_data('rle_data_rg0_col0_chunk_decompressed.bin'),
             read_data('bpe_data_rg0_col0_chunk_decompressed.bin')],
            [_RLE_OUTPUT, _BPE_OUTPUT],
        )

    def test_bpe_page_drain(self):
        # back_to_back_bpe holds two BPE runs of 256 values (bit_width=8), but
        # we configure num_values=257 so the decode stops partway through the
        # second run. The RunDecoder emits those 257 values and resets at the 
        # first data beat of the second run without consuming the rest of the 
        # page, so the page's input `last` has not been seen when num_values 
        # is exhausted.
        self.run_pages(
            [read_data('back_to_back_bpe_chunk_decompressed.bin'),
             read_data('rle_data_rg0_col0_chunk_decompressed.bin')],
            [[i % 200 for i in range(256)] + [0], _RLE_OUTPUT],
        )

    def test_mixed_pages(self):
        self.run_pages(
            [read_data('rle_data_rg0_col0_chunk_decompressed.bin'),
             read_data('bpe_data_rg0_col0_chunk_decompressed.bin'),
             read_data('mixed_data_rg0_col0_chunk_decompressed.bin')],
            [_RLE_OUTPUT, _BPE_OUTPUT,
             [i - 10 for i in range(10, 20) for _ in range(i)] +
             list(range(128 - 118, 256 - 118)) * 2 +
             [i - 10 for i in range(10, 20) for _ in range(i)] +
             list(range(128 - 118, 256 - 118)) * 2],
        )
