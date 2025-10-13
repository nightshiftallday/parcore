#!/usr/bin/env python3

import os
import sys
import subprocess
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import numpy as np
import argparse
import random
from math import log2
from pathlib import Path
from typing import List, Optional, Dict, Any, Tuple

# TPC-H LINEITEM schema definition - NUMERIC COLUMNS ONLY (optimized for FPGA)
# Strings and dates are commented out in dbgen print.c to avoid generating unnecessary data
# All columns are marked as NON-NULLABLE to prevent definition level encoding in parquet
TPCH_LINEITEM_SCHEMA = {
    'L_ORDERKEY': {'type': pa.field('L_ORDERKEY', pa.int64(), nullable=False), 'description': 'Order identifier'},
    'L_PARTKEY': {'type': pa.field('L_PARTKEY', pa.int64(), nullable=False), 'description': 'Part identifier'},
    'L_SUPPKEY': {'type': pa.field('L_SUPPKEY', pa.int64(), nullable=False), 'description': 'Supplier identifier'},
    'L_LINENUMBER': {'type': pa.field('L_LINENUMBER', pa.int32(), nullable=False), 'description': 'Line number within order'},
    'L_QUANTITY': {'type': pa.field('L_QUANTITY', pa.float64(), nullable=False), 'description': 'Quantity ordered'},
    'L_EXTENDEDPRICE': {'type': pa.field('L_EXTENDEDPRICE', pa.float64(), nullable=False), 'description': 'Extended price'},
    'L_DISCOUNT': {'type': pa.field('L_DISCOUNT', pa.float64(), nullable=False), 'description': 'Discount percentage'},
    'L_TAX': {'type': pa.field('L_TAX', pa.float64(), nullable=False), 'description': 'Tax rate'},
    # EXCLUDED COLUMNS (commented out in dbgen print.c):
    # 'L_RETURNFLAG': {'type': pa.string(), 'description': 'Return flag (A/R/N)'},
    # 'L_LINESTATUS': {'type': pa.string(), 'description': 'Line status (O/F)'},
    # 'L_SHIPDATE': {'type': pa.date32(), 'description': 'Ship date (stored as string in TBL)'},
    # 'L_COMMITDATE': {'type': pa.date32(), 'description': 'Commit date (stored as string in TBL)'},
    # 'L_RECEIPTDATE': {'type': pa.date32(), 'description': 'Receipt date (stored as string in TBL)'},
    # 'L_SHIPINSTRUCT': {'type': pa.string(), 'description': 'Shipping instructions'},
    # 'L_SHIPMODE': {'type': pa.string(), 'description': 'Shipping mode'},
    # 'L_COMMENT': {'type': pa.string(), 'description': 'Comment'}
}

def print_schema_info():
    """Print detailed schema information for TPC-H LINEITEM table"""
    print("=== TPC-H LINEITEM SCHEMA ===")
    print(f"Total columns: {len(TPCH_LINEITEM_SCHEMA)}")
    print()
    
    for i, (col_name, info) in enumerate(TPCH_LINEITEM_SCHEMA.items(), 1):
        print(f"{i:2d}. {col_name:<15} {str(info['type']):<20} - {info['description']}")
    
    print()
    print("PyArrow Schema:")
    schema_fields = [info['type'] for name, info in TPCH_LINEITEM_SCHEMA.items()]
    schema = pa.schema(schema_fields)
    print(schema)

def examine_existing_parquet(file_path: str):
    """Examine an existing parquet file to understand its schema"""
    print(f"\n=== Examining {file_path} ===")
    
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return None
    
    try:
        table = pq.read_table(file_path)
        df = table.to_pandas()
        
        print(f"Shape: {df.shape}")
        print(f"File size: {os.path.getsize(file_path):,} bytes")
        
        print("\nSchema:")
        print(table.schema)
        
        print("\nColumn information:")
        for i, field in enumerate(table.schema):
            distinct_count = df[field.name].nunique()
            print(f"{i+1:2d}. {field.name:<15} {str(field.type):<12} - {distinct_count:,} distinct values")
        
        print("\nFirst 3 rows:")
        print(df.head(3))
        
        return table
        
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return None

def analyze_tbl_file(tbl_file: str) -> Dict[str, Any]:
    """Analyze the structure of a .tbl file"""
    print(f"\n=== Analyzing {tbl_file} ===")
    
    if not os.path.exists(tbl_file):
        print(f"File not found: {tbl_file}")
        return {}
    
    # Read first few lines to understand format
    with open(tbl_file, 'r') as f:
        lines = [f.readline().strip() for _ in range(10) if f.readable()]
    
    if not lines:
        print("File is empty or unreadable")
        return {}
    
    # Analyze format
    first_line = lines[0]
    field_count = len(first_line.split('|'))
    
    print(f"First 5 lines:")
    for i, line in enumerate(lines[:5], 1):
        print(f"{i}: {line}")
    
    print(f"\nDetected format:")
    print(f"  Fields per line: {field_count}")
    print(f"  Separator: '|'")
    print(f"  Total lines: {sum(1 for _ in open(tbl_file))}")
    
    # Try to determine if this is single-column or multi-column
    if field_count <= 2:  # Single value + trailing pipe
        print("  Format: Single column (likely L_ORDERKEY only)")
        return {
            'format': 'single_column',
            'column': 'L_ORDERKEY',
            'field_count': field_count,
            'total_lines': sum(1 for _ in open(tbl_file))
        }
    else:
        print("  Format: Multi-column TPC-H format")
        return {
            'format': 'multi_column',
            'field_count': field_count,
            'total_lines': sum(1 for _ in open(tbl_file))
        }

def apply_selective_dictionary_encoding(table: pa.Table, use_dictionary: bool = False, cardinality_threshold: int = 1000) -> pa.Table:
    """Convert low-cardinality columns to dictionary type before writing to Parquet"""
    if not use_dictionary:
        return table
    
    print(f"Analyzing columns for dictionary encoding (cardinality threshold: {cardinality_threshold})")
    
    # Convert table to pandas for cardinality analysis
    df = table.to_pandas()
    
    new_columns = []
    new_fields = []
    
    for i, field in enumerate(table.schema):
        column_data = table.column(i)
        distinct_count = df[field.name].nunique()
        
        # Apply dictionary encoding if below threshold
        if distinct_count <= cardinality_threshold:
            # Convert to dictionary type while preserving non-nullable schema
            dict_array = pa.compute.dictionary_encode(column_data)
            # Create non-nullable field for dictionary type to avoid definition levels
            dict_field = pa.field(field.name, dict_array.type, nullable=False)
            new_columns.append(dict_array)
            new_fields.append(dict_field)
            print(f"  {field.name}: {distinct_count} distinct values -> converted to dictionary type (non-nullable)")
        else:
            new_columns.append(column_data)
            new_fields.append(field)  # Keep original field (already non-nullable)
            print(f"  {field.name}: {distinct_count} distinct values -> keeping as plain type")
    
    # Create new schema with proper nullable settings
    new_schema = pa.schema(new_fields)
    
    # Create new table with dictionary-encoded columns and proper schema
    return pa.Table.from_arrays(new_columns, schema=new_schema)

def run_dbgen(scale_factor: int, table_type: str = 'L', dbgen_dir: str = None) -> bool:
    """Run dbgen to generate TPC-H data"""
    if dbgen_dir is None:
        dbgen_dir = "/local/home/ccaspar/fpga-parquet-reader/benchmarks/data_csv/dbgen"
    
    print(f"\n=== Running DBGEN (Scale Factor: {scale_factor}, Table: {table_type}) ===")
    
    # Change to dbgen directory
    original_dir = os.getcwd()
    os.chdir(dbgen_dir)
    
    try:
        # Run dbgen command
        cmd = ['./dbgen', '-T', table_type, '-s', str(scale_factor), '-f', '-v']
        print(f"Command: {' '.join(cmd)}")
        
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        print(f"Return code: {result.returncode}")
        if result.stdout:
            print(f"STDOUT:\n{result.stdout}")
        if result.stderr:
            print(f"STDERR:\n{result.stderr}")
        
        return result.returncode == 0
        
    except Exception as e:
        print(f"Error running dbgen: {e}")
        return False
    finally:
        os.chdir(original_dir)

def convert_single_column_to_parquet(tbl_file: str, output_file: str, column_name: str = 'L_ORDERKEY', compression: Optional[str] = None, use_dictionary: bool = False, cardinality_threshold: int = 1000):
    """Convert single-column TBL file to parquet"""
    print(f"\nConverting single-column {tbl_file} to {output_file}")
    
    try:
        # Read the single column data
        data = []
        with open(tbl_file, 'r') as f:
            for line in f:
                line = line.strip()
                if line and line != '|':
                    # Remove trailing pipe if present
                    value = line.rstrip('|')
                    if value.isdigit():
                        data.append(int(value))
        
        if not data:
            print("No valid data found in file")
            return False
        
        # Create DataFrame
        df = pd.DataFrame({column_name: data})
        
        # Create PyArrow table with proper non-nullable schema
        schema = pa.schema([TPCH_LINEITEM_SCHEMA[column_name]['type']])
        table = pa.Table.from_pandas(df, schema=schema)
        
        # Apply selective dictionary encoding based on cardinality
        # table = apply_selective_dictionary_encoding(table, use_dictionary, cardinality_threshold)
        
        # Write parquet file - only use dictionary encoding if requested
        pq.write_table(
            table,
            output_file,
            compression=compression,
            data_page_version="1.0",
            use_dictionary=use_dictionary  # Use the actual user setting
        )
        
        print(f"✓ Successfully created {output_file}")
        print(f"  Records: {len(data):,}")
        print(f"  Column: {column_name}")
        print(f"  File size: {os.path.getsize(output_file):,} bytes")
        
        return True
        
    except Exception as e:
        print(f"Error converting {tbl_file}: {e}")
        return False

def convert_multi_column_to_parquet(tbl_file: str, output_file: str, selected_columns: Optional[List[str]] = None, compression: Optional[str] = None, use_dictionary: bool = False, cardinality_threshold: int = 1000):
    """Convert multi-column TBL file to parquet with column selection"""
    print(f"\nConverting multi-column {tbl_file} to {output_file}")
    
    try:
        column_names = list(TPCH_LINEITEM_SCHEMA.keys())
        
        # Read the pipe-delimited file
        df = pd.read_csv(tbl_file, sep='|', header=None, names=column_names + ['empty'])
        
        # Remove the last empty column (trailing pipe creates an empty field)
        if 'empty' in df.columns:
            df = df.drop('empty', axis=1)
        
        # Select only requested columns
        if selected_columns:
            available_columns = [col for col in selected_columns if col in df.columns]
            if not available_columns:
                print(f"None of the selected columns {selected_columns} found in data")
                return False
            df = df[available_columns]
            print(f"Selected columns: {available_columns}")
        
        # Convert data types - simplified for numeric-only schema
        for col in df.columns:

            if col in TPCH_LINEITEM_SCHEMA:
                schema_field = TPCH_LINEITEM_SCHEMA[col]['type']
                schema_type = schema_field.type
                if pa.types.is_integer(schema_type):
                    df[col] = pd.to_numeric(df[col], errors='coerce').astype('int64')
                elif pa.types.is_floating(schema_type):
                    # Convert to float64 for decimal/floating point columns
                    df[col] = pd.to_numeric(df[col], errors='coerce').astype('float64')
                elif pa.types.is_date(schema_type):
                    df[col] = pd.to_datetime(df[col], errors='coerce')
                # String columns are handled automatically
        
        # Create PyArrow table with proper non-nullable schema
        schema_fields = [TPCH_LINEITEM_SCHEMA[col]['type'] for col in df.columns if col in TPCH_LINEITEM_SCHEMA]
        schema = pa.schema(schema_fields)

        distinct_count = df.nunique()
        print(f"Distinct count: {distinct_count}")
        table = pa.Table.from_pandas(df, schema=schema)
        
        # Apply selective dictionary encoding based on cardinality
        # table = apply_selective_dictionary_encoding(table, use_dictionary, cardinality_threshold)
        print("Using dictionary: ", use_dictionary)
        
        # Write parquet file - only use dictionary encoding if requested
        pq.write_table(
            table,
            output_file,
            compression=compression,
            data_page_version="1.0",
            use_dictionary=use_dictionary  # Use the actual user setting
        )
        
        print(f"✓ Successfully created {output_file}")
        print(f"  Records: {len(df):,}")
        print(f"  Columns: {len(df.columns)}")
        print(f"  File size: {os.path.getsize(output_file):,} bytes")
        
        return True
        
    except Exception as e:
        print(f"Error converting {tbl_file}: {e}")
        return False

def generate_random_dictionary_data(dict_size: int, num_values: int, data_type: str, seed: Optional[int] = None) -> Tuple[List, List]:
    """Generate a random dictionary and sample values from it.
    
    Args:
        dict_size: Size of the dictionary (number of unique values)
        num_values: Total number of values to generate (can be larger than dict_size for repetition)
        data_type: One of 'int32', 'int64', 'float', 'double'
        seed: Random seed for reproducibility
        
    Returns:
        Tuple of (dictionary_values, sampled_values)
    """
    if seed is not None:
        random.seed(seed)
        np.random.seed(seed)
    
    # Generate dictionary based on data type
    if data_type == 'int32':
        # Generate random int32 values (avoiding overflow)
        dictionary = list(np.random.randint(-2**30, 2**30, size=dict_size, dtype=np.int32))
    elif data_type == 'int64':
        # Generate random int64 values (avoiding overflow)
        dictionary = list(np.random.randint(-2**62, 2**62, size=dict_size, dtype=np.int64))
    elif data_type == 'float':
        # Generate random float32 values
        dictionary = list(np.random.uniform(-1e6, 1e6, size=dict_size).astype(np.float32))
    elif data_type == 'double':
        # Generate random float64 values
        dictionary = list(np.random.uniform(-1e12, 1e12, size=dict_size).astype(np.float64))
    else:
        raise ValueError(f"Unsupported data type: {data_type}")
    
    # Sample values from dictionary with repetition
    sampled_values = random.choices(dictionary, k=num_values)
    
    return dictionary, sampled_values


def factors_to_num_values(desired_size:int, col_type: Optional[str] = None, compression: Optional[str] = None, dict_size: Optional[int] = None, use_dict: bool = False):
    # Math description (Output size estimation):
    # col_type: byteWidth = 4 / 8
    # size plain = num_vals * byteWidth
    # size dict = num_vals * log2(dict_size) / 8  
    # size snappy = num_vals * byteWidth * 3/5 or 2/2.5 (depending on byteWidth)
    # size dict_snappy = same as dict
    if col_type is not None:
        byteWidth = 4 if (col_type == 'int32' or col_type == 'float') else 8
        snappy_ratio = 2/2.5 if (col_type == 'int32' or col_type == 'float') else 3/5


        # Next is to estimate the num_vals for each variant to fill the desired size
        if use_dict:
            num_vals = desired_size * 4 / log2(dict_size)
        else:
            if compression == 'snappy':
                num_vals =  desired_size / (byteWidth * snappy_ratio * 2)
            else:
                num_vals = desired_size / byteWidth
        
        return num_vals

    else:
        # col_type: None (mixed)
        # all = same variant but sum over different col types
        if use_dict:
            num_vals = desired_size * 4 * 0.25 / (log2(dict_size))
        else:
            if compression == 'snappy':
                num_vals = desired_size / (4 * 2/2.5 + 8*3/5 + 4 * 2/2.5 + 8*3/5)
            else:
                num_vals = desired_size / (4 + 8 + 4 + 8)
        
        return num_vals


def generate_size_mode_parquet_files(dict_sizes: List[int], target_size: int, output_dir: str = None, seed: Optional[int] = 42):
    """Generate parquet files with controllable dictionary size, scaled to achieve target file size.
    
    Args:
        dict_sizes: List of dictionary sizes to generate
        target_size: Target file size in bytes
        output_dir: Output directory for parquet files
        seed: Random seed for reproducibility
    """
    if output_dir is None:
        output_dir = "/local/home/ccaspar/fpga-parquet-reader/benchmarks/data_csv/size_mode"
    
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"\n=== Generating Size Mode Parquet Files ===")
    print(f"Dictionary sizes: {dict_sizes}")
    print(f"Target file size: {target_size:,} bytes")
    print(f"Output directory: {output_dir}")
    print(f"Random seed: {seed}")
    
    # Data types to generate
    data_types = ['int32', 'int64', 'float', 'double']
    
    # Encoding and compression combinations
    variants = [
        ('plain', None),      # _plain
        ('plain', 'snappy'),  # _plain_snappy
        ('dict', None),       # _dict
        ('dict', 'snappy')    # _dict_snappy
    ]
    
    for dict_size in dict_sizes:
        print(f"\n--- Dictionary Size {dict_size} ---")
        
        # Generate single-column files for each data type
        for data_type in data_types:
            print(f"\nGenerating {data_type} variants...")
            
            for encoding, compression in variants:
                # Calculate number of values needed for target size
                use_dict = (encoding == 'dict')
                num_values = int(factors_to_num_values(
                    target_size, data_type, compression, dict_size, use_dict
                ))
                
                print(f"  Generating {data_type} {encoding}" + 
                      (f"_{compression}" if compression else "") + f" variant...")
                print(f"    Calculated num_values: {num_values:,}")
                
                # Single-column file
                dict_suffix = f"_{encoding}" if encoding == 'dict' else ""
                comp_suffix = f"_{compression}" if compression else ""
                filename = f"size_{target_size//1000}k_{dict_size:04d}_{data_type}{dict_suffix}{comp_suffix}.parquet"
                output_file = os.path.join(output_dir, filename)
                
                # Generate the random dictionary and sampled values
                dictionary, sampled_values = generate_random_dictionary_data(
                    dict_size, num_values, data_type, seed
                )
                
                # Create DataFrame
                column_name = f"col_{data_type}"
                df = pd.DataFrame({column_name: sampled_values})
                
                # Determine PyArrow schema based on data type
                if data_type == 'int32':
                    pa_type = pa.int32()
                elif data_type == 'int64':
                    pa_type = pa.int64()
                elif data_type == 'float':
                    pa_type = pa.float32()
                elif data_type == 'double':
                    pa_type = pa.float64()
                
                # Create PyArrow table with proper schema (non-nullable)
                schema = pa.schema([pa.field(column_name, pa_type, nullable=False)])
                table = pa.Table.from_pandas(df, schema=schema)
                
                # Apply dictionary encoding if requested
                if use_dict:
                    # Force dictionary encoding regardless of cardinality
                    dict_array = pa.compute.dictionary_encode(table.column(0))
                    dict_field = pa.field(column_name, dict_array.type, nullable=False)
                    table = pa.Table.from_arrays([dict_array], schema=pa.schema([dict_field]))
                
                try:
                    # Write parquet file
                    pq.write_table(
                        table,
                        output_file,
                        compression=compression,
                        data_page_version="1.0",
                        use_dictionary=use_dict
                    )
                    
                    actual_size = os.path.getsize(output_file)
                    size_ratio = actual_size / target_size
                    print(f"      ✓ {filename}")
                    print(f"        Target: {target_size:,} bytes, Actual: {actual_size:,} bytes (ratio: {size_ratio:.2f})")
                    
                except Exception as e:
                    print(f"      ❌ Failed to create {filename}: {e}")
        
        # Generate multi-column file with all 4 data types (dict+snappy only)
        print(f"\nGenerating multi-column file with all 4 data types...")
        
        # Calculate number of values needed for target size (multi-column)
        use_dict = True
        compression = 'snappy'
        num_values = int(factors_to_num_values(
            target_size, None, compression, dict_size, use_dict
        ))
        
        print(f"  Calculated num_values: {num_values:,}")
        
        # Multi-column file
        filename = f"size_{target_size//1000}k_{dict_size:04d}_all_dict_snappy.parquet"
        output_file = os.path.join(output_dir, filename)
        
        # Generate data for all 4 types
        all_data = {}
        for dt in data_types:
            dictionary, sampled_values = generate_random_dictionary_data(
                dict_size, num_values, dt, seed
            )
            column_name = f"col_{dt}"
            all_data[column_name] = sampled_values
        
        # Create multi-column DataFrame
        multi_df = pd.DataFrame(all_data)
        
        # Create PyArrow schema for all columns
        schema_fields = []
        for dt in data_types:
            column_name = f"col_{dt}"
            if dt == 'int32':
                pa_type = pa.int32()
            elif dt == 'int64':
                pa_type = pa.int64()
            elif dt == 'float':
                pa_type = pa.float32()
            elif dt == 'double':
                pa_type = pa.float64()
            schema_fields.append(pa.field(column_name, pa_type, nullable=False))
        
        multi_schema = pa.schema(schema_fields)
        table = pa.Table.from_pandas(multi_df, schema=multi_schema)
        
        # Apply dictionary encoding for all columns
        new_columns = []
        new_fields = []
        for i, field in enumerate(table.schema):
            dict_array = pa.compute.dictionary_encode(table.column(i))
            dict_field = pa.field(field.name, dict_array.type, nullable=False)
            new_columns.append(dict_array)
            new_fields.append(dict_field)
        table = pa.Table.from_arrays(new_columns, schema=pa.schema(new_fields))
        
        try:
            # Write parquet file
            pq.write_table(
                table,
                output_file,
                compression=compression,
                data_page_version="1.0",
                use_dictionary=use_dict
            )
            
            actual_size = os.path.getsize(output_file)
            size_ratio = actual_size / target_size
            print(f"    ✓ {filename}")
            print(f"      Target: {target_size:,} bytes, Actual: {actual_size:,} bytes (ratio: {size_ratio:.2f})")

            if compression is not None:
                output_file = output_file.replace('_snappy.parquet', f".parquet")
                pq.write_table(
                    table,
                    output_file,
                    compression=None,
                    data_page_version="1.0",
                    use_dictionary=use_dict
                )
                
                actual_size = os.path.getsize(output_file)
                size_ratio = actual_size / target_size
                print(f"    ✓ {filename}")
                print(f"      Target: {target_size:,} bytes, Actual: {actual_size:,} bytes (ratio: {size_ratio:.2f})")
            
        except Exception as e:
            print(f"    ❌ Failed to create {filename}: {e}")

def generate_dictionary_mode_parquet_files(dict_sizes: List[int], num_values: int = 1000000, output_dir: str = None, seed: Optional[int] = 42):
    """Generate parquet files with controllable dictionary size for all data type and encoding variants.
    
    Args:
        dict_sizes: List of dictionary sizes to generate (these become the scale factors)
        num_values: Number of values in each column (default 1M)
        output_dir: Output directory for parquet files
        seed: Random seed for reproducibility
    """
    if output_dir is None:
        output_dir = "/local/home/ccaspar/fpga-parquet-reader/benchmarks/data_csv/dictionary_size"
    
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    print(f"\n=== Generating Dictionary Mode Parquet Files ===")
    print(f"Dictionary sizes: {dict_sizes}")
    print(f"Values per column: {num_values:,}")
    print(f"Output directory: {output_dir}")
    print(f"Random seed: {seed}")
    
    # Data types to generate
    data_types = ['int32', 'int64', 'float', 'double']
    
    # Encoding and compression combinations
    variants = [
        ('plain', None),      # _plain
        ('plain', 'snappy'),  # _plain_snappy
        ('dict', None),       # _dict
        ('dict', 'snappy')    # _dict_snappy
    ]
    
    for dict_size in dict_sizes:
        print(f"\n--- Dictionary Size {dict_size} ---")
        
        for data_type in data_types:
            print(f"\nGenerating {data_type} variants...")
            
            # Generate the random dictionary and sampled values
            dictionary, sampled_values = generate_random_dictionary_data(
                dict_size, num_values, data_type, seed
            )
            
            print(f"  Dictionary size: {len(dictionary)}")
            print(f"  Sample values: {len(sampled_values):,}")
            print(f"  Actual unique values in sample: {len(set(sampled_values))}")
            
            # Generate all encoding/compression variants
            for encoding, compression in variants:
                # Create filename
                comp_suffix = f"_{compression}" if compression else ""
                dict_suffix = f"_{encoding}" if encoding == 'dict' else ""
                filename = f"dict_{dict_size:04d}_{data_type}{dict_suffix}{comp_suffix}.parquet"
                output_file = os.path.join(output_dir, filename)
                
                # Create DataFrame
                column_name = f"col_{data_type}"
                df = pd.DataFrame({column_name: sampled_values})
                
                # Determine PyArrow schema based on data type
                if data_type == 'int32':
                    pa_type = pa.int32()
                elif data_type == 'int64':
                    pa_type = pa.int64()
                elif data_type == 'float':
                    pa_type = pa.float32()
                elif data_type == 'double':
                    pa_type = pa.float64()
                
                # Create PyArrow table with proper schema (non-nullable)
                schema = pa.schema([pa.field(column_name, pa_type, nullable=False)])
                table = pa.Table.from_pandas(df, schema=schema)
                
                # Apply dictionary encoding if requested
                use_dict = (encoding == 'dict')
                if use_dict:
                    # Force dictionary encoding regardless of cardinality
                    dict_array = pa.compute.dictionary_encode(table.column(0))
                    dict_field = pa.field(column_name, dict_array.type, nullable=False)
                    table = pa.Table.from_arrays([dict_array], schema=pa.schema([dict_field]))
                
                try:
                    # Write parquet file
                    pq.write_table(
                        table,
                        output_file,
                        compression=compression,
                        data_page_version="1.0",
                        use_dictionary=use_dict
                    )
                    
                    file_size = os.path.getsize(output_file)
                    print(f"    ✓ {filename} ({file_size:,} bytes)")
                    
                except Exception as e:
                    print(f"    ❌ Failed to create {filename}: {e}")
        
        # Generate multi-column file with all 4 data types
        print(f"\nGenerating multi-column file with all 4 data types...")
        
        # Generate data for all 4 types using the same dictionary size and seed
        all_data = {}
        for data_type in data_types:
            dictionary, sampled_values = generate_random_dictionary_data(
                dict_size, num_values, data_type, seed
            )
            column_name = f"col_{data_type}"
            all_data[column_name] = sampled_values
        
        # Create multi-column DataFrame
        multi_df = pd.DataFrame(all_data)
        
        # Create PyArrow schema for all columns
        schema_fields = []
        for data_type in data_types:
            column_name = f"col_{data_type}"
            if data_type == 'int32':
                pa_type = pa.int32()
            elif data_type == 'int64':
                pa_type = pa.int64()
            elif data_type == 'float':
                pa_type = pa.float32()
            elif data_type == 'double':
                pa_type = pa.float64()
            schema_fields.append(pa.field(column_name, pa_type, nullable=False))
        
        multi_schema = pa.schema(schema_fields)
        multi_table = pa.Table.from_pandas(multi_df, schema=multi_schema)
        
        # Generate the 4 dict+snappy variants for multi-column file
        multi_variants = [
            ('dict', 'snappy', 'all_dict_snappy'),
            ('dict', None, 'all_dict'),
            ('plain', 'snappy', 'all_snappy'), 
            ('plain', None, 'all')
        ]
        
        for encoding, compression, variant_name in multi_variants:
            filename = f"dict_{dict_size:04d}_{variant_name}.parquet"
            output_file = os.path.join(output_dir, filename)
            
            # Apply dictionary encoding if requested
            use_dict = (encoding == 'dict')
            table_to_write = multi_table
            
            if use_dict:
                # Force dictionary encoding for all columns
                new_columns = []
                new_fields = []
                for i, field in enumerate(multi_table.schema):
                    dict_array = pa.compute.dictionary_encode(multi_table.column(i))
                    dict_field = pa.field(field.name, dict_array.type, nullable=False)
                    new_columns.append(dict_array)
                    new_fields.append(dict_field)
                table_to_write = pa.Table.from_arrays(new_columns, schema=pa.schema(new_fields))
            
            try:
                # Write parquet file
                pq.write_table(
                    table_to_write,
                    output_file,
                    compression=compression,
                    data_page_version="1.0",
                    use_dictionary=use_dict
                )
                
                file_size = os.path.getsize(output_file)
                print(f"    ✓ {filename} ({file_size:,} bytes)")
                
            except Exception as e:
                print(f"    ❌ Failed to create {filename}: {e}")

def generate_parquet_files(scale_factors: List[int], selected_columns: Optional[List[str]] = None, output_dir: str = None, compression: Optional[str] = None, use_dictionary: bool = False):
    """Generate parquet files directly from dbgen for multiple scale factors"""
    
    if output_dir is None:
        output_dir = "/local/home/ccaspar/fpga-parquet-reader/benchmarks/data_csv/integer_size"
    
    dbgen_dir = "/local/home/ccaspar/fpga-parquet-reader/benchmarks/data_csv/dbgen"
    
    print(f"\n=== Generating Parquet Files ===")
    print(f"Scale factors: {scale_factors}")
    print(f"Selected columns: {selected_columns or 'All columns'}")
    print(f"Compression: {compression}")
    print(f"Use dictionary: {use_dictionary}")
    print(f"Output directory: {output_dir}")
    print(f"DBGEN directory: {dbgen_dir}")
    
    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)
    
    for scale in scale_factors:
        print(f"\n--- Scale Factor {scale} ---")
        
        # Run dbgen
        if not run_dbgen(scale, 'L', dbgen_dir):
            print(f"❌ Failed to generate data for scale {scale}")
            continue
        
        # Analyze the generated TBL file
        tbl_file = os.path.join(dbgen_dir, "lineitem.tbl")
        analysis = analyze_tbl_file(tbl_file)
        
        if not analysis:
            print(f"❌ Failed to analyze {tbl_file}")
            continue
        
        # Generate parquet file based on detected format
        if selected_columns and len(selected_columns) == 1:
            # Single column output
            output_file = os.path.join(output_dir, f"s{scale:02d}_{selected_columns[0].lower()}.parquet")
        else:
            # Multi-column or full output
            suffix = "_selected" if selected_columns else "_full"
            output_file = os.path.join(output_dir, f"s{scale:02d}{suffix}.parquet")
        if not use_dictionary:
            output_file = output_file.replace('.parquet', f"_plain.parquet")
        if compression is not None:
            output_file = output_file.replace('.parquet', f"_snappy.parquet")

        if analysis['format'] == 'single_column':
            # Handle single-column format (current dbgen output)
            column_name = selected_columns[0] if selected_columns else 'L_ORDERKEY'
            success = convert_single_column_to_parquet(tbl_file, output_file, column_name, compression, use_dictionary)
        else:
            # Handle multi-column format (proper TPC-H output)
            success = convert_multi_column_to_parquet(tbl_file, output_file, selected_columns, compression, use_dictionary)
        
        if success:
            print(f"✓ Generated: {output_file}")
        else:
            print(f"❌ Failed to generate: {output_file}")

def create_parser():
    """Create the argument parser"""
    parser = argparse.ArgumentParser(
        description="TPC-H Data Generator - Direct DBGEN to Parquet Conversion",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 gen.py schema
  python3 gen.py examine lineitem.tbl
  python3 gen.py examine data.parquet
  python3 gen.py existing
  python3 gen.py generate --scales 1,2,3
  python3 gen.py generate --scales 1 --columns L_ORDERKEY
  python3 gen.py generate --scales 1 --columns L_LINENUMBER --use-dict
  python3 gen.py generate --scales 1 --columns L_LINENUMBER --compression snappy
  python3 gen.py generate --scales 1 --columns L_LINENUMBER --use-dict --compression snappy
  python3 gen.py dict-mode --dict-sizes 10,100,1000
  python3 gen.py dict-mode --dict-sizes 50,500 --num-values 2000000
  python3 gen.py dict-mode --dict-sizes 1000 --seed 123 --output-dir ./custom_dict_output
  python3 gen.py size-mode --dict-sizes 10,100,1000 --target-size 1048576
  python3 gen.py size-mode --dict-sizes 50,500 --target-size 5242880 --seed 123
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Schema command
    schema_parser = subparsers.add_parser('schema', help='Print TPC-H LINEITEM schema')
    
    # Examine command
    examine_parser = subparsers.add_parser('examine', help='Examine TBL or Parquet file')
    examine_parser.add_argument('file', help='Path to .tbl or .parquet file to examine')
    
    # Existing command
    existing_parser = subparsers.add_parser('existing', help='Examine existing parquet files')
    
    # Generate command
    generate_parser = subparsers.add_parser('generate', help='Generate parquet files')
    generate_parser.add_argument('--scales', '-s', required=True, 
                                help='Comma-separated scale factors (e.g., 1,2,3)')
    generate_parser.add_argument('--columns', '-c', 
                                help='Comma-separated column names (optional)')
    generate_parser.add_argument('--use-dict', '--use-dictionary', action='store_true',
                                help='Use dictionary encoding for low-cardinality columns')
    generate_parser.add_argument('--compression', choices=['snappy', 'none'], 
                                help='Compression codec (optional)')
    generate_parser.add_argument('--cardinality-threshold', type=int, default=1000,
                                help='Maximum distinct values for dictionary encoding (default: 1000)')
    
    # Dictionary mode command
    dict_parser = subparsers.add_parser('dict-mode', help='Generate parquet files with controllable dictionary size')
    dict_parser.add_argument('--dict-sizes', '-d', required=True,
                            help='Comma-separated dictionary sizes (e.g., 10,100,1000)')
    dict_parser.add_argument('--num-values', '-n', type=int, default=1000000,
                            help='Number of values per column (default: 1,000,000)')
    dict_parser.add_argument('--seed', type=int, default=42,
                            help='Random seed for reproducibility (default: 42)')
    dict_parser.add_argument('--output-dir', '-o',
                            help='Output directory (default: benchmarks/data_csv/dictionary_size)')
    
    # Size mode command
    size_parser = subparsers.add_parser('size-mode', help='Generate parquet files scaled to target file size')
    size_parser.add_argument('--dict-sizes', '-d', required=True,
                            help='Comma-separated dictionary sizes (e.g., 10,100,1000)')
    size_parser.add_argument('--target-size', '-t', type=int, required=True,
                            help='Target file size in bytes (e.g., 1048576 for 1MB)')
    size_parser.add_argument('--seed', type=int, default=42,
                            help='Random seed for reproducibility (default: 42)')
    size_parser.add_argument('--output-dir', '-o',
                            help='Output directory (default: benchmarks/data_csv/size_mode)')
    
    return parser

def main():
    parser = create_parser()
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    if args.command == "schema":
        print_schema_info()
    
    elif args.command == "examine":
        if args.file.endswith('.tbl'):
            analyze_tbl_file(args.file)
        elif args.file.endswith('.parquet'):
            examine_existing_parquet(args.file)
        else:
            print("File must be .tbl or .parquet")
    
    elif args.command == "existing":
        # Examine existing TPC-H parquet files
        tpch_dir = "/local/home/ccaspar/fpga-parquet-reader/maximus/tests/tpch/parquet"
        if os.path.exists(tpch_dir):
            print("=== Existing TPC-H Parquet Files ===")
            for file in sorted(os.listdir(tpch_dir)):
                if file.endswith('.parquet'):
                    examine_existing_parquet(os.path.join(tpch_dir, file))
        else:
            print(f"Directory not found: {tpch_dir}")
    
    elif args.command == "generate":
        # Parse scale factors
        try:
            if ',' in args.scales:
                scales = [int(x.strip()) for x in args.scales.split(',')]
            else:
                scales = [int(args.scales)]
        except ValueError:
            print(f"Invalid scale factors: {args.scales}")
            sys.exit(1)
        
        # Parse selected columns
        selected_columns = None
        if args.columns:
            if ',' in args.columns:
                selected_columns = [x.strip().upper() for x in args.columns.split(',')]
            else:
                selected_columns = [args.columns.strip().upper()]
            
            # Validate column names
            invalid_columns = [col for col in selected_columns if col not in TPCH_LINEITEM_SCHEMA]
            if invalid_columns:
                print(f"Invalid column names: {invalid_columns}")
                print(f"Valid columns: {list(TPCH_LINEITEM_SCHEMA.keys())}")
                sys.exit(1)
        
        # Handle compression
        compression = args.compression if args.compression != 'none' else None
        
        # Generate parquet files
        generate_parquet_files(
            scales, 
            selected_columns, 
            compression=compression, 
            use_dictionary=args.use_dict
        )
        
        # If compression specified, also generate plain parquet files
        if compression is not None:
            generate_parquet_files(
                scales, 
                selected_columns, 
                compression=None, 
                use_dictionary=args.use_dict
            )
    
    elif args.command == "dict-mode":
        # Parse dictionary sizes
        try:
            if ',' in args.dict_sizes:
                dict_sizes = [int(x.strip()) for x in args.dict_sizes.split(',')]
            else:
                dict_sizes = [int(args.dict_sizes)]
        except ValueError:
            print(f"Invalid dictionary sizes: {args.dict_sizes}")
            sys.exit(1)
        
        # Generate dictionary mode parquet files
        generate_dictionary_mode_parquet_files(
            dict_sizes=dict_sizes,
            num_values=args.num_values,
            output_dir=args.output_dir,
            seed=args.seed
        )
    
    elif args.command == "size-mode":
        # Parse dictionary sizes
        try:
            if ',' in args.dict_sizes:
                dict_sizes = [int(x.strip()) for x in args.dict_sizes.split(',')]
            else:
                dict_sizes = [int(args.dict_sizes)]
        except ValueError:
            print(f"Invalid dictionary sizes: {args.dict_sizes}")
            sys.exit(1)
        
        # Generate size mode parquet files
        generate_size_mode_parquet_files(
            dict_sizes=dict_sizes,
            target_size=args.target_size,
            output_dir=args.output_dir,
            seed=args.seed
        )

if __name__ == "__main__":
    main()