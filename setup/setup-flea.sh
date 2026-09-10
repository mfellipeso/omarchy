#!/bin/bash
set -euo pipefail

# =============================================================================
# FLEA — gerenciador de arquivos padrão
#
# O `flea --default` é quem faz o trabalho todo, e em cinco lugares que não dá
# para versionar aqui: o handler de inode/directory no mimeapps.list, o serviço
# org.freedesktop.FileManager1 em ~/.local/share/dbus-1, o FileChooser no
# ~/.config/xdg-desktop-portal/portals.conf e dois blocos delimitados no
# ~/.config/hypr/bindings.lua (as bindings e a regra de janela do seletor). São
# arquivos que o próprio flea reescreve — os blocos saem inteiros com
# `flea --default off` —, então a fonte da verdade é o comando, como no
# setup-omarchy.sh.
#
# Ele é idempotente ponto a ponto (diz "already ..." no que já está no lugar e
# sai 0), então rodamos sem checagem de estado na frente: assim o script
# converge mesmo que só uma das cinco pontas tenha saído do lugar, coisa que uma
# checagem nossa erraria por olhar menos pontos do que o comando toca.
#
# O que precisa de guarda é o restart do portal, que não é idempotente no
# sentido que importa: ele fecha na hora qualquer diálogo de arquivo aberto. O
# portal só lê o portals.conf na subida, então basta reiniciar quando o
# FileChooser mudou agora — daí a única leitura de estado do script, feita antes
# do comando.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PACKAGES=(flea)
PORTALS_CONF="$HOME/.config/xdg-desktop-portal/portals.conf"
FILECHOOSER_RE='^org\.freedesktop\.impl\.portal\.FileChooser=flea(;|$)'

# --- 1. Pacote ----------------------------------------------------------------
info "Pacotes do Flea..."
pkg_install "${PACKAGES[@]}" || _finish 1

need_cmd flea "omarchy pkg add flea" || _finish 1

# --- 2. Padrão do sistema -----------------------------------------------------
portal_was_set=0
grep -qE "$FILECHOOSER_RE" "$PORTALS_CONF" 2>/dev/null && portal_was_set=1

info "Aplicando o flea como padrão..."
if ! flea --default; then
  err "flea --default falhou"
  _finish 1
fi
ok "flea é o padrão (pastas, seletor de arquivos e SUPER + SHIFT + F)"

# --- 3. Recarregar o portal ---------------------------------------------------
if (( portal_was_set )); then
  skipped "seletor de arquivos já era o flea — portal não precisa reiniciar"
  ok "Setup do Flea concluído."
  _finish 0
fi

info "Reiniciando o xdg-desktop-portal..."
if systemctl --user restart xdg-desktop-portal; then
  ok "portal reiniciado — o seletor de arquivos já abre no flea"
else
  err "não deu para reiniciar o xdg-desktop-portal — o seletor muda no próximo login"
fi

ok "Setup do Flea concluído."
