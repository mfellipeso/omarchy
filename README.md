<p align="center">
  <img src="https://raw.githubusercontent.com/basecamp/omarchy/master/icon.png" width="120" alt="Omarchy">
</p>

<h1 align="center">omarchy</h1>

<p align="center">
  Dotfiles for <a href="https://omarchy.org">Omarchy</a>.<br>
  No stow, no symlinks: <code>~/.config</code> stays stock and gets one line pointing here.
</p>

---

## How it works

Omarchy rewrites the files it owns: `sed -i` on `foot.ini`, atomic rename on
`shell.json`, `install` over `~/.config/nvim` during migrations. Symlinking
this repo on top of that would turn the symlink into a regular file on the
first update, and the repo would silently stop tracking the config.

So the rule here is different:

- **Config files** (Hyprland, Neovim): Omarchy's file stays stock and gets
  **one line** that loads the counterpart from this repo. It keeps receiving
  updates, and the personal config lives in `~/.dotfiles`.
- **Preferences that are commands** (font, theme, bar widgets, file manager):
  the source of truth is the command itself (`omarchy font set`,
  `omarchy theme set`, `flea --default`), reapplied idempotently by a script.

The `~/.dotfiles` path is hardcoded in the scripts and in `hypr/init.lua`;
clone it there.

## What's here

| Directory | What it is |
|-----------|------------|
| [`hypr/`](hypr/) | Personal Hyprland config in Lua: `env`, `input`, `bindings`, `windows`, `looknfeel`. `init.lua` is the entry point that Omarchy's `hyprland.lua` calls. |
| [`nvim/`](nvim/) | Binds and preferences on top of the LazyVim shipped by `omarchy-nvim`. Has its [own README](nvim/README.md) explaining what's in and what was left out. |
| [`setup/`](setup/) | Idempotent scripts that set up the machine. `setup.sh` prompts for each one; every script also runs on its own. |

## Install

```bash
git clone git@github.com:mfellipeso/omarchy.git ~/.dotfiles
~/.dotfiles/setup/setup.sh
```

`setup.sh` walks through the scripts in the order below and asks before each
one. All of them are idempotent: running again only confirms what's already in
place.

| Order | Script | What it does |
|-------|--------|--------------|
| 1 | `setup-language.sh` | pt-BR via `omarchy language` (locale, menus and the session's `LANG`). |
| 2 | `setup-docker.sh` | Docker with IPv6 and a no-CoW Btrfs subvolume at `/var/lib/docker`. |
| 2 | `setup-virt.sh` | QEMU/KVM + virt-manager, no-CoW subvolume at `/var/lib/libvirt`. |
| 2 | `setup-flatpak.sh` | Flatpak + Flathub, no-CoW subvolume at `/var/lib/flatpak`. |
| 3 | `setup-hypr.sh` | Plants the line that loads `hypr/init.lua` in `hyprland.lua`. |
| 3 | `setup-nvim.sh` | Plants the three lines that load `nvim/` across LazyVim's load phases. |
| 4 | `setup-omarchy.sh` | Font, theme and bar widgets, by command. |
| 4 | `setup-flea.sh` | Flea as the default file manager (`flea --default`). |
| 4 | `setup-oma-cast.sh` | [oma-cast](https://github.com/typecraft-dev/oma-cast) launcher as an `omarchy-shell` plugin, cloned into the home dir and bound to Alt+Space. |
| 4 | `setup-herdrgotchi.sh` | [Herdrgotchi](https://github.com/jankeesvw/omarchy-herdrgotchi), a Tamagotchi per herdr agent, via `omarchy plugin add`; installs herdr through mise if missing. |
| 5 | `setup-tibia.sh` | Official Tibia client in the home dir, where its auto-update works. |
| 6 | `setup-artcraft.sh` | ArtCraft Launcher as an AppImage in the home dir, self-updating. |

Shared helpers (package install, services, Btrfs subvolumes, idempotent line
planting) live in [`setup/lib/common.sh`](setup/lib/common.sh).

## What's left out

Config only, never runtime state. Logs, sockets and `.bak` files are excluded by the
[`.gitignore`](.gitignore). Neovim's `lazy-lock.json` isn't versioned either:
it lives in `~/.config/nvim`, which is Omarchy's territory.

Anything per-machine (monitors, in `monitors.lua`) stays in Omarchy's
`~/.config`, outside the repo.
