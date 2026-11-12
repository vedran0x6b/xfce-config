# XFCE configurator

`configure-xfce.sh` puts my XFCE keyboard shortcuts into a single readable
configurator, so I don't have to click through the settings dialogs on every new
machine.

`install-themes.sh` installs the Numix and Obsidian packages and then applies
them: the GTK, window-manager and icon themes and the UI and monospace fonts
(Numix + Obsidian-Mint + Sans Regular 10 + DejaVu Sans Mono Book 11 by
default), since XFCE stores those across several channels. `INSTALL=0` applies
settings only; `APPLY=0` installs packages only.

`install-tools.sh` installs my development tools I need on every box.

`setup.sh` runs them in order (tools, themes, shortcuts) and asks which ones
you want. `--all` skips the prompt, `--only tools,themes` runs a subset, and
`--list` shows the steps.

Run any of them with `DRY_RUN=1` to see what it would do.
