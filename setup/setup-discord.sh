#!/bin/bash
set -euo pipefail

# =============================================================================
# DISCORD — força XWayland para os atalhos globais funcionarem
#
# Os atalhos globais do Discord (push-to-talk, mute, deafen) são implementados
# em cima de APIs do X11. Em Wayland nativo ele não tem equivalente — não usa o
# portal de global shortcuts — e as teclas simplesmente nunca disparam. Sob
# XWayland ele volta a enxergá-las, daí o --ozone-platform=x11.
#
# Isso é só metade do problema: sob XWayland o Discord ainda só recebe a tecla
# enquanto está em foco, o que não serve para push-to-talk. A outra metade é o
# bind em hypr/bindings.lua, que injeta a tecla na janela.
#
# O entry não é versionado neste repo nem symlinkado: ele é derivado do que o
# pacote instala, acrescentando a flag ao Exec. Assim Name/Icon/MimeType e
# qualquer mudança futura do upstream vêm de graça, em vez de congelarem numa
# cópia que envelhece calada. ~/.local/share tem precedência sobre /usr/share,
# então o arquivo gerado vence sem tocar no que é do pacman.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

SYSTEM_ENTRY="/usr/share/applications/discord.desktop"
LOCAL_ENTRY="$HOME/.local/share/applications/discord.desktop"
FLAG="--ozone-platform=x11"

# --- 1. Instalar o Discord ----------------------------------------------------
pkg_install discord || _finish 1

# --- 2. O pacote entregou o entry? -------------------------------------------
info "Verificando $SYSTEM_ENTRY..."
if [[ ! -f "$SYSTEM_ENTRY" ]]; then
  err "$SYSTEM_ENTRY não encontrado — o pacote discord mudou de layout?"
  _finish 1
fi
ok "entry do pacote presente"

# --- 3. Gerar o override com a flag ------------------------------------------
if [[ -f "$LOCAL_ENTRY" ]] && grep -qF -- "$FLAG" "$LOCAL_ENTRY"; then
  skipped "$LOCAL_ENTRY já força XWayland"
else
  info "Gerando $LOCAL_ENTRY..."
  mkdir -p "$(dirname "$LOCAL_ENTRY")"

  # A flag entra logo depois do executável, antes dos argumentos do próprio
  # Discord. /usr/bin/discord é um shell script que repassa tudo para o binário
  # em ~/.config/discord/app-*, então a flag sobrevive às auto-atualizações.
  if ! sed -E 's;^(Exec=/usr/bin/discord);\1 '"$FLAG"';' "$SYSTEM_ENTRY" >"$LOCAL_ENTRY"; then
    err "falhou ao gerar $LOCAL_ENTRY"
    _finish 1
  fi

  if ! grep -qF -- "$FLAG" "$LOCAL_ENTRY"; then
    err "a linha Exec= do entry não casou com o padrão esperado:"
    grep '^Exec=' "$SYSTEM_ENTRY"
    rm -f "$LOCAL_ENTRY"
    _finish 1
  fi

  ok "$LOCAL_ENTRY gerado com $FLAG"
fi

# --- 4. Atualizar o cache de MIME --------------------------------------------
# Só para o handler de discord:// apontar para o entry novo; o menu de apps lê
# os .desktop direto e não depende disso.
if command -v update-desktop-database &>/dev/null; then
  update-desktop-database "$(dirname "$LOCAL_ENTRY")" 2>/dev/null || true
  ok "cache de desktop entries atualizado"
fi

# --- 5. Validar ---------------------------------------------------------------
if command -v desktop-file-validate &>/dev/null; then
  info "Validando o entry gerado..."
  # O entry do pacote já emite warnings próprios (chaves depreciadas); só um
  # erro de verdade derruba o script.
  if ! desktop-file-validate "$LOCAL_ENTRY" 2>&1 | grep -v '^.*: warning:' | grep .; then
    ok "entry válido"
  else
    err "desktop-file-validate reportou erros"
    _finish 1
  fi
fi

# Um Discord já aberto não pega a flag: ela vale a partir do próximo launch.
# Olhar a cmdline em vez de só o pgrep evita mandar reiniciar quem já está certo.
if pgrep -x Discord &>/dev/null; then
  if pgrep -x -f ".*Discord $FLAG.*" &>/dev/null; then
    ok "Discord já está rodando com a flag"
  else
    skipped "Discord está rodando sem a flag — feche e reabra pelo menu"
  fi
fi

ok "Pronto. Bind o push-to-talk em Configurações de voz > Premir para falar."
