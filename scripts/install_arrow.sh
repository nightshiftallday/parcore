#!/bin/bash

# Determine the paths to install into
download_path="$HOME/download"
if [ -n "$DOWNLOAD_PATH" ]; then
  download_path="$DOWNLOAD_PATH"
fi
mkdir -p "${download_path}"

install_path="$HOME/opt"
if [ -n "$INSTALL_PATH" ]; then
  install_path="$INSTALL_PATH"
fi
mkdir -p "${install_path}"

echo "Downloading into ${download_path} and installing into ${install_path}"

# Missing packages in the system
pushd $download_path
git clone https://github.com/JuliaStrings/utf8proc
popd

pushd $download_path/utf8proc
make prefix=$install_path install
pop

pushd $download_path
git clone -b fixed-21.0.0 https://github.com/JonasDann/arrow.git
popd

pushd $download_path/arrow/cpp
mkdir -p build
pushd build

cmake_options=(
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_INSTALL_PREFIX=$install_path"
        "-Dxsimd_SOURCE=BUNDLED"
        "-DARROW_WITH_UTF8PROC=OFF"
        "-DARROW_WITH_RE2=ON"
        "-DARROW_FILESYSTEM=ON"
        "-DARROW_TESTING=OFF"
        "-DARROW_WITH_LZ4=OFF"
        "-DARROW_WITH_ZSTD=OFF"
        "-DARROW_BUILD_STATIC=ON"
        "-DARROW_BUILD_SHARED=ON"
        "-DARROW_BUILD_TESTS=OFF"
        "-DARROW_BUILD_BENCHMARKS=OFF"
        "-DARROW_IPC=ON"
        "-DARROW_FLIGHT=OFF"
        "-DARROW_COMPUTE=ON"
        "-DARROW_CUDA=OFF"
        "-DARROW_JEMALLOC=ON"
        "-DARROW_USE_GLOG=OFF"
        "-DARROW_DATASET=ON"
        "-DARROW_BUILD_UTILITIES=OFF"
        "-DARROW_HDFS=OFF"
        "-DCMAKE_VERBOSE_MAKEFILE=ON"
        "-DARROW_TENSORFLOW=OFF"
        "-DARROW_CSV=ON"
        "-DARROW_JSON=ON"
        "-DARROW_WITH_BROTLI=ON"
        "-DARROW_WITH_SNAPPY=ON"
        "-DARROW_WITH_ZLIB=ON"
        "-DARROW_PARQUET=ON"
        "-DARROW_SUBSTRAIT=OFF"
        "-DCMAKE_VERBOSE_MAKEFILE=ON"
        "-DARROW_ACERO=ON"
        "-DARROW_WITH_BACKTRACE=ON"
        "-DARROW_CXXFLAGS=-w"
        "-DARROW_S3=OFF"
        "-DARROW_ORC=OFF"
        "-DARROW_POSITION_INDEPENDENT_CODE=ON"
        "-DARROW_DEPENDENCY_USE_SHARED=ON"
        "-DARROW_BOOST_USE_SHARED=ON"
        "-DARROW_BROTLI_USE_SHARED=ON"
        "-DARROW_GFLAGS_USE_SHARED=ON"
        "-DARROW_GRPC_USE_SHARED=ON"
        "-DARROW_PROTOBUF_USE_SHARED=ON"
        "-DARROW_ZSTD_USE_SHARED=ON"
        "-DProtobuf_SOURCE=BUNDLED"
        "-DRE2_INCLUDE_DIR=/usr/include/re2"
        "-DRE2_LIB=/usr/lib/x86_64-linux-gnu/libre2.so"
        "-Dutf8proc_LIB=$install_path/lib/libutf8proc.so"
        "-Dutf8proc_INCLUDE_DIR=$install_path/include"
)
cmake "${cmake_options[@]}" ..

make -j
make install
