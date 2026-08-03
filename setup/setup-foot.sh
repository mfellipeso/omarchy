#!/bin/bash
set -euo pipefail

# =============================================================================
# FOOT — aponta o config do Omarchy para este repo
#
# O foot lê UM arquivo só (o primeiro que achar em XDG_CONFIG_HOME e depois
# XDG_CONFIG_DIRS) — não faz merge entre eles. A composição vem do `include=`,
# que é inlinado na posição em que aparece, valendo a última atribuição. Por
# isso o include vai no fim do foot.ini: assim o local.ini vence o `font=` que
# o Omarchy escreve mais acima.
#
# Isso importa porque `omarchy font set` e `omarchy display text size` reescrevem
# o foot.ini com `sed -i` — inclusive cravando size=9. Eles não tocam no
# local.ini, então o nosso tamanho sobrevive. E como o local.ini usa a família
# "monospace" em vez de fixar uma fonte, o `omarchy font set` continua mandando
# na família via ~/.config/fontconfig/fonts.conf.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

FOOT_INI="$HOME/.config/foot/foot.ini"
LOCAL_INI="$DOTFILES_DIR/foot/local.ini"
MARKER='.dotfiles/foot/local.ini'

BLOCK='# Personal overrides, kept in ~/.dotfiles. Last include wins, so anything set
# there beats the values above. Not part of stock Omarchy.
[main]
include=~/.dotfiles/foot/local.ini'

# --- 1. O repo tem o que importar? -------------------------------------------
info "Verificando $LOCAL_INI..."
if [[ ! -f "$LOCAL_INI" ]]; then
  err "$LOCAL_INI não encontrado — repo incompleto?"
  _finish 1
fi
ok "local.ini presente"

# --- 2. Plantar o include no config do Omarchy -------------------------------
info "Verificando $FOOT_INI..."
append_block "$FOOT_INI" "$MARKER" "$BLOCK" || _finish 1

# --- 3. Validar ---------------------------------------------------------------
if ! need_cmd foot "pacman -S foot"; then
  skipped "foot não instalado — validação pulada"
  _finish 0
fi

info "Validando a config do foot..."
if ! foot --check-config; then
  err "foot --check-config falhou"
  _finish 1
fi

ok "Config válida. O foot não recarrega sozinho — abra um terminal novo."
