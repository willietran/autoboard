# Installing Autoboard for Codex

Enable Autoboard skills in Codex via native skill discovery. Clone and symlink.

## Prerequisites

- Git

## Installation

1. **Clone the autoboard repository:**
   ```bash
   git clone https://github.com/willietran/autoboard.git ~/.codex/autoboard
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/autoboard/skills ~/.agents/skills/autoboard
   ```

3. **Restart Codex** (quit and relaunch) to discover the skills.

## Verify

```bash
ls -la ~/.agents/skills/autoboard
```

You should see a symlink pointing to your autoboard skills directory.

## Updating

```bash
cd ~/.codex/autoboard && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/autoboard
rm -rf ~/.codex/autoboard
```
