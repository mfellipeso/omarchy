#!/bin/bash
set -euo pipefail

# =============================================================================
# HYDRA — o Hydra Launcher como AppImage na home
#
# AppImage em ~/.local/share com nome sem versão: o electron-updater só
# sobrescreve o próprio arquivo assim, e o .desktop segue válido após cada update.
# Rodar de novo só baixa se o hash diferir do latest-linux.yml.
#
# `setup-hydra.sh --uninstall` desfaz tudo, inclusive ~/.config/hydralauncher
# (biblioteca e fontes). Jogos baixados ficam onde estão.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

RELEASE_URL="https://github.com/hydralauncher/hydra/releases/latest/download"
APP_ID="hydralauncher"
APP_DIR="$HOME/.local/share/hydralauncher"
APPIMAGE="$APP_DIR/Hydra.AppImage"
DESKTOP_FILE="$HOME/.local/share/applications/$APP_ID.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hydralauncher"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hydralauncher-updater"
# O próprio Hydra se registra aqui ao abrir.
MIMEAPPS="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"

uninstall() {
  # Fechar antes: o Electron regravaria o que está em ~/.config ao sair.
  pkill -x "$APP_ID" 2>/dev/null || true
  pkill -f "^$APPIMAGE" 2>/dev/null || true
  for _ in $(seq 20); do
    pgrep -x "$APP_ID" &>/dev/null || pgrep -f "^$APPIMAGE" &>/dev/null || break
    sleep 0.5
  done

  if [[ -f "$MIMEAPPS" ]]; then
    sed -i -E "s/$APP_ID\.desktop;?//g; /=\$/d" "$MIMEAPPS"
  fi
  rm -rf -- "$APP_DIR" "$DESKTOP_FILE" "$ICON_DIR"/*/apps/"$APP_ID".* "$CONFIG_DIR" "$CACHE_DIR"
  ok "Hydra removido"
}

case "${1:-}" in
  --uninstall)
    uninstall
    _finish 0
    ;;
  "") ;;
  *)
    echo "Uso: $(basename "$0") [--uninstall]" >&2
    _finish 1
    ;;
esac

# O latest-linux.yml traz o sha512 em base64; `sha512sum` só dá hexadecimal.
sha512_b64() { openssl dgst -sha512 -binary "$1" | base64 -w0; }

# O runtime do AppImage monta o squashfs por fusermount3 a cada abertura.
pkg_install fuse3 || _finish 1

# Só as chaves da raiz: as de `files:` têm recuo e se repetem para .deb e .rpm.
manifest="$(curl -fsSL --retry 3 "$RELEASE_URL/latest-linux.yml")"
file="$(sed -n 's/^path: *//p' <<<"$manifest")"
sha="$(sed -n 's/^sha512: *//p' <<<"$manifest")"
version="$(sed -n 's/^version: *//p' <<<"$manifest")"

if [[ -x "$APPIMAGE" && "$(sha512_b64 "$APPIMAGE")" == "$sha" ]]; then
  skipped "Hydra $version já instalado"
  _finish 0
fi

tmp="$(mktemp -d)"
download="$APP_DIR/.Hydra.AppImage.download"
trap 'rm -rf "$tmp" "$download"' EXIT

info "Baixando o Hydra $version..."
mkdir -p "$APP_DIR"
curl -fL --retry 3 --progress-bar -o "$download" "$RELEASE_URL/$file"
if [[ "$(sha512_b64 "$download")" != "$sha" ]]; then
  err "o download não bate com o SHA-512 do latest-linux.yml"
  _finish 1
fi
chmod 755 "$download"

# Entry e ícones vêm de dentro do AppImage; o Exec mantém os argumentos do upstream.
(cd "$tmp" && "$download" --appimage-extract "$APP_ID.desktop" >/dev/null &&
  "$download" --appimage-extract "usr/share/icons/hicolor/*/apps/$APP_ID.*" >/dev/null)
mkdir -p "$(dirname "$DESKTOP_FILE")" "$ICON_DIR"
cp -r "$tmp/squashfs-root/usr/share/icons/hicolor/." "$ICON_DIR/"
sed "s|^Exec=AppRun|Exec=$APPIMAGE|" "$tmp/squashfs-root/$APP_ID.desktop" \
  >"$DESKTOP_FILE"

# Por último, e atômico: funciona com o Hydra aberto.
mv -f "$download" "$APPIMAGE"
ok "Hydra $version instalado em $APPIMAGE"
