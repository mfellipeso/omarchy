#!/bin/bash
set -euo pipefail

# =============================================================================
# MDM — o Mister Download Manager como AppImage na home
#
# AppImage com nome sem versão: o MDM se atualiza sobrescrevendo o próprio
# arquivo ($APPIMAGE, Help → Check for updates), então o .desktop segue válido.
# Fica fora de ~/.local/share/misterdownloadmanager, que é o diretório de dados
# do próprio MDM (lista, settings e o browser-host da integração).
# Rodar de novo só baixa se o hash diferir do SHA256SUMS.txt da última release;
# entry e ícone que tenham sumido são refeitos a partir do AppImage instalado.
#
# A integração com os navegadores (native messaging) o MDM registra sozinho a
# cada abertura; a extensão vem da Chrome Web Store / AMO ou pela janela que o
# próprio MDM oferece. Navegadores Flatpak não alcançam o MDM.
#
# `setup-mdm.sh --uninstall` desfaz tudo, inclusive a lista e as settings em
# ~/.local/share/misterdownloadmanager e os manifestos de native messaging.
# Arquivos baixados ficam onde estão.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

RELEASE_URL="https://github.com/anefzaoui/misterdownloadmanager/releases/latest/download"
APP_ID="misterdownloadmanager"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/misterdownloadmanager-appimage"
APPIMAGE="$APP_DIR/MisterDownloadManager.AppImage"
DATA_DIR="$DATA_HOME/$APP_ID"
NMHOST="$DATA_DIR/browser-host/$APP_ID-nmhost"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"
ICON_DIR="$DATA_HOME/icons/hicolor"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$APP_ID"
MIMEAPPS="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"

# PIDs do MDM aberto a partir do NOSSO AppImage. O runtime type 2 se divide em
# dois: o filho fica servindo o FUSE com a linha de comando "$APPIMAGE ..." e o
# pai vira o app (exe dentro de /tmp/.mount_*). Então o app é o pai de cada
# processo ancorado em ^$APPIMAGE — sem casar por nome de mount, que pegaria
# qualquer outro AppImage começando com "Mister".
mdm_pids() {
  local pid ppid exe
  for pid in $(pgrep -f "^$APPIMAGE" || true); do
    ppid="$(ps -o ppid= -p "$pid" | tr -d ' ')" || continue
    exe="$(readlink "/proc/$ppid/exe" 2>/dev/null)" || continue
    [[ "$exe" == */.mount_* ]] && echo "$ppid"
    echo "$pid"
  done
  # O native messaging host roda solto, lançado pelo navegador.
  pgrep -f "^$NMHOST" || true
}

uninstall() {
  # Fechar antes: ao sair o MDM regravaria a lista e as settings, e o host
  # aberto por um navegador seguiria rodando do diretório apagado.
  kill_and_wait mdm_pids MDM || return 1

  # Manifestos de native messaging: o próprio nmhost sabe onde os escreveu. O
  # find (o mesmo da documentação do MDM) pega o que ele não cobre, como os
  # forks do Firefox; com profundidade limitada para não varrer perfis inteiros.
  if [[ -x "$NMHOST" ]]; then
    "$NMHOST" --unregister || true
  fi
  find ~/.mozilla ~/.librewolf ~/.config -maxdepth 4 \
    -name com.misterdownloadmanager.host.json -delete 2>/dev/null || true

  mimeapps_remove "$MIMEAPPS" "$APP_ID\.desktop" || true
  rm -rf -- "$APP_DIR" "$DATA_DIR" "$CONFIG_DIR" "$DESKTOP_FILE" \
    "$ICON_DIR"/*/apps/"$APP_ID".*
  ok "MDM removido"
}

# install_entry <appimage> — .desktop e ícones tirados de dentro do AppImage,
# com o Exec apontando para $APPIMAGE (mantém os argumentos do upstream).
install_entry() {
  local src="$1" tmp
  tmp="$(mktemp -d)"
  if ! (cd "$tmp" && "$src" --appimage-extract "$APP_ID.desktop" >/dev/null &&
    "$src" --appimage-extract "usr/share/icons/hicolor/*/apps/$APP_ID.*" >/dev/null) ||
    [[ ! -f "$tmp/squashfs-root/$APP_ID.desktop" ]]; then
    err "$APP_ID.desktop não encontrado dentro do AppImage — o upstream mudou o layout?"
    rm -rf "$tmp"
    return 1
  fi

  mkdir -p "$(dirname "$DESKTOP_FILE")" "$ICON_DIR"
  if [[ -d "$tmp/squashfs-root/usr/share/icons/hicolor" ]]; then
    cp -r "$tmp/squashfs-root/usr/share/icons/hicolor/." "$ICON_DIR/"
  fi
  sed -E "s|^Exec=[^ ]+|Exec=$APPIMAGE|" "$tmp/squashfs-root/$APP_ID.desktop" \
    >"$DESKTOP_FILE.tmp"
  rm -rf "$tmp"
  if ! grep -qF "Exec=$APPIMAGE" "$DESKTOP_FILE.tmp"; then
    err "a entry do upstream não tem Exec= — não foi possível apontá-la para o AppImage"
    rm -f "$DESKTOP_FILE.tmp"
    return 1
  fi
  mv -f "$DESKTOP_FILE.tmp" "$DESKTOP_FILE"
}

entry_ok() {
  [[ -f "$DESKTOP_FILE" ]] && grep -qF "Exec=$APPIMAGE" "$DESKTOP_FILE" &&
    compgen -G "$ICON_DIR/*/apps/$APP_ID.*" >/dev/null
}

case "${1:-}" in
  --uninstall)
    uninstall || _finish 1
    _finish 0
    ;;
  "") ;;
  *)
    echo "Uso: $(basename "$0") [--uninstall]" >&2
    _finish 1
    ;;
esac

# fuse3: o runtime do AppImage monta o squashfs a cada abertura.
# libxkbcommon-x11: o MDM roda por XWayland e o AppImage não traz essa lib
# (sem ela ele cai para Wayland nativo, com menus abrindo no meio da tela).
pkg_install fuse3 libxkbcommon-x11 || _finish 1

# O nome do arquivo traz a versão; a linha certa é a única que termina em
# -linux-x86_64.AppImage (a do .zsync termina em .zsync). O tr tira um CR
# eventual, que faria o $ do grep não casar.
if ! sums="$(curl -fsSL --retry 3 "$RELEASE_URL/SHA256SUMS.txt")"; then
  err "não foi possível baixar o SHA256SUMS.txt da última release"
  _finish 1
fi
line="$(tr -d '\r' <<<"$sums" | grep -E -- '-linux-x86_64\.AppImage$' || true)"
read -r sha file <<<"$line" || true
if [[ -z "${sha:-}" || -z "${file:-}" ]]; then
  err "AppImage não encontrado no SHA256SUMS.txt — o upstream renomeou o arquivo?"
  _finish 1
fi
version="$(sed -E 's/^MisterDownloadManager-(.*)-linux-x86_64\.AppImage$/\1/' <<<"$file")"

if [[ -x "$APPIMAGE" && "$(sha256sum "$APPIMAGE" | cut -d' ' -f1)" == "$sha" ]]; then
  if entry_ok; then
    skipped "MDM $version já instalado"
  else
    install_entry "$APPIMAGE" || _finish 1
    ok "MDM $version já instalado — entry e ícone refeitos"
  fi
  _finish 0
fi

download="$APP_DIR/.MisterDownloadManager.AppImage.download"
trap 'rm -f "$download"' EXIT

info "Baixando o MDM $version..."
mkdir -p "$APP_DIR"
if ! curl -fL --retry 3 --progress-bar -o "$download" "$RELEASE_URL/$file"; then
  err "falha ao baixar $file"
  _finish 1
fi
if [[ "$(sha256sum "$download" | cut -d' ' -f1)" != "$sha" ]]; then
  err "o download não bate com o SHA-256 do SHA256SUMS.txt"
  _finish 1
fi
chmod 755 "$download"

install_entry "$download" || _finish 1

# Por último, e atômico: funciona com o MDM aberto.
mv -f "$download" "$APPIMAGE"
ok "MDM $version instalado em $APPIMAGE"
info "Abra o MDM uma vez para ele registrar a integração com os navegadores"
