#!/usr/bin/env python3
"""Moves the SkidBuffer module between SystemVerilog sources.

  skid_unit.py extract <src.sv> <out.sv>            writes only the SkidBuffer module of src.sv
  skid_unit.py replace <src.sv> <skid.sv> <out.sv>  writes src.sv with its SkidBuffer module
                                                    replaced by the one in skid.sv
"""
import re
import sys
from pathlib import Path

MODULE = re.compile(r"^module SkidBuffer\b.*?^endmodule\b", re.S | re.M)


def find(text, path):
    matches = MODULE.findall(text)
    if len(matches) != 1:
        sys.exit(f"{path}: expected one SkidBuffer module, found {len(matches)}")
    return matches[0]


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "extract":
        src = Path(sys.argv[2]).read_text()
        Path(sys.argv[3]).write_text("`timescale 1ns / 1ps\n\n" + find(src, sys.argv[2]) + "\n")
    elif len(sys.argv) == 5 and sys.argv[1] == "replace":
        src = Path(sys.argv[2]).read_text()
        find(src, sys.argv[2])
        skid = find(Path(sys.argv[3]).read_text(), sys.argv[3])
        Path(sys.argv[4]).write_text(MODULE.sub(lambda _: skid, src))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
