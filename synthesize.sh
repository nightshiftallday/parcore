#/bin/bash 

#source contents for notification
if [ ! -x "./webhook.sh" ]; then
    echo "Webhook file could not be found or was not executable!"
    exit 1
fi

# Script that will run the synthesis and send a webhook notification when it finished or failed.
SYNTH_DIR=build_synth
# Delete old builds
echo "CLEANING UP OLD BUILD DIRECTORY"
rm -r -f $SYNTH_DIR

# Run sim setup
echo "EXECUTING SETUP"
mkdir $SYNTH_DIR
pushd $SYNTH_DIR
/usr/bin/cmake ..
make project
make sim
popd

# Synthesize
./webhook.sh "started"
pushd $SYNTH_DIR
echo "RUNNING SYNTHESIS"
make bitgen 2>&1 | tee synth.out
EXIT_CODE=$?
popd

# Call web hook
DIR=$(pwd)
LAST_LINES=$(tail -n 10 $SYNTH_DIR/synth.out | cat)
LAST_WNS=$(grep -nE "WNS=-?[0-9]+(\.[0-9]+)?" $SYNTH_DIR/synth.out | tail -1)
MESSAGE="DIR: $DIR"$'\n'$'\n'"$LAST_LINES"$'\n'$'\n'"LAST WNS"$'\n'$'\n'"$LAST_WNS"

./webhook.sh "finished" "$EXIT_CODE" "$MESSAGE"
