#!/usr/bin/env bash
set -u
TSV="$1"
LOGFILE="results.log"

# Start fresh
: > "$LOGFILE"

log() {
    tee -a "$LOGFILE"
}

get_ip() {
    # Try multiple methods to get IP address (OS-agnostic)
    local ip=""
 
    # Method 1: hostname -I (Linux)
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    [[ -n "$ip" ]] && echo "$ip" && return
 
    # Method 2: hostname -i (some Linux)
    ip=$(hostname -i 2>/dev/null | awk '{print $1}')
    [[ -n "$ip" && "$ip" != "127.0.0.1" ]] && echo "$ip" && return
 
    # Method 3: ip command (modern Linux)
    ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
    [[ -n "$ip" ]] && echo "$ip" && return
 
    # Method 4: ip addr show (Linux)
    ip=$(ip addr show 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | cut -d/ -f1 | head -1)
    [[ -n "$ip" ]] && echo "$ip" && return
 
    # Method 5: ifconfig (macOS, BSD, older Linux)
    ip=$(ifconfig 2>/dev/null | grep "inet " | grep -v "127.0.0.1" | awk '{print $2}' | head -1)
    [[ -n "$ip" ]] && echo "$ip" && return
 
    # Method 6: ipconfig (macOS specific)
    ip=$(ipconfig getifaddr en0 2>/dev/null)
    [[ -n "$ip" ]] && echo "$ip" && return
 
    # Method 7: nmcli (NetworkManager on Linux)
    ip=$(nmcli -t -f IP4.ADDRESS dev show 2>/dev/null | grep -v "127.0.0.1" | head -1 | cut -d: -f2 | cut -d/ -f1)
    [[ -n "$ip" ]] && echo "$ip" && return
 
    # Fallback: Use external service (requires internet)
    ip=$(curl -s --max-time 2 ifconfig.me 2>/dev/null)
    [[ -n "$ip" ]] && echo "$ip" && return
 
    # Last resort
    echo "N/A"
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

    # Parse URL to extract protocol and host
    # e.g. https://www.example.com/file.txt -> https://www.example.com
    # e.g. ftp://ftp.silva.de/path/file -> ftp://ftp.silva.de
    PROTOCOL=$(echo "$URL" | sed -E 's|^([a-z]+://[^/]+).*|\1|')
    # Fallback if parsing fails
    [[ -z "$PROTOCOL" ]] && PROTOCOL="$URL"

    # Parse out the current combination of tool + URL we're testing
    URL_BASE=$(echo "$URL" | sed -E 's|^([a-z]+)://([^/]+).*|\1_\2|')
    COMBO="${TOOL}_${URL_BASE}"

    # Designate filename based on current combination of tool + URL being tested
    FILENAME="SILVA_${COMBO}.gz"

    case "$TOOL" in
        wget)
            CMD=(wget -d --no-passive-ftp --tries=2 --progress=dot:giga -O "$FILENAME" "$URL")
            ;;
        curl)
            CMD=(curl -v -L --max-time 300 "$URL" -o "$FILENAME")
            ;;
        lftp)
            # Parse URL into server and path for lftp
            SERVER=$(echo "$URL" | sed -E 's|^([a-z]+://[^/]+).*|\1|')
            FILEPATH=$(echo "$URL" | sed -E 's|^[a-z]+://[^/]+(.*)|\1|')
            echo "Server: $SERVER"
            echo "Filepath: " $FILEPATH
            echo "Output Filename: $FILENAME"
            CMD=(lftp -d -e "set ssl:verify-certificate no; get $FILEPATH -o $FILENAME; bye" $SERVER)
            ;;
        *)
            echo "[$TIMESTAMP]" | log
            echo "Command: UNKNOWN TOOL '$TOOL'" | log
            echo "Output:" | log
            echo "Invalid tool" | log
            echo "Error Message: Unknown tool '$TOOL'" | log
            echo "Status: Failure" | log
            separator
            continue
            ;;
    esac

    # Capture output to a temporary file for error parsing
    TEMP_OUTPUT=$(mktemp)

    # Run each command once, with all output captured
    {
        echo "[$TIMESTAMP]"
        echo "Command: ${CMD[*]}"
        echo "Output:"
        echo "----------------------------------------"
        "${CMD[@]}" 2>&1 | tee "$TEMP_OUTPUT"
        EXIT_CODE=${PIPESTATUS[0]}
        echo "----------------------------------------"


        ### Check to make sure that the download actually completed successfully ###

        # Ensure file exists (create empty file if download failed)
        touch "$FILENAME"

        # Get file size in bytes (works on both macOS and Linux)
        if [[ -f "$FILENAME" ]]; then

            FILE_SIZE=$(stat -f%z "$FILENAME" 2>/dev/null || stat -c%s "$FILENAME" 2>/dev/null || echo "0")
        fi

        # 63MB = 66060288 bytes
        MIN_SIZE=66060288

        # Assign different log/result values based on the success/failure of the command
        if [[ $EXIT_CODE -ne 0 ]]; then
            # Parse error message based on tool
            ERROR_MSG="Unknown error (exit code: $EXIT_CODE)"
            STATUS="Failure"

            case "$TOOL" in
                wget)
                    # Extract wget errors
                    ERROR_MSG=$(grep -i "error\|failed\|unable\|refused\|timeout" "$TEMP_OUTPUT" | head -1 | sed 's/^[[:space:]]*//')
                    [[ -z "$ERROR_MSG" ]] && ERROR_MSG=$(tail -5 "$TEMP_OUTPUT" | grep -v "^$" | tail -1)
                    ;;
                curl)
                    # Extract curl errors
                    ERROR_MSG=$(grep -i "curl: ([0-9]*)" "$TEMP_OUTPUT" | tail -1)
                    [[ -z "$ERROR_MSG" ]] && ERROR_MSG=$(grep -i "error\|failed\|couldn't\|timeout" "$TEMP_OUTPUT" | head -1 | sed 's/^[[:space:]]*//')
                    [[ -z "$ERROR_MSG" ]] && ERROR_MSG=$(tail -5 "$TEMP_OUTPUT" | grep -v "^$" | tail -1)
                    ;;
                lftp)
                    # Extract lftp errors
                    ERROR_MSG=$(grep -i "error\|failed\|fatal\|login incorrect\|access failed" "$TEMP_OUTPUT" | head -1 | sed 's/^[[:space:]]*//')
                    [[ -z "$ERROR_MSG" ]] && ERROR_MSG=$(tail -5 "$TEMP_OUTPUT" | grep -v "^$" | tail -1)
                    ;;
            esac

            # Fallback if no error message found
            [[ -z "$ERROR_MSG" ]] && ERROR_MSG="Command failed with exit code $EXIT_CODE"

            # Truncate if too long
            if [[ ${#ERROR_MSG} -gt 200 ]]; then
                ERROR_MSG="${ERROR_MSG:0:197}..."
            fi

        # Check if command returned success code but the file was not fully downloaded
        elif [[ $EXIT_CODE -eq 0 && $FILE_SIZE < $MIN_SIZE ]]; then
                EXIT_CODE=-1
                ERROR_MSG="Download incomplete - file size too small"
                STATUS="Failure"

        else
            STATUS="Success"
            ERROR_MSG="N/A"

        fi

        echo ""
        echo "########################################"
        echo "# REPORTING RESULTS OF DOWNLOAD ATTEMPT #"
        echo "########################################"

        echo "Command: ${CMD[*]}"
        echo "URL: $URL"
        echo "Tool: $TOOL"
        echo "IP: $(get_ip)"
        echo "Timestamp: $TIMESTAMP"
        echo "File Size: $(( FILE_SIZE / (1024 * 2) )) MB"
        echo "Error Message: $ERROR_MSG"
        echo "Status: $STATUS"
    } | log

    # Clean up temp file
    rm -f "$TEMP_OUTPUT"

    echo "" | log
    echo "" | log
    echo "" | log
done
