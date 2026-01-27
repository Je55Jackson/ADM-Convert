#!/bin/bash
CONVERT_SCRIPT="$1"
PROGRESS_APP="$2"
PARALLEL_JOBS="$3"
shift 3

# Start progress app immediately and stream everything
(
    # Process files as we find them - no waiting
    for p in "$@"; do
        if [ -d "$p" ]; then
            find "$p" -type f \( -iname '*.wav' -o -iname '*.aif' -o -iname '*.aiff' \)
        else
            case "${p##*.}" in
                [Ww][Aa][Vv]|[Aa][Ii][Ff]|[Aa][Ii][Ff][Ff]) printf '%s\n' "$p";;
            esac
        fi
    done | "$CONVERT_SCRIPT" "$PARALLEL_JOBS" | while IFS= read -r line; do
        if [[ "$line" == START:* ]]; then
            echo "$line"
        else
            echo "FILE:$line"
        fi
    done
    echo "DONE"
) | "$PROGRESS_APP"
