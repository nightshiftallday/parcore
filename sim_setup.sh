#!/bin/bash

rm -rf build_hw
mkdir build_hw
cd build_hw
/usr/bin/cmake ..
make sim
