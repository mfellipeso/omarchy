#!/bin/bash
set -euo pipefail

# =============================================================================
# IDIOMA — pt-BR (Português do Brasil)
# =============================================================================
#
# Desde o Omarchy 4.5 o idioma é do próprio Omarchy (Setup > Language, ou
# `omarchy language`). Um único comando:
#   - gera o locale em /etc/locale.gen (regra de sudo sem senha para isso);
#   - grava a escolha em ~/.config/omarchy/language (traduz menus e shell);
#   - exporta LANG em ~/.config/uwsm/env.d/50-omarchy-language, que o uwsm
#     carrega no login e repassa para todos os apps da sessão.
#
# Por isso não mexemos mais no /etc/locale.conf: o LANG da sessão vem do uwsm,
# e o do sistema (TTY, serviços) fica no que o instalador definiu.

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

LANGUAGE="pt-BR"

need_cmd omarchy "este script só roda em cima do Omarchy" || _finish 1

locale="$(omarchy language locale "$LANGUAGE")"
session_env="${XDG_CONFIG_HOME:-$HOME/.config}/uwsm/env.d/50-omarchy-language"

info "Verificando idioma do Omarchy..."
if [[ "$(omarchy language)" == "$LANGUAGE" ]] \
   && grep -qxF "export LANG=$locale" "$session_env" 2>/dev/null; then
  skipped "idioma já é $LANGUAGE (LANG=$locale)"
else
  omarchy language "$LANGUAGE"
  ok "idioma definido para $LANGUAGE (LANG=$locale) — vale para apps abertos daqui em diante"
fi

ok "Setup do idioma concluído."
