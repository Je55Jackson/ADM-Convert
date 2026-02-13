# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JessOS ADM Convert is a native macOS app that converts WAV/AIFF audio files to AAC (.m4a) using Apple Digital Masters encoding parameters (256kbps AAC, optional SoundCheck loudness normalization). It replaces Apple's original x86-only ADM Droplet with an Apple Silicon native implementation.

## Build / Deploy / Release

**IMPORTANT: Know the difference. Only "release" affects users.**

| Term | Command | What it does | Affects users? |
|------|---------|-------------|----------------|
| **Build** | `./build.sh` | Compile, sign, notarize DMG (stays in `build/`) | No |
| **Deploy** | `./build.sh --deploy` | Build + install to `/Applications` for local testing | No |
| **Release** | `./scripts/release.sh` | Push to GitHub, create release, update download page | **YES** |

When the user says "build" or "deploy", keep everything local. Only run the release pipeline when explicitly asked to "release" or "push to users".

The build script:
1. Compiles Swift code with `swiftc` targeting arm64-apple-macosx14.0
2. Copies resources (scripts, ADMProgress, icon)
3. Signs with Developer ID certificate (hardened runtime + timestamp)
4. Creates DMG with `appdmg`
5. Notarizes with Apple and staples ticket

**Code signing identity:** `Developer ID Application: Jess Jackson (K5765CY524)`
**Notarization profile:** `ADM-Convert-Notarization` (stored in keychain)

**Download page:** `jessos.com/admconvert/` (leads stored in DynamoDB `jessos-adm-leads`)
**Admin dashboard:** `jessos.com/admconvert/admin.html`

## Architecture

### Two-App Design

1. **Main App** (`Sources/AppDelegate.swift`) - The Cocoa app that:
   - Handles drag-and-drop, file picker, Services menu
   - Manages user preferences (SoundCheck mode, output folder)
   - Provides dock menu for settings
   - Spawns conversion process and tracks completion
   - Implements Keka-style quit behavior (quits after conversion if launched with files)

2. **ADMProgress** (`ADMProgressSource/main.swift`) - Standalone progress UI that:
   - Reads status from stdin (TOTAL:, START:, FILE:, DONE messages)
   - Shows determinate progress bar with file count
   - Auto-closes after conversion

### Shell Scripts (`Resources/Scripts/`)

- **run_with_progress.sh** - Wrapper that counts files, sends TOTAL: message, pipes to ADMProgress
- **convert.sh** - Performs actual conversion using `afconvert`:
  - With SoundCheck: WAV → CAF (generate SoundCheck) → AAC (read SoundCheck)
  - Without SoundCheck: Direct WAV → AAC (faster)
  - Parallel processing via xargs -P (12 jobs default)
  - Small batches (≤3 files) processed directly to avoid xargs overhead

### IPC Protocol

Progress communication from shell scripts to ADMProgress:
```
TOTAL:N     → Set total file count, switch to determinate mode
START:name  → Show filename being processed
FILE:name   → File completed, increment counter
DONE        → Conversion complete, show summary
```

## Key Technical Details

- **Encoding params:** `-d aac -f m4af -u pgcm 2 -b 256000 -q 127 -s 2`
- **High sample rate handling:** Files >48kHz downsampled with `--src-complexity bats -r 127`
- **Temp files:** CAF intermediates in `/tmp/JessOS_ADM_Convert/`, auto-cleaned
- **Preferences:** Stored in UserDefaults (`includeSoundCheck`, `useOutputFolder`)
- **Launch detection:** Uses timestamp comparison (< 2 seconds = launched with files)

## Rebuilding ADMProgress

If modifying the progress UI:
```bash
swiftc -o ADMProgressSource/ADMProgress \
    -target arm64-apple-macosx11.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa -framework QuartzCore \
    ADMProgressSource/main.swift

cp ADMProgressSource/ADMProgress Resources/ADMProgress
```

Then run `./build.sh --deploy` to rebuild the main app.

## Build Notes / README

`JessOS_ADM_Convert_BUILD_NOTES.txt` doubles as the project README. When adding new version entries to the BUILD LOG section, **newest versions go on top** (reverse chronological order).
