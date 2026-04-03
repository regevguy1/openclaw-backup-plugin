#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Backup — Status Script
# Usage: bash scripts/status.sh [--profile <name>]

BACKUP_DIR="$HOME/.openclaw-backup"
REPO_DIR="$BACKUP_DIR/repo"
KEY_FILE="$BACKUP_DIR/age-key.txt"

# Parse arguments
PROFILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash scripts/status.sh [--profile <name>]"
            echo "  Without --profile: shows all profiles"
            echo "  With --profile: shows details for specific profile"
            exit 0
            ;;
        -*) echo "❌ Unknown option: $1"; exit 1 ;;
        *) shift ;;
    esac
done

echo "🐺 OpenClaw Backup — Status"
echo "============================"
echo ""
echo "🔑 Age key:       $([ -f "$KEY_FILE" ] && echo "✅ Present" || echo "❌ Missing")"
echo "📦 Backup repo:   $REPO_DIR"
echo ""

if [[ ! -d "$REPO_DIR/.git" ]]; then
    echo "❌ Backup repo not found. Run setup first."
    exit 1
fi

# List all profiles
echo "📂 Profiles:"
PROFILES_DIR="$BACKUP_DIR/profiles"
if [[ -d "$PROFILES_DIR" ]]; then
    for conf in "$PROFILES_DIR"/*.conf; do
        [[ -f "$conf" ]] || continue
        PNAME=$(basename "$conf" .conf)
        source "$conf"
        PDIR="$REPO_DIR/$PNAME"
        if [[ -f "$PDIR/.backup-meta.json" ]]; then
            TIMESTAMP=$(grep '"timestamp"' "$PDIR/.backup-meta.json" | sed 's/.*: "//;s/".*//')
            TOTAL=$(grep '"total_files"' "$PDIR/.backup-meta.json" | sed 's/[^0-9]//g')
            echo "   [$PNAME] — $TOTAL files, last: $TIMESTAMP"
            echo "              workspace: $WORKSPACE"
        else
            echo "   [$PNAME] — no backups yet"
            echo "              workspace: $WORKSPACE"
        fi
    done
else
    echo "   (no profiles configured)"
fi

# Show details for specific profile
if [[ -n "$PROFILE" ]]; then
    PROFILE_DIR="$REPO_DIR/$PROFILE"
    PROFILE_CONF="$PROFILES_DIR/$PROFILE.conf"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 Profile: $PROFILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ -f "$PROFILE_CONF" ]]; then
        source "$PROFILE_CONF"
        echo "   Workspace: $WORKSPACE"
    fi
    
    if [[ -f "$PROFILE_DIR/.backup-meta.json" ]]; then
        TIMESTAMP=$(grep '"timestamp"' "$PROFILE_DIR/.backup-meta.json" | sed 's/.*: "//;s/".*//')
        TOTAL=$(grep '"total_files"' "$PROFILE_DIR/.backup-meta.json" | sed 's/[^0-9]//g')
        ENCRYPTED=$(grep '"encrypted_files"' "$PROFILE_DIR/.backup-meta.json" | sed 's/[^0-9]//g')
        PLAIN=$(grep '"plain_files"' "$PROFILE_DIR/.backup-meta.json" | sed 's/[^0-9]//g')
        echo "   Last backup: $TIMESTAMP"
        echo "   Total files: $TOTAL (plain: $PLAIN, encrypted: $ENCRYPTED)"
    else
        echo "   No backups yet."
    fi
    
    echo ""
    echo "📜 Recent commits:"
    cd "$REPO_DIR"
    git log --oneline --grep="$PROFILE" -5 2>/dev/null || echo "   No commits yet."
    
    # Check for changes since last backup
    if [[ -n "${WORKSPACE:-}" && -d "$WORKSPACE" ]]; then
        echo ""
        echo "🔍 Workspace changes since last backup:"
        LAST_COMMIT_TIME=$(cd "$REPO_DIR" && git log -1 --format=%ct 2>/dev/null || echo 0)
        CHANGES=0
        
        if [[ "$LAST_COMMIT_TIME" -gt 0 ]]; then
            while IFS= read -r -d '' file; do
                rel="${file#$WORKSPACE/}"
                [[ "$rel" == .git/* || "$rel" == node_modules/* || "$rel" == __pycache__/* ]] && continue
                FILE_MTIME=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null || echo 0)
                if [[ "$FILE_MTIME" -gt "$LAST_COMMIT_TIME" ]]; then
                    CHANGES=$((CHANGES + 1))
                fi
            done < <(find "$WORKSPACE" -type f -print0 2>/dev/null)
            
            if [[ "$CHANGES" -gt 0 ]]; then
                echo "   ⚠️  ~$CHANGES file(s) modified since last backup"
            else
                echo "   ✅ Workspace appears up to date"
            fi
        else
            echo "   ⚠️  No backups yet — run your first backup!"
        fi
    fi
fi
