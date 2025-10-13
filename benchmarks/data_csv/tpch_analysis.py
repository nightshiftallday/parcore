#!/usr/bin/env python3

import pandas as pd
import pyarrow.parquet as pq
import pyarrow as pa
import numpy as np
import os
import sys

# TPC-H LINEITEM schema with null constraints from dss.ddl
TPCH_LINEITEM_COLUMNS = {
    'L_ORDERKEY': {
        'type': 'INTEGER',
        'parquet_type': pa.int64(),
        'parquet_field': pa.field('L_ORDERKEY', pa.int64(), nullable=False),
        'not_null': True,
        'description': 'Order identifier - PRIMARY KEY component',
        'fpga_compatible': True
    },
    'L_PARTKEY': {
        'type': 'INTEGER', 
        'parquet_type': pa.int64(),
        'parquet_field': pa.field('L_PARTKEY', pa.int64(), nullable=False),
        'not_null': True,
        'description': 'Part identifier - FOREIGN KEY',
        'fpga_compatible': True
    },
    'L_SUPPKEY': {
        'type': 'INTEGER',
        'parquet_type': pa.int64(),
        'parquet_field': pa.field('L_SUPPKEY', pa.int64(), nullable=False),
        'not_null': True,
        'description': 'Supplier identifier - FOREIGN KEY',
        'fpga_compatible': True
    },
    'L_LINENUMBER': {
        'type': 'INTEGER',
        'parquet_type': pa.int32(),
        'parquet_field': pa.field('L_LINENUMBER', pa.int32(), nullable=False),
        'not_null': True,
        'description': 'Line number within order - PRIMARY KEY component',
        'fpga_compatible': True
    },
    'L_QUANTITY': {
        'type': 'DECIMAL(15,2)',
        'parquet_type': pa.float64(),
        'parquet_field': pa.field('L_QUANTITY', pa.float64(), nullable=False),
        'not_null': True,
        'description': 'Quantity ordered',
        'fpga_compatible': True
    },
    'L_EXTENDEDPRICE': {
        'type': 'DECIMAL(15,2)',
        'parquet_type': pa.float64(),
        'parquet_field': pa.field('L_EXTENDEDPRICE', pa.float64(), nullable=False),
        'not_null': True,
        'description': 'Extended price',
        'fpga_compatible': True
    },
    'L_DISCOUNT': {
        'type': 'DECIMAL(15,2)',
        'parquet_type': pa.float64(),
        'parquet_field': pa.field('L_DISCOUNT', pa.float64(), nullable=False),
        'not_null': True,
        'description': 'Discount percentage (0.00-0.10)',
        'fpga_compatible': True
    },
    'L_TAX': {
        'type': 'DECIMAL(15,2)',
        'parquet_type': pa.float64(),
        'parquet_field': pa.field('L_TAX', pa.float64(), nullable=False),
        'not_null': True,
        'description': 'Tax rate (0.00-0.08)',
        'fpga_compatible': True
    },
    'L_RETURNFLAG': {
        'type': 'CHAR(1)',
        'parquet_type': pa.string(),
        'not_null': True,
        'description': 'Return flag (A/R/N)',
        'fpga_compatible': False,
        'reason': 'String type - excluded in current FPGA design'
    },
    'L_LINESTATUS': {
        'type': 'CHAR(1)',
        'parquet_type': pa.string(),
        'not_null': True,
        'description': 'Line status (O/F)',
        'fpga_compatible': False,
        'reason': 'String type - excluded in current FPGA design'
    },
    'L_SHIPDATE': {
        'type': 'DATE',
        'parquet_type': pa.date32(),
        'not_null': True,
        'description': 'Ship date',
        'fpga_compatible': False,
        'reason': 'Date type - excluded in current FPGA design'
    },
    'L_COMMITDATE': {
        'type': 'DATE',
        'parquet_type': pa.date32(),
        'not_null': True,
        'description': 'Commit date',
        'fpga_compatible': False,
        'reason': 'Date type - excluded in current FPGA design'
    },
    'L_RECEIPTDATE': {
        'type': 'DATE',
        'parquet_type': pa.date32(),
        'not_null': True,
        'description': 'Receipt date',
        'fpga_compatible': False,
        'reason': 'Date type - excluded in current FPGA design'
    },
    'L_SHIPINSTRUCT': {
        'type': 'CHAR(25)',
        'parquet_type': pa.string(),
        'not_null': True,
        'description': 'Shipping instructions',
        'fpga_compatible': False,
        'reason': 'String type - excluded in current FPGA design'
    },
    'L_SHIPMODE': {
        'type': 'CHAR(10)',
        'parquet_type': pa.string(),
        'not_null': True,
        'description': 'Shipping mode',
        'fpga_compatible': False,
        'reason': 'String type - excluded in current FPGA design'
    },
    'L_COMMENT': {
        'type': 'VARCHAR(44)',
        'parquet_type': pa.string(),
        'not_null': True,
        'description': 'Comment',
        'fpga_compatible': False,
        'reason': 'String type - excluded in current FPGA design'
    }
}

def print_tpch_analysis():
    """Print comprehensive TPC-H LINEITEM analysis"""
    print("=" * 80)
    print("TPC-H LINEITEM TABLE ANALYSIS FOR FPGA COMPATIBILITY")
    print("=" * 80)
    
    fpga_compatible = [col for col, info in TPCH_LINEITEM_COLUMNS.items() if info['fpga_compatible']]
    fpga_incompatible = [col for col, info in TPCH_LINEITEM_COLUMNS.items() if not info['fpga_compatible']]
    
    print(f"\nTOTAL COLUMNS: {len(TPCH_LINEITEM_COLUMNS)}")
    print(f"FPGA COMPATIBLE: {len(fpga_compatible)} (numerical columns only)")
    print(f"FPGA INCOMPATIBLE: {len(fpga_incompatible)} (strings/dates - excluded)")
    
    print(f"\n{'='*40} FPGA COMPATIBLE COLUMNS {'='*40}")
    print(f"{'Column':<20} {'SQL Type':<15} {'Parquet Type':<15} {'NULL?':<8} {'Description'}")
    print("-" * 95)
    
    for col in fpga_compatible:
        info = TPCH_LINEITEM_COLUMNS[col]
        null_status = "NO" if info['not_null'] else "YES"
        print(f"{col:<20} {info['type']:<15} {str(info['parquet_type']):<15} {null_status:<8} {info['description']}")
    
    print(f"\n✅ EXCELLENT NEWS: All {len(fpga_compatible)} numerical columns are defined as NOT NULL in TPC-H!")
    print("   This means they should NEVER contain null values by design.")
    
    print(f"\n{'='*40} EXCLUDED COLUMNS {'='*40}")
    print(f"{'Column':<20} {'SQL Type':<15} {'Reason'}")
    print("-" * 60)
    
    for col in fpga_incompatible:
        info = TPCH_LINEITEM_COLUMNS[col]
        print(f"{col:<20} {info['type']:<15} {info['reason']}")
    
    return fpga_compatible, fpga_incompatible

def analyze_parquet_compatibility(file_path, expected_columns=None):
    """Analyze a parquet file for FPGA compatibility"""
    print(f"\n{'='*60}")
    print(f"ANALYZING: {file_path}")
    print(f"{'='*60}")
    
    if not os.path.exists(file_path):
        print(f"❌ File not found: {file_path}")
        return None
    
    try:
        table = pq.read_table(file_path)
        df = table.to_pandas()
        
        print(f"Shape: {df.shape[0]:,} rows × {df.shape[1]} columns")
        print(f"File size: {os.path.getsize(file_path):,} bytes")
        
        # Check schema compatibility
        file_columns = list(df.columns)
        if expected_columns is None:
            expected_columns = [col for col, info in TPCH_LINEITEM_COLUMNS.items() if info['fpga_compatible']]
        
        print(f"\nSCHEMA COMPATIBILITY:")
        print(f"Expected FPGA columns: {len(expected_columns)}")
        print(f"File columns: {len(file_columns)}")
        
        # Check column alignment
        missing_columns = set(expected_columns) - set(file_columns)
        extra_columns = set(file_columns) - set(expected_columns)
        matching_columns = set(expected_columns) & set(file_columns)
        
        if missing_columns:
            print(f"❌ Missing columns: {sorted(missing_columns)}")
        if extra_columns:
            print(f"⚠️  Extra columns: {sorted(extra_columns)}")
        if matching_columns:
            print(f"✅ Matching columns: {len(matching_columns)}/{len(expected_columns)}")
        
        # Null analysis
        print(f"\nNULL VALUE ANALYSIS:")
        has_nulls = False
        null_summary = {}
        
        for col in df.columns:
            null_count = df[col].isnull().sum()
            null_percentage = (null_count / len(df)) * 100 if len(df) > 0 else 0
            
            if null_count > 0:
                has_nulls = True
                null_summary[col] = {'count': null_count, 'percentage': null_percentage}
                print(f"❌ {col}: {null_count:,} nulls ({null_percentage:.2f}%)")
            else:
                print(f"✅ {col}: No nulls")
        
        # Data type analysis
        print(f"\nDATA TYPE ANALYSIS:")
        for col in df.columns:
            dtype = df[col].dtype
            expected_info = TPCH_LINEITEM_COLUMNS.get(col)
            
            if expected_info:
                expected_type = expected_info['parquet_type']
                type_compatible = _is_type_compatible(dtype, expected_type)
                status = "✅" if type_compatible else "⚠️ "
                print(f"{status} {col:<20}: {dtype} (expected: {expected_type})")
            else:
                print(f"? {col:<20}: {dtype} (unknown column)")
        
        # Value range analysis for numerical columns
        print(f"\nVALUE RANGE ANALYSIS:")
        for col in df.columns:
            if df[col].dtype in ['int64', 'int32', 'float64']:
                min_val = df[col].min()
                max_val = df[col].max()
                unique_count = df[col].nunique()
                
                print(f"{col:<20}: [{min_val:>12}, {max_val:>12}] ({unique_count:,} unique values)")
                
                # Check for suspicious values
                if df[col].dtype in ['int64', 'int32']:
                    negative_count = (df[col] < 0).sum()
                    zero_count = (df[col] == 0).sum()
                    if negative_count > 0:
                        print(f"  ⚠️  {negative_count:,} negative values")
                    if zero_count > 0 and col in ['L_ORDERKEY', 'L_PARTKEY', 'L_SUPPKEY']:
                        print(f"  ⚠️  {zero_count:,} zero values (suspicious for ID columns)")
        
        # Final verdict
        print(f"\nFPGA COMPATIBILITY VERDICT:")
        if has_nulls:
            print("❌ FILE NOT COMPATIBLE: Contains null values")
            print("   SOLUTION: Use patch functionality or regenerate data")
        elif not matching_columns:
            print("❌ FILE NOT COMPATIBLE: No matching columns")
        elif missing_columns:
            print("⚠️  PARTIALLY COMPATIBLE: Missing some expected columns")
        else:
            print("✅ FILE FULLY COMPATIBLE: Ready for FPGA processing!")
        
        return {
            'compatible': not has_nulls and len(matching_columns) > 0,
            'has_nulls': has_nulls,
            'null_summary': null_summary,
            'matching_columns': matching_columns,
            'missing_columns': missing_columns,
            'extra_columns': extra_columns
        }
        
    except Exception as e:
        print(f"❌ Error analyzing {file_path}: {e}")
        return None

def _is_type_compatible(actual_dtype, expected_parquet_type):
    """Check if actual pandas dtype is compatible with expected PyArrow type"""
    dtype_str = str(actual_dtype)
    expected_str = str(expected_parquet_type)
    
    # Simple compatibility checks
    if 'int' in dtype_str and 'int' in expected_str:
        return True
    if 'float' in dtype_str and ('double' in expected_str or 'float' in expected_str):
        return True
    if 'object' in dtype_str and 'string' in expected_str:
        return True
    
    return False

def generate_fpga_compatible_parquet(input_file, output_file=None):
    """Generate an FPGA-compatible version of a parquet file"""
    if output_file is None:
        base, ext = os.path.splitext(input_file)
        output_file = f"{base}_fpga_compatible{ext}"
    
    print(f"\nGENERATING FPGA-COMPATIBLE FILE:")
    print(f"Input:  {input_file}")
    print(f"Output: {output_file}")
    
    try:
        table = pq.read_table(input_file)
        df = table.to_pandas()
        
        # Select only FPGA-compatible columns
        fpga_columns = [col for col, info in TPCH_LINEITEM_COLUMNS.items() if info['fpga_compatible']]
        available_fpga_columns = [col for col in fpga_columns if col in df.columns]
        
        if not available_fpga_columns:
            print("❌ No FPGA-compatible columns found in input file")
            return False
        
        # Create cleaned DataFrame
        cleaned_df = df[available_fpga_columns].copy()
        
        # Fill any nulls with appropriate defaults
        null_fixes = {}
        for col in cleaned_df.columns:
            null_count = cleaned_df[col].isnull().sum()
            if null_count > 0:
                if cleaned_df[col].dtype in ['int64', 'int32']:
                    cleaned_df[col] = cleaned_df[col].fillna(0)
                    null_fixes[col] = f"{null_count:,} nulls → 0"
                elif cleaned_df[col].dtype in ['float64']:
                    cleaned_df[col] = cleaned_df[col].fillna(0.0)
                    null_fixes[col] = f"{null_count:,} nulls → 0.0"
        
        # Create proper non-nullable schema
        schema_fields = []
        for col in cleaned_df.columns:
            if col in TPCH_LINEITEM_COLUMNS:
                schema_fields.append(TPCH_LINEITEM_COLUMNS[col]['parquet_field'])
        
        schema = pa.schema(schema_fields)
        
        # Write parquet file
        cleaned_table = pa.Table.from_pandas(cleaned_df, schema=schema)
        pq.write_table(
            cleaned_table,
            output_file,
            compression=None,
            data_page_version="1.0",
            use_dictionary=False
        )
        
        print(f"✅ Successfully created: {output_file}")
        print(f"   Rows: {len(cleaned_df):,}")
        print(f"   Columns: {len(cleaned_df.columns)} (FPGA-compatible only)")
        print(f"   Size: {os.path.getsize(output_file):,} bytes")
        
        if null_fixes:
            print(f"   Null fixes applied:")
            for col, fix in null_fixes.items():
                print(f"     {col}: {fix}")
        
        return True
        
    except Exception as e:
        print(f"❌ Error generating FPGA-compatible file: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        print("TPC-H LINEITEM Analysis and FPGA Compatibility Tool")
        print("\nUsage:")
        print("  python3 tpch_analysis.py schema                     # Show TPC-H schema analysis")
        print("  python3 tpch_analysis.py analyze <file>             # Analyze parquet file compatibility")
        print("  python3 tpch_analysis.py analyze-all                # Analyze all parquet files")
        print("  python3 tpch_analysis.py fix <input> [output]       # Generate FPGA-compatible version")
        print("\nExamples:")
        print("  python3 tpch_analysis.py schema")
        print("  python3 tpch_analysis.py analyze integer_size/s01_full.parquet")
        print("  python3 tpch_analysis.py analyze-all")
        print("  python3 tpch_analysis.py fix input.parquet output_fpga.parquet")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "schema":
        fpga_compatible, fpga_incompatible = print_tpch_analysis()
        
        print(f"\n{'='*40} SUMMARY {'='*40}")
        print("🎯 FPGA DESIGN IMPLICATIONS:")
        print(f"   • Use only the {len(fpga_compatible)} numerical columns")
        print("   • All numerical columns are NOT NULL by TPC-H specification")
        print("   • No null handling needed in FPGA design (by specification)")
        print("   • String/date columns excluded from FPGA processing")
        
        print(f"\n📋 RECOMMENDED PARQUET SCHEMA:")
        for col in fpga_compatible:
            info = TPCH_LINEITEM_COLUMNS[col]
            print(f"   {col}: {info['parquet_type']}")
    
    elif command == "analyze" and len(sys.argv) > 2:
        file_path = sys.argv[2]
        analyze_parquet_compatibility(file_path)
    
    elif command == "analyze-all":
        # Find all parquet files
        search_dirs = ["dbgen/", "integer_size/", "."]
        parquet_files = []
        
        for search_dir in search_dirs:
            if os.path.exists(search_dir):
                for file in os.listdir(search_dir):
                    if file.endswith('.parquet'):
                        parquet_files.append(os.path.join(search_dir, file))
        
        if not parquet_files:
            print("No parquet files found!")
            return
        
        print(f"Found {len(parquet_files)} parquet files to analyze:")
        
        compatible_files = []
        incompatible_files = []
        
        for file_path in sorted(parquet_files):
            result = analyze_parquet_compatibility(file_path)
            if result:
                if result['compatible']:
                    compatible_files.append(file_path)
                else:
                    incompatible_files.append(file_path)
        
        print(f"\n{'='*60}")
        print("FINAL SUMMARY")
        print(f"{'='*60}")
        print(f"✅ FPGA-Compatible files: {len(compatible_files)}")
        for f in compatible_files:
            print(f"   {f}")
        
        print(f"❌ Incompatible files: {len(incompatible_files)}")
        for f in incompatible_files:
            print(f"   {f}")
    
    elif command == "fix" and len(sys.argv) > 2:
        input_file = sys.argv[2]
        output_file = sys.argv[3] if len(sys.argv) > 3 else None
        generate_fpga_compatible_parquet(input_file, output_file)
    
    else:
        print("Unknown command. Use 'schema', 'analyze', 'analyze-all', or 'fix'")
        sys.exit(1)

if __name__ == "__main__":
    main()
