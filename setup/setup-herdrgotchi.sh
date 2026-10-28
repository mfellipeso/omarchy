#!/bin/bash
set -euo pipefail

# =============================================================================
# HERDRGOTCHI — um Tamagotchi por agente do herdr, como plugin do omarchy-shell
#
# O herdrgotchi (github.com/jankeesvw/omarchy-herdrgotchi) é um plugin de
# serviço do omarchy-shell: cada agente rodando dentro do herdr vira um cubo na
# tela, que trabalha, pisca vermelho quando espera resposta e comemora quando
# termina. Não tem widget na barra; os ajustes (monitor, canto, escala) vão
# numa entrada própria em ~/.config/omarchy/shell.json, que o Omarchy regrava
# sozinho — por isso não versionamos nada disso aqui, só instalamos.
#
# A instalação é a padrão do Omarchy: `omarchy plugin add <url>` clona para
# ~/.config/omarchy/plugins/<id> e `omarchy plugin enable <id>` liga. Nenhum
# dos dois é idempotente sozinho (o add recusa se a pasta já existe, e o
# enable sempre fala com o shell), então o script olha o estado antes:
# pasta existente vira `omarchy plugin update`, plugin já ligado é pulado.
#
# O `--yes` no add pula o aviso do Omarchy de que plugin é código sem sandbox
# dentro do shell. É escolha consciente: o repo é o mesmo que o README manda
# adicionar, e a confiança é a mesma dos outros plugins já instalados.
#
# O herdr em si vem do mise (~/.config/mise/config.toml); o omarchy-shell tem
# os shims do mise no PATH, então o plugin o encontra. Se não houver herdr,
# instalamos pelo mise. Precisa de 0.9.1+ para os agentes em máquinas SSH.
#
# `setup-herdrgotchi.sh --uninstall` desliga e remove o plugin e o cache em
# ~/.cache/omarchy-herdrgotchi. O herdr fica.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REPO_URL="https://github.com/jankeesvw/omarchy-herdrgotchi"
PLUGIN_ID="jankeesvw.herdrgotchi"
# Caminho fixo de propósito: os omarchy-plugin-* ignoram XDG_CONFIG_HOME, e o
# estado que olhamos tem que ser o mesmo que eles mexem.
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
CACHE_DIR="$HOME/.cache/omarchy-herdrgotchi"
HERDR_MIN="0.9.1"

# jq e hyprctl o plugin usa direto; foot é onde ele abre uma janela nova do
# herdr quando não há nenhuma. Tudo já vem no Omarchy; a lista só evita
# surpresa numa instalação enxuta.
PACKAGES=(jq foot)

# herdr_bin — caminho do herdr, pelo mise quando ele não estiver ativado neste
# shell (setup.sh num TTY ou por SSH): `command -v` sozinho diria "não tem" e
# o passo 2 trocaria o pin do mise por latest sem necessidade.
herdr_bin() {
  command -v herdr 2>/dev/null && return 0
  command -v mise &>/dev/null && mise which herdr 2>/dev/null
}

# -----------------------------------------------------------------------------
# --uninstall
# -----------------------------------------------------------------------------
uninstall() {
  local removed=0

  if [[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]]; then
    need_cmd omarchy "este script só roda em cima do Omarchy" || return 1
    # O remove já desliga no shell antes de apagar a pasta.
    info "Removendo o plugin $PLUGIN_ID..."
    if omarchy plugin remove "$PLUGIN_ID" --yes; then
      ok "plugin removido"
      removed=$((removed + 1))
    else
      err "omarchy plugin remove falhou"
      return 1
    fi
  fi

  if [[ -d "$CACHE_DIR" ]]; then
    rm -rf -- "$CACHE_DIR"
    ok "removido $CACHE_DIR"
    removed=$((removed + 1))
  fi

  if (( removed )); then
    ok "herdrgotchi desinstalado (o herdr continua instalado)"
  else
    skipped "nada do herdrgotchi estava instalado"
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
need_cmd omarchy-shell "o herdrgotchi roda dentro do omarchy-shell (Omarchy 4+)" || _finish 1

# --- 1. Dependências ----------------------------------------------------------
info "Dependências do herdrgotchi..."
pkg_install "${PACKAGES[@]}" || _finish 1

# --- 2. herdr -----------------------------------------------------------------
# Sem herdr, ou com um anterior a 0.9.1 (agentes em máquinas SSH), o mesmo
# passo resolve: `mise use --global` instala e deixa pinado no config.toml.
info "Verificando o herdr..."
herdr_path="$(herdr_bin || true)"
herdr_version=""
[[ -n "$herdr_path" ]] && herdr_version="$("$herdr_path" --version 2>/dev/null | awk '{print $2}')"
if [[ -n "$herdr_version" ]] &&
   [[ "$(printf '%s\n%s\n' "$HERDR_MIN" "$herdr_version" | sort -V | head -1)" == "$HERDR_MIN" ]]; then
  skipped "herdr $herdr_version já instalado ($herdr_path)"
else
  need_cmd mise "o herdr é instalado pelo mise: omarchy pkg add mise-bin" || _finish 1
  if [[ -n "$herdr_version" ]]; then
    info "herdr $herdr_version é anterior a $HERDR_MIN — atualizando pelo mise..."
  else
    info "Instalando o herdr pelo mise..."
  fi
  if ! mise use --global herdr@latest; then
    err "mise use --global herdr@latest falhou"
    _finish 1
  fi
  herdr_path="$(mise which herdr 2>/dev/null || true)"
  ok "herdr $("$herdr_path" --version 2>/dev/null | awk '{print $2}') instalado ($herdr_path)"
fi

# --- 3. Plugin em ~/.config/omarchy/plugins -----------------------------------
# Pasta já existente: tem que ser o clone deste repo, e aí o `update` (fetch +
# merge --ff-only, com validação do manifest e rollback) é a atualização.
info "Plugin $PLUGIN_ID..."
if [[ -d "$PLUGIN_DIR/.git" ]]; then
  origin="$(git -C "$PLUGIN_DIR" remote get-url origin 2>/dev/null || echo "")"
  if [[ "${origin%.git}" != "${REPO_URL%.git}" ]]; then
    err "$PLUGIN_DIR é um clone de '${origin:-?}', não de $REPO_URL — remova com: omarchy plugin remove $PLUGIN_ID"
    _finish 1
  fi
  # O update diz "is up to date." ou "Updated ..." por conta própria.
  if ! omarchy plugin update "$PLUGIN_ID" --yes; then
    err "omarchy plugin update falhou (alterações locais em $PLUGIN_DIR?)"
    _finish 1
  fi
elif [[ -e "$PLUGIN_DIR" || -L "$PLUGIN_DIR" ]]; then
  err "$PLUGIN_DIR existe e não é um clone git — remova com: omarchy plugin remove $PLUGIN_ID"
  _finish 1
else
  if ! omarchy plugin add "$REPO_URL" --yes; then
    err "omarchy plugin add falhou"
    _finish 1
  fi
  ok "plugin clonado em $PLUGIN_DIR"
fi

# --- 4. Habilitar no shell ----------------------------------------------------
# O helper pula se já estiver habilitado e repete só enquanto o shell ainda
# estiver carregando o plugin depois do add.
info "Habilitando $PLUGIN_ID no omarchy-shell..."
omarchy_plugin_enable "$PLUGIN_ID" || _finish 1

ok "Pronto. Os gotchis aparecem no canto da tela assim que houver agentes no herdr."
echo ""
info "Monitor, canto e escala: entrada \"$PLUGIN_ID\" em ~/.config/omarchy/shell.json (ver README do plugin)."
info "Atalho útil: omarchy-shell $PLUGIN_ID attend — vai para quem espera há mais tempo."
