# 🐺 OpenClaw Backup Plugin

Automated backup of your OpenClaw workspace to a private GitHub repo, with **age encryption** for secrets. Supports **multi-agent profiles** — back up multiple agents to one repo.

## What Gets Backed Up

| Category | Examples | Encrypted? |
|----------|----------|:----------:|
| Identity | SOUL.md, IDENTITY.md, USER.md | ❌ Plain |
| Memory | MEMORY.md, memory/*.md | ❌ Plain |
| Config | AGENTS.md, TOOLS.md, HEARTBEAT.md | ❌ Plain |
| Skills | skills/**/* | ❌ Plain |
| Secrets | .secrets/**/* | ✅ `.age` |
| Environment | .env, .env.* | ✅ `.age` |

## Quick Start

### 1. Install dependencies

```bash
brew install age    # macOS
# or: apt install age   # Linux
```

### 2. Setup (per agent)

```bash
# Single agent
bash scripts/setup.sh https://github.com/your-user/your-backup-repo

# Multi-agent
bash scripts/setup.sh https://github.com/your-user/your-backup-repo --profile nymeria --workspace ~/.openclaw/workspace
bash scripts/setup.sh https://github.com/your-user/your-backup-repo --profile mandy --workspace ~/.mandy/workspace
```

This generates a shared `age` keypair and configures per-agent profiles. **Save the key file securely** — it's the only way to decrypt your secrets.

### 3. Backup

```bash
bash scripts/backup.sh --profile nymeria
bash scripts/backup.sh --profile mandy
bash scripts/backup.sh --profile nymeria --dry-run   # Preview only
```

### 4. Check status

```bash
bash scripts/status.sh                     # All profiles
bash scripts/status.sh --profile nymeria   # Specific profile
```

### 5. Restore

```bash
bash scripts/restore.sh --profile nymeria
```

## How It Works

1. **Plain files** (memory, soul, skills, config) are copied to `<repo>/<profile>/`
2. **Sensitive files** (.secrets/, .env) are encrypted with `age` → committed as `.age` blobs
3. Everything is committed and pushed to your private GitHub repo
4. On restore, `.age` files are decrypted using your local key

## Security Model

- Secrets **never** appear in plaintext in git history
- The `age` master key stays local (`~/.openclaw-backup/age-key.txt`) — never committed
- Even if the private repo leaks, encrypted secrets remain protected
- One key for all profiles — back it up separately (password manager, secure note)

## Protecting Manual Files

If you add files directly to the backup repo (docs, notes, etc.), place a `.backup-keep` marker file in that directory to prevent the orphan cleanup from removing them:

```bash
touch backup-repo/nymeria/docs/.backup-keep
```

## Repo Structure

```
backup-repo/
├── .gitignore
├── nymeria/
│   ├── SOUL.md
│   ├── MEMORY.md
│   ├── memory/
│   ├── skills/
│   ├── .secrets/*.age
│   └── .backup-meta.json
└── mandy/
    ├── SOUL.md
    ├── MEMORY.md
    └── ...
```

## Scheduling Automatic Backups

```bash
# Via crontab (every 6 hours)
0 */6 * * * /path/to/scripts/backup.sh --profile nymeria >> /tmp/openclaw-backup.log 2>&1

# Or via OpenClaw cron / HEARTBEAT.md for agent-driven backups
```

## License

MIT
