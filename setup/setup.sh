#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# =============================================================================
# SCRIPTS DE SETUP — adicione novos scripts aqui em ordem de execução
# =============================================================================
SETUP_SCRIPTS=(
  # 1) Sistema base
  setup-locale.sh
  setup-ioschedulers.sh
  setup-sysctl.sh

  # 2) Containers / VMs
  setup-docker.sh
  setup-virt.sh
  setup-flatpak.sh

  # 3) Configs do Omarchy (plantam a linha que aponta para este repo)
  setup-hypr.sh
  setup-foot.sh

  # 4) Preferências do Omarchy aplicadas por comando (fonte, tema, barra)
  setup-omarchy.sh
)
# =============================================================================

source "$SCRIPT_DIR/lib/common.sh"

for script in "${SETUP_SCRIPTS[@]}"; do
  path="$SCRIPT_DIR/$script"
  echo -e "${CYAN}==============================${RESET}"
  echo -e "${CYAN} $script${RESET}"
  echo -e "${CYAN}==============================${RESET}"

  if [[ ! -f "$path" ]]; then
    err "$path não encontrado — pulando"
    continue
  fi

  read -r -p "$(echo -e "${CYAN}Executar $script? [s/N] ${RESET}")" answer
  if [[ "${answer,,}" != "s" ]]; then
    skipped "$script pulado"
    echo ""
    continue
  fi

  # shellcheck source=/dev/null
  source "$path"

  echo -e "${GREEN} $script concluído${RESET}"
  echo ""
done

echo -e "${GREEN}=============================="
echo -e " Setup completo!"
echo -e "==============================${RESET}"
