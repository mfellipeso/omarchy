#!/bin/bash
set -euo pipefail

# =============================================================================
# CONFIGURAÇÃO DO LOCALE — pt_BR.UTF-8
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

LOCALE="pt_BR.UTF-8"
LOCALE_GEN="/etc/locale.gen"
LOCALE_CONF="/etc/locale.conf"

# --- 1. Descomentar locale no locale.gen --------------------------------------
info "Verificando $LOCALE em $LOCALE_GEN..."
if grep -q "^${LOCALE} UTF-8" "$LOCALE_GEN" 2>/dev/null; then
  skipped "$LOCALE já descomentado em $LOCALE_GEN"
else
  sudo sed -i "s/^#\s*${LOCALE} UTF-8/${LOCALE} UTF-8/" "$LOCALE_GEN"
  info "Gerando locales..."
  sudo locale-gen
  ok "$LOCALE gerado"
fi

# --- 2. Configurar LANG no locale.conf ---------------------------------------
info "Verificando LANG em $LOCALE_CONF..."
current_lang="$(grep '^LANG=' "$LOCALE_CONF" 2>/dev/null | cut -d= -f2 || echo "")"
if [[ "$current_lang" == "$LOCALE" ]]; then
  skipped "LANG já é $LOCALE"
else
  sudo localectl set-locale LANG="$LOCALE"
  ok "LANG definido para $LOCALE"
fi

ok "Setup do locale concluído."
