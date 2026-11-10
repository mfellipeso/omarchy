#!/bin/bash
set -euo pipefail

# =============================================================================
# HERDR-APP — config e tema do Herdr desktop via stow
#
# O pacote herdr-app/ é stowado em ~ (--no-folding, só arquivos viram link):
#   .config/herdr-app/{settings,keys}.json         config do Herdr
#   .config/omarchy/themed/herdr-app.json.tpl      paleta do Omarchy -> Herdr
#   .config/omarchy/hooks/theme-set.d/20-herdr-app publica themes/omarchy.json
#
# Ordem importa: settings.json seleciona o tema "omarchy", e o Herdr recusa o
# layout se o tema ainda não existir. Então primeiro o template e o hook, depois
# o tema publicado, e só então o settings.json.
#
# O Herdr recria settings/keys.json no instante em que somem, então o stow
# normal (ou --adopt) bate de frente com ele. Esses dois ficam fora do stow e
# entram por rename atômico de um symlink relativo (igual ao do stow) sobre o
# arquivo, com backup do original. O Herdr segue escrevendo pelo link.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

PKG="herdr-app"
HERDR_HOME="${HERDR_APP_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}/herdr-app}"
PALETTE="$HOME/.local/state/omarchy/current/theme/herdr-app.json"
HOOK="$HOME/.config/omarchy/hooks/theme-set.d/20-herdr-app"

# link_atomic <nome> — troca ~/.config/herdr-app/<nome> por link para o repo
link_atomic() {
  local name="$1"
  local src="$DOTFILES_DIR/$PKG/.config/herdr-app/$name"
  local dst="$HERDR_HOME/$name"

  if [[ -L $dst && $(readlink "$dst") != /* && $(readlink -f "$dst") == "$src" ]]; then
    ok "$name já aponta para o repo"
    return 0
  fi
  if [[ -f $dst && ! -L $dst ]] && ! cmp -s "$dst" "$src"; then
    cp -p "$dst" "$dst.bak"
    ok "$name original salvo em $dst.bak"
  fi
  ln -sfn "$(realpath -s --relative-to="$HERDR_HOME" "$src")" "$dst.dotfiles-link"
  mv -T "$dst.dotfiles-link" "$dst"
  ok "$name -> repo"
}

# --- 1. Template e hook do tema -------------------------------------------------
info "Stow do pacote $PKG (template e hook)..."
mkdir -p "$HERDR_HOME"
stow_pkg "$PKG" --no-folding --ignore='(settings|keys)\.json' || _finish 1
ok "template e hook linkados"

# --- 2. Publicar o tema omarchy -------------------------------------------------
# Só gera a paleta (refresh completo do tema) se ela ainda não existir; senão
# basta o hook copiá-la para o Herdr.
info "Publicando o tema omarchy do Herdr..."
if [[ ! -f $PALETTE ]]; then
  omarchy theme refresh >/dev/null
fi
bash "$HOOK"

if [[ ! -f $HERDR_HOME/themes/omarchy.json ]]; then
  if [[ ! -f $PALETTE ]]; then
    err "o tema atual não gerou $PALETTE (ele tem colors.toml?)"
  else
    err "$PALETTE foi rejeitado pelo hook (cores inválidas ou não resolvidas)"
  fi
  err "settings.json não foi linkado: ele seleciona um tema que não existe"
  link_atomic keys.json
  _finish 1
fi
ok "themes/omarchy.json publicado"

# --- 3. settings/keys.json ------------------------------------------------------
info "Linkando settings.json e keys.json..."
link_atomic keys.json
link_atomic settings.json
