from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join
from random import randint

def read_data(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        data = bytearray(f.read())

    return data

class DecompressorOriginalTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "decompressor_test_original.sv"
    debug_mode = True
    # verbose_logging = True

    def test_original_three_compression_decompress(self):
        n = 1024
        data = [randint(-n, n) for _ in range(n)]
        data_type = fpga_stream.StreamType.SIGNED_INT_32
        raw_data = fpga_stream.Stream(data_type, data)

        compressed_data = read_data('data_rg0_col0_chunk_compressed.bin')
        self.set_stream_input(0, compressed_data)
        self.set_stream_input(0, compressed_data)
        self.set_stream_input(0, compressed_data)
        # self.set_stream_input(0, raw_data)
        decompressed_data = read_data('data_rg0_col0_chunk_decompressed.bin')
        self.set_expected_output(0, decompressed_data)
        self.set_expected_output(0, decompressed_data)
        self.set_expected_output(0, decompressed_data)
        # self.set_expected_output(0, raw_data)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
