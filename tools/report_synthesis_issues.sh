#!/bin/bash
# merging, constant, unused, optimized, removed
cat build_synth/synth.out | grep -F -f tools/txt/filter_keywords.txt > tools/filtered_synthesis_report.txt