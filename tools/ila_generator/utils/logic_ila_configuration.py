
from abc import ABC, abstractmethod
from tools.ila_generator.utils.token import Token
from typing import List, Iterator
from tools.ila_generator.utils.matching import *
from tools.ila_generator.utils.ila_configuration import ILAConfiguration, Probe, ProbeWithLogicRedefinition

class LogicILAConfiguration(ILAConfiguration):

    def __init__(self):
        super().__init__()
        self.name = ""
        self.array = None

    def set_name(self, name):
        self.name = name

    def set_array(self, array: Array):
        self.array = array

    @staticmethod
    def try_parse(tokens: Iterator[Token]) -> ILAConfiguration:
        configuration = LogicILAConfiguration()
        array = Array()
        match_group = MatchGroup(
            OptionalMatchGroup(
                AnyOf(
                    InputDeclaration(),
                    OutputDeclaration()
                ),
                name="In- & Output declarations"
            ),
            Logic(),
            OptionalMatchGroup(array, name="Logic Array"),
            SymbolIdentifier(None, configuration.set_name),
            name = "Logic"
        )

        if match_group.number_of_matching_tokens(tokens) > 0:
            if array.get_dimensions() > 0:
                configuration.set_array(array)
            return configuration
    
        return None

    def generate_probes_for_interface_instance(self, source_signal_name, new_signal_name, bit_width: int) -> List[Probe]:
        return ProbeWithLogicRedefinition(
            f"{source_signal_name}",
            f"{new_signal_name}_probe",
            bit_width
        )
        
    def generate_probe_definitions(self) -> List[Probe]:
        if self.array == None:  
            return [self.generate_probes_for_interface_instance(self.name, self.name, 1)]
        
        # Go through all of the dimensions. But: Keep the last dimension
        # -> We probe a logic array directly instead of probing every single signal
        elements = [(self.name, self.name)]
        for dimension in range(0, self.array.get_dimensions() - 1):
            new_elements = []
            for element in range(0, self.array.get_size(dimension)):
                for (source_name, target_name) in elements:
                    new_elements.append((f"{source_name}[{element}]", f"{target_name}_{element}"))

            elements = new_elements

        probes = []
        # Generate all the probes!
        bit_width = self.array.get_size(self.array.get_dimensions() - 1)
        for (source, new_signal) in elements:
            probes.append(self.generate_probes_for_interface_instance(source, new_signal, bit_width))
        
        return probes
