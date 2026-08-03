#!/bin/bash
set -euo pipefail

# =============================================================================
# OMARCHY — preferências que são comando, não arquivo de config
#
# Fonte, tema e widgets da barra vivem em arquivos que o Omarchy reescreve
# sozinho (o shell.json inteiro é regravado por rename atômico a cada mudança
# na barra, e o omarchy-font-set passa sed no foot.ini/alacritty.toml). Versionar
# esses arquivos faria o repo divergir em silêncio, então a fonte da verdade
# aqui são os comandos — este script apenas os reaplica de forma idempotente.
#
# Sobre a fonte: o omarchy-font-set reescreve a linha `font=` do foot.ini
# cravando size=9. Não é problema — o nosso ~/.dotfiles/foot/local.ini é
# incluído depois e vence no tamanho, e usa a família "monospace", que o próprio
# font-set alimenta via ~/.config/fontconfig/fonts.conf.
# =============================================================================

FONT_FAMILY="CaskaydiaMono Nerd Font"
FONT_PACKAGE="ttf-cascadia-mono-nerd"
THEME="Solitude"
BAR_WIDGETS=(
  "omarchy.microphone --section right --before omarchy.audio"
)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

need_cmd omarchy "este script só roda em cima do Omarchy" || _finish 1

# slug <texto> — "Tokyo Night" -> "tokyo-night", para comparar nomes de tema
slug() { echo "${1,,}" | tr -s ' ' '-'; }

# --- 1. Fonte ----------------------------------------------------------------
info "Verificando a fonte do sistema..."
current_font="$(omarchy font current 2>/dev/null || echo "")"
if [[ "$current_font" == "$FONT_FAMILY" ]]; then
  skipped "fonte já é $FONT_FAMILY"
else
  info "Fonte atual: ${current_font:-desconhecida} -> $FONT_FAMILY"
  # `omarchy pkg add` já ignora o que estiver instalado.
  omarchy pkg add "$FONT_PACKAGE"
  omarchy font set "$FONT_FAMILY"
  ok "fonte definida para $FONT_FAMILY"
fi

# --- 2. Tema ------------------------------------------------------------------
info "Verificando o tema..."
current_theme="$(omarchy theme current 2>/dev/null || echo "")"
if [[ "$(slug "$current_theme")" == "$(slug "$THEME")" ]]; then
  skipped "tema já é $THEME"
else
  info "Tema atual: ${current_theme:-desconhecido} -> $THEME"
  omarchy theme set "$THEME"
  ok "tema definido para $THEME"
fi

# --- 3. Widgets da barra ------------------------------------------------------
# `omarchy bar move` só reordena widgets já presentes; quem adiciona é o
# `omarchy plugin enable`. O helper confere o estado antes de chamar.
info "Verificando os widgets da barra..."
need_cmd jq "pacman -S jq" || _finish 1
for widget in "${BAR_WIDGETS[@]}"; do
  # shellcheck disable=SC2086 # a placement vai como argumentos separados
  omarchy_plugin_enable $widget
done

ok "Setup do Omarchy concluído."
