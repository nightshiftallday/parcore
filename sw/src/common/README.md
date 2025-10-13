# Common Library

This directory contains the core library files for parquet analysis and standalone binary I/O.

## Files

### Core Library Files
- **`common.h`** - Main header with parquet-dependent data structures and functions
- **`common.cpp`** - Implementation of parquet analysis and reading functions

### Standalone Package (No Parquet Dependencies)
- **`standalone_types.h`** - Data structures without any parquet or thrift dependencies, first metadata store idea for Maximus (outdated)
- **`standalone_binary_io.h`** - Binary I/O functions for reading/writing files between (outdated)
- **`type_converter.h`** - Converts between parquet-dependent and standalone types (outdated)

## Usage Idea for Maximums

### For Systems with Parquet Dependencies
```cpp
#include "common.h"

// Analyze parquet file and save to text + binary
analyseParquetFileToFile("data.parquet");
```

### For Standalone Systems (No Parquet Dependencies)
Copy these files to your system:
```
standalone_types.h
standalone_binary_io.h
```

Then use:
```cpp
#include "standalone_types.h"
#include "standalone_binary_io.h"

// Load binary file in Maximus
std::vector<standalone::row_group_info_compact> row_groups;
parquet_pageinfo::load_row_groups_binary("data_pages.bin", row_groups);
```
