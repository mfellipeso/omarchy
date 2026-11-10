#!/bin/bash
set -euo pipefail

# =============================================================================
# WinBox — o WinBox 4 da MikroTik na home, direto de mikrotik.com
#
# A MikroTik publica um WinBox_Linux.zip (binário Qt nativo + ícone) com um
# .sha256 ao lado, numa URL com a versão: /routeros/winbox/<versão>/. A versão
# atual sai da própria página de download. O WinBox não se atualiza sozinho
# (o "update" que ele tem é o do RouterOS), então quem atualiza é este script:
# rodar de novo só baixa se a versão publicada mudou ou se o binário instalado
# não bate mais com o hash; entry que tenha sumido é refeita.
#
# Sem rede (ou com mikrotik.com fora do ar), um WinBox já instalado e íntegro
# conta como instalado: só não dá para saber se há versão nova.
#
# Só tem plataforma xcb: no Hyprland roda por XWayland.
#
# `setup-winbox.sh --uninstall` desfaz tudo, inclusive os dados do WinBox em
# ~/.local/share/MikroTik/WinBox (endereços e sessões salvas) e o cache.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PAGE_URL="https://mikrotik.com/download/winbox"
BASE_URL="https://download.mikrotik.com/routeros/winbox"
ZIP="WinBox_Linux.zip"
APP_ID="winbox"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
APP_DIR="$DATA_HOME/winbox"
BIN="$APP_DIR/WinBox"
ICON="$APP_DIR/assets/img/winbox.png"
STAMP="$APP_DIR/.version"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"
# Diretórios do próprio WinBox (QStandardPaths com org MikroTik, app WinBox).
WB_DATA="$DATA_HOME/MikroTik/WinBox"
WB_CACHE="$CACHE_HOME/MikroTik/WinBox"

# PIDs do WinBox aberto a partir do NOSSO binário. Um aberto durante uma
# atualização aponta para "$APP_DIR.old/WinBox (deleted)".
winbox_pids() {
  local pid exe
  for pid in $(pgrep -x WinBox || true); do
    exe="$(readlink "/proc/$pid/exe" 2>/dev/null)" || continue
    if [[ "$exe" == "$BIN" || "$exe" == "$APP_DIR.old/WinBox (deleted)" ]]; then
      echo "$pid"
    fi
  done
  return 0
}

uninstall() {
  # Fechar antes: ao sair o WinBox regravaria os dados que vamos apagar.
  kill_and_wait winbox_pids WinBox || return 1

  rm -rf -- "$APP_DIR" "$APP_DIR.new" "$APP_DIR.old" "$WB_DATA" "$WB_CACHE" "$DESKTOP_FILE"
  # O diretório MikroTik só sai se ficou vazio (pode ter outro app deles).
  rmdir "$DATA_HOME/MikroTik" "$CACHE_HOME/MikroTik" 2>/dev/null || true
  ok "WinBox removido"
}

# Exec= entre aspas, com o escape da especificação de .desktop (\ " ` $), para
# que um caminho com espaço não seja partido pelo launcher.
EXEC_LINE="Exec=\"$(sed -E 's/[\\"`$]/\\&/g' <<<"$BIN")\""

install_entry() {
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  cat >"$DESKTOP_FILE.tmp" <<EOF
[Desktop Entry]
Type=Application
Name=WinBox
GenericName=MikroTik Router Manager
Comment=Gerenciar roteadores MikroTik RouterOS
$EXEC_LINE
Icon=$ICON
Terminal=false
Categories=Network;System;
StartupWMClass=WinBox
EOF
  mv -f "$DESKTOP_FILE.tmp" "$DESKTOP_FILE"
}

entry_ok() {
  [[ -f "$DESKTOP_FILE" ]] && grep -qxF "$EXEC_LINE" "$DESKTOP_FILE"
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

# Bibliotecas que o binário linka e que não vêm com o Qt embutido nele.
pkg_install unzip libxkbcommon-x11 xcb-util xcb-util-image xcb-util-keysyms \
  xcb-util-renderutil xcb-util-wm libglvnd || _finish 1

# O que está instalado: versão do stamp, e se o binário ainda bate com o hash
# que o stamp guardou na instalação.
inst_version=""
if [[ -x "$BIN" && -f "$STAMP" ]] && read -r v h <"$STAMP" &&
  [[ "$(sha256sum "$BIN" | cut -d' ' -f1)" == "$h" ]]; then
  inst_version="$v"
fi

# already_installed <versão> [obs] — entry refeita se sumiu, e fim.
already_installed() {
  if entry_ok; then
    skipped "WinBox $1 já instalado${2:+ ($2)}"
  else
    install_entry
    ok "WinBox $1 já instalado${2:+ ($2)} — entry refeita"
  fi
  _finish 0
}

# Sem a página ou sem o hash: segue com o instalado, se houver um íntegro.
offline() {
  if [[ -n "$inst_version" ]]; then
    skipped "$1"
    already_installed "$inst_version" "sem checar atualização"
  fi
  err "$1"
  _finish 1
}

# Versão atual: o link do zip de Linux na página de download. Só versões de
# dígitos e pontos, para nunca pegar um beta ou rc listado junto; sort -V
# escolhe a maior se houver mais de uma.
page="$(curl -fsSL --retry 3 "$PAGE_URL")" ||
  offline "não foi possível abrir $PAGE_URL"
version="$(grep -oE "$BASE_URL/[0-9][0-9.]*/$ZIP" <<<"$page" |
  sed -E "s|^$BASE_URL/([^/]+)/.*|\1|" | sort -uV | tail -n1 || true)"
if [[ -z "$version" ]]; then
  err "link do $ZIP não encontrado em $PAGE_URL — a MikroTik mudou a página?"
  _finish 1
fi
url="$BASE_URL/$version/$ZIP"

[[ "$inst_version" == "$version" ]] && already_installed "$version"

# O .sha256 é "<hash>  WinBox_Linux.zip"; o tr tira um CR eventual.
sha="$(curl -fsSL --retry 3 "$url.sha256" | tr -d '\r' | awk '{print $1}')" || true
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || offline "não foi possível obter o SHA-256 de $url"

work="$(mktemp -d)"
# Se a troca de diretórios for interrompida no meio, devolve o antigo.
cleanup() {
  if [[ ! -d "$APP_DIR" && -d "$APP_DIR.old" ]]; then
    mv "$APP_DIR.old" "$APP_DIR" || true
  fi
  rm -rf "$work" "$APP_DIR.new"
}
trap cleanup EXIT

info "Baixando o WinBox $version..."
if ! curl -fL --retry 3 --progress-bar -o "$work/$ZIP" "$url"; then
  err "falha ao baixar $url"
  _finish 1
fi
if [[ "$(sha256sum "$work/$ZIP" | cut -d' ' -f1)" != "$sha" ]]; then
  err "o download não bate com o SHA-256 publicado"
  _finish 1
fi

rm -rf "$APP_DIR.new"
mkdir -p "$APP_DIR.new"
if ! unzip -q "$work/$ZIP" -d "$APP_DIR.new" || [[ ! -f "$APP_DIR.new/WinBox" ]]; then
  err "WinBox não encontrado dentro do $ZIP — a MikroTik mudou o layout?"
  _finish 1
fi
# O zip traz assets/ como 777.
chmod -R u=rwX,go=rX "$APP_DIR.new"
chmod 755 "$APP_DIR.new/WinBox"
echo "$version $(sha256sum "$APP_DIR.new/WinBox" | cut -d' ' -f1)" >"$APP_DIR.new/.version"

# Troca o diretório inteiro (o trap desfaz se parar no meio); um WinBox aberto segue rodando do
# binário antigo (o inode continua vivo até ele fechar).
if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR.old"
  mv "$APP_DIR" "$APP_DIR.old"
fi
mv "$APP_DIR.new" "$APP_DIR"
rm -rf "$APP_DIR.old"

install_entry
ok "WinBox $version instalado em $APP_DIR"
