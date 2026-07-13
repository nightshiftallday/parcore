from coyote_test import fpga_register
from libstf_utils.output_writer_test_case import OutputWriterTestCase

from column_chunk_decoder_test import (
    _german_views,
    _plain_string_body,
    make_string_plain_chunk,
)

_CCD_CONFIG_ID = 0x5c19f934407065bd


class VfpgaTopTest(OutputWriterTestCase):
    """
    End-to-end test of the product vfpga_top: a string chunk into decoder 0,
    whose values StreamWriter (interrupt id 0) and heap StreamWriter
    (interrupt id 1) share physical channel 0 through the PairedOutputWriter.
    Uses the real hardware/src/vfpga_top.svh (no alternative test top).
    """

    debug_mode = True
    verbose_logging = True

    def test_string_plain_chunk_end_to_end(self):
        heap_base = 0x40000
        strings = [b"hello", b"x" * 20, b"yo", b"abcdefghijklm", b"s"]
        views, _ = _german_views(strings, heap_base)
        heap = _plain_string_body(strings)  # raw page bytes, prefixes included
        chunk = make_string_plain_chunk([strings], heap_base)

        self.simulate_fpga_non_blocking()

        # Decoder 0's config registers are the first two of the
        # ColumnChunkDecoderConfig address space, discovered at runtime:
        # base = heap base address, base+1 = conf word (enqueues the config).
        conf_base = self.global_config.get_config_bounds(_CCD_CONFIG_ID)[0]
        heap_reg, conf_reg = chunk._registers()
        self.write_register(fpga_register.vFPGARegister(conf_base, heap_reg))
        self.write_register(fpga_register.vFPGARegister(conf_base + 1, conf_reg))

        self.set_stream_input(0, chunk.chunk_bytes)
        self.set_expected_output(0, views)
        self.set_expected_output(1, heap)

        self.finish_fpga_simulation()
        self.assert_simulation_output()
