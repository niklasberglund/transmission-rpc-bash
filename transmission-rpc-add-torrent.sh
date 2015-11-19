#!/bin/sh

HOST_ARG="127.0.0.1:9092" # host passed to curl invocations
USER_PASSWORD_ARG="" # curl invocations' --user argument

HOST_STRING=$1
TORRENT_PATH=$2

FILE_NAME="" # will be set further down after reading options with getopts. Added here for brevity.

function usage {
    echo "
    Usage: $0 [options] <Torrent address>

    This script adds a torrent for download through Transmission's RPC protocol.
    
    EXAMPLE:
        $0 -s my-server.com -u myUsername -p myPassword \"http://www.frostclick.com/torrents/video/animation/Big_Buck_Bunny_1080p_surround_frostclick.com_frostwire.com.torrent\"

    OPTIONS:
       -h      Show this message
       -s      Server hostname and optionally port in the format host:port. Defaults to 127.0.0.1:9092 if not specified.
       -u      Server username
       -p      Server password
    "
}

function torrent_percent_done {
    ARG_ID=$1
    
    TORRENT_GET=$(curl --silent --anyauth$USER_PASSWORD_ARG --header "$SESSION_HEADER" "http://$HOST_ARG/transmission/rpc" -d "{\"method\":\"torrent-get\",\"arguments\": {\"ids\":$ARG_ID,\"fields\":[\"id\",\"percentDone\"]}}")
    PERCENT_DONE=$(echo $TORRENT_GET | sed 's/.*percentDone\"://g;s/\}.*//g')
    PERCENT=$(perl -e "printf('%.0f', $PERCENT_DONE*100)")
    
    echo $PERCENT
}

function progress_visualiser {
    ARG_PERCENT=$1
    
    OUTPUT_STRING=""
    STEPS=50
    STEPS_COMPLETED=$(perl -e "print int(($ARG_PERCENT/100) * $STEPS)")
    
    OUTPUT_STRING="$OUTPUT_STRING $ARG_PERCENT%%  "
    
    OUTPUT_STRING="$OUTPUT_STRING| "
    
    for i in $(seq 1 $STEPS_COMPLETED)
    do
        OUTPUT_STRING="$OUTPUT_STRING#"
    done
    
    for j in $(seq $STEPS_COMPLETED $STEPS)
    do
        OUTPUT_STRING="$OUTPUT_STRING-"
    done
    
    OUTPUT_STRING="$OUTPUT_STRING |"
    
    printf "\r$OUTPUT_STRING  "
}

SPINNER_INDEX=0
function spinner {
    SPINNER_CHARACTERS="◴◷◶◵"
    SPINNER_CHARACTER_COUNT=4
    
    let SPINNER_INDEX=$SPINNER_INDEX+1
}


while getopts "hs:u:p:" OPTION
do
    case $OPTION in
        h)
            usage
            exit 0
            ;;
        u)
            echo "user $OPTARG"
            RPC_USER=$OPTARG
            ;;
        p)
            echo "password $OPTARG"
            RPC_PASSWORD=$OPTARG
            ;;
        \?)
            exit 1
            ;;
    esac
done

FILE_NAME=${@:$OPTIND:1}

# set USER_PASSWORD_ARG
if [ ! -z "$RPC_USER" ] && [ ! -z "$RPC_PASSWORD" ]
then
    USER_PASSWORD_ARG=" --user $RPC_USER:$RPC_PASSWORD"
elif [ ! -z "$RPC_USER" ]
then
    USER_PASSWORD_ARG=" --user $RPC_USER"
elif [ ! -z "$RPC_PASSWORD" ]
then
    echo "You specified a password but no username"
    exit 1
fi

SESSION_HEADER=$(curl --silent --anyauth$USER_PASSWORD_ARG $HOST_ARG/transmission/rpc/ | sed 's/.*<code>//g;s/<\/code>.*//g')


ADD_RESULT=$(curl --silent --anyauth$USER_PASSWORD_ARG --header "$SESSION_HEADER" "http://$HOST_ARG/transmission/rpc" -d "{\"method\":\"torrent-add\",\"arguments\":{\"paused\":false,\"filename\":\"${FILE_NAME}\"}}")
TORRENT_ID=$(echo $ADD_RESULT | sed 's/.*id\"://g;s/\,.*//g')
#TORRENT_NAME=$(echo $ADD_RESULT | sed 's/.*name\":\"//g;s/\"\}.*//g')
#echo $ADD_RESULT
echo $TORRENT_ID
echo "result"
echo $ADD_RESULT

if [ -z "$ADD_RESULT" ]
then
    echo "Could not connect to server. Verify that hostname and port is correct."
    exit 1
fi

if [ ! -z "$(echo "$ADD_RESULT" | grep "Unauthorized User")" ]
then
    echo "Reached server but could not log on. Verify that the login credentials are correct."
fi

echo "Downloading $TORRENT_NAME"

PERCENT_DONE=$(torrent_percent_done 576)

while [ $PERCENT_DONE -lt 100 ]
do
    PERCENT_DONE=$(torrent_percent_done 576)
    
    progress_visualiser $PERCENT_DONE
    sleep 1
done
