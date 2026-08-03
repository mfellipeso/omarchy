#!/bin/bash
set -euo pipefail

# =============================================================================
# CONFIGURAÇÕES SYSCTL — edite os valores aqui
# =============================================================================
SYSCTL_FILE="/etc/sysctl.d/99-settings.conf"
declare -A SYSCTL_SETTINGS=(
  [vm.swappiness]=180
  [vm.page-cluster]=0
  [vm.dirty_bytes]=268435456
  [vm.dirty_background_bytes]=67108864
)
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

info "Verificando configurações sysctl..."

needs_apply=false

for key in "${!SYSCTL_SETTINGS[@]}"; do
  desired="${SYSCTL_SETTINGS[$key]}"
  current="$(sysctl -n "$key" 2>/dev/null || echo "")"

  if [[ "$current" == "$desired" ]]; then
    skipped "$key = $current"
    continue
  fi

  echo -e "${CYAN}    ~: $key: $current -> $desired${RESET}"

  sudo mkdir -p "$(dirname "$SYSCTL_FILE")"
  if sudo grep -q "^${key}\s*=" "$SYSCTL_FILE" 2>/dev/null; then
    sudo sed -i "s|^${key}\s*=.*|${key} = ${desired}|" "$SYSCTL_FILE"
  else
    echo "${key} = ${desired}" | sudo tee -a "$SYSCTL_FILE" > /dev/null
  fi

  needs_apply=true
done

if ! $needs_apply; then
  ok "Todas as configurações já estão aplicadas."
  _finish 0
fi

info "Aplicando com sysctl --system..."
sudo sysctl --system --quiet
ok "Configurações aplicadas."
