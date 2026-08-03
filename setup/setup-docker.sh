#!/bin/bash
set -euo pipefail

# =============================================================================
# CONFIGURAÇÃO DO DOCKER
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PACKAGES=(docker docker-compose docker-buildx)
DAEMON_JSON="/etc/docker/daemon.json"
DAEMON_CONFIG='{
  "ipv6": true,
  "fixed-cidr-v6": "2001:db8:1::/64"
}'
DOCKER_DATA_DIR="/var/lib/docker"

# --- 1. Btrfs prep antes da instalação ---------------------------------------
btrfs_subvol_nocow "$DOCKER_DATA_DIR" docker

# --- 2. Pacotes ---------------------------------------------------------------
info "Pacotes Docker..."
pacman_install "${PACKAGES[@]}"

# --- 3. Serviço docker --------------------------------------------------------
enable_service docker

# --- 4. Usuário no grupo docker -----------------------------------------------
info "Verificando grupo docker para $USER..."
if id -nG "$USER" | grep -qw docker; then
  skipped "$USER já está no grupo docker"
else
  sudo usermod -aG docker "$USER"
  ok "$USER adicionado ao grupo docker (efetivo no próximo login)"
fi

# --- 5. daemon.json (IPv6) ----------------------------------------------------
info "Verificando $DAEMON_JSON..."
needs_daemon_update=false

if [[ ! -f "$DAEMON_JSON" ]]; then
  needs_daemon_update=true
elif ! command -v jq &>/dev/null; then
  needs_daemon_update=true
else
  current_ipv6="$(sudo jq -r '.ipv6 // false' "$DAEMON_JSON" 2>/dev/null || echo "false")"
  current_cidr="$(sudo jq -r '."fixed-cidr-v6" // ""' "$DAEMON_JSON" 2>/dev/null || echo "")"
  if [[ "$current_ipv6" == "true" && "$current_cidr" == "2001:db8:1::/64" ]]; then
    skipped "$DAEMON_JSON já configurado"
  else
    needs_daemon_update=true
  fi
fi

if $needs_daemon_update; then
  sudo mkdir -p /etc/docker
  echo "$DAEMON_CONFIG" | sudo tee "$DAEMON_JSON" > /dev/null
  ok "$DAEMON_JSON configurado"

  info "Reiniciando docker..."
  sudo systemctl restart docker
  ok "docker reiniciado"
fi

ok "Setup do Docker concluído."
