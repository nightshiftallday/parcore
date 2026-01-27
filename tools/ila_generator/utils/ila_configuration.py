from abc import ABC, abstractmethod
from tools.ila_generator.utils.token import Token
from typing import List, Iterator
from tools.ila_generator.utils.matching import *


class Probe():
    def __init__(self, name: str, bit_width: int, definition_code: List[str]):
        self.name = name
        self.definition_code = definition_code
        self.bit_width = bit_width
    
    def get_bit_width(self):
        return self.bit_width

    def get_signal_name(self):
        return self.name
    
    def get_code(self):
        return self.definition_code
    
class ProbeWithLogicRedefinition(Probe):
    def __init__(self, source_signal_name, new_signal_name, bit_width):
        logic_size = ""
        if bit_width > 1:
            logic_size = f"[{bit_width - 1}:0]"

        new_signal = f"logic {logic_size} {new_signal_name};"
        assign = f"assign {new_signal_name} = {source_signal_name};"
        super().__init__(
            new_signal_name,
            bit_width,
            "\n".join([new_signal, assign])
        )

class ILAConfiguration(ABC):

    @staticmethod
    @abstractmethod
    def try_parse(tokens: Iterator[Token]) -> 'ILAConfiguration':
        """
        Returns a `ILAConfiguration` if the given tokens could be parsed
        and None otherwise
        """
        pass

    @abstractmethod
    def generate_probe_definitions(self) -> List[Probe]:
        """
        Returns a list of all additional definitions that 
        are needed to get the probes working.
        E.g. Array elements need to be re-assigned to a standalone
             Logic array
        """
        pass
