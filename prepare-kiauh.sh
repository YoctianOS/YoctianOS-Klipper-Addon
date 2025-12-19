#!/usr/bin/env bash

GIT_REPO="https://github.com/dw-0/kiauh.git"

# Check if the user is root or using sudo
if [ "$EUID" -eq 0 ] || [ -n "$SUDO_USER" ]; then
    echo "This script must not be run as root or with sudo."
    exit 1
fi

cd "$HOME" || {
    echo "Unable to change directory to \$HOME"
    exit 1
}

# Check if git is installed
if ! command -v git >/dev/null 2>&1; then
    echo "git is not installed. Please install git first."
    exit 1
fi

git clone $GIT_REPO

echo "Preparation done!"
