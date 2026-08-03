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
# Os extras do LazyVim não entram por import: vão para o lazyvim.json, que é o
# arquivo que o :LazyExtras edita. Assim o LazyVim resolve a ordem deles sozinho
# e o lazy.lua fica com um import nosso só.
#
# Nada de tema aqui: o Omarchy symlinka lua/plugins/theme.lua para o tema atual
# e faz hot-reload sozinho.
# =============================================================================

NVIM_EXTRAS=(
  lazyvim.plugins.extras.editor.snacks_explorer
  lazyvim.plugins.extras.lang.typescript
  lazyvim.plugins.extras.lang.docker
  lazyvim.plugins.extras.lang.json
  lazyvim.plugins.extras.lang.prisma
  lazyvim.plugins.extras.lang.python
  lazyvim.plugins.extras.lang.tailwind
  lazyvim.plugins.extras.lang.go
  lazyvim.plugins.extras.linting.eslint
  lazyvim.plugins.extras.formatting.prettier
)

# O Omarchy marca o extra do neo-tree. Ele e o do snacks_explorer disputam o
# mesmo <leader>e, e é o extra que liga cada explorer: o do snacks só existe se
# `editor.snacks_explorer` estiver marcado (é ele que passa `opts.explorer`, que
# por sua vez substitui o netrw). Desmarcar aqui é o mesmo que faria o
# :LazyExtras — desabilitar só o plugin do neo-tree deixaria os dois desligados
# e o netrw assumindo os diretórios.
NVIM_EXTRAS_REMOVE=(
  lazyvim.plugins.extras.editor.neo-tree
)

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

# Depois do import "plugins" do Omarchy, para os overrides daqui vencerem.
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

# --- 4. Extras do LazyVim -----------------------------------------------------
# Mesmo arquivo e mesmo formato que o :LazyExtras grava. Fora os de
# NVIM_EXTRAS_REMOVE, só acrescentamos: o que o Omarchy já tiver marcado ali
# continua marcado.
info "Verificando os extras em $NVIM_DIR/lazyvim.json..."
need_cmd jq "omarchy pkg add jq" || _finish 1

lazyvim_json="$NVIM_DIR/lazyvim.json"
[[ -f "$lazyvim_json" ]] || echo '{}' >"$lazyvim_json"

wanted="$(printf '%s\n' "${NVIM_EXTRAS[@]}" | jq -R . | jq -s .)"
unwanted="$(printf '%s\n' "${NVIM_EXTRAS_REMOVE[@]}" | jq -R . | jq -s .)"

if jq -e --argjson want "$wanted" --argjson drop "$unwanted" \
    '(.extras // []) as $have
     | ($want - $have | length == 0) and ($drop - ($drop - $have) | length == 0)' \
    "$lazyvim_json" >/dev/null; then
  skipped "os extras do lazyvim.json já estão como esperado"
else
  tmp="$(mktemp)"
  jq --argjson want "$wanted" --argjson drop "$unwanted" \
    '.extras = (((.extras // []) + $want | unique) - $drop)' \
    "$lazyvim_json" >"$tmp"
  mv "$tmp" "$lazyvim_json"
  ok "extras gravados no lazyvim.json"
fi

# --- 5. Sincronizar os plugins ------------------------------------------------
need_cmd nvim "omarchy pkg add neovim" || _finish 1

info "Sincronizando os plugins (lazy sync)..."
# `Lazy! sync` roda sem esperar UI; o wait faz o headless segurar até terminar.
if nvim --headless "+Lazy! sync" +qa 2>&1 | tail -5; then
  ok "plugins sincronizados"
else
  err "o lazy sync falhou — abra o nvim e rode :Lazy sync"
  _finish 1
fi

# --- 6. Validar ---------------------------------------------------------------
info "Validando a config..."
errors="$(nvim --headless "+lua vim.cmd('qa')" 2>&1 | grep -iE "error|E[0-9]+:" || true)"
if [[ -n "$errors" ]]; then
  err "o nvim reclamou ao subir:"
  echo "$errors"
  _finish 1
fi

ok "Setup do Neovim concluído."
