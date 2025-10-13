#!/usr/bin/env python3

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import os

def test_nullable_vs_non_nullable():
    """Test the difference between nullable and non-nullable parquet schemas"""
    
    # Create test data
    data = {
        'L_ORDERKEY': [1, 2, 3, 4, 5],
        'L_PARTKEY': [100, 200, 300, 400, 500],
        'L_QUANTITY': [10.0, 20.0, 30.0, 40.0, 50.0]
    }
    df = pd.DataFrame(data)
    
    print("=== Test Data ===")
    print(df)
    print()
    
    # Test 1: Nullable schema (old way)
    print("=== Test 1: Nullable Schema (Default) ===")
    nullable_schema = pa.schema([
        ('L_ORDERKEY', pa.int64()),
        ('L_PARTKEY', pa.int64()),
        ('L_QUANTITY', pa.float64())
    ])
    
    print("Nullable schema:")
    print(nullable_schema)
    
    nullable_table = pa.Table.from_pandas(df, schema=nullable_schema)
    pq.write_table(nullable_table, 'test_nullable.parquet', compression=None)
    
    print(f"Nullable file size: {os.path.getsize('test_nullable.parquet'):,} bytes")
    print()
    
    # Test 2: Non-nullable schema (new way)
    print("=== Test 2: Non-nullable Schema (FPGA Optimized) ===")
    non_nullable_schema = pa.schema([
        pa.field('L_ORDERKEY', pa.int64(), nullable=False),
        pa.field('L_PARTKEY', pa.int64(), nullable=False),
        pa.field('L_QUANTITY', pa.float64(), nullable=False)
    ])
    
    print("Non-nullable schema:")
    print(non_nullable_schema)
    
    non_nullable_table = pa.Table.from_pandas(df, schema=non_nullable_schema)
    pq.write_table(non_nullable_table, 'test_non_nullable.parquet', compression=None)
    
    print(f"Non-nullable file size: {os.path.getsize('test_non_nullable.parquet'):,} bytes")
    print()
    
    # Compare file sizes
    nullable_size = os.path.getsize('test_nullable.parquet')
    non_nullable_size = os.path.getsize('test_non_nullable.parquet')
    savings = nullable_size - non_nullable_size
    savings_pct = (savings / nullable_size) * 100 if nullable_size > 0 else 0
    
    print("=== Comparison ===")
    print(f"Nullable file:     {nullable_size:,} bytes")
    print(f"Non-nullable file: {non_nullable_size:,} bytes")
    print(f"Space savings:     {savings:,} bytes ({savings_pct:.1f}%)")
    
    if savings > 0:
        print("✅ Non-nullable schema is more efficient (no definition levels stored)")
    elif savings == 0:
        print("ℹ️  Same size (might vary with larger datasets)")
    else:
        print("⚠️  Unexpected result - non-nullable file is larger")
    
    print()
    
    # Verify schemas in the files
    print("=== Schema Verification ===")
    nullable_file = pq.read_table('test_nullable.parquet')
    non_nullable_file = pq.read_table('test_non_nullable.parquet')
    
    print("Nullable file schema:")
    for field in nullable_file.schema:
        nullable_status = "nullable" if field.nullable else "not null"
        print(f"  {field.name}: {field.type} ({nullable_status})")
    
    print("Non-nullable file schema:")
    for field in non_nullable_file.schema:
        nullable_status = "nullable" if field.nullable else "not null"
        print(f"  {field.name}: {field.type} ({nullable_status})")
    
    # Clean up
    os.remove('test_nullable.parquet')
    os.remove('test_non_nullable.parquet')
    
    print("\n✅ Test completed successfully!")

if __name__ == "__main__":
    test_nullable_vs_non_nullable()
