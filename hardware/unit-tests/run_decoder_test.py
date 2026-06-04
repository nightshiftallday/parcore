from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream, fpga_register
from os.path import dirname, realpath, join


def read_data(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        return bytearray(f.read())


@dataclass
class _RunDecoderConfig:
    """One RunDecoder page configuration (RunDecoderConfig registers).

    The fixtures store a decompressed page as
        def_levels_length (4 bytes LE) | def_levels | bit_width (1 byte) | body
    so the RLE/BPE body starts at byte `offset` (4 + len(def_levels) + 1).
    """
    bit_width: int
    offset: int
    num_values: int

    def _registers(self) -> dict[int, bytearray]:
        return {
            3: bytearray(self.bit_width.to_bytes(4, 'little')),  # bit_width_t
            4: bytearray(self.offset.to_bytes(4, 'little')),     # offset_t
            5: bytearray(self.num_values.to_bytes(4, 'little')), # num_values
        }


class RunDecoderTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "vfpga_tops/run_decoder_test.sv"
    debug_mode = True

    def run_page(self, config: _RunDecoderConfig, chunk: bytearray, output: list[int]):
        """Drive the RunDecoder with a single configured page and assert its output.

        Page configuration is written to the RunDecoderConfig registers, the
        page bytes are streamed in, and the expected output is asserted.
        """
        for reg, value in config._registers().items():
            self.write_register(fpga_register.vFPGARegister(reg, value))

        self.set_stream_input(0, chunk)
        self.set_expected_output(
            0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_32, output)
        )

        self.simulate_fpga()
        self.assert_simulation_output()

    # Each fixture's def_levels length prefix is 3 bytes, so the body starts at
    # offset 8 (4-byte prefix + 3 def_levels + 1 bit_width byte).
    def test_one_rle_page(self):
        self.run_page(
            _RunDecoderConfig(bit_width=4, offset=8, num_values=145),
            read_data('rle_data_rg0_col0_chunk_decompressed.bin'),
            [v for i in range(10, 20) for v in [i - 10] * i],
        )

    def test_one_bpe_page(self):
        self.run_page(
            _RunDecoderConfig(bit_width=4, offset=8, num_values=150),
            read_data('bpe_data_rg0_col0_chunk_decompressed.bin'),
            list(range(10 - 10, 20 - 10)) * 15,
        )

    def test_mixed_page(self):
        self.run_page(
            _RunDecoderConfig(bit_width=8, offset=8, num_values=802),
            read_data('mixed_data_rg0_col0_chunk_decompressed.bin'),
            ([v for i in range(10, 20) for v in [i - 10] * i]
             + list(range(128 - 118, 256 - 118)) * 2) * 2,
        )

    def test_back_to_back_bpe(self):
        # Two BPE runs of 256 values (bit_width=8). The first run is long enough
        # to wrap the RunDecoder's 64-byte double-buffer and then finishes into
        # the second run, exercising finish_bpe()'s offset-wrap handling.
        vals1 = [i % 200 for i in range(256)]
        vals2 = [(i * 3) % 200 for i in range(256)]
        self.run_page(
            _RunDecoderConfig(bit_width=8, offset=8, num_values=512),
            read_data('back_to_back_bpe_chunk_decompressed.bin'),
            vals1 + vals2,
        )
