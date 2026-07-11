# claude-statusline

A two-line, boxed status line for [Claude Code](https://claude.com/claude-code) with progress bars, live weather, git state, and rate-limit gauges. No dependencies beyond `jq` and `curl`.

```
╭─  macbook │  Projects/app │  main*  +12/-3 │  #42
╰─  Sonnet 5 │ ⛅ +18°C Amsterdam │  ctx ▓▓▓▓▓▒▒▒▒▒ 47%   5h ▓▓▒▒▒▒▒▒▒▒ 22%   7d ▓▓▓▓▓▓▒▒▒▒ 61% │ 08:17
```

## What it shows

**Top line**
- Hostname
- Current directory (last two path segments, `~`-aware)
- Git branch, with `*` when dirty and a live `+added/-removed` diffstat
- Open PR badge (color reflects review state: green=approved, red=changes requested, yellow=pending/draft) — only shown when a PR exists
- Worktree badge — only shown inside a `--worktree` session

**Bottom line**
- Model name, and output style if it's non-default
- Weather — auto-detected by IP via [wttr.in](https://wttr.in), cached for 20 minutes
- Context window usage bar
- 5-hour and 7-day subscription rate-limit bars (Claude.ai subscribers only)
- Vim mode badge, if vim mode is enabled
- Clock

Every segment is conditional — things that don't apply (no PR, no git repo, no rate-limit data yet) just don't render, so the line never shows empty junk.

## Requirements

- `jq` and `curl` (`brew install jq` on macOS; both usually preinstalled on Linux)
- A [Nerd Font](https://www.nerdfonts.com/) set as your terminal's font, for the icons to render correctly. Without one, the icons will show as tofu boxes — see [Customizing](#customizing) to swap them for plain unicode/emoji instead.
- macOS or Linux (uses `scutil`/`stat -f` on macOS with a `hostname -s`/`stat -c` fallback on Linux)

## Install

```bash
git clone https://github.com/adrianjean/claude-statusline.git ~/claude/statusline
```

Then point Claude Code's status line at it. Edit `~/.claude/settings.json` and set:

```json
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/claude/statusline/statusline.sh"
  }
}
```

(Merge this into your existing `settings.json` — don't overwrite the rest of the file.)

Restart Claude Code or open a new session to see it.

## Installing on another machine

```bash
git clone https://github.com/adrianjean/claude-statusline.git ~/claude/statusline
```

then add the same `statusLine` block to that machine's `~/.claude/settings.json`.

To pull down future updates:

```bash
cd ~/claude/statusline && git pull
```

## Customizing

Everything lives in one file, `statusline.sh`, in clearly labeled sections:

- **Colors** — a block of 256-color ANSI variables near the top (`GRAY`, `CYAN`, `GREEN`, etc.)
- **Icons** — `ICON_*` variables, each a `printf` of the raw UTF-8 bytes for a Nerd Font codepoint. Swap any of these for plain unicode/emoji if you don't use a Nerd Font.
- **`bar()`** — the progress bar renderer (width, fill/empty characters, color thresholds at 50%/80%)
- **Weather** — cached at `~/.claude/cache/statusline-weather`, refreshed in the background every 20 minutes (`age -ge 1200` — change the threshold to adjust). Uses `wttr.in/?format=%c+%t+%l&m` (metric units); switch to a fixed city by replacing the URL with `wttr.in/YourCity?format=...`.

## Notes

- Weather fetches are non-blocking: a stale cached value is shown immediately while a background job refreshes the cache, guarded by a lock directory so concurrent renders don't spawn duplicate `curl` calls.
- Git status calls use `--no-optional-locks` so the status line never blocks on a git lock file.
- Session cost/token spend isn't included here — the Claude Code status line JSON doesn't currently expose it.
