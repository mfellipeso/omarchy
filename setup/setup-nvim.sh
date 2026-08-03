#!/bin/bash
set -euo pipefail

# =============================================================================
# NEOVIM — aponta o config do Omarchy para este repo
#
# O ~/.config/nvim vem do pacote omarchy-nvim e continua stock: as migrations do
# Omarchy dão `install` por cima de arquivos de lá. Plantamos três linhas, uma
# por fase de carregamento do LazyVim — o rtp e os plugins no lazy.lua, as
# options no options.lua (antes do lazy subir) e os keymaps no keymaps.lua
# (VeryLazy, depois dos defaults do LazyVim, para os overrides vencerem).
#
# Nada de tema aqui: o Omarchy 4 já symlinka lua/plugins/theme.lua para o tema
# atual e faz hot-reload sozinho.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

NVIM_DIR="$HOME/.config/nvim"
REPO_NVIM="$DOTFILES_DIR/nvim"

# --- 1. O repo tem o que importar? -------------------------------------------
info "Verificando $REPO_NVIM..."
if [[ ! -d "$REPO_NVIM/lua/dotfiles" ]]; then
  err "$REPO_NVIM/lua/dotfiles não encontrado — repo incompleto?"
  _finish 1
fi
ok "módulo dotfiles presente"

if [[ ! -d "$NVIM_DIR" ]]; then
  err "$NVIM_DIR não existe — instale o pacote omarchy-nvim primeiro"
  _finish 1
fi

# --- 2. runtimepath + specs no lazy.lua --------------------------------------
info "Verificando $NVIM_DIR/lua/config/lazy.lua..."

# O runtimepath entra por performance.rtp.paths, e não por um vim.opt.rtp:prepend
# antes do setup(): o lazy roda com performance.rtp.reset = true e reconstrói o
# rtp do zero dentro do próprio setup(), descartando qualquer prepend anterior.
# Ele aplica `paths` no Config.setup(), antes do Loader importar os specs, então
# o módulo já resolve a tempo. É append, então os módulos "config." e "plugins."
# do Omarchy continuam tendo precedência — por isso o namespace aqui é
# "dotfiles.".
insert_block_after "$NVIM_DIR/lua/config/lazy.lua" \
  '    rtp = {' \
  '.dotfiles/nvim' \
  '      -- Config pessoal, mantida em ~/.dotfiles.
      paths = { vim.fn.expand("~/.dotfiles/nvim") },' || _finish 1

insert_block_after "$NVIM_DIR/lua/config/lazy.lua" \
  '{ import = "plugins" },' \
  'import = "dotfiles.plugins"' \
  '    { import = "dotfiles.plugins" },' || _finish 1

# --- 3. options e keymaps -----------------------------------------------------
info "Verificando $NVIM_DIR/lua/config/options.lua..."
append_block "$NVIM_DIR/lua/config/options.lua" \
  'dotfiles.options' \
  'require("dotfiles.options")' || _finish 1

info "Verificando $NVIM_DIR/lua/config/keymaps.lua..."
append_block "$NVIM_DIR/lua/config/keymaps.lua" \
  'dotfiles.keymaps' \
  'require("dotfiles.keymaps")' || _finish 1

# --- 4. Sincronizar os plugins ------------------------------------------------
need_cmd nvim "pacman -S neovim" || _finish 1

info "Sincronizando os plugins (lazy sync)..."
# `Lazy! sync` roda sem esperar UI; o wait faz o headless segurar até terminar.
if nvim --headless "+Lazy! sync" +qa 2>&1 | tail -5; then
  ok "plugins sincronizados"
else
  err "o lazy sync falhou — abra o nvim e rode :Lazy sync"
  _finish 1
fi

# --- 5. Validar ---------------------------------------------------------------
info "Validando a config..."
errors="$(nvim --headless "+lua vim.cmd('qa')" 2>&1 | grep -iE "error|E[0-9]+:" || true)"
if [[ -n "$errors" ]]; then
  err "o nvim reclamou ao subir:"
  echo "$errors"
  _finish 1
fi

ok "Setup do Neovim concluído."
