#!/bin/sh
# Claude Code "TUI dashboard" status line — two-line, boxed, with progress bars.
input=$(cat)

# ---- colors -----------------------------------------------------------
RESET=$(printf '\033[0m')
DIM=$(printf '\033[2m')
BOLD=$(printf '\033[1m')
GRAY=$(printf '\033[38;5;240m')
CYAN=$(printf '\033[38;5;51m')
BLUE=$(printf '\033[38;5;75m')
GREEN=$(printf '\033[38;5;114m')
YELLOW=$(printf '\033[38;5;215m')
RED=$(printf '\033[38;5;203m')
PURPLE=$(printf '\033[38;5;141m')
MAGENTA=$(printf '\033[38;5;176m')
SKY=$(printf '\033[38;5;117m')
LABEL=$(printf '\033[38;5;245m')

# ---- icons (Nerd Font) --------------------------------------------------
ICON_HOST=$(printf '\357\204\211')  # U+F109 nf-fa-laptop
ICON_DIR=$(printf '')
ICON_GIT=$(printf '')
ICON_MODEL=$(printf '')
ICON_CTX=$(printf '')
ICON_5H=$(printf '')
ICON_7D=$(printf '')
ICON_PR=$(printf '')
ICON_ADVISOR=$(printf '')  # U+F0EB nf-fa-lightbulb-o

# ---- progress bar helper: bar <pct 0-100> <width> ---------------------
bar() {
  pct=$1
  width=$2
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  filled=$(( (pct * width + 50) / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  empty=$(( width - filled ))
  if [ "$pct" -ge 80 ]; then col=$RED
  elif [ "$pct" -ge 50 ]; then col=$YELLOW
  else col=$GREEN
  fi
  f=""; i=0
  while [ $i -lt $filled ]; do f="${f}▓"; i=$((i + 1)); done
  e=""; i=0
  while [ $i -lt $empty ]; do e="${e}▒"; i=$((i + 1)); done
  printf '%s%s%s%s%s' "$col" "$f" "$GRAY" "$e" "$RESET"
}

# ---- host / dir ---------------------------------------------------------
host=$(scutil --get ComputerName 2>/dev/null || hostname -s 2>/dev/null)
dir=$(echo "$input" | jq -r '.workspace.current_dir')
case "$dir" in
  "$HOME") shortdir="~" ;;
  "$HOME"/*) rest="${dir#"$HOME"/}"
    parent=$(dirname "$rest"); cur=$(basename "$rest")
    [ "$parent" = "." ] && shortdir="$cur" || shortdir="$(basename "$parent")/$cur"
    ;;
  *) parent=$(basename "$(dirname "$dir")"); cur=$(basename "$dir")
    [ -z "$parent" ] || [ "$parent" = "/" ] && shortdir="$cur" || shortdir="$parent/$cur"
    ;;
esac

# ---- git branch / dirty / diffstat (locks skipped so we never block) ---
gitpart=""
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  gcolor=$GREEN
  dirty=""
  diffstat=""
  if [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
    dirty="*"
    gcolor=$YELLOW
    nums=$(git -C "$dir" --no-optional-locks diff --numstat 2>/dev/null | awk '{a+=$1; d+=$2} END{printf "%d %d", a+0, d+0}')
    add=${nums% *}; del=${nums#* }
    if [ "$add" -gt 0 ] || [ "$del" -gt 0 ]; then
      diffstat="  ${DIM}${GREEN}+${add}${RESET}${DIM}/${RED}-${del}${RESET}"
    fi
  fi
  gitpart="  ${GRAY}│${RESET} ${ICON_GIT} ${gcolor}${branch}${dirty}${RESET}${diffstat}"
fi

# ---- PR badge (only if an open PR exists for this branch) --------------
prpart=""
prnum=$(echo "$input" | jq -r '.pr.number // empty')
if [ -n "$prnum" ]; then
  prstate=$(echo "$input" | jq -r '.pr.review_state // empty')
  case "$prstate" in
    approved) pcolor=$GREEN ;;
    changes_requested) pcolor=$RED ;;
    *) pcolor=$YELLOW ;;
  esac
  prpart="  ${GRAY}│${RESET} ${pcolor}${ICON_PR} #${prnum}${RESET}"
fi

# ---- worktree badge -------------------------------------------------
wtpart=""
wtname=$(echo "$input" | jq -r '.worktree.name // empty')
[ -n "$wtname" ] && wtpart="  ${GRAY}│${RESET} ${MAGENTA}⑂ ${wtname}${RESET}"

# ---- model / output style ------------------------------------------
model=$(echo "$input" | jq -r '.model.display_name')
ostyle=$(echo "$input" | jq -r '.output_style.name // empty')
stylepart=""
[ -n "$ostyle" ] && [ "$ostyle" != "default" ] && stylepart="  ${DIM}(${ostyle})${RESET}"

# ---- advisor model (from settings.json; not per-session) -------------
advisorpart=""
advisorkey=$(jq -r '.advisorModel // empty' "$HOME/.claude/settings.json" 2>/dev/null)
if [ -n "$advisorkey" ]; then
  case "$advisorkey" in
    sonnet) advisorname="Sonnet" ;;
    opus) advisorname="Opus" ;;
    haiku) advisorname="Haiku" ;;
    fable) advisorname="Fable" ;;
    *) advisorname="$advisorkey" ;;
  esac
  advisorpart="  ${GRAY}│${RESET} ${ICON_ADVISOR} ${LABEL}advisor${RESET} ${PURPLE}${advisorname}${RESET}"
fi

# ---- vim mode badge --------------------------------------------------
vimpart=""
vimmode=$(echo "$input" | jq -r '.vim.mode // empty')
if [ -n "$vimmode" ]; then
  case "$vimmode" in
    INSERT) vcolor=$GREEN ;;
    VISUAL*) vcolor=$MAGENTA ;;
    *) vcolor=$BLUE ;;
  esac
  vimpart="  ${GRAY}│${RESET} ${vcolor}${BOLD}${vimmode}${RESET}"
fi

# ---- weather (cached, non-blocking background refresh, IP geolocation) -
CACHE_DIR="$HOME/.claude/cache"
WCACHE="$CACHE_DIR/statusline-weather"
WLOCK="$CACHE_DIR/statusline-weather.lock"
mkdir -p "$CACHE_DIR" 2>/dev/null

age=99999
if [ -f "$WCACHE" ]; then
  mtime=$(stat -c %Y "$WCACHE" 2>/dev/null || stat -f %m "$WCACHE" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - mtime ))
fi
if [ "$age" -ge 1200 ] && mkdir "$WLOCK" 2>/dev/null; then
  (
    curl -s --max-time 3 'https://wttr.in/?format=%c+%t+%l&m' 2>/dev/null | tr -d '\n' > "$WCACHE.tmp" \
      && mv "$WCACHE.tmp" "$WCACHE"
    rmdir "$WLOCK" 2>/dev/null
  ) >/dev/null 2>&1 &
fi
weather=$(cat "$WCACHE" 2>/dev/null)
weatherpart=""
[ -n "$weather" ] && weatherpart="  ${GRAY}│${RESET} ${SKY}${weather}${RESET}"

# ---- context / rate-limit bars --------------------------------------
barspart=""
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used" ]; then
  pct=$(printf '%.0f' "$used")
  barspart="${barspart}${ICON_CTX} ${LABEL}ctx${RESET} $(bar "$pct" 10) ${DIM}${pct}%${RESET}"
fi
five=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
if [ -n "$five" ]; then
  pct=$(printf '%.0f' "$five")
  [ -n "$barspart" ] && barspart="${barspart}  "
  barspart="${barspart}${ICON_5H} ${LABEL}5h${RESET} $(bar "$pct" 10) ${DIM}${pct}%${RESET}"
fi
seven=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
if [ -n "$seven" ]; then
  pct=$(printf '%.0f' "$seven")
  [ -n "$barspart" ] && barspart="${barspart}  "
  barspart="${barspart}${ICON_7D} ${LABEL}7d${RESET} $(bar "$pct" 10) ${DIM}${pct}%${RESET}"
fi

clock=$(date '+%H:%M')

barssep=""
[ -n "$barspart" ] && barssep="  ${GRAY}│${RESET} "

# ---- render -----------------------------------------------------------
line1="${GRAY}╭─${RESET} ${CYAN}${ICON_HOST} ${host}${RESET} ${GRAY}│${RESET} ${BLUE}${ICON_DIR} ${shortdir}${RESET}${gitpart}${wtpart}${prpart}${vimpart}${weatherpart}"
line2="${GRAY}╰─${RESET} ${ICON_MODEL} ${LABEL}worker${RESET} ${PURPLE}${model}${RESET}${stylepart}${advisorpart}${barssep}${barspart}  ${GRAY}│${RESET} ${DIM}${clock}${RESET}"

printf '%s\n%s\n' "$line1" "$line2"
