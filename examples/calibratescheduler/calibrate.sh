#!/bin/bash

# Configuration
OUTPUT_FILE="calibration.csv"
BASE_DIR="/dev/shm"
COMPRESSIONS=("with_compression" "no_compression")
NUMBERS=("1" "3" "10")

# Flag to handle CSV headers
FIRST_RUN=true

# Clear the output file if it already exists
> "$OUTPUT_FILE"

for comp in "${COMPRESSIONS[@]}"; do
    for num in "${NUMBERS[@]}"; do
        TARGET_DIR="$BASE_DIR/$comp/parquet-$num"

        if [ -d "$TARGET_DIR" ]; then
            echo "Scanning: $TARGET_DIR"
            
            for file in "$TARGET_DIR"/*.parquet; do
                [ -e "$file" ] || continue

                [[ "$(basename "$file")" == "orders.parquet" ]] && continue

                # [[ "$(basename "$file")" != "lineitem.parquet" ]] && continue
                
                echo "running: ./calibratescheduler -f $file"
                if [ "$FIRST_RUN" = true ]; then
                    # Run and keep everything (Header + Data)
                    ./build/calibratescheduler -f "$file" >> "$OUTPUT_FILE"
                    FIRST_RUN=false
                else
                    # Run and strip the first line (Data only)
                    ./build/calibratescheduler -f "$file" | tail -n +2 >> "$OUTPUT_FILE"
                fi
            done
        fi
    done
done

echo "Done! Results consolidated in $OUTPUT_FILE"
