#!/bin/sh

LC_CTYPE=C

HOST_ARG="127.0.0.1:9092" # host passed to curl invocations
USER_PASSWORD_ARG="" # curl invocations' --user argument

TASK_LIST=0
TASK_LIST_PAUSED=0
TASK_ADD=0
COLORED_OUTPUT=0

QUIET_MODE=0 # can be set through the -q flag

TORRENT_LINK="" # will be set further down after reading options with getopts. Added here for brevity.
LOCAL_TORRENT_FILE="" # will be set further down after reading options with getopts. Added here for brevity.
METAINFO="" # will be set with base64 encoded torrent file content if local file is specified

# for text styling
TEXT_RESET=$(tput sgr0)
TEXT_INVERTED=$(tput rev)
TEXT_BOLD=$(tput bold)
FOREGROUND_RED=$(tput setaf 1)
FOREGROUND_GREEN=$(tput setaf 2)
FOREGROUND_BLUE=$(tput setaf 4)
FOREGROUND_YELLOW=$(tput setaf 3)
FOREGROUND_LIGHT_GRAY="$(tput bold)$(tput setaf 7)"
FOREGROUND_LIGHT_RED="$(tput bold)$(tput setaf 1)"
BACKGROUND_RED=$(tput setab 1)

usage() {
cat << EOF
    Usage: $0 [options] <Torrent address or local file path>

    This script adds a torrent for download through Transmission's RPC protocol.
    
    EXAMPLE:
        $0 -s my-server.com:9092 -u myUsername -p myPassword "http://www.frostclick.com/torrents/video/animation/Big_Buck_Bunny_1080p_surround_frostclick.com_frostwire.com.torrent"

    OPTIONS:
       -h      Show this help message
       -s      Server hostname and optionally port in the format host:port. Defaults to 127.0.0.1:9092 if not specified.
       -u      Server username
       -p      Server password
       -l      List active torrents and their progress
       -P      Used together with the -l flag. Makes -l list not only active torrents but also paused ones.
       -q      Quiet mode. Add torrent for download then exit - don't display download progress
       -c      Colored output
EOF
}

torrent_percent_done() {
    ARG_TORRENT_INFO=$1
    
    PERCENT_DONE=$(echo "$ARG_TORRENT_INFO" | sed 's/.*percentDone\"://g;s/\,.*//g')
    PERCENT=$(perl -e "printf('%.0f', $PERCENT_DONE*100)")
    
    echo $PERCENT
}

torrent_download_speed() {
    ARG_TORRENT_INFO=$1
    
    DOWNLOAD_SPEED=$(echo "$ARG_TORRENT_INFO" | sed 's/.*rateDownload\"://g;s/\}.*//g')
    DOWNLOAD_SPEED_KB=$(perl -e "printf('%.1f', $DOWNLOAD_SPEED/1024)")
    
    echo $DOWNLOAD_SPEED_KB
}

print_torrents_listing() {
    JSON=$1
    
    STATUS_PAUSED=0
    STATUS_QUEUED=3
    STATUS_DOWNLOADING=4
    STATUS_SEEDING=6
    
    ROW_BY_ROW=$(echo "$TORRENTS_INFO" | sed 's/}\,{/}\
{/g' | sed 's/^{//g' | sed 's/}$//g' | sed 's/}]},\"result\":.*$//g')
    
    # use grep to ignore paused torrents if they shouldn't be listed
    if [ $TASK_LIST_PAUSED -eq 0 ]
    then
        ROW_BY_ROW=$(echo "$ROW_BY_ROW" | grep -v "\"status\":0")
    fi
    
    # header of table output
    TABLE_HEADER="${TEXT_INVERTED}\nStatus\tName\tProgress\tDl.\tUp.        ${TEXT_RESET}" # Dirty. I'm sorry
    
    TABLE_DATA=$(echo "$ROW_BY_ROW" | while read LINE
    do
        STATUS=$(echo "$LINE" | grep -Eo "\".*status\":(.*?)\$" | sed 's/.*\"status\"://')
        
        if [ $TASK_LIST_PAUSED -eq 1 ] || [ ! "$STATUS" -eq $STATUS_PAUSED ] # not displaying paused torrent downloads by default
        then
            NAME=$(echo "$LINE" | grep -Eo "\"name\":\"(.*?)\"" | sed 's/\"name\":\"//' | sed 's/\"$//')
            PERCENT_DONE=$(echo "$LINE" | grep -Eo "\"percentDone\":(.*?)," | sed 's/\"percentDone\"://' | sed 's/,$//')
            PERCENT_DONE=$(perl -e "print int($PERCENT_DONE*100)")
            RATE_DOWNLOAD=$(echo "$LINE" | grep -Eo "\"rateDownload\":(.*?)," | sed 's/\"rateDownload\"://' | sed 's/,$//')
            RATE_UPLOAD=$(echo "$LINE" | grep -Eo "\"rateUpload\":(.*?)," | sed 's/\"rateUpload\"://' | sed 's/,$//')
            
            RATE_DOWNLOAD_KB=$(perl -e "printf('%.1f', $RATE_DOWNLOAD/1024)")
            RATE_UPLOAD_KB=$(perl -e "printf('%.1f', $RATE_UPLOAD/1024)")
            
            # turn status code into string
            if [ "$STATUS" -eq $STATUS_QUEUED ]
            then
                STATUS_STRING="Queued"
            elif [ "$STATUS" -eq $STATUS_DOWNLOADING ]
            then
                STATUS_STRING="Dl"
            elif [ "$STATUS" -eq $STATUS_SEEDING ]
            then
                STATUS_STRING="Seeding"
            elif [ "$STATUS" -eq $STATUS_PAUSED ]
            then
                STATUS_STRING="Paused"
            else
                STATUS_STRING="N/A"
            fi
            
            printf "${STATUS_STRING}\t%.40s\t${PERCENT_DONE}%s\t${RATE_DOWNLOAD_KB} KB/s\t${RATE_UPLOAD_KB} KB/s\n" "$NAME" "%%"
        fi
    done)
    
    # solution for conditional colored output. output is piped through colorize_table which either colorizes or just forwards(cat -)
    if [ $COLORED_OUTPUT -eq 1 ]
    then
        colorize_table() {
            sed "s/^Dl/${FOREGROUND_GREEN}Dl${TEXT_RESET}/" |
            sed "s/^Seeding/${FOREGROUND_BLUE}Seeding${TEXT_RESET}/" |
            sed "s/^Queued/${FOREGROUND_YELLOW}Queued${TEXT_RESET}/" |
            sed "s/^Paused/${FOREGROUND_LIGHT_RED}Paused${TEXT_RESET}/" |
            sed "s/100\%/${FOREGROUND_GREEN}100\%${TEXT_RESET}/"
        }
    else
        colorize_table() {
            cat -
        }
    fi
    
    # output table. the colorize_table function only colorizes if COLORED_OUTPUT is set to 1
    printf "${TABLE_HEADER}\n${TABLE_DATA}\n" | column -ts $'\t' | colorize_table
}

progress_visualiser() {
    ARG_PERCENT=$1
    ARG_DOWNLOAD_SPEED=$2
    
    OUTPUT_STRING=""
    STEPS=50
    STEPS_COMPLETED=$(perl -e "print int(($ARG_PERCENT/100) * $STEPS)")
    
    OUTPUT_STRING="$OUTPUT_STRING $ARG_PERCENT%% "
    
    OUTPUT_STRING="$OUTPUT_STRING| "
    
    if [ $STEPS_COMPLETED -gt 0 ]
    then
        for i in $(seq 1 $STEPS_COMPLETED)
        do
            OUTPUT_STRING="$OUTPUT_STRING#"
        done
    fi
    
    for j in $(seq $STEPS_COMPLETED $STEPS)
    do
        OUTPUT_STRING="$OUTPUT_STRING-"
    done
    
    OUTPUT_STRING="$OUTPUT_STRING |"
    OUTPUT_STRING="$OUTPUT_STRING $ARG_DOWNLOAD_SPEED KB/s"
    
    printf "\r$OUTPUT_STRING  "
}

while getopts "hs:u:p:lPqc" OPTION
do
    case $OPTION in
        h)
            usage
            exit 0
            ;;
        u)
            RPC_USER=$OPTARG
            ;;
        p)
            RPC_PASSWORD=$OPTARG
            ;;
        l)
            TASK_LIST=1
            ;;
        P)
            TASK_LIST_PAUSED=1
            ;;
        q)
            QUIET_MODE=1
            ;;
        s)
            HOST_ARG=$OPTARG
            ;;
        c)
            COLORED_OUTPUT=1
            ;;
        \?)
            exit 1
            ;;
    esac
done

# make sure -P isn't used without -l
if [ $TASK_LIST_PAUSED -eq 1 ] && [ $TASK_LIST -eq 0 ]
then
    echo "The -P flag must be used together with the -l flag."
    exit 1
fi

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

# get header for this Transmission RPC session
SESSION_HEADER=$(curl --silent --anyauth$USER_PASSWORD_ARG $HOST_ARG/transmission/rpc/ | sed 's/.*<code>//g;s/<\/code>.*//g')

if [ $TASK_LIST -eq 1 ]
then
    TORRENTS_INFO=$(curl --silent --anyauth$USER_PASSWORD_ARG --header "$SESSION_HEADER" "http://$HOST_ARG/transmission/rpc" -d "{\"method\":\"torrent-get\",\"arguments\": {\"fields\":[\"rateDownload\",\"rateUpload\",\"id\",\"percentDone\",\"status\",\"name\"]}}")
    if [ "$?" -gt 0 ]
    then
        COLOR_START=
        COLOR_END=
        if [ $COLORED_OUTPUT -eq 1 ]
        then
            COLOR_START=$BACKGROUND_RED
            COLOR_END=$TEXT_RESET
        fi
        
        printf "${COLOR_START}Error:${COLOR_END} Could not connect to Transmission RPC server. Make sure the specified credentials are correct. For additional info check help text by passing the -h flag."
        exit 1
    fi
    
    print_torrents_listing "$TORRENTS_INFO"
    exit 0
fi

# one of these will be set further down
LOCAL_TORRENT_FILE=
TORRENT_LINK=

TORRENT_ARG=${@:$OPTIND:1}
PROTOCOL_COMPONENT=$(echo $TORRENT_ARG | cut -d ":" -f 1)

if [ "$PROTOCOL_COMPONENT" == "magnet" ] || [ "$PROTOCOL_COMPONENT" == "http" ] || [ "$PROTOCOL_COMPONENT" == "https" ]
then
    TORRENT_LINK=$TORRENT_ARG
else
    LOCAL_TORRENT_FILE=$TORRENT_ARG
fi

METAINFO_OR_TORRENT_LINK_FIELD="" # populated with either filename or metainfo further down

if [ ! -z "$TORRENT_LINK" ]
then
    METAINFO_OR_TORRENT_LINK_FIELD="\"filename\":\"${TORRENT_LINK}\""
fi

if [ ! -z "$LOCAL_TORRENT_FILE" ]
then
    BASE64_ENCODED_TORRENT_FILE=$(cat "$LOCAL_TORRENT_FILE" | base64)
    METAINFO_OR_TORRENT_LINK_FIELD="\"metainfo\":\"$BASE64_ENCODED_TORRENT_FILE\""
fi

ADD_RESULT=$(curl --silent --anyauth$USER_PASSWORD_ARG --header "$SESSION_HEADER" "http://$HOST_ARG/transmission/rpc" -d "{\"method\":\"torrent-add\",\"arguments\":{\"paused\":false,$METAINFO_OR_TORRENT_LINK_FIELD}}")
TORRENT_ID=$(echo $ADD_RESULT | sed 's/.*id\"://g;s/\,.*//g')
TORRENT_NAME=$(echo $ADD_RESULT | sed 's/.*name\":\"//g;s/\"\}.*//g')

if [ -z "$ADD_RESULT" ]
then
    echo "Could not connect to server. Verify that hostname and port is correct."
    exit 1
fi

if [ ! -z "$(echo "$ADD_RESULT" | grep "Unauthorized User")" ]
then
    echo "Reached server but could not log on. Verify that the login credentials are correct."
    exit 1
fi

echo "Downloading $TORRENT_NAME"

if [ $QUIET_MODE -eq 0 ]
then
    PERCENT_DONE=0 # so the while loop below will start
    
    while [ $PERCENT_DONE -lt 100 ]
    do
        TORRENT_INFO=$(curl --silent --anyauth$USER_PASSWORD_ARG --header "$SESSION_HEADER" "http://$HOST_ARG/transmission/rpc" -d "{\"method\":\"torrent-get\",\"arguments\": {\"ids\":$TORRENT_ID,\"fields\":[\"rateDownload\",\"id\",\"percentDone\"]}}")
        
        # have we lost the connection?
        if [ "$?" -gt 0 ]
        then
            COLOR_START=
            COLOR_END=
            if [ $COLORED_OUTPUT -eq 1 ]
            then
                COLOR_START=$BACKGROUND_RED
                COLOR_END=$TEXT_RESET
            fi
            
            printf "\n${COLOR_START}Error:${COLOR_END} Lost the connection to Transmission RPC server. Progress cannot be displayed but your torrent is still active.${COLOR_END}"
            exit 1
        fi
        
        PERCENT_DONE=$(torrent_percent_done "$TORRENT_INFO")
        DOWNLOAD_SPEED=$(torrent_download_speed "$TORRENT_INFO")
        
        progress_visualiser $PERCENT_DONE $DOWNLOAD_SPEED
        sleep 1
    done
fi
