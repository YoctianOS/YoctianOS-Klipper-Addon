#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

## DON'T RUN IT MANUALLY!!!

# Directory of this script (resolve relative paths reliably)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Do not run as root or with sudo
if [ "$EUID" -eq 0 ] || [ -n "${SUDO_USER:-}" ]; then
    echo "This script must not be run as root or with sudo."
    exit 1
fi

# Configurable variables
REPO_DIR="${REPO_DIR:-$HOME/KlipperScreen}"
TARGET="${TARGET:-$REPO_DIR/scripts/KlipperScreen-install.sh}"

# Basic checks
if ! command -v git >/dev/null 2>&1; then
    echo "git is required but not found in PATH."
    exit 1
fi

if [ ! -d "$REPO_DIR" ]; then
    echo "Repository directory $REPO_DIR does not exist."
    exit 1
fi

if [ ! -f "$TARGET" ]; then
    echo "Target file $TARGET does not exist."
    exit 1
fi

# Make target executable if possible
if [ ! -x "$TARGET" ]; then
    if chmod +x "$TARGET" 2>/dev/null; then
        echo "Made executable: $TARGET"
    else
        echo "Warning: could not make $TARGET executable (permission denied)."
    fi
fi

# Apply patches if present (patches path is relative to this script)
PATCH_DIR="$SCRIPT_DIR/patches/KlipperScreen"
if [ -d "$PATCH_DIR" ]; then
    shopt -s nullglob
    patches=("$PATCH_DIR"/*.patch)
    shopt -u nullglob

    if [ "${#patches[@]}" -eq 0 ]; then
        echo "No patches found in $PATCH_DIR."
    else
        for patch in "${patches[@]}"; do
            echo "----------------------------------------"
            echo "Processing patch: $patch"

            # 1) Quick check if patch applies cleanly
            if git -C "$REPO_DIR" apply --check "$patch" 2>/dev/null; then
                echo "Patch applies cleanly. Applying..."
                if git -C "$REPO_DIR" apply --whitespace=fix "$patch"; then
                    echo "Applied: $patch"
                    continue
                else
                    echo "Unexpected failure applying patch after check. Attempting fallback strategies..."
                fi
            fi

            # 2) If check failed, test if the patch is already applied (reverse check)
            if git -C "$REPO_DIR" apply --reverse --check "$patch" 2>/dev/null; then
                echo "Patch appears to be already applied. Skipping: $patch"
                continue
            fi

            # 3) Try a three-way merge apply
            echo "Attempting three-way merge apply for: $patch"
            if git -C "$REPO_DIR" apply --3way --whitespace=fix "$patch" 2>/dev/null; then
                echo "Applied with 3way: $patch"
                continue
            else
                echo "3way apply failed or not possible for: $patch"
            fi

            # 4) As a last automated attempt, create reject hunks for manual resolution
            echo "Attempting apply with rejects for manual resolution: $patch"
            if git -C "$REPO_DIR" apply --reject --whitespace=fix "$patch" 2>/dev/null; then
                # Detect .rej files created by git apply --reject
                rej_count=$(find "$REPO_DIR" -maxdepth 3 -name '*.rej' -print 2>/dev/null | wc -l || true)
                if [ "${rej_count:-0}" -gt 0 ]; then
                    echo "Patch produced reject hunks. ${rej_count} .rej file(s) created. Please inspect and resolve them."
                    echo "You can list rejects with: find \"$REPO_DIR\" -name '*.rej' -print"
                else
                    echo "Applied with --reject but no .rej files found. Inspect repository for partial changes."
                fi
                # Continue to next patch instead of aborting
                continue
            else
                echo "apply --reject failed for: $patch"
            fi

            # 5) If we reach here, nothing worked. Log and continue
            echo "Could not apply patch $patch automatically and it does not appear to be already applied."
            echo "Suggested manual command: git -C \"$REPO_DIR\" apply --reject --whitespace=fix \"$patch\""
            echo "Continuing to next patch."
            continue
        done
    fi
fi

# Execute the target script, replacing the current shell
exec "$TARGET"
