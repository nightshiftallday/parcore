#!/bin/bash
echo "SENDING NOTIFICATION"
WEBHOOK="ntfy.sh/vivado-synth"
if [ "$1" = "started" ]; then
    MESSAGE="Synthesis started"
elif [ "$1" = "finished" ]; then
    # JSON escape the input
    # We need tail and head to cut of the "" inserted by jq
    LAST_LINES=$(echo "$3" | jq -R -s '.' | tail -c +2 | head -c -2 )
    MESSAGE="Synthesis exited with code $2\nLast output lines:\n\`\`\`$LAST_LINES\`\`\`"
fi

curl -d "$MESSAGE" "$WEBHOOK"
