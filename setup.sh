#!/usr/bin/env bash
#
# setup.sh -- run the configurator scripts in order, prompting which ones.
#
# Steps run in this order, because later steps depend on what earlier ones
# install:
#
#   1. install-tools.sh     alacritty + helix, default terminal/editor
#   2. install-themes.sh    Numix/Obsidian packages, then themes + fonts
#   3. configure-xfce.sh    keyboard shortcuts
#
# Run this as your normal user, NOT as root: the individual scripts escalate
# per command themselves, and the xfconf settings must be written to your
# session bus.  DRY_RUN=1 is passed through to every step.
#
# Usage:
#   ./setup.sh                       # prompt for which steps to run
#   ./setup.sh --all                 # run every step, no prompt
#   ./setup.sh --only tools,themes   # run selected steps, no prompt
#   ./setup.sh --list                # show the steps
#   DRY_RUN=1 ./setup.sh             # prompt, then dry-run each step
#
# Options:
#   -a, --all          run every step
#   -o, --only LIST    run only these steps (names or numbers, comma separated)
#   -l, --list         list the steps and exit
#   -n, --dry-run      same as DRY_RUN=1
#   -h, --help         show this help

set -euo pipefail

DRY_RUN=${DRY_RUN:-0}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

STEP_KEYS=(tools themes shortcuts)
STEP_SCRIPTS=(install-tools.sh install-themes.sh configure-xfce.sh)
STEP_DESCS=(
  "alacritty + helix (GitHub .deb), set default terminal/editor"
  "Numix + Obsidian packages, then GTK/WM/icon themes and fonts"
  "keyboard shortcuts via xfconf"
)

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

step_table() {
  local i
  for i in "${!STEP_KEYS[@]}"; do
    printf '  %d) %-18s %s\n' "$((i + 1))" "${STEP_SCRIPTS[$i]}" "${STEP_DESCS[$i]}"
  done
}

usage() {
  sed -n '3,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# Map a name, script filename or 1-based number to a step index.
resolve_step() {
  local want=$1 i
  for i in "${!STEP_KEYS[@]}"; do
    if [[ $want == "${STEP_KEYS[$i]}" || $want == "${STEP_SCRIPTS[$i]}" || $want == "$((i + 1))" ]]; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  return 1
}

declare -A chosen=()
declare -a selected=()

add_selection() {
  local raw=$1 tok idx
  raw=${raw//,/ }
  if [[ ${raw// /} == all || ${raw// /} == a ]]; then
    raw=${STEP_KEYS[*]}
  fi
  for tok in $raw; do
    idx=$(resolve_step "$tok") || die "unknown step '$tok' (see --list)"
    chosen[$idx]=1
  done
}

finalize_selection() {
  local i
  selected=()
  for i in "${!STEP_KEYS[@]}"; do
    [[ -n ${chosen[$i]+x} ]] && selected+=("$i")
  done
  ((${#selected[@]})) || die "nothing selected (see --list)"
}

selected_names() {
  local i out=()
  for i in "${selected[@]}"; do
    out+=("${STEP_SCRIPTS[$i]}")
  done
  local IFS=' '
  printf '%s' "${out[*]}"
}

prompt_selection() {
  local reply
  say "Steps (in order):"
  step_table >&2
  printf 'Run which? [Enter = all, or numbers/names separated by spaces] ' >&2
  IFS= read -r reply || reply=
  reply=${reply:-all}
  add_selection "$reply"
}

confirm() {
  local reply
  printf 'Run %s%s? [Y/n] ' "$(selected_names)" "$([[ $DRY_RUN == 1 ]] && echo ' (dry run)')" >&2
  IFS= read -r reply || reply=
  [[ -z $reply || $reply == [Yy]* ]]
}

mode=prompt
while (($#)); do
  case $1 in
    -a | --all) mode=all; shift ;;
    -o | --only)
      [[ $# -ge 2 ]] || die "--only needs a list"
      mode=only
      add_selection "$2"
      shift 2
      ;;
    -l | --list) mode=list; shift ;;
    -n | --dry-run) DRY_RUN=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown option '$1' (try --help)" ;;
  esac
done

# The child scripts inherit DRY_RUN only if it is exported.
export DRY_RUN

if [[ $mode == list ]]; then
  step_table
  exit 0
fi

if [[ $EUID -eq 0 ]]; then
  die "run this as your normal user, not root: the scripts escalate per command,
and xfconf settings must be written to your session bus"
fi

case $mode in
  all) add_selection "${STEP_KEYS[*]}" ;;
  only) : ;;
  prompt)
    [[ -t 0 ]] || die "no terminal to prompt on; use --all or --only LIST"
    prompt_selection
    ;;
esac

finalize_selection

if [[ $mode == prompt ]] && ! confirm; then
  say "Aborted."
  exit 0
fi

say ""

for i in "${selected[@]}"; do
  script=$script_dir/${STEP_SCRIPTS[$i]}
  [[ -f $script ]] || die "missing ${STEP_SCRIPTS[$i]} in $script_dir"

  say "==> ${STEP_SCRIPTS[$i]}"
  if ! bash "$script"; then
    die "step failed: ${STEP_SCRIPTS[$i]} (fix it, then re-run with --only ${STEP_KEYS[$i]})"
  fi
  say ""
done

say "All done."
