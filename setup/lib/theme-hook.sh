#!/bin/bash
# =============================================================================
# Helper dos hooks theme-set que publicam a paleta do Omarchy num app
#
# Carregado pelos hooks stowados (herdr-app, mdm) a partir do caminho real do
# hook no repo, então funciona com o repo clonado em qualquer lugar.
#
# Um hook nunca falha: um tema sem colors.toml ou com cores que o app não aceita
# só mantém o último tema bom publicado.
# =============================================================================

# publish_palette <app> <app_home> <src> <dst> <validador>
#   Copia <src> (renderizado pelo Omarchy) para <dst> se o app estiver instalado
#   (<app_home> existe) e se `<validador> <src>` aceitar o arquivo. O arquivo
#   temporário fica oculto (prefixo ".") ao lado de <dst> para o mv ser atômico
#   sem que um app que vigia a pasta enxergue a cópia pela metade.
publish_palette() {
  local app="$1" app_home="$2" src="$3" dst="$4" validate="$5" tmp

  [[ -d $app_home ]] || return 0
  if [[ ! -f $src ]]; then
    echo "Skipping $app theme: this theme has no colors.toml to render." >&2
    return 0
  fi
  if ! "$validate" "$src"; then
    echo "Skipping $app theme: generated colors are invalid or unresolved." >&2
    return 0
  fi

  cmp -s "$src" "$dst" && return 0
  mkdir -p "${dst%/*}"
  tmp=$(mktemp "${dst%/*}/.${dst##*/}.XXXXXX") || return 0
  if ! { cp "$src" "$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$dst"; }; then
    rm -f "$tmp"
    echo "Skipping $app theme: could not write $dst." >&2
  fi
  return 0
}
