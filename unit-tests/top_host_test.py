from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream
from os.path import dirname, realpath, join

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

    def data(self) -> list[bytearray]:
        return [self.dictionary, self.hybrid]

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

_rle_output =  [i for i in range(10, 20) for _ in range(i)]
_rle_input = read_data('rle_data_rg0_col0', len(_rle_output))

_bpe_output = list(range(10, 20)) * 15
_bpe_input = read_data('bpe_data_rg0_col0', len(_bpe_output))

_mixed_output = ([i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2 +
                [i**8 for i in range(10, 20) for _ in range(i)] +
                list(range(128, 256)) * 2)
_mixed_input = read_data('mixed_data_rg0_col0', len(_mixed_output))

_big_bpe_output = list(range(10, 100)) * 5
_big_bpe_input = read_data('big_bpe_data_rg0_col0', len(_big_bpe_output))

_test_cases = (
    _TestCase(
        inputs=[_rle_input],
        outputs=[_rle_output],
    ),
    _TestCase(
        inputs=[_bpe_input],
        outputs=[_bpe_output],
    ),
    _TestCase(
        inputs=[_mixed_input],
        outputs=[_mixed_output],
    ),
    _TestCase(
        inputs=[_big_bpe_input],
        outputs=[_big_bpe_output],
    ),
    _TestCase(
        inputs=[_rle_input, _bpe_input, _mixed_input, _big_bpe_input],
        outputs=[_rle_output, _bpe_output, _mixed_output, _big_bpe_output],
    )
)

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
        

    def test_one_rle_page(self):
        # Arrange
        self._setup_test(_test_cases[0])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_bpe_page(self):
        # Arrange
        self._setup_test(_test_cases[1])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_mixed_page(self):
        # Arrange
        self._setup_test(_test_cases[2])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_big_bpe_pages(self):
        # Arrange
        self._setup_test(_test_cases[3])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_all_pages(self):
        # Arrange
        self._setup_test(_test_cases[4])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
