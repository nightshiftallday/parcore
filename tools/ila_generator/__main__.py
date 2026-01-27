import os
import json
from tools.ila_generator.utils.process_runner import ProcessRunner
from tools.ila_generator.utils.ila_configuration import ILAConfiguration, Probe
from tools.ila_generator.utils.axi_ila_configuration import AxiILAConfiguration
from tools.ila_generator.utils.logic_ila_configuration import LogicILAConfiguration
from tools.ila_generator.utils.token import Token, COMMENT_ILA_DEFINITION, COMMENT_BEGINNING_SECTION
from typing import List, Tuple

SOURCE_FOLDER = "src/hdl"
PROBE_FILE_FILE_EXTENSION = ".probe.sv"
TCL_PROBE_CONFIG_FILE = "src/init_ip.probe.tcl"

def list_files_in_folder(folder_path):
    try:
        files = [os.path.join(folder_path, f) for f in os.listdir(folder_path) if os.path.isfile(os.path.join(folder_path, f))]
        return list(filter(lambda x: x.endswith(".sv") and (not x.endswith(PROBE_FILE_FILE_EXTENSION)), files))
    except FileNotFoundError:
        return f"Error: The folder '{folder_path}' does not exist."
    except PermissionError:
        return f"Error: Permission denied for accessing '{folder_path}'."

def parse_sv_syntax(files) -> List[Tuple[str, List[Token]]]:
    parsed_files = []
    for file in files:
        [success, parsed_str, error] = ProcessRunner().analyze_file_with_verible(file)
        if success == False:
            print(f"Could not parse file at: {file}. Got the following error: {error}")
        parsed = json.loads(parsed_str)
        # High level key is the file name
        # This gives us the object we actually want
        # Inside this we return the list of raw tokens!
        raw_tokens = parsed[file]["rawtokens"]
        parsed_files.append((file, [Token.from_raw_token(raw) for raw in raw_tokens]))
    
    return parsed_files

def filter_files_that_need_ILA_def(parsed_files: List[Tuple[str, List[Token]]]) -> List[Tuple[str, List[Token]]]:
    """
    Filters the parsed files to only return those who have a @ILA definition
    """
    filtered = []
    for file_name, tokens in parsed_files:
        if any([token.is_ila_definition_token() for token in tokens]):
            filtered.append((file_name, tokens))

    return filtered

def strip_white_space(tokens: List[Token]):
    return list(filter(lambda x: not x.is_white_space_token(), tokens))

def parse_ila_configuration(tokens: List[Token]) -> ILAConfiguration:
    """
    tokens: all tokens following a `COMMENT_ILA_DEFINITION`
            definition
    """
    if (config := AxiILAConfiguration.try_parse(tokens)) is not None:
        return config
    if (config := LogicILAConfiguration.try_parse(tokens)) is not None:
        return config
    else:
        raise ValueError(f"Found {COMMENT_ILA_DEFINITION} for not supported symbol: {[str(token) for token in tokens]}")

def get_line_end_relative_index(token: List[Token]) -> int:
    for index, token in enumerate(token):
        if token.is_line_end_token():
            return index 

def infer_ila_configuration(tokens) -> List[ILAConfiguration]:
    configs = []

    for index, token in enumerate(tokens):
        if token.is_ila_definition_token():
            striped = strip_white_space(tokens[index + 1:])
            end = get_line_end_relative_index(striped)
            # Now we need to follow the following tokens to figure
            # out the type of ILA we are supposed to add!
            configs.append(parse_ila_configuration(striped[:end]))

    return configs

def write_verilog_probe_file(file_name, ila_name, probes: List[Probe]):
    
    probe_code : List[str] = [probe.get_code() for probe in probes]
    probe_code.append("")
    probe_code.append("// ILA DEFINITION")
    probe_code.append("")
    probe_code.append(f"ila_{ila_name} inst_{ila_name} (")

    # Use spaces instead of tabs
    probe_signals : List[str] = ["   .clk(HERE)"]
    for index, probe in enumerate(probes):
        probe_signals.append(f"   .probe{index}({probe.get_signal_name()})")

    # Write to the probe file
    target_file = file_name.replace(".sv", PROBE_FILE_FILE_EXTENSION)
    with open(target_file, "w") as f:
        f.write("\n")
        f.write(COMMENT_BEGINNING_SECTION)
        f.write("\n")
        f.write("\n".join(probe_code))
        f.write("\n")
        f.write("   //TODO: Add clock signal below\n")
        f.write(",\n".join(probe_signals))
        f.write("\n);")
        f.write("\n")
    
    print(f"Wrote configuration to {target_file}")

def write_tcl_probe_file(ila_name, probes: List[Probe]):
    # The config parameter that needs to be written for each probe
    probe_config = []
    for index, probe in enumerate(probes):
        probe_config.append(f"CONFIG.C_PROBE{index}_WIDTH {{{probe.get_bit_width()}}}")
        probe_config.append(f"CONFIG.C_PROBE{index}_MU_CNT {{2}}")

    # Append - File has been overwritten earlier
    with open(TCL_PROBE_CONFIG_FILE, "a") as f:
        f.write(f"create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_{ila_name}\n")
        # All of the following needs to be written in one line!
        f.write("set_property -dict [list CONFIG.C_EN_STRG_QUAL {1} ")
        f.write(f"CONFIG.C_NUM_OF_PROBES {{{len(probes)}}} ")
        f.write(" ".join(probe_config))
        f.write(f" CONFIG.ALL_PROBE_SAME_MU_CNT {{2}} ] [get_ips ila_{ila_name}]\n")
    
    print(f"Updated configuration in {TCL_PROBE_CONFIG_FILE}")

def reset_tcl_probe_file():
    # Overwrite the file
    with open(TCL_PROBE_CONFIG_FILE, "w") as f:
        pass

def configurations_to_probe_output(file_name, configurations: List[ILAConfiguration]):
    print(f"Found probe configuration in {file_name}")
    probes : List[Probe] = []

    for config in configurations:
        probes += config.generate_probe_definitions()

    ila_name =  os.path.basename(file_name).replace(".sv", "")
    write_verilog_probe_file(file_name, ila_name, probes)
    write_tcl_probe_file(ila_name, probes)
    

if __name__ == "__main__":
    files_to_analyze = list_files_in_folder(SOURCE_FOLDER)
    parsed = parse_sv_syntax(files_to_analyze)
    needs_ila = filter_files_that_need_ILA_def(parsed)
    ila_configurations = [(file_name, infer_ila_configuration(tokens)) for [file_name, tokens] in needs_ila]

    # Generate the probe output for each file and all found probe configurations!
    reset_tcl_probe_file()
    for (file_name, configs) in ila_configurations:
        configurations_to_probe_output(file_name, configs)
