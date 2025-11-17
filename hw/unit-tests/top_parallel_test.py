from dataclasses import dataclass
from coyote_test import fpga_stream, constants
from os.path import dirname, realpath, join
from utils.output_writer_test_case import OutputWriterTestCase
from utils.memory_manager import FPGAOutputMemoryManager

MAX_NUMBER_STREAMS = constants.MAX_NUMBER_STREAMS
TRANSFER_SIZE_BYTES_OVERWRITE = "TRANSFER_SIZE_BYTES_OVERWRITE"


@dataclass
class _Data:
    dictionary: bytearray
    hybrid: bytearray
    num_values: int

    def _cmd(self, vaddr: int, len: int, page_type: int) -> bytearray:
        b = bytearray([0] * 64)

        b[-23] = page_type.to_bytes(1, 'big')[0] # page_t
        b[-22] = int(2).to_bytes(1, 'big')[0] # type_t = INT64_T

        if page_type == 0: # hybrid
            b[-21:-17] = self.num_values.to_bytes(4, 'little')
        # otherwise we can leave 0, it's ignored

        b[-17] = int(1).to_bytes(1, 'big')[0] # compression_t =  SNAPPY

        b[-16:-8] = len.to_bytes(8, 'little')
       
        # b[56-64:64] = vaddr.to_bytes(8, 'little')
        b[-8:] = vaddr.to_bytes(8, 'little')

        return b

    def cmd(self, memory_offset: int) -> bytearray:
        first = self._cmd(memory_offset, len(self.dictionary), 1)
        second = self._cmd(memory_offset + len(self.dictionary), len(self.hybrid), 0)
        return first + second

    def data(self) -> bytearray:
        return self.dictionary[:] + self.hybrid[:]

def read_data(filename: str, num_values: int) -> _Data:
    files = [filename + '_dict_compressed.bin', filename + '_chunk_compressed.bin']
    data: list[bytearray] = []
    for filename in files:
        dir = dirname(realpath(__file__))
        with open(join(dir, 'data', filename), 'rb') as f:
            data.append(bytearray(f.read()))

    return _Data(dictionary=data[0], hybrid=data[1], num_values=num_values)

@dataclass
class _TestCase:
    inputs: list[_Data]
    outputs: list[list[int]]

_mixed_output = ([i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2 +
                [i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2)
_mixed_input = read_data('mixed_data_rg0_col0', len(_mixed_output))

_test_case = _TestCase(
    inputs=[_mixed_input],
    outputs=[_mixed_output],
)

class TopTestCase(OutputWriterTestCase):
    alternative_vfpga_top_file = "top_parallel_test.sv"
    debug_mode = True
    # verbose_logging = True

    def setUp(self):
        super().setUp()
        # All data in this test is streamed through.
        # There is no actual computation happening
        # (due to the way the wiring is done)
        self.streams: list[fpga_stream.Stream] = []

    def simulate_fpga(self):
        super().simulate_fpga()

    def overwrite_memory_manager(self, allocation_size: int, transfer_size: int):
        """
        Overwrites the existing memory manager to have the new transfer & allocation size.
        Also sets those values for the simulation
        """
        self.memory_manager = FPGAOutputMemoryManager(
            self.get_io_writer(), 0, allocation_size, transfer_size
        )
        self.set_system_verilog_defines(
            {TRANSFER_SIZE_BYTES_OVERWRITE: str(transfer_size)}
        )

    # buffers are a list of (len, vaddr)
    def _setup_test(self, test_case: _TestCase) -> None:
        allocation_size = 512
        transfer_size = 128
        self.overwrite_memory_manager(allocation_size, transfer_size)

        offset = 0
        for input in test_case.inputs:
            data = input.data()
            self.remote_rdma_write(offset, data)

            cmd = input.cmd(offset)
            self.set_stream_input(0, cmd)
            offset += len(data)

        for output in test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, output))
        
    def test_one_mixed_page(self):
        # Arrange
        self._setup_test(_test_case)

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
