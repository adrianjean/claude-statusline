# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single POSIX `sh` script (`statusline.sh`) that Claude Code invokes as an external `statusLine` command. It reads a JSON blob on stdin (session/workspace/git/model/rate-limit info supplied by Claude Code) and prints a two-line, boxed, ANSI-colored status line to stdout. There is no build step, package manager, or test suite — the entire project is this one file plus `README.md`.

## Testing changes

There's no test harness. To check a change, feed it a representative JSON payload on stdin and inspect the printed output, e.g.:

```bash
echo '{"workspace":{"current_dir":"'"$PWD"'"},"model":{"display_name":"Sonnet 5"},"context_window":{"used_percentage":47},"rate_limits":{"five_hour":{"used_percentage":22},"seven_day":{"used_percentage":61}}}' | sh statusline.sh
```

To actually see it live in Claude Code, point `~/.claude/settings.json`'s `statusLine.command` at your working copy and start a new session (see README "Install").

Since the script targets `sh` (not bash-specific), avoid bashisms — test with `sh` explicitly, and prefer `[ ]` over `[[ ]]`, POSIX parameter expansion over arrays, etc.

## Architecture

The script is a linear pipeline over one `$input` JSON blob, built from independently-computed, independently-conditional segments that are concatenated at the very end. Each segment (git, PR, worktree, model/style, vim mode, weather, context/rate-limit bars) computes its own `*part` string and leaves it empty if the corresponding data isn't present in the input — so nothing renders when a field is absent (no PR, not a git repo, no rate-limit data yet). New segments should follow this same pattern: compute a `foopart` variable guarded by presence checks, then splice it into `line1` or `line2` at the bottom.

Key pieces, in file order:
- **Colors / Icons** — `printf`-built ANSI escape and Nerd Font codepoint constants at the top. Icons are literal UTF-8 bytes for Nerd Font glyphs; keep them swappable for plain unicode/emoji (this is the documented customization path).
- **`bar()`** — shared progress-bar renderer used by all three gauges (ctx/5h/7d): fixed width, ▓/▒ fill, color thresholds at 50%/80%.
- **Git segment** — uses `--no-optional-locks` on every git invocation so the status line never blocks on a git lock file; this constraint applies to any new git calls added here too.
- **Weather segment** — cached at `~/.claude/cache/statusline-weather`, refreshed via a backgrounded subshell guarded by a `mkdir`-based lock directory (`statusline-weather.lock`) so concurrent renders don't spawn duplicate `curl` calls, and a stale cached value is shown immediately rather than blocking on the network. Refresh interval is the `age -ge 1200` check (seconds).
- **Bars segment** — reads `context_window.used_percentage`, `rate_limits.five_hour.used_percentage`, `rate_limits.seven_day.used_percentage` from the input JSON; each is independently optional.
- **Advisor segment** — the one segment that doesn't read `$input` at all: it reads `advisorModel` directly from `~/.claude/settings.json` via a second `jq` call, since that setting isn't part of the statusline JSON payload (confirmed: the payload only exposes the main session's `.model.display_name`, not per-role model config). Follow this same direct-settings-read pattern for any other config-only value that Claude Code doesn't surface in the statusline JSON.
- **Render** — `line1`/`line2` are assembled by concatenating the precomputed `*part` variables in a fixed order, then printed.

macOS/Linux portability is handled with fallback chains (`scutil --get ComputerName || hostname -s`, `stat -f %m || stat -c %Y`) rather than branching on `uname` — keep that pattern for any new platform-dependent calls.
