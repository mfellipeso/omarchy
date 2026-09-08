#!/bin/bash
set -euo pipefail

# =============================================================================
# TIBIA — cliente oficial de Linux instalado na home
#
# O pacote `tibia` do AUR joga o cliente em /opt, e isso quebra na prática: o
# que a CipSoft distribui é só um launcher de 1,4 MB que baixa e atualiza o
# cliente de verdade DENTRO da própria pasta. Em /opt (root) o auto-update não
# tem permissão de escrita, e o PKGBUILD ainda usa pkgver=latest — o pacman
# nunca vê versão nova, então cada atualização viraria rebuild na mão.
#
# Instalando na home o launcher se atualiza sozinho e este script só precisa
# rodar uma vez. As dependências continuam vindo do repositório: o tarball traz
# o Qt6 dele em Tibia/lib, mas não traz as libs de sistema (xcb-util, libxml2
# legacy, glu).
#
# ttf-ms-fonts é do AUR e não é opcional na prática: sem as fontes da Microsoft
# o cliente cai num fallback e a interface fica com texto cortado/ilegível.
#
# O .desktop e o ícone ficam em ~/.local/share, que tem precedência sobre
# /usr/share — nada aqui pede sudo além da instalação de pacotes.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

TIBIA_DIR="${TIBIA_DIR:-$HOME/Games/Tibia}"
TARBALL_URL="https://static.tibia.com/download/tibia.x64.tar.gz"
LAUNCHER="$HOME/.local/bin/tibia"
ICON="$HOME/.local/share/icons/hicolor/256x256/apps/tibia.png"
DESKTOP_ENTRY="$HOME/.local/share/applications/tibia.desktop"

# Lista enxuta de propósito. O tarball embute o Qt6 dele, e do resto do
# `depends` do PKGBUILD a maior parte é garantida numa Omarchy: fontconfig,
# freetype2, dbus, libxkbcommon, libxext e libice entram como dependência de
# meia distro, e xcb-util-{image,keysyms,renderutil,wm} são dependência do
# próprio hyprland. Instalar tudo isso só encheria o log de "já instalado".
#
# Sobra o que pode faltar de verdade:
#   - xcb-util-cursor / libxkbcommon-x11: só chegam via qt6-base ou steam, e o
#     libQt6XcbQpa.so.6 do bundle precisa deles quando o cliente roda em
#     X11/XWayland em vez de Wayland nativo.
#   - glu / libxml2-legacy: não aparecem nos NEEDED do launcher (que é só o
#     downloader), mas estão no depends do PKGBUILD do AUR porque são do
#     cliente que o launcher baixa depois — esse não dá para inspecionar sem
#     abrir o jogo, então seguimos o upstream.
PACKAGES=(
  glu
  libxml2-legacy
  libxkbcommon-x11
  xcb-util-cursor
)

# --- 1. Dependências ----------------------------------------------------------
info "Dependências do cliente..."
pkg_install "${PACKAGES[@]}" || _finish 1
aur_install ttf-ms-fonts || _finish 1

# --- 2. Baixar e extrair na home ---------------------------------------------
# Reextrair por cima é seguro (o tarball só tem o launcher e as libs dele), mas
# desnecessário: o próprio launcher se atualiza. TIBIA_FORCE=1 refaz mesmo assim,
# para o caso de uma instalação corrompida.
if [[ -x "$TIBIA_DIR/Tibia" && "${TIBIA_FORCE:-0}" != "1" ]]; then
  skipped "cliente já instalado em $TIBIA_DIR (TIBIA_FORCE=1 reinstala)"
else
  need_cmd curl || _finish 1

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  info "Baixando o cliente de $TARBALL_URL..."
  # -e com a própria URL: sem Referer o static.tibia.com responde 403. É o mesmo
  # truque que o DLAGENT do PKGBUILD do AUR usa.
  if ! curl -fL --compressed --progress-bar --retry 3 -e "$TARBALL_URL" -o "$tmp/tibia.tar.gz" "$TARBALL_URL"; then
    err "download falhou"
    _finish 1
  fi
  ok "tarball baixado ($(du -h "$tmp/tibia.tar.gz" | cut -f1))"

  info "Extraindo em $TIBIA_DIR..."
  mkdir -p "$TIBIA_DIR"
  # --strip-components=1 tira o diretório Tibia/ do tarball: assim o conteúdo
  # cai direto em $TIBIA_DIR em vez de $TIBIA_DIR/Tibia/.
  if ! tar xzf "$tmp/tibia.tar.gz" -C "$TIBIA_DIR" --strip-components=1; then
    err "extração falhou"
    _finish 1
  fi

  if [[ ! -x "$TIBIA_DIR/Tibia" ]]; then
    err "$TIBIA_DIR/Tibia não existe depois da extração — o tarball mudou de layout?"
    _finish 1
  fi
  ok "cliente instalado em $TIBIA_DIR"

  rm -rf "$tmp"
  trap - EXIT
fi

# --- 3. Wrapper em ~/.local/bin ----------------------------------------------
# O qt.conf do cliente traz Prefix=. — os plugins são procurados por caminho
# relativo, então o launcher precisa rodar com o cwd na pasta de instalação.
# Daí o wrapper em vez de um symlink para o binário.
info "Wrapper $LAUNCHER..."
mkdir -p "$(dirname "$LAUNCHER")"
launcher_content="$(
  cat <<EOF
#!/bin/bash
# Gerado por setup-tibia.sh — não edite na mão.
cd "$TIBIA_DIR" || exit 1
exec ./Tibia "\$@"
EOF
)"
if [[ -f "$LAUNCHER" ]] && [[ "$(cat "$LAUNCHER")" == "$launcher_content" ]]; then
  skipped "$LAUNCHER já atualizado"
else
  printf '%s\n' "$launcher_content" >"$LAUNCHER"
  chmod +x "$LAUNCHER"
  ok "$LAUNCHER gerado"
fi

# --- 4. Ícone -----------------------------------------------------------------
# O tibia.ico do tarball é multi-resolução e uma das camadas já é um PNG 256x256;
# extraí-la dá um ícone que qualquer launcher lê. Sem o ImageMagick, apontamos o
# .desktop direto para o .ico (o gdk-pixbuf lê, mas nem todo menu usa gdk-pixbuf).
icon_key="tibia"
if [[ -f "$ICON" && "${TIBIA_FORCE:-0}" != "1" ]]; then
  skipped "ícone já em $ICON"
elif command -v magick &>/dev/null && [[ -f "$TIBIA_DIR/tibia.ico" ]]; then
  info "Extraindo o ícone 256x256 do tibia.ico..."
  mkdir -p "$(dirname "$ICON")"
  # O .ico tem várias camadas e a ordem delas não é a de tamanho, então achamos
  # a maior por área (w*h) e convertemos só esse índice — converter o arquivo
  # inteiro geraria um PNG por camada.
  layer="$(magick identify -format '%[fx:w*h] %s\n' "$TIBIA_DIR/tibia.ico" 2>/dev/null |
             sort -rn | head -1 | cut -d' ' -f2)"
  if [[ -n "$layer" ]] &&
     magick "$TIBIA_DIR/tibia.ico[$layer]" -resize 256x256 "$ICON" 2>/dev/null &&
     [[ -s "$ICON" ]]; then
    ok "ícone gravado em $ICON"
    command -v gtk-update-icon-cache &>/dev/null &&
      gtk-update-icon-cache -qft "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
  else
    rm -f "$ICON"
    skipped "conversão falhou — usando o .ico direto"
    icon_key="$TIBIA_DIR/tibia.ico"
  fi
else
  skipped "magick não encontrado — usando o .ico direto"
  icon_key="$TIBIA_DIR/tibia.ico"
fi
[[ -f "$ICON" ]] && icon_key="tibia"

# --- 5. Entry no menu ---------------------------------------------------------
info "Entry $DESKTOP_ENTRY..."
mkdir -p "$(dirname "$DESKTOP_ENTRY")"
entry_content="$(
  cat <<EOF
[Desktop Entry]
Type=Application
Name=Tibia
GenericName=MMORPG
Comment=Cliente oficial do Tibia
Exec=$LAUNCHER
Path=$TIBIA_DIR
Icon=$icon_key
Terminal=false
Categories=Game;RolePlaying;
Keywords=tibia;mmorpg;cipsoft;
StartupWMClass=Tibia
EOF
)"
if [[ -f "$DESKTOP_ENTRY" ]] && [[ "$(cat "$DESKTOP_ENTRY")" == "$entry_content" ]]; then
  skipped "$DESKTOP_ENTRY já atualizado"
else
  printf '%s\n' "$entry_content" >"$DESKTOP_ENTRY"
  ok "$DESKTOP_ENTRY gerado"
fi

if command -v desktop-file-validate &>/dev/null; then
  if desktop-file-validate "$DESKTOP_ENTRY" 2>&1 | grep -v ': warning:' | grep .; then
    err "desktop-file-validate reportou erros"
    _finish 1
  fi
  ok "entry válido"
fi

if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$(dirname "$DESKTOP_ENTRY")" 2>/dev/null || true
  ok "cache de desktop entries atualizado"
fi

ok "Pronto. Abra pelo menu ou rode 'tibia'."
echo ""
info "As configs (hotkeys, action bars, minimapa) ficam em ~/.local/share/CipSoft —"
info "são locais, não vêm da conta. Faça backup dessa pasta antes de trocar de máquina."
