#!/bin/bash
set -euo pipefail

# =============================================================================
# CONFIGURAÇÃO DE VIRTUALIZAÇÃO (QEMU/KVM + virt-manager)
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PACKAGES=(qemu-desktop virt-manager swtpm dnsmasq dmidecode)
VM_DIR="/var/lib/libvirt"
NETWORK_CONF="/etc/libvirt/network.conf"
FIREWALL_ENTRY='firewall_backend = "iptables"'

# --- 1. Btrfs prep antes da instalação ---------------------------------------
btrfs_subvol_nocow "$VM_DIR" libvirtd

# --- 2. Pacotes ---------------------------------------------------------------
info "Pacotes de virtualização..."
pkg_install "${PACKAGES[@]}"

# --- 3. firewall_backend = iptables ------------------------------------------
info "Verificando $NETWORK_CONF..."
if grep -qF "$FIREWALL_ENTRY" "$NETWORK_CONF" 2>/dev/null; then
  skipped "firewall_backend já configurado"
else
  sudo mkdir -p "$(dirname "$NETWORK_CONF")"
  echo "$FIREWALL_ENTRY" | sudo tee -a "$NETWORK_CONF" > /dev/null
  ok "firewall_backend adicionado"
fi

# --- 4. Usuário no grupo libvirt ----------------------------------------------
info "Verificando grupo libvirt para $USER..."
if id -nG "$USER" | grep -qw libvirt; then
  skipped "$USER já está no grupo libvirt"
else
  sudo usermod -aG libvirt "$USER"
  ok "$USER adicionado ao grupo libvirt (efetivo no próximo login)"
fi

# --- 5. Serviços libvirtd -----------------------------------------------------
enable_service libvirtd.service
enable_service libvirtd.socket

# --- 6. Rede default do libvirt com autostart ---------------------------------
# LC_ALL=C: o virsh traduz a saída, e em pt-BR os greps abaixo nunca casariam.
# Saída em variável, e não em pipe: o grep -q sai no primeiro match e, com
# pipefail, o SIGPIPE no virsh faz uma rede ativa parecer inativa.
info "Verificando rede 'default' do libvirt..."
net_info="$(sudo LC_ALL=C virsh net-info default 2>/dev/null || true)"
if grep -q "Autostart:.*yes" <<<"$net_info"; then
  skipped "rede default já com autostart"
else
  sudo virsh net-autostart default
  ok "autostart habilitado na rede default"
fi

if grep -q "Active:.*yes" <<<"$net_info"; then
  skipped "rede default já ativa"
else
  sudo virsh net-start default
  ok "rede default iniciada"
fi

# --- 7. UFW: permitir roteamento da subnet do libvirt ------------------------
ensure_cmd ufw || _finish 1

info "Verificando regra UFW para rede virtual..."
ufw_status="$(sudo ufw status verbose 2>/dev/null || true)"
if grep -qF "192.168.122.0/24" <<<"$ufw_status"; then
  skipped "regra UFW já existe"
else
  sudo ufw route allow from 192.168.122.0/24
  ok "regra UFW adicionada"
fi

ok "Setup de virtualização concluído."
