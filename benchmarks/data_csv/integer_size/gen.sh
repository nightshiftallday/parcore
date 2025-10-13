#!/bin/bash

SCRIPT_DEPTH=3

SCRIPT_DIR=$(dirname "$(realpath "$0")")
BASE_DIR=$SCRIPT_DIR
for i in $(seq 1 "$SCRIPT_DEPTH"); do
    BASE_DIR=$(dirname "$BASE_DIR")
done

rm -f $SCRIPT_DIR/*.csv

cd $BASE_DIR/benchmarks/data_csv/dbgen
for i in {1..25}; do
    # Generate TPC-H CSV data
    echo "Generating with scaling factor $i"
    ./dbgen -T L -s $i -f
    tr -d '|' < lineitem.tbl > $(printf "%s/s%02d.csv" "$SCRIPT_DIR" "$i")
done