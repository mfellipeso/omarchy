#!/bin/bash
set -euo pipefail

# =============================================================================
# I/O SCHEDULERS — atribuição automática por tipo de dispositivo
# Defaults voltados para workloads desktop/interativos.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

IOSCHED_FILE="/etc/udev/rules.d/60-ioschedulers.rules"

read -r -d '' IOSCHED_RULES <<'EOF' || true
# Automatically assign I/O schedulers based on device type.
# These defaults are tuned for desktop and interactive workloads.

# NVMe devices use the 'kyber' scheduler.
# - Low-latency multi-queue scheduler tuned for fast devices.
# - Balances read/write latency without the overhead of full fairness scheduling.
ACTION=="add|change", KERNEL=="nvme*", SUBSYSTEM=="block", ATTR{queue/scheduler}="kyber"

# SATA SSDs use the BFQ scheduler.
# - BFQ provides per-process I/O budgeting and prioritizes latency-sensitive tasks.
# - Improves desktop responsiveness during heavy background I/O.
ACTION=="add|change", KERNEL=="sd*", SUBSYSTEM=="block", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="bfq"

# Rotational HDDs use the BFQ scheduler.
# - HDDs benefit significantly from request fairness and seek-aware scheduling.
# - Prevents large sequential workloads from monopolizing the disk.
ACTION=="add|change", KERNEL=="sd*", SUBSYSTEM=="block", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF
# =============================================================================

info "Configurando scheduler de I/O (kyber/bfq)..."

current="$(sudo cat "$IOSCHED_FILE" 2>/dev/null || echo "")"
if [[ "$current" == "$IOSCHED_RULES" ]]; then
  skipped "$IOSCHED_FILE já está atualizado"
else
  sudo mkdir -p "$(dirname "$IOSCHED_FILE")"
  echo "$IOSCHED_RULES" | sudo tee "$IOSCHED_FILE" > /dev/null
  ok "Regras udev gravadas em $IOSCHED_FILE"

  info "Recarregando regras do udev..."
  sudo udevadm control --reload-rules
  sudo udevadm trigger
  ok "Regras udev aplicadas"
fi
