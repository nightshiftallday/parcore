from dataclasses import dataclass
from enum import Enum
from coyote_test import fpga_test_case, fpga_stream, fpga_register, simulation_time
from os.path import dirname, realpath, join
import pickle

class _PageType(Enum):
    HYBRID = 0
    DICT = 1
    PLAIN = 2

@dataclass
class _Page:
    page_type: _PageType
    data: bytearray
    num_values: int
    last: bool

    def registers(self) -> dict[int, bytearray]:
        offset = 4
        return {
            offset+0: bytearray(self.page_type.value.to_bytes(1, 'big')), # page_t
            offset+1: bytearray(self.num_values.to_bytes(4, 'little')), # num_values
            offset+2: bytearray((1 if self.last else 0).to_bytes(1, 'big')), # last
        }

@dataclass
class _ColumnChunk:
    compression: bool
    num_values: int
    hybrid_num_values: int
    pages: list[_Page]

    def _registers(self) -> dict[int, bytearray]:
        return {
            0: bytearray(int(1 if self.compression else 0).to_bytes(1, 'big')), # compression_t
            1: bytearray(self.num_values.to_bytes(4, 'little')), # num_values
            2: bytearray(self.hybrid_num_values.to_bytes(4, 'little')), # hybrid_num_values
            3: bytearray(int(2).to_bytes(1, 'big')), # type_t = int64_t
        }

    def registers(self) -> list[dict[int, bytearray]]:
        result = [self._registers()]

        for page in self.pages:
            result.append(page.registers())

        return result

    def data(self) -> list[bytearray]:
        return [page.data for page in self.pages]

def read_bytes(filename: str) -> bytearray:
    dir = dirname(realpath(__file__))
    with open(join(dir, 'data', filename), 'rb') as f:
        return bytearray(f.read())

def read_page(filename: str, page_type: _PageType, num_values: int) -> _Page:
    bytes = read_bytes(filename)
    return _Page(page_type=page_type, data=bytes, num_values=num_values, last=False)

def plain_page(items: list[int]) -> _Page:
    stream = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, items)
    data = stream.data_to_bytearray()
    return _Page(page_type=_PageType.PLAIN, data=data, num_values=len(items), last=True)

def read_data(filename: str, num_values: int) -> _ColumnChunk:
    files = [(filename + '_dict_compressed.bin', _PageType.DICT), (filename + '_chunk_compressed.bin', _PageType.HYBRID)]
    pages = [read_page(file, pt, num_values) for file, pt in files]
    pages[-1].last = True

    return _ColumnChunk(compression=True, num_values=num_values, hybrid_num_values=num_values, pages=pages)

def read_data_compressed_no_dict(filename: str, num_values: int) -> _ColumnChunk:
    dict_page = read_page('broken/first_rg0_col0_dict_compressed.bin', _PageType.DICT, 0) # get some random dictionary

    data_page = read_page(filename, _PageType.HYBRID, num_values)
    data_page.last = True
    return _ColumnChunk(compression=True, num_values=num_values, hybrid_num_values=num_values, pages=[dict_page, data_page])

@dataclass
class _TestCase:
    inputs: list[_ColumnChunk]
    outputs: list[list[int]]

_first_output =  list(range(16, 32)) * (2**6)
_first_input = read_data('broken/first_rg0_col0', len(_first_output))

_second_output =  list(range(16, 32)) * (2**7)
_second_input = read_data('broken/second_rg0_col0', len(_second_output))

_third_output =  [1] * 59392
_third_input = read_data_compressed_no_dict('broken/third_data.bin', 59392)

class TopHostTestCase(fpga_test_case.FPGATestCase):
    alternative_vfpga_top_file = "vfpga_tops/page_decoder_test.sv"
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

        self.overwrite_simulation_time(simulation_time.SimulationTime.till_finished())

        for input in self.test_case.inputs:
            for register_set in input.registers():
                for i, value in register_set.items():
                    # Configuration (offset of 3 because of GlobalConfig)
                    self.write_register(fpga_register.vFPGARegister(4 + i, value))

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
