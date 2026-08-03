#!/bin/bash
set -euo pipefail

# =============================================================================
# VPN HEXA — L2TP/IPsec + widget da barra
#
# Instala o suporte a L2TP no NetworkManager, instala o plugin da barra e
# aplica o split tunnel no perfil da VPN.
#
# Quando o perfil não existe, o script pergunta gateway, usuário, senha e PSK
# e cria a conexão. Nada disso fica no repo: os segredos são lidos com `read -s`
# e entregues direto ao NetworkManager, que é quem os guarda.
#
# Sobre o metric 600 no 192.168.0.0/16: sua LAN normalmente é uma /24 dentro
# desse bloco. Não há conflito, porque o kernel resolve rota por prefixo mais
# específico ANTES de olhar metric — a /24 da LAN continua ganhando da /16 da
# VPN. O metric só desempata rotas de mesmo prefixo.
# =============================================================================

VPN_NAME="Hexa"
VPN_METRIC=600
VPN_ROUTES=(
  "10.0.0.0/8"
  "172.16.0.0/12"
  "192.168.0.0/16"
)
PACKAGES=(networkmanager-l2tp strongswan)

PLUGIN_ID="hexa.vpn"
PLUGIN_URL="${HEXA_VPN_PLUGIN_URL:-git@github.com:mfellipeso/omarchy-hexa-vpn.git}"
PLUGIN_PLACEMENT=(--section right --before omarchy.network)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

need_cmd nmcli "instale o NetworkManager primeiro" || _finish 1

# --- 1. Pacotes L2TP ----------------------------------------------------------
info "Verificando os pacotes de L2TP/IPsec..."
# `|| true` é obrigatório: pacman -Qq sai 1 quando algum pacote não existe e,
# com set -euo pipefail, isso mataria o script justamente na máquina nova em
# que ele mais precisa rodar.
before="$(pacman -Qq "${PACKAGES[@]}" 2>/dev/null | wc -l || true)"
pkg_install "${PACKAGES[@]}"
after="$(pacman -Qq "${PACKAGES[@]}" 2>/dev/null | wc -l || true)"

# O NetworkManager só enxerga o plugin de VPN depois de reiniciar, mas só vale
# reiniciar se algo novo entrou — derrubar a rede à toa é rude.
if [[ "$before" != "$after" ]]; then
  info "Reiniciando o NetworkManager para carregar o plugin de VPN..."
  sudo systemctl restart NetworkManager
  ok "NetworkManager reiniciado"
else
  skipped "NetworkManager não precisa reiniciar"
fi

# --- 2. Plugin da barra -------------------------------------------------------
info "Verificando o plugin $PLUGIN_ID..."
plugin_dir="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

if [[ -d "$plugin_dir" ]]; then
  skipped "$PLUGIN_ID já instalado em $plugin_dir"
else
  info "Instalando a partir de $PLUGIN_URL..."
  # `omarchy plugin add` clona, valida o manifest e liga o bit via IPC —
  # nunca executa código do plugin. --yes o torna não-interativo.
  omarchy plugin add "$PLUGIN_URL" --enable --yes
  ok "$PLUGIN_ID instalado"
fi

if [[ -d "$plugin_dir" ]]; then
  need_cmd jq "omarchy pkg add jq" || _finish 1
  omarchy_plugin_enable "$PLUGIN_ID" "${PLUGIN_PLACEMENT[@]}"
fi

# --- 3. Split tunnel no perfil da VPN ----------------------------------------
info "Verificando o perfil '$VPN_NAME' no NetworkManager..."
if nmcli -t -f NAME connection show | grep -qxF "$VPN_NAME"; then
  ok "perfil '$VPN_NAME' encontrado"
else
  if [[ ! -t 0 ]]; then
    skipped "perfil '$VPN_NAME' não existe e não há terminal para perguntar — rode este script direto"
    _finish 0
  fi

  info "Perfil '$VPN_NAME' não existe. Vamos criá-lo."
  echo "  (senha e PSK não são exibidos nem gravados neste repo)"
  echo ""

  read -r -p "  Gateway (host ou IP da VPN): " vpn_gateway
  [[ -n "$vpn_gateway" ]] || { err "gateway é obrigatório"; _finish 1; }

  read -r -p "  Usuário: " vpn_user
  [[ -n "$vpn_user" ]] || { err "usuário é obrigatório"; _finish 1; }

  read -r -s -p "  Senha: " vpn_password; echo ""
  [[ -n "$vpn_password" ]] || { err "senha é obrigatória"; _finish 1; }

  read -r -s -p "  PSK do IPsec (vazio = sem IPsec): " vpn_psk; echo ""
  echo ""

  # flags=0 diz ao NetworkManager para guardar o segredo no próprio perfil, em
  # vez de pedir a cada conexão.
  vpn_data="gateway=${vpn_gateway}, user=${vpn_user}, password-flags=0"
  if [[ -n "$vpn_psk" ]]; then
    vpn_data+=", ipsec-enabled=yes, ipsec-psk-flags=0"
  fi

  info "Criando o perfil '$VPN_NAME'..."
  nmcli connection add type vpn con-name "$VPN_NAME" ifname "*" vpn-type l2tp \
    vpn.data "$vpn_data" >/dev/null

  # Os segredos vão num `modify` separado. Passar por argv expõe a string no
  # /proc por instantes; num desktop de usuário único o risco é baixo, e a
  # alternativa (escrever o keyfile à mão em /etc) exigiria sudo e replicar o
  # formato interno do NetworkManager.
  vpn_secrets="password=${vpn_password}"
  [[ -n "$vpn_psk" ]] && vpn_secrets+=", ipsec-psk=${vpn_psk}"
  nmcli connection modify "$VPN_NAME" vpn.secrets "$vpn_secrets"

  unset vpn_password vpn_psk vpn_secrets

  ok "perfil '$VPN_NAME' criado"
  skipped "se o servidor exigir MSCHAPv2/MPPE específicos, ajuste em nm-connection-editor"
fi

# nmcli aceita as rotas como uma lista separada por vírgula, cada uma no
# formato "<rede> <next-hop> <metric>"; 0.0.0.0 mantém o next-hop do link.
desired_routes=""
for route in "${VPN_ROUTES[@]}"; do
  desired_routes+="${desired_routes:+, }${route} 0.0.0.0 ${VPN_METRIC}"
done

current_routes="$(nmcli -t -f ipv4.routes connection show "$VPN_NAME" | cut -d: -f2-)"
current_never="$(nmcli -t -f ipv4.never-default connection show "$VPN_NAME" | cut -d: -f2-)"
current_ipv6="$(nmcli -t -f ipv6.method connection show "$VPN_NAME" | cut -d: -f2-)"

needs_routes=false
for route in "${VPN_ROUTES[@]}"; do
  if ! grep -qF "$route" <<<"$current_routes" || ! grep -qE "${route//./\\.}[^,]*${VPN_METRIC}" <<<"$current_routes"; then
    needs_routes=true
    break
  fi
done

if [[ "$needs_routes" == "false" && "$current_never" == "yes" && "$current_ipv6" == "disabled" ]]; then
  skipped "rotas, split tunnel e IPv6 já aplicados em '$VPN_NAME'"
  _finish 0
fi

# never-default descarta a rota padrão que o servidor empurra; ipv6.method
# disabled derruba endereço e rotas v6 do túnel de uma vez, em vez de depender
# de um never-default v6 que só cobriria a rota padrão.
info "Aplicando split tunnel: ${VPN_ROUTES[*]} com metric $VPN_METRIC, IPv6 desligado"
nmcli connection modify "$VPN_NAME" \
  ipv4.never-default yes \
  ipv6.method disabled \
  ipv4.routes "$desired_routes"
ok "rotas aplicadas em '$VPN_NAME'"

if nmcli -t -f NAME,STATE connection show --active | grep -qE "^${VPN_NAME}:activated$"; then
  skipped "a VPN está conectada — reconecte para as rotas novas valerem"
fi

ok "Setup da VPN Hexa concluído."
