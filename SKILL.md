---
name: openclaw-backup
description: Back up and restore OpenClaw workspace files (memory, soul, skills, config) to a private GitHub repo with age encryption for secrets. Supports multiple agent profiles in one repo. Use when the user asks to back up, restore, or check backup status of their OpenClaw workspace. Triggers on "backup", "restore workspace", "backup status", "save my workspace".
---

# OpenClaw Backup Plugin

Automated backup of OpenClaw workspace to a private GitHub repo with `age` encryption for sensitive files. Supports multi-agent profiles.

## Prerequisites

- `git` and `gh` CLI (authenticated)
- `age` (`brew install age` / `apt install age`)
- A private GitHub repo for backups

## Setup (First Time)

```bash
bash scripts/setup.sh <backup-repo-url> --profile <agent-name> --workspace <path>
```

Examples:
```bash
bash scripts/setup.sh https://github.com/user/backup --profile nymeria --workspace ~/.openclaw/workspace
bash scripts/setup.sh https://github.com/user/backup --profile mandy --workspace ~/.mandy/workspace
```

Generates an `age` keypair (shared across profiles) at `~/.openclaw-backup/age-key.txt`. **User must save this key securely** — it's the only way to decrypt secrets.

## Backup

```bash
bash scripts/backup.sh --profile <agent-name> [--dry-run]
```

**Flags:**
- `--profile <name>` — which agent profile to back up (default: "default")
- `--dry-run` — preview what would be backed up without making changes

**What gets backed up:**

| Category | Encrypted? |
|----------|:----------:|
| Identity (SOUL.md, IDENTITY.md, USER.md, AGENTS.md) | No |
| Memory (MEMORY.md, memory/*.md) | No |
| Config (TOOLS.md, HEARTBEAT.md) | No |
| Skills (skills/**/*) | No |
| Secrets (.secrets/**/*) | **Yes (.age)** |
| Environment (.env*) | **Yes (.age)** |

**When to auto-trigger backup:**
- After significant memory updates (new daily memory file, MEMORY.md changes)
- During heartbeat checks (add to HEARTBEAT.md)
- After skill installations or config changes
- Via cron for periodic backups: `"0 */6 * * *"` (every 6 hours)

**Preserving manual files:** Place a `.backup-keep` marker file in any repo directory to protect manually-added files (docs, notes) from orphan cleanup.

## .backupignore

Place a `.backupignore` file in the workspace root to customize exclusions. Syntax is like `.gitignore`:

```
# Directories
services/
build/
dist/

# Extensions (already excluded by default: images, video, audio, binaries, archives)
*.dat
*.db

# Include overrides (keep specific extensions that would otherwise be excluded)
!*.png
!*.svg
```

**Default excluded extensions** (no .backupignore needed):
`png jpg jpeg gif webp bmp ico svg mp4 mp3 wav avi mov mkv webm ogg so dylib dll zip tar gz bz2 xz 7z rar qml qmlc qmltypes wasm ttf otf woff woff2 pdf xlsx xls docx pptx`

Use `!*.ext` in `.backupignore` to override and include a default-excluded extension.

## Restore

```bash
bash scripts/restore.sh --profile <agent-name> [workspace-path]
```

Pulls latest, decrypts `.age` files, restores to workspace. Creates safety backup of existing workspace first.

## Status

```bash
bash scripts/status.sh                     # All profiles
bash scripts/status.sh --profile nymeria   # Specific profile details
```

## Repo Structure (Multi-Agent)

```
backup-repo/
├── .gitignore
├── nymeria/                # Profile: Nymeria
│   ├── SOUL.md
│   ├── MEMORY.md
│   ├── memory/
│   ├── skills/
│   ├── .secrets/*.age
│   └── .backup-meta.json
└── mandy/                  # Profile: Mandy
    ├── SOUL.md
    ├── MEMORY.md
    ├── memory/
    ├── skills/
    ├── .secrets/*.age
    └── .backup-meta.json
```
