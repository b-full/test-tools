#!/usr/bin/env bash

set -u

TSV="$1"
LOGDIR="logs"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
MASTER_LOG="${LOGDIR}/run_${TIMESTAMP}.log"

mkdir -p "$LOGDIR"

echo "Starting run at $(date)" | tee "$MASTER_LOG"
echo "Input file: $TSV" | tee -a "$MASTER_LOG"
echo "----------------------------------------" | tee -a "$MASTER_LOG"

tail -n +2 "$TSV" | while IFS=$'\t' read -r URL TOOL; do
    [[ -z "$URL" || -z "$TOOL" ]] && continue

    SAFE_URL=$(echo "$URL" | sed 's#[/:]#_#g')
    RUN_LOG="${LOGDIR}/${TOOL}_${SAFE_URL}_${TIMESTAMP}.log"

    echo "[$(date)] Running: $TOOL $URL" | tee -a "$MASTER_LOG"
    echo "Log file: $RUN_LOG" | tee -a "$MASTER_LOG"

    {
        echo "Command: $TOOL $URL"
        echo "Started: $(date)"
        echo "----------------------------------------"

        case "$TOOL" in
            wget)
                wget -d "$URL"
                ;;
            curl)
                curl -v -L "$URL"
                ;;
            lftp)
                lftp -d -e "get $URL; bye"
                ;;
            *)
                echo "ERROR: Unknown tool '$TOOL'"
                exit 127
                ;;
        esac

        EXIT_CODE=$?
        echo "----------------------------------------"
        echo "Exit code: $EXIT_CODE"
        echo "Finished: $(date)"
        exit $EXIT_CODE
    } 2>&1 | tee "$RUN_LOG"

    EXIT_CODE=${PIPESTATUS[0]}

    if [[ $EXIT_CODE -ne 0 ]]; then
        echo "❌ FAILED: $TOOL $URL (exit $EXIT_CODE)" | tee -a "$MASTER_LOG"
    else
        echo "✅ SUCCESS: $TOOL $URL" | tee -a "$MASTER_LOG"
    fi

    echo "----------------------------------------" | tee -a "$MASTER_LOG"
done

echo "All runs completed at $(date)" | tee -a "$MASTER_LOG"

