#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Do not run as root or with sudo
if [[ "$EUID" -eq 0 || -n "${SUDO_USER:-}" ]]; then
    echo "This script must not be run as root or with sudo."
    exit 1
fi

# Configurable
REFRESH_BEFORE_PATCH="${REFRESH_BEFORE_PATCH:-true}"
PRIMARY_REPO_NAME="${PRIMARY_REPO_NAME:-kiauh}"
REPOS_FILE="${REPOS_FILE:-$SCRIPT_DIR/repos.conf}"   # changed filename here

# Primary repo defaults
declare -A REPO_URL
declare -A REPO_DIR
declare -A REPO_TARGET

REPO_URL[kiauh]="${REPO_URL[kiauh]:-https://github.com/dw-0/kiauh.git}"
REPO_DIR[kiauh]="${REPO_DIR[kiauh]:-$HOME/kiauh}"
REPO_TARGET[kiauh]="${REPO_TARGET[kiauh]:-${REPO_DIR[kiauh]}/kiauh.sh}"

# Helpers
_trim() { local s="$*"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
_expand() { eval "printf '%s' \"$1\""; }

# Load secondary repos from repos.conf (format: name|git_url)
if [[ -f "$REPOS_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="$(_trim "$line")"
        [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
        IFS='|' read -r name git_url <<< "$line"
        name="$(_trim "$name")"
        git_url="$(_trim "$git_url")"
        if [[ -z "$name" || -z "$git_url" ]]; then
            echo "Skipping invalid line in $REPOS_FILE: $line"
            continue
        fi
        dir="$HOME/$name"
        target="$dir/${name}.sh"
        REPO_URL["$name"]="$git_url"
        REPO_DIR["$name"]="$dir"
        REPO_TARGET["$name"]="$target"
    done < "$REPOS_FILE"
else
    echo "Repos file not found: $REPOS_FILE (no secondary repos loaded)"
fi

# Ensure git is available
if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required but not found in PATH."
    exit 1
fi

# Backup / restore helpers
create_backup_for() {
    local name="$1"; local dir="$2"; local prev_file="$dir/.${name}_prev_head"
    if git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "$dir" rev-parse HEAD > "$prev_file" || true
        local backup_branch="pre-update-${name}-$(date +%Y%m%d-%H%M%S)"
        git -C "$dir" branch "$backup_branch" "$(cat "$prev_file")" >/dev/null 2>&1 || true
        echo "[$name] Backup created: $backup_branch (commit $(cat "$prev_file"))"
    else
        echo "[$name] Unable to read HEAD to create backup."
    fi
}

restore_backup_for() {
    local name="$1"; local dir="$2"; local prev_file="$dir/.${name}_prev_head"
    if [[ -f "$prev_file" ]]; then
        local prev_head; prev_head="$(cat "$prev_file")"
        if git -C "$dir" rev-parse --verify "$prev_head" >/dev/null 2>&1; then
            echo "[$name] Restoring $dir to commit $prev_head..."
            git -C "$dir" reset --hard "$prev_head"
            git -C "$dir" clean -fd
            echo "[$name] Restore complete."
            return 0
        else
            echo "[$name] Recorded commit ($prev_head) not found."
            return 1
        fi
    else
        echo "[$name] No backup file found ($prev_file)."
        return 1
    fi
}

# Restore CLI handling
if [[ "${1:-}" == "--restore-all" ]]; then
    for name in "${!REPO_URL[@]}"; do
        dir="${REPO_DIR[$name]}"
        [[ -d "$dir" ]] && restore_backup_for "$name" "$dir" || echo "[$name] $dir missing; skipping"
    done
    exit 0
fi

if [[ "${1:-}" == "--restore" && -n "${2:-}" ]]; then
    name="$2"
    if [[ -z "${REPO_DIR[$name]:-}" ]]; then echo "Unknown repo: $name"; exit 1; fi
    dir="${REPO_DIR[$name]}"
    [[ -d "$dir" ]] && restore_backup_for "$name" "$dir" || { echo "Directory $dir not found for $name"; exit 1; }
    exit 0
fi

# Process each repo
for name in "${!REPO_URL[@]}"; do
    git_url="${REPO_URL[$name]}"
    dir="${REPO_DIR[$name]}"
    target="${REPO_TARGET[$name]}"
    patch_dir="$SCRIPT_DIR/patches/$name"

    echo "========================================"
    echo "Processing repo: $name"
    echo "  URL: $git_url"
    echo "  Dir: $dir"

    # Clone if missing
    if [[ ! -d "$dir" ]]; then
        echo "[$name] Directory not found. Attempting to clone..."
        cd "$HOME" || { echo "Unable to cd to HOME"; exit 1; }
        if git clone --depth 1 "$git_url" "$dir"; then
            echo "[$name] Cloned $git_url into $dir"
        else
            echo "[$name] git clone failed. Skipping this repo."
            continue
        fi
    fi

    # Ensure it's a git repo
    if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "[$name] $dir is not a git repository. Skipping."
        continue
    fi

    # Backup
    create_backup_for "$name" "$dir"

    # Attempt fast-forward pull
    echo "[$name] Attempting git pull --ff-only..."
    if git -C "$dir" pull --ff-only; then
        echo "[$name] Updated (fast-forward)."
    else
        echo "[$name] git pull --ff-only failed or no fast-forward possible. Continuing."
    fi

    # Make target executable if present
    if [[ -f "$target" && ! -x "$target" ]]; then
        chmod +x "$target" 2>/dev/null && echo "[$name] Made executable: $target" || echo "[$name] Could not chmod $target"
    fi

    # Optional destructive refresh before patching
    if [[ "${REFRESH_BEFORE_PATCH,,}" == "true" ]]; then
        echo "[$name] REFRESH_BEFORE_PATCH=true: fetching and attempting hard reset..."
        current_branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        git -C "$dir" fetch --all --prune || echo "[$name] Warning: git fetch failed."
        reset_target=""
        if [[ -n "$current_branch" ]] && git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/$current_branch"; then
            reset_target="origin/$current_branch"
        elif git -C "$dir" show-ref --verify --quiet "refs/remotes/origin/HEAD"; then
            reset_target="origin/HEAD"
        fi
        if [[ -n "$reset_target" ]]; then
            git -C "$dir" reset --hard "$reset_target" && git -C "$dir" clean -fd && echo "[$name] Reset to $reset_target and cleaned." || echo "[$name] Reset/clean failed."
        else
            echo "[$name] No suitable remote tracking branch found; skipping hard reset."
        fi
    else
        echo "[$name] REFRESH_BEFORE_PATCH=false: skipping refresh."
    fi

    # Always apply patches for this repo
    if [[ -d "$patch_dir" ]]; then
        shopt -s nullglob
        patches=("$patch_dir"/*.patch)
        shopt -u nullglob

        if [[ ${#patches[@]} -eq 0 ]]; then
            echo "[$name] No patches in $patch_dir."
        else
            for patch in "${patches[@]}"; do
                echo "----------------------------------------"
                echo "[$name] Processing patch: $patch"

                if git -C "$dir" apply --check "$patch" 2>/dev/null; then
                    echo "[$name] Patch applies cleanly. Applying..."
                    if git -C "$dir" apply --whitespace=fix "$patch"; then
                        echo "[$name] Applied: $patch"
                        continue
                    else
                        echo "[$name] Failed to apply after check. Trying fallbacks..."
                    fi
                fi

                if git -C "$dir" apply --reverse --check "$patch" 2>/dev/null; then
                    echo "[$name] Patch appears already applied. Skipping: $patch"
                    continue
                fi

                echo "[$name] Attempting three-way apply for: $patch"
                if git -C "$dir" apply --3way --whitespace=fix "$patch" 2>/dev/null; then
                    echo "[$name] Applied with 3way: $patch"
                    continue
                else
                    echo "[$name] 3way apply failed or not possible."
                fi

                echo "[$name] Attempting apply with rejects for manual resolution: $patch"
                if git -C "$dir" apply --reject --whitespace=fix "$patch" 2>/dev/null; then
                    rej_count=$(find "$dir" -maxdepth 3 -name '*.rej' -print 2>/dev/null | wc -l || true)
                    if [[ ${rej_count:-0} -gt 0 ]]; then
                        echo "[$name] Patch produced ${rej_count} .rej file(s). Inspect them."
                        echo "[$name] List rejects: find \"$dir\" -name '*.rej' -print"
                    else
                        echo "[$name] Applied with --reject but no .rej found. Inspect repository for partial changes."
                    fi
                    continue
                else
                    echo "[$name] apply --reject failed for: $patch"
                fi

                echo "[$name] Could not apply patch automatically. Suggested manual command:"
                echo "    git -C \"$dir\" apply --reject --whitespace=fix \"$patch\""
            done
        fi
    else
        echo "[$name] Patch directory $patch_dir not found; skipping."
    fi
done

# Execute primary repo target
primary_target="${REPO_TARGET[$PRIMARY_REPO_NAME]:-}"
if [[ -n "$primary_target" && -f "$primary_target" ]]; then
    echo "Executing primary target: $primary_target"
    exec "$primary_target"
else
    echo "Primary target for $PRIMARY_REPO_NAME not found. Exiting."
    exit 0
fi
