#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Backup — Restore Script
# Usage: bash scripts/restore.sh [--profile <name>] [workspace-path]
#
# Restores workspace from backup repo. Decrypts .age files with the local age key.
# If workspace already exists, creates a timestamped backup before overwriting.

BACKUP_DIR="$HOME/.openclaw-backup"
KEY_FILE="$BACKUP_DIR/age-key.txt"
REPO_DIR="$BACKUP_DIR/repo"

# Parse arguments
PROFILE="default"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash scripts/restore.sh [--profile <name>] [workspace-path]"
            echo ""
            echo "Options:"
            echo "  --profile <name>   Profile to restore (default: 'default')"
            exit 0
            ;;
        -*) echo "❌ Unknown option: $1"; exit 1 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

CONFIG_FILE="$BACKUP_DIR/profiles/$PROFILE.conf"

# Load config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
elif [[ -f "$BACKUP_DIR/config" ]]; then
    source "$BACKUP_DIR/config"
else
    echo "❌ Profile '$PROFILE' not found."
    exit 1
fi

WORKSPACE="${POSITIONAL[0]:-${WORKSPACE:-$HOME/.openclaw/workspace}}"
PROFILE_DIR="$REPO_DIR/$PROFILE"

echo "🐺 OpenClaw Backup — Restore"
echo "============================="
echo "   Profile:   $PROFILE"
echo "   From:      $PROFILE_DIR"
echo "   To:        $WORKSPACE"
echo ""

# Verify backup repo exists
if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "❌ Backup repo not found at $REPO_DIR"
    echo "   Run setup first or clone manually."
    exit 1
fi

# Verify profile directory exists
if [[ ! -d "$PROFILE_DIR" ]]; then
    echo "❌ Profile directory not found: $PROFILE_DIR"
    echo "   Available profiles:"
    ls -d "$REPO_DIR"/*/ 2>/dev/null | xargs -I{} basename {} || echo "   (none)"
    exit 1
fi

# Verify age key exists
if [[ ! -f "$KEY_FILE" ]]; then
    echo "❌ Age key not found: $KEY_FILE"
    echo "   Cannot decrypt encrypted files without the key."
    echo "   Place your age key at: $KEY_FILE"
    exit 1
fi

# Pull latest
cd "$REPO_DIR"
echo "📥 Pulling latest backup..."
git pull --ff-only 2>/dev/null || echo "   (no remote changes or not on tracking branch)"

# Safety: backup existing workspace
if [[ -d "$WORKSPACE" ]] && [[ "$(ls -A "$WORKSPACE" 2>/dev/null)" ]]; then
    BACKUP_STAMP=$(date +"%Y%m%d_%H%M%S")
    SAFETY_BACKUP="${WORKSPACE}.pre-restore.${BACKUP_STAMP}"
    echo ""
    echo "⚠️  Existing workspace found. Creating safety backup:"
    echo "   $SAFETY_BACKUP"
    cp -a "$WORKSPACE" "$SAFETY_BACKUP"
fi

# Create workspace if needed
mkdir -p "$WORKSPACE"

# Track stats
RESTORED=0
DECRYPTED=0

echo ""
echo "📋 Restoring files..."

cd "$PROFILE_DIR"
while IFS= read -r -d '' file; do
    rel_path="${file#./}"
    
    # Skip metadata and markers
    [[ "$rel_path" == .git/* ]] && continue
    [[ "$rel_path" == ".gitignore" ]] && continue
    [[ "$rel_path" == ".backup-meta.json" ]] && continue
    [[ "$rel_path" == ".backup-keep" ]] && continue
    
    if [[ "$rel_path" == *.age ]]; then
        # Decrypt age file — strip .age extension for target
        target_path="${rel_path%.age}"
        target_full="$WORKSPACE/$target_path"
        mkdir -p "$(dirname "$target_full")"
        
        if age -d -i "$KEY_FILE" -o "$target_full" "$file" 2>/dev/null; then
            DECRYPTED=$((DECRYPTED + 1))
            echo "   🔓 ${rel_path} → $target_path"
        else
            echo "   ❌ Failed to decrypt: $rel_path"
        fi
    else
        # Copy plaintext
        target_full="$WORKSPACE/$rel_path"
        mkdir -p "$(dirname "$target_full")"
        cp "$file" "$target_full"
        RESTORED=$((RESTORED + 1))
    fi
done < <(find . -type f -print0)

echo ""
echo "✅ Restore complete!"
echo "   Profile:               $PROFILE"
echo "   Plain files restored:  $RESTORED"
echo "   Encrypted decrypted:   $DECRYPTED"
echo "   Workspace:             $WORKSPACE"

if [[ -n "${SAFETY_BACKUP:-}" ]]; then
    echo ""
    echo "   Safety backup at: $SAFETY_BACKUP"
    echo "   (delete when satisfied with restore)"
fi
