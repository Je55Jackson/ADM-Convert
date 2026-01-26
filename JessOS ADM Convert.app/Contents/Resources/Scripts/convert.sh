#!/bin/bash
PARALLEL_JOBS=${1:-12}
TEMP_DIR="/tmp/JessOS_ADM_Convert"

# Create temp directory if it doesn't exist
mkdir -p "$TEMP_DIR"

process_file() {
    local input_file="$1"
    local temp_dir="$TEMP_DIR"
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

    local caf_file="${temp_dir}/adm_${RANDOM}_${basename}.caf"
    local sr=$(afinfo "$input_file" 2>/dev/null | grep -o '[0-9]* Hz' | grep -o '[0-9]*')

    if [[ "$sr" -gt 48000 ]] 2>/dev/null; then
        afconvert "$input_file" -d LEF32@48000 -f caff --soundcheck-generate --src-complexity bats -r 127 "$caf_file" 2>/dev/null || return 0
    else
        afconvert "$input_file" "$caf_file" -d 0 -f caff --soundcheck-generate 2>/dev/null || return 0
    fi

    afconvert "$caf_file" -d aac -f m4af -u pgcm 2 --soundcheck-read -b 256000 -q 127 -s 2 "$aac_file" 2>/dev/null
    rm -f "$caf_file"
    
    echo "$name"
}

export -f process_file
export TEMP_DIR

# Process and output completed filenames
xargs -P "$PARALLEL_JOBS" -I {} bash -c 'process_file "$1"' _ {}
