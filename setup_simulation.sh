#!/bin/bash

rm -rf build-hw
mkdir build-hw
pushd build-hw
/usr/bin/cmake ..
make sim
