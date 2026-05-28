# ParCore Project
This repo contains a hardware design to read Parquet column chunks of specific compression/encoding 
combinations (Snappy or no compression, plain and dictionary/hybrid encoding). ParCore depends on 
[libSTF](https://github.com/fpgasystems/libstf) and [VHSNUnzip](https://github.com/abs-tudelft/vhsnunzip).

The hardware component requires the libstf submodule and its dependencies to be loaded by either 
cloning this repo with submodules directly:

```bash
git clone --recurse-submodules git@github.com:celeris-labs/parcore.git
```

Or initializing the submodules as a step after cloning:

```bash
git submodule update --init --recursive
```

## Hardware
The functionality of the hardware component can be verified with unit tests that are built on top of 
the Coyote unit test framework. We also describe how to synthesize the hardware.

### Unit tests
To run the unit tests, the Vivado simulation project needs to be set up:

```bash
./scripts/setup_simulation.sh
```

After this is finished, VSCode shows the unit tests as a test flask on the left side. The simulation
project needs to be regenerated whenever new files are added (also for the dependencies).

### Synthesis
For synthesis, execute the following command:

```bash
./scripts/synthesize.sh
```

The script spins off the synthesis in the background in a way that the user can disconnect from 
the server without the synthesis stopping. You can check the progress in `hardware/build-**/bitgen.log`. 
It is expected that the synthesis takes multiple hours to finish sometimes not printing anything new 
to the log for a while.

## Deprecated Doc
`./setup_project -b hw/final_bitstreams/<>.bit`. Deployment also injects the design to the FPGA, needs built Coyote driver. 

Requires CMake version 3.31 to be installed locally in the path. Put it in the home folder.

For the future: Maximus setup is disabled at the moment and is not complete. Pass the parameters to CMake in setup_project.sh. Also readd the git submodules dependency.

### Test data

In the folder test_data run `python3 gen.py` creates small Parquet test files for the simulation.

### SW Binaries

The main binaries built are simulation, test_bench and examples. The main methodology is in the common sublibrary functions. 

Simulation offers the most options and debug capabilities while test_bench implements the same logic for deployment. 

### Benchmark data

In folder benchmarks/data_csv run `python3 gen.py` with many options. The file contains information and examples. It uses the dbgen to create tbl files, which are converted to Parquet files. 

The rest are the older benchmarks by Phillip.
