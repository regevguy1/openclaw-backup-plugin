#!/usr/bin/env bash
set -euo pipefail

# OpenClaw Backup — Backup Script
# Usage: bash scripts/backup.sh [--profile <name>] [--dry-run] [workspace-path]

BACKUP_DIR="$HOME/.openclaw-backup"
KEY_FILE="$BACKUP_DIR/age-key.txt"
REPO_DIR="$BACKUP_DIR/repo"

# Parse flags
DRY_RUN=false
PROFILE="default"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --profile) PROFILE="$2"; shift 2 ;;
        --help|-h)
            echo "Usage: bash scripts/backup.sh [--profile <name>] [--dry-run] [workspace-path]"
            echo ""
            echo "Options:"
            echo "  --profile <name>   Profile to back up (default: 'default')"
            echo "  --dry-run          Preview changes without modifying anything"
            exit 0
            ;;
        -*) echo "❌ Unknown option: $1"; exit 1 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

CONFIG_FILE="$BACKUP_DIR/profiles/$PROFILE.conf"

# Load profile config
if [[ ! -f "$CONFIG_FILE" ]]; then
    # Fallback to legacy config
    if [[ -f "$BACKUP_DIR/config" ]]; then
        source "$BACKUP_DIR/config"
    else
        echo "❌ Profile '$PROFILE' not found. Run: bash scripts/setup.sh <repo-url> --profile $PROFILE"
        exit 1
    fi
else
    source "$CONFIG_FILE"
fi

WORKSPACE="${POSITIONAL[0]:-${WORKSPACE:-$HOME/.openclaw/workspace}}"
PROFILE_DIR="$REPO_DIR/$PROFILE"

if [[ ! -d "$WORKSPACE" ]]; then
    echo "❌ Workspace not found: $WORKSPACE"
    exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
    echo "❌ Age key not found: $KEY_FILE"
    echo "   Run setup first: bash scripts/setup.sh <repo-url>"
    exit 1
fi

# Extract public key (macOS + Linux compatible)
PUBLIC_KEY=$(grep 'public key:' "$KEY_FILE" | awk '{print $NF}')

echo "🐺 OpenClaw Backup"
echo "=================="
echo "   Profile:   $PROFILE"
echo "   Workspace: $WORKSPACE"
echo "   Repo:      $PROFILE_DIR"
$DRY_RUN && echo "   Mode:      🏜️  DRY RUN (no changes)"
echo ""

# Patterns for files/dirs that should be encrypted
ENCRYPT_PATTERNS=(
    ".secrets"
    ".env"
    ".env.*"
)

# Default patterns to always exclude from backup
DEFAULT_EXCLUDE_PATTERNS=(
    ".git"
    "node_modules"
    "__pycache__"
    ".DS_Store"
    "*.pyc"
    ".cache"
)

# Default binary/media extensions to exclude
DEFAULT_EXCLUDE_EXTENSIONS=(
    "png" "jpg" "jpeg" "gif" "webp" "bmp" "ico" "svg"
    "mp4" "mp3" "wav" "avi" "mov" "mkv" "webm" "ogg"
    "so" "dylib" "dll" "o" "a"
    "zip" "tar" "gz" "bz2" "xz" "7z" "rar"
    "whl" "egg"
    "qml" "qmlc" "qmltypes"
    "wasm"
    "ttf" "otf" "woff" "woff2"
    "pdf"
    "xlsx" "xls" "docx" "pptx"
)

# Load .backupignore if it exists (from workspace root)
BACKUPIGNORE_PATTERNS=()
BACKUPIGNORE_EXTENSIONS=()
BACKUPIGNORE_DIRS=()
BACKUPIGNORE_INCLUDE_EXTENSIONS=()

load_backupignore() {
    local ignore_file="$1/.backupignore"
    [[ -f "$ignore_file" ]] || return 0
    
    echo "📄 Loading .backupignore from workspace..."
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ -z "$line" || "$line" == \#* ]] && continue
        # Trim whitespace
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$line" ]] && continue
        
        # Include patterns (override excludes): !*.ext
        if [[ "$line" == !*.* ]]; then
            ext="${line#!*.}"
            BACKUPIGNORE_INCLUDE_EXTENSIONS+=("$ext")
            continue
        fi
        
        # Extension patterns: *.ext
        if [[ "$line" == \*.* ]]; then
            ext="${line#\*.}"
            BACKUPIGNORE_EXTENSIONS+=("$ext")
            continue
        fi
        
        # Directory patterns: dir/ or dir
        if [[ "$line" == */ ]]; then
            BACKUPIGNORE_DIRS+=("${line%/}")
        else
            BACKUPIGNORE_PATTERNS+=("$line")
        fi
    done < "$ignore_file"
}

# Max file size in bytes (50MB — GitHub's recommended limit)
MAX_FILE_SIZE=$((50 * 1024 * 1024))
SKIPPED_LARGE=0

# Secret patterns to detect (forces encryption if found in plain files)
SECRET_PATTERNS='ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{80,}|sk-[A-Za-z0-9]{20,}|vcp_[A-Za-z0-9]{50,}|xoxb-[A-Za-z0-9-]+'

# Function to check if a path should be encrypted
should_encrypt() {
    local rel_path="$1"
    local filename
    filename=$(basename "$rel_path")
    
    for pattern in "${ENCRYPT_PATTERNS[@]}"; do
        # Directory-style patterns (e.g., ".secrets")
        if [[ "$rel_path" == "$pattern" || "$rel_path" == "$pattern"/* || "$rel_path" == *"/$pattern" || "$rel_path" == *"/$pattern"/* ]]; then
            return 0
        fi
        # Filename glob patterns (e.g., ".env", ".env.*") — match anywhere in tree
        if [[ "$filename" == $pattern ]]; then
            return 0
        fi
    done
    return 1
}

# Function to check if path should be excluded
should_exclude() {
    local rel_path="$1"
    local filename ext
    filename=$(basename "$rel_path")
    ext="${filename##*.}"
    
    # Check include overrides first (from .backupignore !*.ext)
    if [[ "$filename" == *.* ]]; then
        for iext in "${BACKUPIGNORE_INCLUDE_EXTENSIONS[@]+"${BACKUPIGNORE_INCLUDE_EXTENSIONS[@]}"}"; do
            [[ "$ext" == "$iext" ]] && return 1  # Explicitly included
        done
    fi
    
    # Check default directory/pattern excludes
    for pattern in "${DEFAULT_EXCLUDE_PATTERNS[@]+"${DEFAULT_EXCLUDE_PATTERNS[@]}"}"; do
        if [[ "$rel_path" == "$pattern" || "$rel_path" == "$pattern"/* || "$rel_path" == *"/$pattern" || "$rel_path" == *"/$pattern"/* ]]; then
            return 0
        fi
    done
    
    # Check default extension excludes
    if [[ "$filename" == *.* ]]; then
        for dext in "${DEFAULT_EXCLUDE_EXTENSIONS[@]+"${DEFAULT_EXCLUDE_EXTENSIONS[@]}"}"; do
            [[ "$ext" == "$dext" ]] && return 0
        done
    fi
    
    # Check .backupignore directory excludes
    for dir in "${BACKUPIGNORE_DIRS[@]+"${BACKUPIGNORE_DIRS[@]}"}"; do
        if [[ "$rel_path" == "$dir" || "$rel_path" == "$dir"/* || "$rel_path" == *"/$dir" || "$rel_path" == *"/$dir"/* ]]; then
            return 0
        fi
    done
    
    # Check .backupignore extension excludes
    if [[ "$filename" == *.* ]]; then
        for bext in "${BACKUPIGNORE_EXTENSIONS[@]+"${BACKUPIGNORE_EXTENSIONS[@]}"}"; do
            [[ "$ext" == "$bext" ]] && return 0
        done
    fi
    
    # Check .backupignore pattern excludes
    for pattern in "${BACKUPIGNORE_PATTERNS[@]+"${BACKUPIGNORE_PATTERNS[@]}"}"; do
        if [[ "$rel_path" == "$pattern" || "$rel_path" == "$pattern"/* || "$rel_path" == *"/$pattern" || "$rel_path" == *"/$pattern"/* ]]; then
            return 0
        fi
        # Glob match
        if [[ "$rel_path" == $pattern ]]; then
            return 0
        fi
    done
    
    return 1
}

# Function to check if a file in the repo is manually added (should be kept)
is_backup_keep() {
    local file_path="$1"
    local dir
    dir="$(dirname "$file_path")"
    
    # Check for .backup-keep marker in the file's directory or any parent up to profile root
    while [[ "$dir" != "$PROFILE_DIR" && "$dir" != "/" && "$dir" != "." ]]; do
        if [[ -f "$dir/.backup-keep" ]]; then
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    if [[ -f "$PROFILE_DIR/.backup-keep" ]]; then
        # Root-level .backup-keep — check if file is listed or if marker is wildcard
        return 0
    fi
    return 1
}

# Track stats (initialize to 0; use arithmetic that doesn't fail under set -e)
TOTAL_FILES=0
ENCRYPTED_FILES=0
PLAIN_FILES=0
SKIPPED_EXCLUDE=0

if ! $DRY_RUN; then
    # Ensure profile directory exists
    mkdir -p "$PROFILE_DIR"
    
    # Clean up orphaned files (files in repo that no longer exist in workspace)
    if [[ -d "$PROFILE_DIR" ]]; then
        cd "$PROFILE_DIR"
        while IFS= read -r -d '' file; do
            rel_path="${file#./}"
            [[ "$rel_path" == .git/* ]] && continue
            [[ "$rel_path" == ".gitignore" ]] && continue
            [[ "$rel_path" == ".backup-meta.json" ]] && continue
            [[ "$rel_path" == ".backup-keep" ]] && continue
            
            # Skip files marked with .backup-keep
            if is_backup_keep "$PROFILE_DIR/$rel_path"; then
                continue
            fi
            
            # For .age files, check if source exists
            if [[ "$rel_path" == *.age ]]; then
                source_path="${rel_path%.age}"
                if [[ ! -f "$WORKSPACE/$source_path" ]]; then
                    rm -f "$PROFILE_DIR/$rel_path"
                    echo "   🗑️  Removed orphan: $rel_path"
                fi
            else
                if [[ ! -f "$WORKSPACE/$rel_path" ]]; then
                    rm -f "$PROFILE_DIR/$rel_path"
                    echo "   🗑️  Removed orphan: $rel_path"
                fi
            fi
        done < <(find . -type f -print0 2>/dev/null)
    fi
fi

# Load .backupignore from workspace
load_backupignore "$WORKSPACE"

# Process workspace files
echo "📋 Scanning workspace..."

cd "$WORKSPACE"
while IFS= read -r -d '' file; do
    rel_path="${file#./}"
    
    # Skip excluded patterns
    if should_exclude "$rel_path"; then
        continue
    fi
    
    # Skip files larger than MAX_FILE_SIZE
    FILE_SIZE=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null || echo 0)
    if [[ "$FILE_SIZE" -gt "$MAX_FILE_SIZE" ]]; then
        SKIPPED_LARGE=$((SKIPPED_LARGE + 1))
        echo "   ⏭️  Skipped ($(( FILE_SIZE / 1024 / 1024 ))MB > 50MB limit): $rel_path"
        continue
    fi
    
    TOTAL_FILES=$((TOTAL_FILES + 1))
    
    # Auto-detect secrets in plain files → force encryption
    FORCE_ENCRYPT=false
    if ! should_encrypt "$rel_path"; then
        if grep -qE "$SECRET_PATTERNS" "$file" 2>/dev/null; then
            FORCE_ENCRYPT=true
            echo "   ⚠️  Secret detected in plain file, encrypting: $rel_path"
        fi
    fi
    
    if should_encrypt "$rel_path" || $FORCE_ENCRYPT; then
        ENCRYPTED_FILES=$((ENCRYPTED_FILES + 1))
        if $DRY_RUN; then
            echo "   🔒 [would encrypt] $rel_path → ${rel_path}.age"
        else
            target_file="$PROFILE_DIR/${rel_path}.age"
            mkdir -p "$(dirname "$target_file")"
            age -r "$PUBLIC_KEY" -o "$target_file" "$file"
            echo "   🔒 $rel_path → ${rel_path}.age"
        fi
    else
        PLAIN_FILES=$((PLAIN_FILES + 1))
        if $DRY_RUN; then
            echo "   📄 [would copy] $rel_path"
        else
            target_dir="$PROFILE_DIR/$(dirname "$rel_path")"
            mkdir -p "$target_dir"
            cp "$file" "$PROFILE_DIR/$rel_path"
        fi
    fi
done < <(find . -type f -print0)

echo ""
echo "📊 Summary:"
echo "   Total files:     $TOTAL_FILES"
echo "   Plain text:      $PLAIN_FILES"
echo "   Encrypted:       $ENCRYPTED_FILES"
[[ "$SKIPPED_LARGE" -gt 0 ]] && echo "   Skipped (>50MB):  $SKIPPED_LARGE"

if $DRY_RUN; then
    echo ""
    echo "🏜️  Dry run complete — no files were changed."
    echo "   Remove --dry-run to perform the actual backup."
    exit 0
fi

# Create .gitignore in backup repo root (if not exists or update)
cat > "$REPO_DIR/.gitignore" <<'EOF'
# Never commit decrypted secrets
**/.secrets/**
!**/.secrets/**/*.age
**/.env
**/.env.*
!**/.env*.age

# OS junk
.DS_Store
Thumbs.db

# Runtime
node_modules/
__pycache__/
*.pyc
.cache/
EOF

# Create backup metadata for this profile
cat > "$PROFILE_DIR/.backup-meta.json" <<EOF
{
    "profile": "$PROFILE",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "hostname": "$(hostname)",
    "workspace": "$WORKSPACE",
    "total_files": $TOTAL_FILES,
    "encrypted_files": $ENCRYPTED_FILES,
    "plain_files": $PLAIN_FILES,
    "age_public_key": "$PUBLIC_KEY"
}
EOF

# Commit and push
cd "$REPO_DIR"
git add -A

if git diff --cached --quiet; then
    echo ""
    echo "✅ No changes to back up — workspace is already synced."
else
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    COMMIT_MSG="backup($PROFILE): $TIMESTAMP — $TOTAL_FILES files ($ENCRYPTED_FILES encrypted, $PLAIN_FILES plain)"
    git commit -m "$COMMIT_MSG"
    
    echo ""
    echo "📤 Pushing to remote..."
    git push origin main 2>/dev/null || git push origin master 2>/dev/null || {
        BRANCH=$(git branch --show-current)
        git push -u origin "$BRANCH"
    }
    
    echo ""
    echo "✅ Backup complete!"
    echo "   Commit: $COMMIT_MSG"
fi
