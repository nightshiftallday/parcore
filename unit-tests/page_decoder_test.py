from dataclasses import dataclass
from enum import Enum
from coyote_test import fpga_test_case, fpga_stream, fpga_register
from os.path import dirname, realpath, join
import pickle

class _PageType(Enum):
    HYBRID = 0
    DICT = 1
    PLAIN = 2

@dataclass
class _Data:
    compression: bool
    dictionary: bytearray | None
    hybrid: bytearray
    num_values: int
    plain: bool

    def _registers(self, page_type: _PageType) -> list[bytearray]:
        return [
            bytearray(int(1 if self.compression else 0).to_bytes(1, 'big')), # compression_t
            bytearray(page_type.value.to_bytes(1, 'big')), # page_t
            bytearray(self.num_values.to_bytes(4, 'little')), # num_values
            bytearray(int(2).to_bytes(1, 'big')), # type_t = int64_t
        ]

    def registers(self) -> list[list[bytearray]]:
        if self.dictionary is not None:
            first = self._registers(_PageType.DICT)
        second = self._registers(_PageType.PLAIN if self.plain else _PageType.HYBRID)

        if self.dictionary is not None:
            return [first, second]
        return [second]

    def data(self) -> list[bytearray]:
        if self.dictionary is not None:
            return [self.dictionary, self.hybrid]
        return  [self.hybrid]

def read_bytes(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        return bytearray(f.read())

def read_data(filename: str, num_values: int) -> _Data:
    files = [filename + '_dict_compressed.bin', filename + '_chunk_compressed.bin']
    data = [read_bytes(file) for file in files]

    return _Data(dictionary=data[0], hybrid=data[1], num_values=num_values, compression=True, plain=False)

def read_data_decompressed(filename: str, num_values: int) -> _Data:
    files = [filename + '_dict_decompressed.bin', filename + '_chunk_decompressed.bin']
    data = [read_bytes(file) for file in files]

    return _Data(dictionary=data[0], hybrid=data[1], num_values=num_values, compression=False, plain=False)

def make_plain_data(items: list[int]) -> _Data:
    stream = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, items)
    return _Data(dictionary=None, hybrid=stream.data_to_bytearray(), num_values=len(items), compression=False, plain=True)

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

# NOTE: This test output is trimmed significantly (should be about 1M values)
# because the simulation doesn't run for long enough to produce all values
_huge_output = pickle.loads(read_bytes('huge_rg0_col0_result.pkl'))[:6408]
_huge_input = read_data('huge_rg0_col0', len(_huge_output))

_huge_two_output = ([4294967296] * 64) + ([6975757441] * 896) + ([11019960576] * 960) + \
    ([16983563041] * 1024) + [k for n in range(128, 137) for k in [n] * 32]
_huge_two_input = read_data_decompressed('test', len(_huge_two_output))

_mixed_output_plain = list(range(0,256))
_mixed_input_plain = make_plain_data(_mixed_output_plain)

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
    ),
    _TestCase(
        inputs=[_huge_input],
        outputs=[_huge_output],
    ),
    _TestCase(
        inputs=[_huge_two_input],
        outputs=[_huge_two_output],
    ),
    _TestCase(
        inputs=[_mixed_input_plain],
        outputs=[_mixed_output_plain],
    )
)

class TopHostTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "page_decoder_test.sv"
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
        assert self.test_case is not None, (
            "Cannot have host test with empty test case!"
        )

        for input in self.test_case.inputs:
            for register_set in input.registers():
                for i, value in enumerate(register_set):
                    # Configuration (offset of 3 because of GlobalConfig)
                    self.write_register(fpga_register.vFPGARegister(3 + i, value))

        # Set the input data
        for input in (data for i in self.test_case.inputs for data in i.data()):
            self.set_stream_input(0, input)

        # Set the expected output data
        for output in self.test_case.outputs:
            self.set_expected_output(0, fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, output))

        return super().simulate_fpga()

    def test_one_rle_page(self):
        # Arrange
        self.test_case= _test_cases[0]

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_bpe_page(self):
        # Arrange
        self.test_case = (_test_cases[1])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_mixed_page(self):
        # Arrange
        self.test_case = (_test_cases[2])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_one_big_bpe_pages(self):
        # Arrange
        self.test_case = (_test_cases[3])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_all_pages(self):
        # Arrange
        self.test_case = (_test_cases[4])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_plain_page(self):
        # Arrange
        self.test_case = (_test_cases[7])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    # def test_one_huge_page(self):
    #     # Arrange
    #     self.test_case = (_test_cases[5])
    #
    #     # Act
    #     self.simulate_fpga()
    #
    #     # Assert
    #     self.assert_simulation_output()
    #
    # def test_huge_two_page(self):
    #     # Arrange
    #     self.test_case = (_test_cases[6])
    #
    #     # Act
    #     self.simulate_fpga()
    #
    #     # Assert
    #     self.assert_simulation_output()
