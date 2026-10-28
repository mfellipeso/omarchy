#!/bin/bash
set -euo pipefail

# =============================================================================
# OMA-CAST — launcher estilo Raycast como plugin do omarchy-shell
#
# O oma-cast (github.com/typecraft-dev/oma-cast) não tem pacote: ele roda de
# dentro do próprio clone. O `bin/oma-cast install` faz um symlink de
# ~/.config/omarchy/plugins/typecraft.oma-cast -> <clone>/plugin e outro de
# ~/.local/bin/oma-cast -> <clone>/bin/oma-cast, depois habilita o plugin no
# shell. Então o clone precisa ficar num lugar permanente — aqui,
# ~/.local/share/oma-cast (OMA_CAST_DIR muda) — e atualizar é `git pull`
# seguido de `oma-cast reload`, porque o Quickshell guarda o QML em cache
# enquanto o shell vive.
#
# Os comandos do upstream são idempotentes em partes diferentes:
#   - `install` reaponta os symlinks e reabilita o plugin sem reclamar, mas
#     reescaneia e espera o plugin responder; rodamos só quando algo saiu do
#     lugar, para não encher o log.
#   - `setup hyprland` NÃO é: ele regrava ~/.config/hypr/oma-cast.lua do zero,
#     e esse arquivo é justamente onde o README manda trocar o atalho. Por isso
#     só o chamamos quando o arquivo ainda não existe; se existe, apenas
#     garantimos o require() em hyprland.lua com o append_block do common.sh.
#
# O atalho padrão é Alt+Space (Super+Space continua sendo o menu do Omarchy).
# O `setup hyprland` recusa se Alt+Space já estiver ligado em algum lugar.
#
# `setup-oma-cast.sh --uninstall` desfaz: plugin, symlink do CLI, atalho,
# require() e o clone. O estado do launcher (frecency, favoritos, aliases) fica
# em ~/.local/share/omarchy/... e não é tocado.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REPO_URL="https://github.com/typecraft-dev/oma-cast.git"
OMA_CAST_DIR="${OMA_CAST_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/oma-cast}"
OMA_CAST="$OMA_CAST_DIR/bin/oma-cast"
PLUGIN_ID="typecraft.oma-cast"
PLUGIN_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
CLI_LINK="$HOME/.local/bin/oma-cast"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
HYPR_LUA="$HYPR_DIR/hyprland.lua"
BIND_LUA="$HYPR_DIR/oma-cast.lua"
REQUIRE_LINE='require("hypr.oma-cast")'

# socat o Omarchy já traz; entra na lista só para o doctor não reclamar numa
# instalação enxuta. git é o que faz o clone.
PACKAGES=(git socat)

# plugin_enabled — true se o shell lista o plugin como habilitado
plugin_enabled() {
  omarchy plugin list --json 2>/dev/null |
    jq -e --arg id "$PLUGIN_ID" 'any(.[]; .id == $id and .enabled)' >/dev/null
}

# plugin_answers — true se o plugin responde ao IPC do shell
plugin_answers() {
  [[ "$(omarchy-shell oma-cast ping 2>/dev/null)" == "ok" ]]
}

# link_points_to <link> <alvo> — true se <link> é symlink resolvendo em <alvo>
link_points_to() {
  [[ -L "$1" && "$(readlink -f "$1")" == "$(readlink -f "$2")" ]]
}

# -----------------------------------------------------------------------------
# --uninstall
# -----------------------------------------------------------------------------
uninstall() {
  local removed=0

  # O `oma-cast uninstall` do upstream desabilita o plugin e tira os dois
  # symlinks, mas só reconhece os que apontam para o clone dele mesmo.
  if [[ -x "$OMA_CAST" ]] && command -v omarchy-shell &>/dev/null; then
    info "Desinstalando o plugin pelo próprio oma-cast..."
    "$OMA_CAST" uninstall || err "oma-cast uninstall falhou — seguindo com a limpeza"
    removed=$((removed + 1))
  fi

  # Sobras: links que apontem para outro clone, ou de uma versão antiga.
  local p
  for p in "$PLUGIN_LINK" "$PLUGIN_LINK".dev-* "$CLI_LINK"; do
    if [[ -L "$p" ]]; then
      rm -f -- "$p"
      ok "removido $p"
      removed=$((removed + 1))
    fi
  done

  if [[ -f "$BIND_LUA" ]]; then
    rm -f -- "$BIND_LUA"
    ok "removido $BIND_LUA"
    removed=$((removed + 1))
  fi

  if [[ -f "$HYPR_LUA" ]] && grep -qF -- "$REQUIRE_LINE" "$HYPR_LUA"; then
    # Tira a linha (só a não comentada) e os brancos que sobram no fim do
    # arquivo, já que o setup hyprland a põe no final precedida de um branco.
    local tmp
    tmp="$(mktemp)"
    awk '
      /^[ \t]*require\("hypr\.oma-cast"\)[ \t]*$/ { next }
      { buf[++n] = $0 }
      END {
        while (n && buf[n] == "") n--
        for (i = 1; i <= n; i++) print buf[i]
      }
    ' "$HYPR_LUA" >"$tmp"
    mv "$tmp" "$HYPR_LUA"
    ok "$REQUIRE_LINE removido de $HYPR_LUA"
    removed=$((removed + 1))
    command -v hyprctl &>/dev/null && hyprctl reload >/dev/null 2>&1 || true
  fi

  if [[ -d "$OMA_CAST_DIR" ]]; then
    rm -rf -- "$OMA_CAST_DIR"
    ok "removido $OMA_CAST_DIR"
    removed=$((removed + 1))
  fi

  if (( removed )); then
    ok "oma-cast desinstalado"
  else
    skipped "nada do oma-cast estava instalado"
  fi
}

case "${1:-}" in
  --uninstall|--remove|uninstall|remove)
    uninstall
    _finish $?
    ;;
  "") ;;
  *)
    echo "Uso: $(basename "$0") [--uninstall]" >&2
    _finish 1
    ;;
esac

# -----------------------------------------------------------------------------
# Instalação
# -----------------------------------------------------------------------------
need_cmd omarchy "este script só roda em cima do Omarchy" || _finish 1
need_cmd omarchy-shell "o oma-cast roda dentro do omarchy-shell (Omarchy 4+)" || _finish 1
need_cmd jq "omarchy pkg add jq" || _finish 1

# --- 1. Dependências ----------------------------------------------------------
info "Dependências do oma-cast..."
pkg_install "${PACKAGES[@]}" || _finish 1

# --- 2. Clone em ~/.local/share -----------------------------------------------
# O clone é a instalação: os symlinks do passo 3 apontam para dentro dele.
# Reexecutar o script é como se atualiza (pull --ff-only). Se a pasta existir
# mas não for um clone deste repo, paramos em vez de passar por cima.
info "Clone em $OMA_CAST_DIR..."
updated=0
if [[ -d "$OMA_CAST_DIR/.git" ]]; then
  origin="$(git -C "$OMA_CAST_DIR" remote get-url origin 2>/dev/null || echo "")"
  if [[ "${origin%.git}" != "${REPO_URL%.git}" ]]; then
    err "$OMA_CAST_DIR é um clone de '${origin:-?}', não de $REPO_URL — mova a pasta ou ajuste OMA_CAST_DIR"
    _finish 1
  fi
  before="$(git -C "$OMA_CAST_DIR" rev-parse HEAD)"
  if ! git -C "$OMA_CAST_DIR" pull --ff-only --quiet; then
    err "git pull falhou em $OMA_CAST_DIR (alterações locais? sem rede?)"
    _finish 1
  fi
  after="$(git -C "$OMA_CAST_DIR" rev-parse HEAD)"
  if [[ "$before" == "$after" ]]; then
    skipped "já na revisão ${after:0:7}"
  else
    updated=1
    ok "atualizado ${before:0:7} -> ${after:0:7}"
  fi
elif [[ -e "$OMA_CAST_DIR" ]]; then
  err "$OMA_CAST_DIR existe e não é um clone git — mova a pasta ou ajuste OMA_CAST_DIR"
  _finish 1
else
  mkdir -p "$(dirname "$OMA_CAST_DIR")"
  if ! git clone --quiet "$REPO_URL" "$OMA_CAST_DIR"; then
    err "git clone falhou"
    _finish 1
  fi
  ok "clonado em $OMA_CAST_DIR ($(git -C "$OMA_CAST_DIR" rev-parse --short HEAD))"
fi

if [[ ! -x "$OMA_CAST" ]]; then
  err "$OMA_CAST não existe ou não é executável — o upstream mudou de layout?"
  _finish 1
fi

# --- 3. Plugin no shell + CLI em ~/.local/bin ---------------------------------
# Três pontas: symlink do plugin, plugin habilitado e respondendo, symlink do
# CLI. Se todas estão no lugar, pulamos o `install`, que senão reescaneia os
# plugins e espera o ping — inofensivo, mas lento e barulhento.
info "Plugin $PLUGIN_ID no omarchy-shell..."
if link_points_to "$PLUGIN_LINK" "$OMA_CAST_DIR/plugin" \
   && link_points_to "$CLI_LINK" "$OMA_CAST" \
   && plugin_enabled && plugin_answers; then
  skipped "plugin linkado, habilitado e respondendo; CLI em $CLI_LINK"
  if (( updated )); then
    # O Quickshell só relê o QML quando o caminho do plugin muda; o reload do
    # upstream troca o symlink por um com sufixo novo justamente para isso.
    info "Clone mudou — recarregando o plugin..."
    "$OMA_CAST" reload || _finish 1
    ok "plugin recarregado"
  fi
else
  if [[ -e "$CLI_LINK" && ! -L "$CLI_LINK" ]]; then
    # O install do upstream pula o link silenciosamente nesse caso; melhor avisar.
    err "$CLI_LINK existe e não é symlink — remova para o CLI ficar no PATH"
    _finish 1
  fi
  # Quem checa omarchy-shell rodando, rescan e habilitação é o próprio install.
  "$OMA_CAST" install || _finish 1
  ok "plugin instalado e habilitado"
fi

# --- 4. Atalho Alt+Space -------------------------------------------------------
# `setup hyprland` escreve oma-cast.lua, planta o require() e dá hyprctl reload.
# Se o arquivo já existe (talvez com outro atalho, editado na mão), não deixamos
# ele ser reescrito; só conferimos o require().
info "Atalho do launcher ($BIND_LUA)..."
if [[ ! -f "$HYPR_LUA" ]]; then
  err "$HYPR_LUA não existe — o Omarchy está instalado?"
  _finish 1
fi
if [[ -f "$BIND_LUA" ]]; then
  skipped "$BIND_LUA já existe — mantido como está"
  if grep -qF -- "$REQUIRE_LINE" "$HYPR_LUA"; then
    skipped "$HYPR_LUA já referencia $REQUIRE_LINE"
  else
    append_block "$HYPR_LUA" "$REQUIRE_LINE" "$REQUIRE_LINE" || _finish 1
    hyprctl reload >/dev/null 2>&1 && ok "Hyprland recarregado" || skipped "hyprctl reload falhou — fora de uma sessão Hyprland?"
  fi
else
  "$OMA_CAST" setup hyprland || _finish 1
  ok "Alt+Space ligado ao oma-cast"
fi

# --- 5. Doctor ----------------------------------------------------------------
info "oma-cast doctor..."
if "$OMA_CAST" doctor; then
  ok "tudo no lugar. Alt+Space abre o launcher; Super+Space continua o menu do Omarchy."
else
  err "o doctor encontrou problemas (acima)"
  _finish 1
fi
