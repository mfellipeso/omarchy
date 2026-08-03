#!/bin/bash
set -euo pipefail

# =============================================================================
# HYPRLAND — aponta o config do Omarchy para este repo
#
# O Omarchy carrega os defaults dele e depois os arquivos do usuário em
# ~/.config/hypr. Em vez de sobrescrever esses arquivos (ou symlinkar por cima
# deles), plantamos UMA linha no hyprland.lua chamando o init.lua do repo, que
# é quem carrega input/bindings/windows. Assim ~/.config/hypr continua idêntico
# ao stock do Omarchy e segue recebendo updates.
#
# A linha entra logo após o último require do usuário para carregar depois dos
# defaults (as bindings dependem disso: elas dão hl.unbind antes de rebindar) e
# antes do require dos toggles, que são estado dinâmico do `omarchy toggle`.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

HYPRLAND_LUA="$HOME/.config/hypr/hyprland.lua"
INIT_LUA="$DOTFILES_DIR/hypr/init.lua"
ANCHOR='require("hypr.autostart")'
MARKER='.dotfiles/hypr/init.lua'

BLOCK='-- Personal config, kept in ~/.dotfiles. This is the only line in ~/.config/hypr
-- that is not stock Omarchy; the repo'"'"'s init.lua loads everything else.
dofile(os.getenv("HOME") .. "/.dotfiles/hypr/init.lua")'

# --- 1. O repo tem o que importar? -------------------------------------------
info "Verificando $INIT_LUA..."
if [[ ! -f "$INIT_LUA" ]]; then
  err "$INIT_LUA não encontrado — repo incompleto?"
  _finish 1
fi
ok "init.lua presente"

# --- 2. Plantar a linha no config do Omarchy ---------------------------------
info "Verificando $HYPRLAND_LUA..."
insert_block_after "$HYPRLAND_LUA" "$ANCHOR" "$MARKER" "$BLOCK" || _finish 1

# --- 3. Validar ---------------------------------------------------------------
# Só dá para validar com o Hyprland rodando; num primeiro boot pós-instalação
# ele pode não estar de pé ainda, e aí a validação fica para o próximo login.
if ! command -v hyprctl &>/dev/null || [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  skipped "Hyprland não está rodando — a config será validada no próximo login"
  _finish 0
fi

info "Recarregando o Hyprland..."
hyprctl reload >/dev/null 2>&1 || true
sleep 1

errors="$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)"
if [[ -n "$errors" ]]; then
  err "hyprctl configerrors reportou:"
  echo "$errors"
  _finish 1
fi

ok "Config carregada sem erros."
