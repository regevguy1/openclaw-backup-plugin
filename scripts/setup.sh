#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Backup — Setup Script
# Usage: bash scripts/setup.sh <backup-repo-url> [--profile <name>] [--workspace <path>]
#
# Profiles allow multiple agents to back up to the same repo under separate directories.
# Default profile: "default"

BACKUP_DIR="$HOME/.openclaw-backup"
KEY_FILE="$BACKUP_DIR/age-key.txt"

# Parse arguments
REPO_URL=""
PROFILE="default"
WORKSPACE="$HOME/.openclaw/workspace"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --profile) PROFILE="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash scripts/setup.sh <backup-repo-url> [--profile <name>] [--workspace <path>]"
            echo ""
            echo "Options:"
            echo "  --profile <name>     Profile name (default: 'default'). Each profile backs up"
            echo "                       to its own subdirectory in the repo."
            echo "  --workspace <path>   Workspace path (default: ~/.openclaw/workspace)"
            echo ""
            echo "Examples:"
            echo "  bash scripts/setup.sh https://github.com/user/backup-repo"
            echo "  bash scripts/setup.sh https://github.com/user/backup-repo --profile nymeria --workspace ~/.openclaw/workspace"
            echo "  bash scripts/setup.sh https://github.com/user/backup-repo --profile mandy --workspace ~/.mandy/workspace"
            exit 0
            ;;
        -*) echo "❌ Unknown option: $1"; exit 1 ;;
        *) REPO_URL="$1"; shift ;;
    esac
done

REPO_DIR="$BACKUP_DIR/repo"
CONFIG_FILE="$BACKUP_DIR/profiles/$PROFILE.conf"

if [[ -z "$REPO_URL" ]]; then
    echo "❌ Usage: bash scripts/setup.sh <backup-repo-url> [--profile <name>] [--workspace <path>]"
    echo "   Example: bash scripts/setup.sh https://github.com/user/backup-repo --profile nymeria"
    exit 1
fi

# Check dependencies
for cmd in git age age-keygen; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Missing dependency: $cmd"
        [[ "$cmd" == "age" || "$cmd" == "age-keygen" ]] && echo "   Install with: brew install age"
        exit 1
    fi
done

echo "🐺 OpenClaw Backup — Setup"
echo "=========================="
echo "   Profile:   $PROFILE"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR/profiles"
chmod 700 "$BACKUP_DIR"

# Helper: extract public key from age key file (macOS + Linux compatible)
extract_public_key() {
    grep 'public key:' "$1" | awk '{print $NF}'
}

# Generate age keypair if not exists (shared across profiles)
if [[ -f "$KEY_FILE" ]]; then
    echo "🔑 Age key already exists at $KEY_FILE"
    PUBLIC_KEY=$(extract_public_key "$KEY_FILE")
else
    echo "🔑 Generating age keypair..."
    age-keygen -o "$KEY_FILE" 2>&1
    chmod 600 "$KEY_FILE"
    PUBLIC_KEY=$(extract_public_key "$KEY_FILE")
    echo ""
    echo "⚠️  SAVE THIS PUBLIC KEY — needed for encryption:"
    echo "   $PUBLIC_KEY"
    echo ""
    echo "⚠️  SAVE THE KEY FILE — needed for decryption:"
    echo "   $KEY_FILE"
    echo "   Back this up separately (password manager, secure note, etc.)"
    echo ""
fi

# Clone or update backup repo
if [[ -d "$REPO_DIR/.git" ]]; then
    echo "📁 Backup repo already exists at $REPO_DIR"
    cd "$REPO_DIR"
    git pull --ff-only 2>/dev/null || echo "   (no remote changes)"
else
    echo "📦 Cloning backup repo..."
    git clone "$REPO_URL" "$REPO_DIR" 2>/dev/null || {
        # Empty repo — initialize
        mkdir -p "$REPO_DIR"
        cd "$REPO_DIR"
        git init
        git remote add origin "$REPO_URL"
    }
fi

# Create profile subdirectory in repo
mkdir -p "$REPO_DIR/$PROFILE"

# Save profile config
cat > "$CONFIG_FILE" <<EOF
REPO_URL=$REPO_URL
WORKSPACE=$WORKSPACE
PROFILE=$PROFILE
PUBLIC_KEY=$PUBLIC_KEY
EOF
chmod 600 "$CONFIG_FILE"

echo ""
echo "✅ Setup complete!"
echo "   Profile:     $PROFILE"
echo "   Backup dir:  $BACKUP_DIR"
echo "   Repo:        $REPO_DIR/$PROFILE"
echo "   Workspace:   $WORKSPACE"
echo "   Public key:  $PUBLIC_KEY"
echo ""
echo "Next steps:"
echo "  1. Save the age key file securely (password manager, etc.)"
echo "  2. Run your first backup: bash scripts/backup.sh --profile $PROFILE"
