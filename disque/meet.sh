#!/bin/sh

set -e

HOST=localhost
PORT=
NODES=./nodes.conf
WAIT=2
MAX=-1

while getopts "h:p:f:w:c:" opt; do
    case $opt in
        h)
            HOST="$OPTARG"
            ;;
        p)
            PORT="$OPTARG"
            ;;
        f)
            NODES="$OPTARG"
            ;;
        w)
            WAIT="$OPTARG"
            ;;
        c)
            MAX="$OPTARG"
            ;;
        \?)
            set +x
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            set +x
            echo "Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done
shift $(expr $OPTIND - 1)

# Wait for Disque to be properly started through discovering the existence of
# the nodes configuration file. (see: https://stackoverflow.com/a/6270803 for
# test)
COUNT=$MAX
while { [ -n "$NODES" ] && [ ! -f "$NODES" ]; } && { [ $MAX -lt 0 ] || [ $COUNT -gt 0 ]; }; do
    echo "Waiting for Disque to start..."
    sleep $WAIT
    COUNT=$(($COUNT - 1))
done

# Discover port of locally running disque-server whenever possible and
# necessary.
if [ "$HOST" = "localhost" ] && [ "$PORT" = "" ]; then
    PORT=$(ps -o args|grep disque-server|grep -o -E ':[0-9]+'|cut -c2-)
    if [ -n "$PORT" ]; then
        echo "Discovered port: $PORT"
    fi
fi

# Defaulting to port 7711 for the disque-server whenever none is available.
if [ -z "$PORT" ]; then
    echo "Defaulting to port 7711 for local Disque server connection"
    PORT=7711
fi

# For each remote specification, attempt to meet the cluster. Default to port
# 7711 whenver the port at the remote destination isn't specified.
for REMOTE in "$@"; do
    RHOST=$(echo "$REMOTE"|cut -d : -f 1)
    RPORT=$(echo "$REMOTE"|cut -d : -f 2 -s)
    if [ "$RPORT" = "" ]; then
        RPORT=7711
    fi

    # Stop stopping on errors, since we use error reporting to detect remote host
    # presence. 
    set +e

    COUNT=$MAX
    while true; do
        # Test availability of remote host and port using nc in reporting mode
        # and stop as soon as the port is available or we have reached the max
        # number of attempts.
        echo "Checking availability of ${RHOST}:${RPORT}"
        nc -z $RHOST $RPORT
        if [ ! "$?" ] || { [ $MAX -gt 0 ] && [ $COUNT -le 1 ]; }; then
            break
        fi
        COUNT=$(($COUNT - 1))
        sleep $WAIT
    done

    set -e
    if [ ! "$?" ]; then
        echo "Joining Disque remote at ${RHOST}:${RPORT}"
        disque -p $PORT -h $HOST cluster meet "$RHOST" "$RPORT"
    else
        echo "!! No Disque server at ${RHOST}:${RPORT}, cannot join"
    fi
done