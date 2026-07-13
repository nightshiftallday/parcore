from coyote_test import fpga_test_case


def _page(length: int, seed: int) -> bytearray:
    """Distinguishable per-page content so mis-packing is visible in memory."""
    return bytearray((seed + i) & 0xFF for i in range(length))


class CrossPageNormalizerTest(fpga_test_case.FPGATestCase):
    """
    CrossPageNormalizer packs a per-page byte stream into dense beats across page
    boundaries. Each page is driven as a separate input transfer (its own last);
    only the final page's last ends the chunk. The normalized output written to
    memory must equal the concatenation of all page bytes.
    """

    alternative_vfpga_top_file = "vfpga_tops/cross_page_normalizer_test.sv"
    debug_mode = True

    def _run(self, pages: list[bytearray]):
        self.set_system_verilog_defines({"CPN_NUM_PAGES": str(len(pages))})
        for p in pages:
            self.set_stream_input(0, p)
        expected = bytearray()
        for p in pages:
            expected += p
        self.set_expected_output(0, expected)
        self.simulate_fpga()
        self.assert_simulation_output()

    def test_single_full_beats(self):
        # One page, exact multiple of the 64-byte beat: pure pass-through.
        self._run([_page(256, 0)])

    def test_single_partial(self):
        # One page ending on a partial beat (200 % 64 != 0).
        self._run([_page(200, 7)])

    def test_two_pages_partial(self):
        # Page 0 ends mid-beat (80 = 64 + 16); page 1's bytes must pack into the
        # leftover 48 bytes of that beat.
        self._run([_page(80, 1), _page(80, 100)])

    def test_three_pages_partial(self):
        self._run([_page(80, 1), _page(48, 90), _page(100, 200)])

    def test_mixed_full_and_partial(self):
        # A full-beat page between two partial ones.
        self._run([_page(70, 3), _page(128, 40), _page(30, 130)])

    def test_many_small_pages(self):
        self._run([_page(20, i * 10) for i in range(1, 8)])

    def test_more_pages_than_flag_fifo(self):
        # 12 pages exceed the 8-deep per-page flag FIFO, exercising its
        # backpressure and refill while pages keep streaming.
        self._run([_page(30 + 7 * i, i * 17) for i in range(12)])
