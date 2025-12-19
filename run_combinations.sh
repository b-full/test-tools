#!/usr/bin/env bash
set -u

TSV="$1"
LOGFILE="results.log"



# Start fresh
: > "$LOGFILE"

log() {
    tee -a "$LOGFILE"
}

separator() {
    echo ""
    echo "########################################" | log
    echo "#####  START OF DOWNLOAD  #####" | log
    echo "########################################" | log
}



tail -n +2 "$TSV" | while IFS=$'\t' read -r URL TOOL; do
    [[ -z "$URL" || -z "$TOOL" ]] && continue
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

    separator

    case "$TOOL" in
        wget)
            CMD=(wget -d --no-passive-ftp --tries=2 --progress=dot:giga "$URL")
            ;;
        curl)
            CMD=(curl -v -L --max-time 300 "$URL")
            ;;
        lftp)
            CMD=(
                lftp -d -e "
                    set net:max-retries 2;
                    set net:timeout 20;
                    set net:reconnect-interval-base 5;
                    set cmd:fail-exit true;
                    set ftp:passive-mode no;
                    get $URL;
                    bye
                "
            )
            ;;
        *)
            echo "[$TIMESTAMP]" | log
            echo "Command: UNKNOWN TOOL '$TOOL'" | log
            echo "Output:" | log
            echo "Invalid tool" | log
            echo "Status: Failure" | log
            separator
            continue
            ;;
    esac

    # Run the command once, with all output logged
    {
        echo "[$TIMESTAMP]"
        echo "Command: ${CMD[*]}"
        echo "Output:"
        echo "----------------------------------------"

        "${CMD[@]}"
        EXIT_CODE=$?

        echo "----------------------------------------"
        if [[ $EXIT_CODE -eq 0 ]]; then
            echo "Status: Success"
        else
            echo "Status: Failure"
        fi
    } 2>&1 | log

    echo "" | log
    echo "" | log
    echo "" | log

done

