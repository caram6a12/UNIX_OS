#!/bin/sh

DIR="/data"
LOCK="$DIR/.sync.lock"

ID=$(cat /proc/sys/kernel/random/uuid)

SEQ=1

mkdir -p "$DIR"

while true; do
    CREATED=""

    exec 9>"$LOCK"
    flock 9

    i=1
    while [ $i -le 999 ]; do
        NAME=$(printf "%03d" $i)
        TARGET="$DIR/$NAME"

        if [ ! -e "$TARGET" ]; then
            echo "$ID $SEQ" > "$TARGET"
            CREATED="$NAME"
            break
        fi
        i=$((i + 1))
    done

    exec 9>&-

    if [ -z "$CREATED" ]; then
        sleep 1
        continue
    fi

    sleep 1

    rm -f "$DIR/$CREATED"

    SEQ=$((SEQ + 1))
done