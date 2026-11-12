#!/usr/bin/env bash
#
# install-tools.sh -- install alacritty and helix and make them the default
# terminal and editor via update-alternatives.
#
# alacritty comes from Debian's repos.  helix comes from the upstream release
# .deb on GitHub rather than the distro package, so we get a current version:
#
#   https://github.com/helix-editor/helix/releases
#
# Both defaults go through update-alternatives, which is what the system
# consults: XFCE's exo-open falls back to /usr/bin/x-terminal-emulator, and
# Debian's git and sensible-editor fall back to /usr/bin/editor. Setting
# ~/.config/xfce4/helpers.rc or $EDITOR instead would shadow the alternative
# and make `update-alternatives --config` silently stop working.
#
# `--install` is used rather than a bare `--set` because helix does not
# register an editor alternative (neither the Debian package nor the upstream
# .deb does; alacritty registers x-terminal-emulator via
# dh_installalternatives). --install is idempotent, so running it for both
# keeps this uniform.
#
# Usage:
#   ./install-tools.sh
#   DRY_RUN=1 ./install-tools.sh    # print commands, change nothing
#
# Environment:
#   HELIX_DEB_URL   override the helix .deb to install

set -euo pipefail

HELIX_DEB_URL=${HELIX_DEB_URL:-https://github.com/helix-editor/helix/releases/download/25.07.1/helix_25.7.1-1_amd64.deb}
DRY_RUN=${DRY_RUN:-0}

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

# The release asset is amd64-only.
case $(uname -m) in
  x86_64 | amd64) ;;
  *) die "the helix .deb is amd64 only (this machine is $(uname -m))" ;;
esac

if command -v curl >/dev/null 2>&1; then
  fetch=(curl -fL --retry 3 -o)
elif command -v wget >/dev/null 2>&1; then
  fetch=(wget -O)
else
  die "curl or wget is required to download helix"
fi

run sudo apt-get update
run sudo apt-get install -y alacritty curl git

# Download first, then hand the file to apt, so dependency resolution still
# happens.  A dry run prints a representative path instead of creating one.
deb_name=${HELIX_DEB_URL##*/}
if [[ $DRY_RUN == 1 ]]; then
  deb_path=${TMPDIR:-/tmp}/$deb_name
else
  tmp_dir=$(mktemp -d)
  trap 'rm -rf "$tmp_dir"' EXIT
  deb_path=$tmp_dir/$deb_name
fi

say "Downloading helix: $HELIX_DEB_URL"
run "${fetch[@]}" "$deb_path" "$HELIX_DEB_URL"
run sudo apt-get install -y "$deb_path"

run sudo update-alternatives --install \
  /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/alacritty 20
run sudo update-alternatives --set x-terminal-emulator /usr/bin/alacritty

run sudo update-alternatives --install \
  /usr/bin/editor editor /usr/bin/hx 40
run sudo update-alternatives --set editor /usr/bin/hx

if [[ $DRY_RUN != 1 ]]; then
  printf 'x-terminal-emulator : %s\n' "$(readlink -f /usr/bin/x-terminal-emulator)"
  printf 'editor              : %s\n' "$(readlink -f /usr/bin/editor)"
fi
