
SCRIPT_DIR=$(dirname "$(realpath "$0")")
BASE_DIR=$SCRIPT_DIR

# Default value for Maximus toggle
WITH_MAXIMUS="OFF"
BITSTREAM_FILE=""

# Parse named arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--bitstream)
      BITSTREAM_FILE="$2"
      shift 2
      ;;
    --with-maximus)
      WITH_MAXIMUS="ON"
      shift 1
      ;;
    *)  # Unknown option
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done


if [ ! -d "$BASE_DIR/build" ]; then
    mkdir $BASE_DIR/build
fi

pushd $BASE_DIR/build
if [[ -n "$BITSTREAM_FILE" ]]; then
    cmake -DCMAKE_BUILD_TYPE=Release -DDEBUG=ON -DDEBUG_1=ON -DDEBUG_2=ON -DDEBUG_3=OFF -DUSE_HUGEPAGES=ON ..
else
    echo "Building with SIM_DIR=$BASE_DIR/hw/build_sim"
    cmake -DSIM_DIR=$BASE_DIR/hw/build_sim -DCMAKE_BUILD_TYPE=Release -DDEBUG=ON -DDEBUG_1=ON -DDEBUG_2=ON -DDEBUG_3=OFF -DUSE_HUGEPAGES=OFF ..
fi
make
popd

if [[ -n "$BITSTREAM_FILE" ]]; then
    if [[ -f "$BITSTREAM_FILE" ]]; then
    echo "Programming FPGA"
    echo "y" | ./coyote/util/program_hacc_local.sh $BITSTREAM_FILE coyote/driver/build/coyote_driver.ko
    fi
fi
