from typing import List
from unit_test.fpga_stream import Stream, StreamType
from libstf_utils.output_writer_test_case import OutputWriterTestCase
from libstf_utils.memory_manager import FPGAOutputMemoryManager

TRANSFER_SIZE_BYTES_OVERWRITE = "TRANSFER_SIZE_BYTES_OVERWRITE"


class StreamWriterPairTest(OutputWriterTestCase):
    """
    Two StreamWriters sharing one physical write channel (dest 0) via a
    StreamWriterPairArbiter. Stream 0 and stream 1 land in their own buffers
    (distinct interrupt stream ids) even though every transfer departs from
    axis_host_send[0].
    """

    alternative_vfpga_top_file = "vfpga_tops/stream_writer_pair_test.sv"
    debug_mode = True
    verbose_logging = True

    def setUp(self):
        super().setUp()
        # Data streams straight through the writers; no computation involved.
        self.streams: List[Stream] = []

    def simulate_fpga(self):
        assert len(self.streams) > 0, "Cannot perform output test with 0 streams"

        self.simulate_fpga_non_blocking()

        # Set input & output after the non-blocking start so the test case can
        # do configuration discovery for the buffer-handle registers.
        for id, stream in enumerate(self.streams):
            self.set_stream_input(id, stream)
            self.set_expected_output(id, stream)

        self.finish_fpga_simulation()

    def overwrite_memory_manager(self, allocation_size: int, transfer_size: int):
        self.memory_manager = FPGAOutputMemoryManager(
            self.get_io_writer(),
            self.global_config,
            allocation_size,
            transfer_size,
        )
        self.set_system_verilog_defines(
            {TRANSFER_SIZE_BYTES_OVERWRITE: str(transfer_size)}
        )

    def test_single_writer_only(self):
        # Only writer 0 carries data; writer 1 stays idle on the shared channel.
        self.overwrite_memory_manager(allocation_size=512, transfer_size=128)
        self.streams.append(Stream(StreamType.UNSIGNED_INT_64, list(range(0, 904 // 8))))

        self.simulate_fpga()
        self.assert_simulation_output()

    def test_both_writers_interleaved(self):
        # One-beat transfers force fine-grained interleaving of both writers'
        # requests and data on the shared channel.
        self.overwrite_memory_manager(allocation_size=256, transfer_size=64)
        for _ in range(2):
            self.streams.append(Stream(StreamType.UNSIGNED_INT_64, list(range(0, 2000 // 8))))

        self.simulate_fpga()
        self.assert_simulation_output()

    def test_multiple_transfers_per_allocation(self):
        self.overwrite_memory_manager(allocation_size=512, transfer_size=128)
        for _ in range(2):
            self.streams.append(Stream(StreamType.UNSIGNED_INT_64, list(range(0, 904 // 8))))

        self.simulate_fpga()
        self.assert_simulation_output()

    def test_unequal_lengths(self):
        # A long stream on writer 0 with a short partial-tail stream on
        # writer 1: writer 1 finishes early and writer 0 must keep flowing.
        self.overwrite_memory_manager(allocation_size=256, transfer_size=64)
        self.streams.append(Stream(StreamType.UNSIGNED_INT_64, list(range(0, 4000 // 8))))
        self.streams.append(Stream(StreamType.UNSIGNED_INT_64, list(range(0, 88 // 8))))

        self.simulate_fpga()
        self.assert_simulation_output()
