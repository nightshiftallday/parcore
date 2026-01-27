from abc import ABC, abstractmethod
from tools.ila_generator.utils.token import Token
from typing import List, Dict
from tools.ila_generator.utils.matching import *
from tools.ila_generator.utils.ila_configuration import ILAConfiguration, Probe, ProbeWithLogicRedefinition

class AxiILAConfiguration(ILAConfiguration):
    
    def __init__(self):
        super().__init__()
        self.name = ""
        self.array = None
        self.tdata_signal_width = 512

    def set_name(self, name):
        self.name = name

    def set_array(self, array: Array):
        self.array = array

    def set_tdata_signal_width(self, width: int):
        self.tdata_signal_width = width

    def get_signal_map(self) -> Dict[str, int]:
        return {
            "tvalid": 1,
            "tready": 1,
            "tlast": 1,
            "tdata": self.tdata_signal_width
        }

    @staticmethod
    def try_parse(tokens: List[Token]) -> ILAConfiguration:
        configuration = AxiILAConfiguration()
        
        # Matching (and setting properties!)
        array = Array()
        match_group = MatchGroup(
            SymbolIdentifier("AXI4SR"),
            AnyOf(
                #  E.g. AXI4SR.s axis_host_recv,
                MatchGroup(
                    Dot(True),
                    AnyOf(
                        SymbolIdentifier("s"),
                        SymbolIdentifier("m")
                    )
                ),
                # E.g. AXI4SR #(.AXI4S_DATA_BITS(512)) default_stream
                MatchGroup(
                    Hashtag(),
                    Parentheses(True),
                    Dot(True),
                    AnyOf(
                        MatchGroup(
                            SymbolIdentifier("AXI4S_DATA_BITS"),
                            Parentheses(True),
                            Decimal(configuration.set_tdata_signal_width),
                            Parentheses(False),
                        ),
                        # Any other interface configuration
                        MatchGroup(
                            SymbolIdentifier(),
                            Parentheses(True),
                            Decimal(),
                            Parentheses(False),
                        )
                    ),
                    Parentheses(False)
                )
            ),
            MatchGroup(
                SymbolIdentifier(None, configuration.set_name),
                OptionalMatchGroup(array)
            )
        )

        if match_group.number_of_matching_tokens(tokens) > 0:
            if array.get_dimensions() > 0:
                configuration.set_array(array)
            return configuration
    
        return None
    
    def generate_probes_for_interface_instance(self, source_signal_name, new_signal_name) -> List[Probe]:
        signal_map = self.get_signal_map()
        probes = []
        for key in signal_map.keys():
            probes.append(ProbeWithLogicRedefinition(
                f"{source_signal_name}.{key}",
                f"{new_signal_name}_{key}",
                signal_map[key]
            ))
        
        return probes

    def generate_probe_definitions(self) -> List[Probe]:
        if self.array == None:
            return self.generate_probes_for_interface_instance(self.name, self.name)

        # Go through all of the dimensions and add the access indices to the name!
        elements = [(self.name, self.name)]
        for dimension in range(0, self.array.get_dimensions()):
            new_elements = []
            for element in range(0, self.array.get_size(dimension)):
                for (source_name, target_name) in elements:
                    new_elements.append((f"{source_name}[{element}]", f"{target_name}_{element}"))

            elements = new_elements

        probes = []
        # Generate all the probes!
        for (source, new_signal) in elements:
            probes += self.generate_probes_for_interface_instance(source, new_signal)
        
        return probes