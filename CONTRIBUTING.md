# Contributing to Autoboard

Autoboard is alpha software (v0.1.0). Contributions are welcome!

## Reporting Bugs

Open a [GitHub Issue](https://github.com/willietran/autoboard/issues) with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- Claude Code version (`claude --version`) or Codex version (`codex --version`)

## Requesting Features

Open an issue with the `enhancement` label describing your use case.

## Contributing Code

1. Fork the repo
2. Create a feature branch (`git checkout -b my-feature`)
3. Make your changes
4. Test locally in Claude Code with the plugin-dir flag:
   ```bash
   claude --plugin-dir /path/to/your/autoboard
   ```
5. Test locally in Codex with a home-local plugin symlink:
   ```bash
   mkdir -p ~/.agents/plugins ~/plugins
   ln -sfn /path/to/your/autoboard ~/plugins/autoboard
   ```
6. Open a PR against `main`

## Local Development

Clone the repo and point Claude Code at it:

```bash
git clone https://github.com/willietran/autoboard.git
alias claude="claude --plugin-dir ~/path/to/autoboard"
```

Changes to skills, agents, and config are reflected immediately — no build step needed.

For Codex local development, register the repo as a local plugin:

```bash
mkdir -p ~/.agents/plugins ~/plugins
ln -sfn ~/path/to/autoboard ~/plugins/autoboard
```

Then add an `autoboard` entry to `~/.agents/plugins/marketplace.json` pointing to `./plugins/autoboard`. Codex will pick up the repo's `.codex-plugin/plugin.json` and the shared skills from `.agents/skills/`.

## Code Standards

- Zero dead code (no commented-out blocks, no unused functions)
- Predictable naming (purpose obvious from name)
- Small, focused files (one clear responsibility each)
- Shell scripts must pass `shellcheck`
