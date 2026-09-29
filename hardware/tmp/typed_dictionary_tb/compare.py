#!/usr/bin/env python3
"""Compares the per-dictionary cycle metrics of the inline and ITC variants from run_xsim.sh."""
import csv
import sys
from pathlib import Path

RESULTS = Path(__file__).parent / "results"
METRICS = ("conv_cycles", "id_phase_cycles", "first_out_latency", "conv_beats", "out_beats")
WIDE = ("INT64_T", "DOUBLE_T")


def load(variant, mode):
    with open(RESULTS / f"metrics_{variant}_{mode}.csv") as f:
        return {int(r["dict"]): r for r in csv.DictReader(f)}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "nostall"
    inline, itc = load("inline", mode), load("itc", mode)
    print(f"{'dict':>4} {'typ':>9} {'ids':>5} | {'conv inl/itc':>13} | {'id_phase inl/itc':>16} "
          f"| {'latency inl/itc':>15}")
    totals = {}
    for k in sorted(inline):
        a, b = inline[k], itc[k]
        width = 64 if a["typ"] in WIDE else 32
        for m in METRICS:
            t = totals.setdefault((width, m), [0, 0])
            t[0] += int(a[m])
            t[1] += int(b[m])
        print(f"{k:>4} {a['typ']:>9} {a['num_ids']:>5} | {a['conv_cycles']:>6}/{b['conv_cycles']:<6} "
              f"| {a['id_phase_cycles']:>8}/{b['id_phase_cycles']:<7} "
              f"| {a['first_out_latency']:>7}/{b['first_out_latency']:<7}")
    print()
    for (width, m), (a, b) in sorted(totals.items()):
        print(f"{width}-bit {m:>18}: inline {a:>6}  itc {b:>6}  diff {b - a:+6} ({(b - a) / a * 100:+.1f}%)")


if __name__ == "__main__":
    main()
