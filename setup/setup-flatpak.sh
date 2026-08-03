#!/bin/bash
set -euo pipefail

# =============================================================================
# CONFIGURAÇÃO DO FLATPAK
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PACKAGES=(flatpak)
FLATPAK_DATA_DIR="/var/lib/flatpak"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"

# --- 1. Btrfs prep antes da instalação ---------------------------------------
btrfs_subvol_nocow "$FLATPAK_DATA_DIR"

# --- 2. Pacotes ---------------------------------------------------------------
info "Pacotes Flatpak..."
pacman_install "${PACKAGES[@]}"

# --- 3. Remote Flathub --------------------------------------------------------
info "Verificando remote flathub..."
if flatpak remotes --system | awk '{print $1}' | grep -qx flathub; then
  skipped "remote flathub já configurado"
else
  sudo flatpak remote-add --if-not-exists flathub "$FLATHUB_URL"
  ok "remote flathub adicionado"
fi

ok "Setup do Flatpak concluído."
