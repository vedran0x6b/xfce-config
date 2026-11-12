# AGENTS.md

Notes for agents. Human-facing docs are in `README.md`.

## Hard rules

- **Never write to a live xfconf channel while testing.** Use `DRY_RUN=1`, or
  point the channel env vars at a scratch channel. Quote paths containing
  `<`/`>` or the shell treats them as redirections.
- **Never invent bindings.** Read the live channel first. Illustrative
  placeholders in the arrays have been mistaken for the user's real setup
  before; ask when intent is unclear.
- Only touch the properties the scripts already manage. These are not a general
  XFCE config manager.
- Don't commit or push unless asked.

## xfconf-query gotchas

- `-n` requires `-t` when creating a property. Passing a *different* `-t` on an
  existing property **changes its type** — always pass the correct one.
- Removing a shortcut needs `-r -R` when a `startup-notify` child exists. Plain
  `-r` leaves an orphaned child that resurfaces later.
- Shortcut commands are **not** shell-interpreted: XFCE uses
  `g_shell_parse_argv()` and spawns directly, so pipes/`&&`/redirects/variables
  need an explicit `sh -c '…'`.
- Accelerators must be unique across `commands` and `xfwm4`. Both `xfsettingsd`
  and `xfwm4` grab keys, so collisions resolve by grab order, not intent.
  Overlapping accelerators are fine when they differ by modifier.
- xfwm4 binds only **one** accelerator per action: it takes the first match
  from the shortcuts provider, whose order is hash-table dependent. Two
  accelerators for one action (e.g. stock `<Super>KP_Right` plus custom
  `<Super>Right` for `tile_right_key`) make the winner nondeterministic, and
  the loser falls through to the focused app (a terminal shows `^[[C`).
  Unbind the losers; the script does this before binding.
- A container path may not exist as a property even though children do, so
  don't rely on `-p /commands/custom` succeeding. Use `-l` to enumerate.
- Resetting a scratch channel's properties leaves an empty `<channel>.xml`
  behind; delete it or `xfconf-query -l` keeps listing the dead channel.

## Shortcuts: the `override` switch

For each provider (`commands`, `xfwm4`), `/<provider>/custom/override` selects
which subtree is read: `false`/absent → **only** `/default`; `true` → **only**
`/custom`.

Setting `override=true` without first copying `/default` into `/custom`
silently drops every stock shortcut. `seed_provider()` replicates what the GUI
does: skip if already custom, otherwise reset `/custom`, clone `/default` into
it (preserving `startup-notify` as bools), then set `override`.

## Themes: two traps

**`/Xfce/SyncThemes` is dialog-side only.** The sync logic lives in
`dialogs/appearance-settings/main.c`, so it runs only while the Appearance
dialog makes the change. Nothing watches `/Net/ThemeName` at runtime — writing
it with `xfconf-query` leaves `/general/theme` untouched. Both must be written
explicitly.

**`monospace-font-name` is not mirrored to GSettings.** `xfsettingsd`'s
`translations` table covers `font-name` and the theme keys but omits
`monospace-font-name`, so `/Gtk/MonospaceFontName` is invisible to GTK4 apps
unless `org.gnome.desktop.interface monospace-font-name` is written too.

Also:

- All validation happens **before any write**, so a bad theme name cannot leave
  settings half-applied. Preserve that ordering.
- Icon theme is not part of the WM sync — the dialog only mirrors
  `/Net/ThemeName`.
- Pango canonicalises `Sans Regular 10` to `Sans 10` (Regular is the default
  weight); `DejaVu Sans Mono Book 11` keeps `Book` because it is not.
- `ICON_THEME`, `FONT_NAME`, `MONOSPACE_FONT` use `${VAR-Default}` rather than
  `${VAR:-Default}` so an explicitly empty value means "skip", not "default".

## install-themes.sh

One script, two phases. Package install needs root; applying settings must
**not** be root, since `xfconf-query` writes to the logged-in user's session
bus. The script escalates per command; when started as root it re-executes
itself with `_THEME_PHASE=apply` as `$SUDO_USER`, forwarding
`DBUS_SESSION_BUS_ADDRESS`, `DISPLAY` and the theme/font settings. `INSTALL=0`
skips the install phase, `APPLY=0` skips the apply phase.

## Discovering things

```bash
xfconf-query -l                                   # channels
xfconf-query -c <channel> -l -v                   # every property + value
xfconf-query -c xfce4-keyboard-shortcuts -p /xfwm4/default -l -v   # stock WM actions
xfconf-query -c xfce4-keyboard-shortcuts -m       # watch changes live
```

Valid `/xfwm4/custom/<accelerator>` values are the action names in xfwm4's
`src/settings.c`; enumerate the stock set with the command above rather than
hardcoding a list.

## Verifying

`bash -n <script>` for syntax, then `DRY_RUN=1` against the real channel, then a
scratch channel for writes. A second real run should be a no-op. Scratch
channels are ordinary channels — create, exercise, then delete both the
properties and the leftover XML file.
