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

def read_data(filename: str, num_values: int) -> _ColumnChunk:
    files = [(filename + '_dict_compressed.bin', _PageType.DICT), (filename + '_chunk_compressed.bin', _PageType.HYBRID)]
    pages = [read_page(file, pt, num_values) for file, pt in files]
    pages[-1].last = True

    return _ColumnChunk(compression=True, num_values=num_values, hybrid_num_values=num_values, pages=pages)

def read_data_decompressed(filename: str, num_values: int) -> _ColumnChunk:
    files = [(filename + '_dict_decompressed.bin', _PageType.DICT), (filename + '_chunk_decompressed.bin', _PageType.HYBRID)]
    pages = [read_page(file, pt, num_values) for file, pt in files]
    pages[-1].last = True

    return _ColumnChunk(compression=False, num_values=num_values, hybrid_num_values=num_values, pages=pages)

def plain_page(items: list[int]) -> _Page:
    stream = fpga_stream.Stream(fpga_stream.StreamType.SIGNED_INT_64, items)
    data = stream.data_to_bytearray()
    return _Page(page_type=_PageType.PLAIN, data=data, num_values=len(items), last=True)

def make_plain_data(items: list[int]) -> _ColumnChunk:
    page = plain_page(items)
    page.last = True
    num_values = len(items)
    return _ColumnChunk(compression=False, num_values=num_values, hybrid_num_values=num_values, pages=[page])

def make_tricky(filename: str, num_values: int, items: list[int], factor: int) -> _ColumnChunk:
    files = [(filename + '_dict_decompressed.bin', _PageType.DICT)] + [(filename + '_chunk_decompressed.bin', _PageType.HYBRID)] * factor
    pages = [read_page(file, pt, num_values) for file, pt in files]
    pp = plain_page(items)
    pp.last = True
    pages.append(pp)

    return _ColumnChunk(compression=False, num_values=num_values * factor + len(items), hybrid_num_values=num_values * factor, pages=pages)

@dataclass
class _TestCase:
    inputs: list[_ColumnChunk]
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

_tricky_factor = 3
_tricky_output_plain = list(range(0,256))
_tricky_output = _rle_output * _tricky_factor + list(range(0,256))
_tricky_input= make_tricky('rle_data_rg0_col0', len(_rle_output), _tricky_output_plain, _tricky_factor)

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
    ),
    _TestCase(
        inputs=[_tricky_input, _rle_input],
        outputs=[_tricky_output, _rle_output],
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

    def test_tricky_page(self):
        # Arrange
        self.test_case = (_test_cases[8])

        # Act
        self.simulate_fpga()

        # Assert
        self.assert_simulation_output()
