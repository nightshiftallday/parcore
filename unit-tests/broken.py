from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join
import pickle

@dataclass
class _Data:
    compression: bool
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

        # compression_t = SNAPPY (1) or RAW (0)
        b[-17] = int(1 if self.compression else 0).to_bytes(1, 'big')[0] 

        b[-16:-8] = len.to_bytes(8, 'little')
       
        # b[56-64:64] = vaddr.to_bytes(8, 'little')
        b[-8:] = vaddr.to_bytes(8, 'little')

        return b

    def cmd(self, memory_offset: int) -> bytearray:
        first = self._cmd(memory_offset, len(self.dictionary), 1)
        second = self._cmd(memory_offset + len(self.dictionary), len(self.hybrid), 0)
        return first + second

    def data(self) -> list[bytearray]:
        return [self.dictionary, self.hybrid]

def read_bytes(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        return bytearray(f.read())

def read_data(filename: str, num_values: int) -> _Data:
    files = [filename + '_dict_compressed.bin', filename + '_chunk_compressed.bin']
    data = [read_bytes(file) for file in files]

    return _Data(dictionary=data[0], hybrid=data[1], num_values=num_values, compression=True)

def read_data_decompressed(filename: str, num_values: int) -> _Data:
    files = [filename + '_dict_decompressed.bin', filename + '_chunk_decompressed.bin']
    data = [read_bytes(file) for file in files]

    return _Data(dictionary=data[0], hybrid=data[1], num_values=num_values, compression=False)

@dataclass
class _TestCase:
    inputs: list[_Data]
    outputs: list[list[int]]

_first_output =  list(range(16, 32)) * (2**6)
_first_input = read_data('broken/first_rg0_col0', len(_first_output))

class TopHostTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "top_host_test.sv"
    debug_mode = True
    # verbose_logging = True

    def __init__(self, a) -> None:
        super().__init__(a)

    # Method that gets executed once per test case
    def setUp(self):
        return super().setUp()
    
    # Overwrite of the parent classes simulation method.
    # Can be used to implement common behavior between tests
    def simulate_fpga(self):
        return super().simulate_fpga()

    # buffers are a list of (len, vaddr)
    def _setup_test(self, test_case: _TestCase) -> None:
        offset = 0
        for input in test_case.inputs:
            for data in input.data():
                self.set_stream_input(1, data)

            cmd = input.cmd(0)
            self.set_stream_input(0, cmd)
            offset += len(data)

        for output in test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, output))
        

    def test_first(self):
        # Arrange
        self._setup_test(_TestCase(
            inputs=[_first_input],
            outputs=[_first_output],
        ))

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
