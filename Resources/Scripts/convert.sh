#!/bin/bash
PARALLEL_JOBS=${1:-12}
SOUNDCHECK_MODE=${2:-soundcheck}
OUTPUT_MODE=${3:-samefolder}
TEMP_DIR="/tmp/JessOS_ADM_Convert"

mkdir -p "$TEMP_DIR"

process_file() {
    local input_file="$1"
    local soundcheck_mode="$2"
    local output_mode="$3"
    [[ -f "$input_file" ]] || return 0

    local dir=$(dirname "$input_file")
    local name=$(basename "$input_file")
    local basename="${name%.*}"

    echo "START:$name"

    # Determine output directory
    local output_dir="$dir"
    if [[ "$output_mode" == "usefolder" ]]; then
        output_dir="${dir}/M4A"
        mkdir -p "$output_dir"
    fi

    # Handle duplicate filenames
    local aac_file="${output_dir}/${basename}.m4a"
    if [[ -f "$aac_file" ]]; then
        local counter=1
        while [[ -f "${output_dir}/${basename}-${counter}.m4a" ]]; do
            ((counter++))
        done
        aac_file="${output_dir}/${basename}-${counter}.m4a"
    fi

    local sr=$(afinfo "$input_file" 2>/dev/null | grep -o '[0-9]* Hz' | grep -o '[0-9]*')

    if [[ "$soundcheck_mode" == "soundcheck" ]]; then
        # Two-pass conversion with SoundCheck metadata
        local caf_file="${TEMP_DIR}/adm_${RANDOM}_${basename}.caf"

        if [[ "$sr" -gt 48000 ]] 2>/dev/null; then
            afconvert "$input_file" -d LEF32@48000 -f caff --soundcheck-generate --src-complexity bats -r 127 "$caf_file" 2>/dev/null || return 0
        else
            afconvert "$input_file" "$caf_file" -d 0 -f caff --soundcheck-generate 2>/dev/null || return 0
        fi

        afconvert "$caf_file" -d aac -f m4af -u pgcm 2 --soundcheck-read -b 256000 -q 127 -s 2 "$aac_file" 2>/dev/null
        rm -f "$caf_file"
    else
        # Direct single-pass conversion (faster, no SoundCheck)
        if [[ "$sr" -gt 48000 ]] 2>/dev/null; then
            afconvert "$input_file" -d aac -f m4af -u pgcm 2 -b 256000 -q 127 -s 2 --src-complexity bats -r 127 "$aac_file" 2>/dev/null || return 0
        else
            afconvert "$input_file" -d aac -f m4af -u pgcm 2 -b 256000 -q 127 -s 2 "$aac_file" 2>/dev/null || return 0
        fi
    fi

    echo "$name"
}

export -f process_file
export TEMP_DIR
export SOUNDCHECK_MODE
export OUTPUT_MODE

xargs -P "$PARALLEL_JOBS" -I {} bash -c 'process_file "$1" "$SOUNDCHECK_MODE" "$OUTPUT_MODE"' _ {}

# Cleanup temp directory
rm -rf "$TEMP_DIR"
