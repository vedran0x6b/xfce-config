#!/usr/bin/env bash
#
# install-themes.sh -- install the selected theme and the icon theme as well,
# then apply themes and fonts to the current XFCE session.
#
# Two phases with different privileges:
#
#   1. install  -> apt-get, needs root
#   2. apply    -> xfconf-query/gsettings, must NOT be root, because
#                  xfconf-query talks to the session bus / xfconfd of the
#                  logged-in user.  Running it as root would write root's
#                  config, not yours.
#
# The script escalates per command rather than requiring you to run the whole
# thing under sudo.  If you do run it as root anyway, it re-executes itself as
# $SUDO_USER for the apply phase, forwarding the session bus and display.
#
# Appearance-related settings live in these places:
#
#   xsettings /Net/ThemeName          GTK theme        (Settings > Appearance)
#   xsettings /Net/IconThemeName      icon theme       (Settings > Appearance)
#   xsettings /Gtk/FontName           UI font          (Settings > Appearance)
#   xsettings /Gtk/MonospaceFontName  monospace font   (Settings > Appearance)
#   xfwm4     /general/theme          window manager   (Settings > Window Manager)
#
# GTK3 apps read XSETTINGS (served by xfsettingsd from xfconf).  GTK4 apps
# read GSettings (org.gnome.desktop.interface).  xfsettingsd mirrors most of
# these properties into GSettings, but NOT /Gtk/MonospaceFontName, so that one
# must also be written with gsettings for GTK4 apps to see it.
#
# The Appearance dialog's "Set matching xfwm4 theme if there is one" switch
# (/Xfce/SyncThemes) is handled *inside the dialog*: it copies the GTK theme
# into /general/theme only while that dialog is making the change.  Nothing
# watches /Net/ThemeName at runtime, so setting it with xfconf-query does NOT
# update the window manager.  Both properties must be written explicitly.
#
# Usage:
#   ./install-themes.sh                 # install, then apply (prompts for sudo)
#   sudo ./install-themes.sh            # works; settings applied as $SUDO_USER
#   INSTALL=0 ./install-themes.sh       # apply only (packages already present)
#   APPLY=0 ./install-themes.sh         # install only, leave settings alone
#   DRY_RUN=1 ./install-themes.sh       # print commands, change nothing
#
# Environment:
#   THEME              GTK/WM theme name (default: Numix)
#   ICON_THEME         icon theme name (default: Obsidian-Mint; empty to skip)
#   FONT_NAME          UI font, Pango syntax (default: Sans Regular 10)
#   MONOSPACE_FONT     monospace font, Pango syntax (default: DejaVu Sans Mono Book 11)
#   SET_SYNC_TOGGLE    also set /Xfce/SyncThemes=true (default: 1)
#   INSTALL            1 = install packages (default: 1)
#   APPLY              1 = apply settings (default: 1)
#   SKIP_APT_UPDATE=1  skip `apt-get update`
#   ASSUME_YES=0       do not pass -y to apt-get
#   XSETTINGS_CHANNEL  xfconf channel for GTK settings (default: xsettings)
#   XFWM4_CHANNEL      xfconf channel for the window manager (default: xfwm4)
#   XFCONF_QUERY       path to xfconf-query (default: xfconf-query)
#   GSETTINGS          path to gsettings (default: gsettings)

set -euo pipefail

PACKAGES=(numix-gtk-theme obsidian-icon-theme)

THEME=${THEME:-Numix}
ICON_THEME=${ICON_THEME-Obsidian-Mint}
FONT_NAME=${FONT_NAME-Sans Regular 10}
MONOSPACE_FONT=${MONOSPACE_FONT-DejaVu Sans Mono Book 11}
SET_SYNC_TOGGLE=${SET_SYNC_TOGGLE:-1}
XSETTINGS_CHANNEL=${XSETTINGS_CHANNEL:-xsettings}
XFWM4_CHANNEL=${XFWM4_CHANNEL:-xfwm4}
XFCONF=${XFCONF_QUERY:-xfconf-query}
GSETTINGS=${GSETTINGS:-gsettings}
DRY_RUN=${DRY_RUN:-0}
INSTALL=${INSTALL:-1}
APPLY=${APPLY:-1}
ASSUME_YES=${ASSUME_YES:-1}

APT_UPDATE=${APT_UPDATE:-1}
if [[ -n ${SKIP_APT_UPDATE:-} && $SKIP_APT_UPDATE != 0 ]]; then
  APT_UPDATE=0
fi

SUDO=()

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
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

# ---------------------------------------------------------------------------
# Install phase
# ---------------------------------------------------------------------------

as_root() { run "${SUDO[@]}" "$@"; }

verify_theme() {
  local dir=$1 what=$2
  if [[ $DRY_RUN == 1 ]]; then
    say "would verify $dir"
    return 0
  fi
  [[ -d $dir ]] || die "$what not installed: $dir is missing"
  say "ok: $dir"
}

install_phase() {
  local apt_args

  if [[ $EUID -eq 0 ]]; then
    SUDO=()
  else
    command -v sudo >/dev/null 2>&1 \
      || die "not root and sudo is not installed; re-run as root"
    SUDO=(sudo)
  fi

  command -v apt-get >/dev/null 2>&1 \
    || die "apt-get not found; this script targets Debian/Ubuntu"

  if [[ $DRY_RUN != 1 ]]; then
    "${SUDO[@]}" true 2>/dev/null \
      || die "cannot obtain root (sudo failed); re-run as root or fix sudo access"
  fi

  say "Installing: ${PACKAGES[*]}"

  if [[ $APT_UPDATE == 1 ]]; then
    as_root apt-get update
  fi

  apt_args=(install)
  if [[ $ASSUME_YES == 1 ]]; then
    apt_args+=(-y)
  fi
  as_root apt-get "${apt_args[@]}" "${PACKAGES[@]}"

  verify_theme /usr/share/themes/Numix "Numix GTK theme"
  verify_theme /usr/share/themes/Numix/xfwm4 "Numix xfwm4 theme"
  verify_theme /usr/share/icons/Obsidian-Mint "Obsidian icon theme"
}

# ---------------------------------------------------------------------------
# Apply phase
# ---------------------------------------------------------------------------

set_string() {
  local channel=$1 prop=$2 value=$3
  run "$XFCONF" -c "$channel" -p "$prop" -n -t string -s "$value"
}

set_bool() {
  local channel=$1 prop=$2 value=$3
  run "$XFCONF" -c "$channel" -p "$prop" -n -t bool -s "$value"
}

set_gsetting() {
  local schema=$1 key=$2 value=$3
  run "$GSETTINGS" set "$schema" "$key" "$value"
}

# Pango font descriptions end with a size (points, optionally "px").
validate_font() {
  local name=$1 label=$2
  [[ -n $name ]] || die "$label is empty"
  [[ $name =~ [[:space:]][0-9]+([.][0-9]+)?(px)?$ ]] \
    || die "$label '$name' has no trailing size (Pango syntax, e.g. 'Sans Regular 10')"
}

# Directories GTK/XFCE search for a resource type (themes, icons), in the
# same order the Appearance dialog uses: XDG data dirs first, then the legacy
# ~/.themes / ~/.icons.
resource_roots() {
  local kind=$1 dir root
  local -a data_dirs roots
  local -A seen=()

  IFS=: read -ra data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"

  roots=("${XDG_DATA_HOME:-$HOME/.local/share}/$kind")
  for dir in "${data_dirs[@]}"; do
    [[ -n $dir ]] && roots+=("${dir%/}/$kind")
  done
  roots+=("$HOME/.$kind")

  for root in "${roots[@]}"; do
    [[ -n ${seen[$root]+x} ]] && continue
    seen[$root]=1
    printf '%s\n' "$root"
  done
}

find_resource() {
  local kind=$1 name=$2 root

  while IFS= read -r root; do
    if [[ -d $root/$name ]]; then
      printf '%s\n' "$root/$name"
      return 0
    fi
  done < <(resource_roots "$kind")

  return 1
}

apply_phase() {
  local theme_dir icon_dir has_gtk has_wm have_gsettings

  command -v "$XFCONF" >/dev/null 2>&1 || die "xfconf-query not found (package: xfconf)"
  if [[ $DRY_RUN != 1 ]] && ! "$XFCONF" -l >/dev/null 2>&1; then
    die "cannot talk to xfconfd; run this inside an XFCE session"
  fi

  # GTK4 apps read fonts from GSettings.  Both keys are in one schema, so a
  # single check covers them.
  have_gsettings=0
  if command -v "$GSETTINGS" >/dev/null 2>&1 \
     && "$GSETTINGS" list-keys org.gnome.desktop.interface 2>/dev/null \
        | grep -qx 'monospace-font-name'; then
    have_gsettings=1
  fi

  theme_dir=$(find_resource themes "$THEME") \
    || die "theme '$THEME' is not installed; looked in: $(resource_roots themes | paste -sd ' ' -)"

  # Match the Appearance dialog's definition of a usable GTK theme.
  has_gtk=0
  [[ -f $theme_dir/gtk-3.0/gtk.css || -f $theme_dir/gtk-2.0/gtkrc ]] && has_gtk=1

  # A window-manager theme is a themerc in the theme's xfwm4/ directory.
  has_wm=0
  [[ -f $theme_dir/xfwm4/themerc ]] && has_wm=1

  [[ $has_gtk == 1 ]] || die "theme '$THEME' has no GTK part ($theme_dir/gtk-3.0/gtk.css)"

  # Icon theme.  Independent of the GTK theme, and never synced to xfwm4 (the
  # dialog only mirrors /Net/ThemeName).  An icon theme is a directory whose
  # index.theme has a Directories key and is not marked Hidden.
  icon_dir=
  if [[ -n $ICON_THEME ]]; then
    icon_dir=$(find_resource icons "$ICON_THEME") \
      || die "icon theme '$ICON_THEME' is not installed; looked in: $(resource_roots icons | paste -sd ' ' -)"

    [[ -f $icon_dir/index.theme ]] \
      || die "icon theme '$ICON_THEME' has no index.theme ($icon_dir/index.theme)"
    grep -qE '^Directories=' "$icon_dir/index.theme" \
      || die "icon theme '$ICON_THEME' has no Directories entry; GTK cannot use it"
    if grep -qiE '^Hidden=true' "$icon_dir/index.theme"; then
      die "icon theme '$ICON_THEME' is marked Hidden and is not shown in Appearance"
    fi
  fi

  validate_font "$FONT_NAME" "FONT_NAME"
  validate_font "$MONOSPACE_FONT" "MONOSPACE_FONT"

  # Everything validated; only now start writing.
  set_string "$XSETTINGS_CHANNEL" /Net/ThemeName "$THEME"
  say "GTK theme  -> $THEME"

  if ! command -v xfwm4 >/dev/null 2>&1; then
    warn "xfwm4 is not installed; leaving the window-manager theme alone"
  elif [[ $has_wm == 1 ]]; then
    set_string "$XFWM4_CHANNEL" /general/theme "$THEME"
    say "WM theme   -> $THEME"
  else
    # Same choice the Appearance dialog makes: a theme without an xfwm4 part
    # leaves the window-manager theme untouched rather than pointing it at a
    # directory that does not exist.
    warn "theme '$THEME' has no xfwm4 part; leaving the window-manager theme unchanged"
  fi

  # Keep the dialog's sync switch consistent with what we just did, so a later
  # change in Appearance also carries over to the window manager.
  if [[ $SET_SYNC_TOGGLE == 1 ]] && command -v xfwm4 >/dev/null 2>&1; then
    set_bool "$XSETTINGS_CHANNEL" /Xfce/SyncThemes true
    say "Theme sync -> on"
  fi

  if [[ -n $icon_dir ]]; then
    set_string "$XSETTINGS_CHANNEL" /Net/IconThemeName "$ICON_THEME"
    say "Icon theme -> $ICON_THEME"
  fi

  # Fonts.  xfsettingsd mirrors /Gtk/FontName into GSettings, but not
  # /Gtk/MonospaceFontName, so write both places explicitly.
  set_string "$XSETTINGS_CHANNEL" /Gtk/FontName "$FONT_NAME"
  say "UI font    -> $FONT_NAME"

  set_string "$XSETTINGS_CHANNEL" /Gtk/MonospaceFontName "$MONOSPACE_FONT"
  say "Mono font  -> $MONOSPACE_FONT"

  if [[ $have_gsettings == 1 ]]; then
    set_gsetting org.gnome.desktop.interface font-name "$FONT_NAME"
    set_gsetting org.gnome.desktop.interface monospace-font-name "$MONOSPACE_FONT"
  else
    warn "gsettings or org.gnome.desktop.interface unavailable; GTK4 apps will not see the fonts"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

# When started as root, the apply phase is re-executed as $SUDO_USER; this
# marker tells the re-executed copy to do only that.
if [[ ${_THEME_PHASE:-} == apply ]]; then
  apply_phase
  exit 0
fi

if [[ $INSTALL == 1 ]]; then
  install_phase
else
  say "INSTALL=0: skipping package installation."
fi

if [[ $APPLY != 1 ]]; then
  say "APPLY=0: settings left alone."
  exit 0
fi

if [[ $EUID -eq 0 ]]; then
  if [[ -z ${SUDO_USER:-} ]]; then
    warn "running as root with no \$SUDO_USER; cannot apply settings to a user session."
    warn "Log in as your normal user and run: $0"
    exit 0
  fi
  say "Applying settings as user: $SUDO_USER"

  # sudo -u does not carry the session bus or our configuration by default, so
  # pass through what the apply phase needs.  An empty value would be worse
  # than none, hence the set-ness test.
  self=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")
  handoff_env=()
  for var in DBUS_SESSION_BUS_ADDRESS DISPLAY \
             THEME ICON_THEME FONT_NAME MONOSPACE_FONT SET_SYNC_TOGGLE \
             XSETTINGS_CHANNEL XFWM4_CHANNEL XFCONF_QUERY GSETTINGS DRY_RUN; do
    [[ -v $var ]] && handoff_env+=("$var=${!var}")
  done
  run sudo -u "$SUDO_USER" "${handoff_env[@]}" _THEME_PHASE=apply bash "$self"
else
  say "Applying settings"
  apply_phase
fi

say "Done."
