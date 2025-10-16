from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join

def read_data(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        data = bytearray(f.read())

    return data

class DecompressorTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "decompressor_test.sv"
    debug_mode = True
    verbose_logging = True

    # Method that gets executed once per test case
    def setUp(self):
        return super().setUp()
    
    # Overwrite of the parent classes simulation method.
    # Can be used to implement common behavior between tests
    def simulate_fpga(self):
        return super().simulate_fpga()

    # Example test case, following the AAA-pattern.
    # The test case shows all the methods needed to 
    # define tests and invoke the simulation.
    def test_one_page_decompress(self):
        n = 1024
        compressed_data = read_data('rg0_col0_chunk_compressed.bin')
        self.set_stream_input(0, compressed_data)
        decompressed_data = read_data('rg0_col0_chunk_decompressed.bin')
        self.set_expected_output(0, decompressed_data)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
