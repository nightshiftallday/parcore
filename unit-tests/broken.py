from dataclasses import dataclass
from coyote_test import fpga_test_case, fpga_stream, fpga_register
from enum import Enum
from os.path import dirname, realpath, join

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

def read_data_decompressed_no_dict(filename: str, num_values: int) -> _Data:
    return _Data(
        dictionary=None,
        hybrid=read_bytes(filename + '_chunk_decompressed.bin'),
        num_values=num_values,
        compression=False, plain=False,
    )

@dataclass
class _TestCase:
    inputs: list[_Data]
    outputs: list[list[int]]

_first_output =  list(range(16, 32)) * (2**6)
_first_input = read_data('broken/first_rg0_col0', len(_first_output))

_second_output =  list(range(16, 32)) * (2**7)
_second_input = read_data('broken/second_rg0_col0', len(_second_output))

_third_output =  list(range(16, 32)) * (2**7)
_third_input = read_data_decompressed_no_dict('broken/third_rg0_col0', len(_third_output))

class TopHostTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "page_decoder_test.sv"
    debug_mode = True
    verbose_logging = True

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

    def test_first(self):
        # Arrange
        self.test_case = _TestCase(
            inputs=[_first_input],
            outputs=[_first_output],
        )

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_second(self):
        # Arrange
        self.test_case = _TestCase(
            inputs=[_second_input],
            outputs=[_second_output],
        )

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()

    def test_third(self):
        # Arrange
        self.test_case = _TestCase(
            inputs=[_third_input],
            outputs=[_third_output],
        )

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
