#!/bin/bash
PARALLEL_JOBS=${1:-12}

process_file() {
    local input_file="$1"
    [[ -f "$input_file" ]] || return 0

    local dir=$(dirname "$input_file")
    local name=$(basename "$input_file")
    local basename="${name%.*}"

    # Signal that we're starting this file
    echo "START:$name"

    local aac_file="${dir}/${basename}.m4a"
    if [[ -f "$aac_file" ]]; then
        local counter=1
        while [[ -f "${dir}/${basename}-${counter}.m4a" ]]; do
            ((counter++))
        done
        aac_file="${dir}/${basename}-${counter}.m4a"
    fi

    # Single-pass conversion - no SoundCheck, much faster
    afconvert "$input_file" -d aac -f m4af -b 256000 -q 127 -s 2 "$aac_file" 2>/dev/null || return 0

    echo "$name"
}

export -f process_file

# Process and output completed filenames
xargs -P "$PARALLEL_JOBS" -I {} bash -c 'process_file "$1"' _ {}
