#!/bin/bash
# =============================================================================
# Helpers compartilhados pelos setup-*.sh
# =============================================================================

# Source guard
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
RESET='\033[0m'

info()    { echo -e "${CYAN}==> $*${RESET}"; }
ok()      { echo -e "${GREEN}    ok: $*${RESET}"; }
skipped() { echo -e "${YELLOW}    --: $*${RESET}"; }
err()     { echo -e "${RED}    erro: $*${RESET}"; }

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# Permite return quando sourced, exit quando executado direto.
_finish() {
  return "${1:-0}" 2>/dev/null || exit "${1:-0}"
}

# need_cmd <cmd> [hint]
need_cmd() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd não encontrado${hint:+ — $hint}"
    return 1
  fi
}

# pacman_install pkg1 pkg2 ...
pacman_install() {
  local to_install=()
  local pkg
  for pkg in "$@"; do
    if pacman -Q "$pkg" &>/dev/null; then
      skipped "$pkg já instalado"
    else
      to_install+=("$pkg")
    fi
  done
  if [[ ${#to_install[@]} -gt 0 ]]; then
    info "Instalando: ${to_install[*]}"
    sudo pacman -S --noconfirm "${to_install[@]}"
    ok "${#to_install[@]} pacote(s) instalado(s)"
  fi
}

# enable_service <unit>
enable_service() {
  local unit="$1"
  if systemctl is-enabled --quiet "$unit" 2>/dev/null \
     && systemctl is-active --quiet "$unit" 2>/dev/null; then
    skipped "$unit já habilitado e ativo"
    return 0
  fi
  sudo systemctl enable --now "$unit"
  ok "$unit habilitado e iniciado"
}

# btrfs_subvol_nocow <path> [service_a_parar_durante_a_migracao]
btrfs_subvol_nocow() {
  local path="$1" stop_svc="${2:-}"
  local fs
  fs="$(findmnt -n -o FSTYPE /)"
  if [[ "$fs" != "btrfs" ]]; then
    skipped "FS é '$fs', sem configuração btrfs necessária"
    return 0
  fi

  info "btrfs detectado — verificando subvolume $path..."
  if sudo btrfs subvolume show "$path" &>/dev/null; then
    skipped "subvolume $path já existe"
    if lsattr -d "$path" 2>/dev/null | grep -q 'C'; then
      skipped "CoW já desativado em $path"
    else
      sudo chattr +C "$path"
      ok "CoW desativado em $path (atenção: arquivos preexistentes mantêm CoW)"
    fi
    return 0
  fi

  [[ -n "$stop_svc" ]] && sudo systemctl stop "$stop_svc" 2>/dev/null || true
  sudo mkdir -p "$(dirname "$path")"

  local had_data=0
  if [[ -d "$path" ]]; then
    sudo mv "$path" "${path}.bak"
    had_data=1
  fi

  sudo btrfs subvolume create "$path"
  # +C precisa ser aplicado no subvolume vazio para que os arquivos copiados
  # depois nasçam já sem CoW (chattr +C em diretório não-vazio não converte
  # os arquivos existentes).
  sudo chattr +C "$path"

  if (( had_data )); then
    # cp --reflink=never força reescrita: arquivos novos herdam o +C do
    # diretório-pai. mv no mesmo FS é só rename e preservaria CoW antigo.
    sudo cp --reflink=never -a "${path}.bak"/. "$path"/
    sudo rm -rf "${path}.bak"
  fi

  ok "subvolume $path criado com CoW desativado"
}

# stow_pkg <name> — linka pacote na raiz de $DOTFILES_DIR
stow_pkg() {
  local name="$1"
  need_cmd stow "pacman -S stow" || return 1
  stow --dir="$DOTFILES_DIR" --target="$HOME" "$name"
}

# -----------------------------------------------------------------------------
# Ponte dotfiles <-> configs do Omarchy
#
# Nada deste repo é symlinkado para dentro de ~/.config: o tooling do Omarchy
# reescreve os arquivos que ele possui com `sed -i` e rename atômico, o que
# troca um symlink por arquivo comum e faz o repo parar de acompanhar o config
# em silêncio. Em vez disso cada arquivo do Omarchy ganha UMA linha apontando
# para cá. Estas funções cuidam de plantar essa linha de forma idempotente.
#
# Não fazemos backup do arquivo alterado de propósito: a mudança é um único
# bloco acrescentado (fácil de remover na mão) e o original é recuperável com
# `omarchy refresh config <caminho-relativo-a-~/.config>`. Deixar .bak pelo
# ~/.config atrapalharia a auditoria contra o /etc/skel.
# -----------------------------------------------------------------------------

# append_block <arquivo> <marcador> <bloco>
#   Acrescenta <bloco> ao fim do arquivo se <marcador> ainda não estiver lá.
#   O marcador é comparado literal (grep -F), então use um trecho único —
#   tipicamente o próprio caminho do arquivo importado.
append_block() {
  local file="$1" marker="$2" block="$3"

  if [[ ! -f "$file" ]]; then
    err "$file não existe — o Omarchy está instalado?"
    return 1
  fi

  if grep -qF -- "$marker" "$file"; then
    skipped "$file já referencia $marker"
    return 0
  fi

  printf '\n%s\n' "$block" >>"$file"
  ok "$marker adicionado em $file"
}

# insert_block_after <arquivo> <ancora> <marcador> <bloco>
#   Igual ao append_block, mas insere logo depois da primeira linha que contém
#   <ancora>. A âncora é comparada literal (nada de regex), então pode ter
#   parênteses e pontos à vontade. Se a âncora não existir (o Omarchy mudou o
#   template), cai para o fim do arquivo avisando, em vez de falhar.
insert_block_after() {
  local file="$1" anchor="$2" marker="$3" block="$4"

  if [[ ! -f "$file" ]]; then
    err "$file não existe — o Omarchy está instalado?"
    return 1
  fi

  if grep -qF -- "$marker" "$file"; then
    skipped "$file já referencia $marker"
    return 0
  fi

  if ! grep -qF -- "$anchor" "$file"; then
    skipped "âncora '$anchor' não encontrada em $file — acrescentando ao fim"
    append_block "$file" "$marker" "$block"
    return $?
  fi

  local tmp
  tmp="$(mktemp)"
  awk -v anchor="$anchor" -v block="$block" '
    { print }
    !done && index($0, anchor) { print ""; print block; done = 1 }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"

  ok "$marker inserido em $file após \"$anchor\""
}

# omarchy_plugin_enable <id> [args...] — habilita um widget da barra
omarchy_plugin_enable() {
  local id="$1"
  shift
  need_cmd omarchy "este script só roda em cima do Omarchy" || return 1

  if omarchy plugin list --json 2>/dev/null |
     jq -e --arg id "$id" 'any(.[]; .id == $id and .enabled)' >/dev/null; then
    skipped "$id já habilitado na barra"
    return 0
  fi

  omarchy plugin enable "$id" "$@"
  ok "$id habilitado na barra"
}
