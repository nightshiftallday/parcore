# FPGA Parquet Reader
This repo contains a hardware design to read Parquet data pages of specific compression/encoding combinations.

## Project Setup

* Build with the Coyote simulation setup 

Run `./setup_project`. 
Needs created vivado simulation project.

* Build for deployment. 

`./setup_project -b hw/final_bitstreams/<>.bit`. Deployment also injects the design to the FPGA, needs built Coyote driver. 

Requires CMake version 3.31 to be installed locally in the path. Put it in the home folder.

For the future: Maximus setup is disabled at the moment and is not complete. Pass the parameters to CMake in setup_project.sh. Also readd the git submodules dependency.

### Simulation Setup
* In the hw folder, use `sim_setup.sh` to build the simulation environment. 
* Code changes should automatically be picked up by the simulation (on rerun) unless the changes are to a file in `hw/tst` or new files were created, then those files need to be linked again with `ln -f ../tst/* sim/hdl/` from the build folder.

Use Coyote simulation framework.

### Synthesis Setup
* In the hw folder, use `synth_setup.sh` to start a simulation.
* Code changes are not picked up automatically, so it is advisable to always rebuild on a new synthesis.
* Top module is `src/vfpga_top.svh`.


### Test data

In the folder test_data run `python3 gen.py` creates small Parquet test files for the simulation.

## SW Binaries

The main binaries built are simulation, test_bench and examples. The main methodology is in the common sublibrary functions. 

Simulation offers the most options and debug capabilities while test_bench implements the same logic for deployment. 


## Benchmark data

In folder benchmarks/data_csv run `python3 gen.py` with many options. The file contains information and examples. It uses the dbgen to create tbl files, which are converted to Parquet files. 

The rest are the older benchmarks by Phillip.

### Old Benchmarks by Phillip
* The name of a benchmark folder is the compression + encoding used (`rle` stands for hybrid encoding). The last part is the type of measurement: nothing -> different input sizes; `distinct` -> different numbers of distinct values (bit widths) in dict encoding; `rgs` -> different number of row groups; `ratio` -> varied compression ratio in hybrid encoding
* Each benchmark folder contains:
    * A `data` folder with a `gen.py` script to generate input data.
    * A (symlink to a) bitstream `cyt_top.bit` of the design measured.
    * A `run.sh` script to execute all measurement while rewriting the bitstream in between (because the design or Coyote or something else has been known to crash occasionally).
* The `data_csv` folder handles the generation of TPC-H data in `data_csv/integer_size/gen.sh`. This is a prerequisite for the data generation of the benchmarks that use dictionary encoding (except `rgs`).
* For an explanation of the columns in the output file, see the bottom of `sw/src/main.cpp`.
* For debugging, the SW can be run with `DEBUG` defined to print more output: `cmake -DDEBUG=ON ..` (Note that this will by default also dump the entire output in a file which could take a while for large data sets.)
* The benchmark baseline is implemented in `cpu_reader/main.cpp`.