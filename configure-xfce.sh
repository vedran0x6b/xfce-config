#!/usr/bin/env bash
#
# configure-xfce.sh -- declarative XFCE keyboard shortcuts via xfconf-query.
#
# Run inside an XFCE session.  Repeatable: only the keys listed below are
# touched; every other shortcut is left alone.
#
# How XFCE stores shortcuts (channel: xfce4-keyboard-shortcuts):
#
#   /commands/custom/<accelerator>   command line   (global application shortcut)
#   /xfwm4/custom/<accelerator>      action name    (xfwm4 window-manager shortcut)
#
# Each provider also has a /default subtree shipped by XFCE.  When
# /<provider>/custom/override is true, ONLY /custom is read; when it is
# false/absent, ONLY /default is read.  The GUI clones defaults into /custom
# on first use, so enabling custom mode does not drop the stock shortcuts.
# This script does the same before applying its overrides.
#
# Accelerators use GTK syntax, e.g. <Primary> (Ctrl), <Alt>, <Shift>,
# <Super> (Windows key), <Hyper>, plus a key name (t, F4, Left, KP_1,
# Page_Down, space, XF86AudioRaiseVolume, ...).
#
# Usage:
#   ./configure-xfce.sh
#   DRY_RUN=1 ./configure-xfce.sh          # print commands, change nothing
#
# Environment:
#   XFCONF_QUERY   path to xfconf-query (default: xfconf-query)
#   CHANNEL        xfconf channel (default: xfce4-keyboard-shortcuts)

set -euo pipefail

CHANNEL=${CHANNEL:-xfce4-keyboard-shortcuts}
XFCONF=${XFCONF_QUERY:-xfconf-query}
DRY_RUN=${DRY_RUN:-0}

# ---------------------------------------------------------------------------
# Desired application shortcuts: accelerator -> command line.
#
# The command is split with g_shell_parse_argv() and spawned directly, NOT
# through a shell.  Pipes, redirection, &&, variables, etc. therefore need an
# explicit shell, e.g.:  ["<Super>x"]="sh -c 'foo | bar'"
# ---------------------------------------------------------------------------
declare -A APP_SHORTCUTS=(
  ["<Super>t"]="exo-open --launch TerminalEmulator"
  ["<Super>f"]="thunar"
  ["<Super>e"]="xfce4-appfinder"
  ["<Super>w"]="exo-open --launch WebBrowser"
)

# ---------------------------------------------------------------------------
# Desired window-manager shortcuts: accelerator -> xfwm4 action name.
#
# Run `xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/default -l -v`
# to see the stock set, or see the action list in README.md.
#
# xfwm4 binds only one accelerator per action.  Any other accelerator already
# mapped to one of these actions (e.g. the stock <Super>KP_Right for
# tile_right_key) is unbound before the bindings below are applied.
# ---------------------------------------------------------------------------
declare -A WM_SHORTCUTS=(
  ["<Super>Left"]="tile_left_key"
  ["<Super>Right"]="tile_right_key"
  ["<Super>Up"]="tile_up_key"
  ["<Super>Down"]="tile_down_key"
  ["<Super>j"]="next_workspace_key"
  ["<Super>k"]="prev_workspace_key"
  ["<Super><Shift>j"]="move_window_next_workspace_key"
)

# ---------------------------------------------------------------------------
# Accelerators to remove from the active set.  Applied before the bindings
# above, so an explicit binding always wins.  Each key is cleared from both
# providers.  Uncomment to use.
# ---------------------------------------------------------------------------
UNBIND=(
  # "<Primary><Alt>t"   # stock terminal; we use <Super>t instead
  # "<Super>Tab"        # stock window switcher
)

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

run() {
  if [[ $DRY_RUN == 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# Value of a property, or empty if it does not exist.
get() {
  "$XFCONF" -c "$CHANNEL" -p "$1" -v 2>/dev/null || true
}

has_prop() {
  "$XFCONF" -c "$CHANNEL" -p "$1" >/dev/null 2>&1
}

set_string() {
  run "$XFCONF" -c "$CHANNEL" -p "$1" -n -t string -s "$2"
}

set_bool() {
  run "$XFCONF" -c "$CHANNEL" -p "$1" -n -t bool -s "$2"
}

# -R also removes child properties such as .../startup-notify.
unset_prop() {
  if has_prop "$1"; then
    run "$XFCONF" -c "$CHANNEL" -p "$1" -r -R
  fi
}

# Mirror /<provider>/default into /<provider>/custom and switch to custom mode.
# Only done once: if override is already true, existing custom bindings (and
# any deliberate removals) are respected.
seed_provider() {
  local provider=$1
  local override_prop="/$provider/custom/override"
  local default_base="/$provider/default"
  local prop value target

  if [[ $(get "$override_prop") == true ]]; then
    return 0
  fi

  say "Seeding /$provider/custom from /$provider/default (first run)"

  # Match the GUI: clear any inactive custom subtree before cloning, so stale
  # entries cannot become active when override is switched on.
  if [[ -n $("$XFCONF" -c "$CHANNEL" -p "/$provider/custom" -l 2>/dev/null || true) ]]; then
    run "$XFCONF" -c "$CHANNEL" -p "/$provider/custom" -r -R
  fi

  while IFS= read -r prop; do
    [[ -n $prop ]] || continue
    value=$(get "$prop")
    target="/$provider/custom/${prop#"$default_base/"}"
    if [[ $prop == */startup-notify ]]; then
      set_bool "$target" "$value"
    else
      set_string "$target" "$value"
    fi
  done < <("$XFCONF" -c "$CHANNEL" -p "$default_base" -l 2>/dev/null || true)

  set_bool "$override_prop" true
}

command -v "$XFCONF" >/dev/null 2>&1 || die "xfconf-query not found (package: xfconf)"
if [[ $DRY_RUN != 1 ]] && ! "$XFCONF" -l >/dev/null 2>&1; then
  die "cannot talk to xfconfd; run this inside an XFCE session"
fi

# The two providers must not claim the same accelerator.
for key in "${!APP_SHORTCUTS[@]}"; do
  if [[ -n ${WM_SHORTCUTS[$key]+x} ]]; then
    die "accelerator $key is defined in both APP_SHORTCUTS and WM_SHORTCUTS"
  fi
done

seed_provider commands
seed_provider xfwm4

for key in "${UNBIND[@]}"; do
  unset_prop "/commands/custom/$key"
  unset_prop "/xfwm4/custom/$key"
done

for key in "${!APP_SHORTCUTS[@]}"; do
  set_string "/commands/custom/$key" "${APP_SHORTCUTS[$key]}"
done

# xfwm4 keeps only one accelerator per action: it takes the first match from
# the shortcuts provider, whose order is hash-table dependent.  A leftover
# stock binding for the same action (e.g. <Super>KP_Right for tile_right_key)
# would therefore shadow ours at random.  Unbind every other accelerator that
# still maps to an action we manage.
declare -A wm_targets=()
for key in "${!WM_SHORTCUTS[@]}"; do
  wm_targets["/xfwm4/custom/$key"]=1
done

while IFS= read -r prop; do
  [[ -n $prop && -z ${wm_targets[$prop]+x} ]] || continue
  [[ ${prop#/xfwm4/custom/} == */* ]] && continue  # skip startup-notify children
  [[ $prop == "/xfwm4/custom/override" ]] && continue
  value=$(get "$prop")
  for key in "${!WM_SHORTCUTS[@]}"; do
    if [[ $value == "${WM_SHORTCUTS[$key]}" ]]; then
      say "Unbinding $prop (same action as $key)"
      unset_prop "$prop"
      break
    fi
  done
done < <("$XFCONF" -c "$CHANNEL" -p "/xfwm4/custom" -l 2>/dev/null || true)

for key in "${!WM_SHORTCUTS[@]}"; do
  set_string "/xfwm4/custom/$key" "${WM_SHORTCUTS[$key]}"
done

say "Done. Changes apply to the running session immediately."
