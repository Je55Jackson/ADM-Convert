#!/bin/bash
CONVERT_SCRIPT="$1"
PROGRESS_APP="$2"
PARALLEL_JOBS="$3"
SOUNDCHECK_MODE="$4"
OUTPUT_MODE="$5"
shift 5

# First, collect all files into a temp file
TEMP_FILE=$(mktemp)

for p in "$@"; do
    if [ -d "$p" ]; then
        find "$p" -type f \( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' \) >> "$TEMP_FILE"
    else
        case "${p##*.}" in
            [Ww][Aa][Vv]|[Aa][Ii][Ff]|[Aa][Ii][Ff][Ff]) printf '%s\n' "$p" >> "$TEMP_FILE";;
        esac
    fi
done

# Count total files
TOTAL=$(wc -l < "$TEMP_FILE" | tr -d ' ')

# Now process with progress
(
    # Send total count first
    echo "TOTAL:$TOTAL"

    # Process files and report progress
    cat "$TEMP_FILE" | "$CONVERT_SCRIPT" "$PARALLEL_JOBS" "$SOUNDCHECK_MODE" "$OUTPUT_MODE" | while IFS= read -r line; do
        if [[ "$line" == START:* ]]; then
            echo "$line"
        else
            echo "FILE:$line"
        fi
    done
    echo "DONE"
) | "$PROGRESS_APP"

# Cleanup
rm -f "$TEMP_FILE"
