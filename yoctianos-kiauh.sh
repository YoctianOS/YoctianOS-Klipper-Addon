#!/bin/bash

# Check if the user is root or using sudo
if [ "$EUID" -eq 0 ] || [ -n "$SUDO_USER" ]; then
    echo "This script must not be run as root or with sudo."
    exit 1
fi

TARGET="$HOME/kiauh/kiauh.sh"
REPO_DIR="$HOME/kiauh"

# Check if the target file exists
if [ ! -f "$TARGET" ]; then
    echo "The file $TARGET does not exist."
    exit 1
fi

# Apply patches if any exist in ./patches using git
PATCH_DIR="./patches"
if [ -d "$PATCH_DIR" ]; then
    cd "$REPO_DIR" || {
        echo "Failed to enter repository directory $REPO_DIR"
        exit 1
    }

    for patch in "$PATCH_DIR"/kiauh/*.patch; do
        [ -f "$patch" ] || continue
        echo "Applying patch with git: $patch"
        git apply "$patch" || {
            echo "Failed to apply $patch"
            exit 1
        }
    done
fi

# Run the script
"$TARGET"
