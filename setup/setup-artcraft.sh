#!/bin/bash
set -euo pipefail

# =============================================================================
# ARTCRAFT — o Launcher oficial como AppImage na home
#
# O ArtCraft (getartcraft.com) é duas coisas: o estúdio de IA (`artcraft`, que
# no Linux só existe no AUR, compilado com Tauri) e a Craft App Suite
# (PhotoCraft, VectorCraft, FilmCraft, ...), cada app com release própria no
# GitHub. Quem amarra a suíte é o ArtCraft Launcher: um catálogo onde se
# instala só o que se quer, botão a botão, e que atualiza os apps instalados e
# a si mesmo conferindo o SHA-256 publicado na release.
#
# Este script instala só o Launcher, no mesmo esquema que o Omarchy usa para o
# T3 Code (omarchy-install-t3code-app): AppImage em ~/.local/share com nome sem
# versão, porque o auto-update dele faz rename por cima do próprio arquivo e o
# .desktop continua válido. Entry e ícones vêm de dentro do AppImage em vez de
# serem escritos do zero. Nada vai para /usr; o único sudo é o fuse3, que o
# AppImage precisa para montar a si mesmo.
#
# Rodando como AppImage, o Launcher instala os apps também como AppImage, em
# ~/Applications, com entry e ícone em ~/.local/share — tudo na home, sem
# pacman nem Flatpak. Quais instalar é escolha sua na janela dele.
#
# Estúdio de IA: ARTCRAFT_STUDIO=1 instala o pacote `artcraft` do AUR (build
# longo: cargo-tauri + webkit2gtk; o pacote só traz o binário, sem entry no
# menu). Desligado por padrão.
#
# Padrões de abertura: os entries que o Launcher escreve não declaram MimeType
# e ele não instala as definições de MIME que cada AppImage traz, então o
# sistema não sabe que o GridCraft abre planilha. O passo 6 registra isso para
# cada app já instalado, pela tabela MIME_DEFAULTS abaixo, do mesmo jeito que o
# omarchy-nvim-setup faz para o nvim (`xdg-mime default`, ~/.config/mimeapps.list).
#
# `setup-artcraft.sh --uninstall` desfaz tudo: Launcher, apps que ele instalou
# (AppImage, Flatpak ou pacote), entries, ícones, padrões de abertura, caches e
# as configs de cada app. Documentos salvos ficam onde você os salvou.
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

REPO_URL="https://github.com/storytold/craft-launcher"
RELEASE_URL="$REPO_URL/releases/latest/download"
APP_ID="ai.storyteller.artcraft-launcher"
APP_DIR="$HOME/.local/share/artcraft-launcher"
APPIMAGE="$APP_DIR/ArtCraft-Launcher.AppImage"
DESKTOP_FILE="$HOME/.local/share/applications/$APP_ID.desktop"
ICON_DIR="$HOME/.local/share/icons/hicolor"
# Onde o Launcher põe os AppImages dos apps (convenção do AppImageLauncher).
APPS_DIR="$HOME/Applications"
# Ids da suíte, como o catálogo do Launcher os chama (printcraft é o nome antigo
# do pdfcraft). Servem para o --uninstall achar AppImages, entries e configs.
CRAFT_APPS=(photocraft vectorcraft filmcraft lightcraft pdfcraft printcraft
            effectcraft designcraft figcraft wordcraft soundcraft deckcraft
            cadcraft gridcraft)
MIME_DIR="$HOME/.local/share/mime"
# Onde o `xdg-mime default` grava.
MIMEAPPS="${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list"

# De quais tipos cada app vira o padrão. Documento de escritório, PDF e formato
# de design; imagem comum fica com o imv e texto com o nvim, que são os padrões
# do Omarchy. Os tipos vêm do .desktop de cada AppImage.
declare -A MIME_DEFAULTS=(
  [pdfcraft]="application/pdf"
  [gridcraft]="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
               application/vnd.ms-excel.sheet.macroEnabled.12
               application/vnd.ms-excel.sheet.binary.macroEnabled.12
               application/vnd.oasis.opendocument.spreadsheet
               text/csv
               text/tab-separated-values"
  [wordcraft]="application/vnd.openxmlformats-officedocument.wordprocessingml.document
               application/vnd.ms-word.document.macroEnabled.12
               application/vnd.openxmlformats-officedocument.wordprocessingml.template
               application/vnd.ms-word.template.macroEnabled.12
               application/msword
               application/msword-template
               application/vnd.oasis.opendocument.text
               application/rtf
               text/rtf"
  [deckcraft]="application/x-deckcraft
               application/vnd.openxmlformats-officedocument.presentationml.presentation
               application/vnd.openxmlformats-officedocument.presentationml.template
               application/vnd.openxmlformats-officedocument.presentationml.slideshow"
  [photocraft]="application/x-photocraft
                image/vnd.adobe.photoshop
                image/x-psd
                image/x-psb
                image/openraster
                application/x-krita
                image/x-paintnet"
)

# -----------------------------------------------------------------------------
# --uninstall
# -----------------------------------------------------------------------------
uninstall() {
  shopt -s nullglob
  local removed=0

  # rm_path <caminho> — remove se existir e conta; silencioso se já não está lá.
  rm_path() {
    local p="$1"
    if [[ -e "$p" || -L "$p" ]]; then
      rm -rf -- "$p"
      ok "removido $p"
      removed=$((removed + 1))
    fi
  }

  # --- 1. Fechar o Launcher ---------------------------------------------------
  # Apagar um AppImage em uso não quebra o processo, mas ele reescreveria o
  # installed.json ao sair. O kernel trunca o nome do processo em 15 chars, então
  # o binário de dentro aparece como "artcraft-launch" e o runtime do AppImage
  # como "ArtCraft-Launch"; `pgrep -x artcraft-launcher` nunca acharia nenhum.
  launcher_running() { pgrep -x artcraft-launch &>/dev/null || pgrep -f "^$APPIMAGE" &>/dev/null; }
  if launcher_running; then
    info "Fechando o ArtCraft Launcher..."
    pkill -x artcraft-launch 2>/dev/null || true
    pkill -f "^$APPIMAGE" 2>/dev/null || true
    for _ in $(seq 20); do
      launcher_running || break
      sleep 0.5
    done
    launcher_running && err "o Launcher não fechou — seguindo mesmo assim" || ok "Launcher fechado"
  fi

  # --- 2. Apps da suíte: Flatpak e pacotes -----------------------------------
  # Só entram aqui se a preferência do Launcher foi trocada na mão; por padrão
  # ele instala AppImage. Ficam antes dos arquivos porque removem os deles.
  if command -v flatpak &>/dev/null; then
    local fp
    while IFS= read -r fp; do
      [[ -n "$fp" ]] || continue
      info "Removendo o flatpak $fp..."
      if flatpak uninstall -y --noninteractive "$fp" >/dev/null; then
        ok "flatpak $fp removido"
        removed=$((removed + 1))
      else
        err "flatpak uninstall $fp falhou"
      fi
    done < <(flatpak list --app --columns=application 2>/dev/null | grep '^ai\.storyteller\.' || true)
  fi

  local pkgs=()
  mapfile -t pkgs < <(pacman -Qq 2>/dev/null |
    grep -E '^(ai\.storyteller\.|artcraft($|-)|storytold-)' || true)
  if (( ${#pkgs[@]} )); then
    need_cmd omarchy "este repo é só para Omarchy" || return 1
    info "Removendo pacotes: ${pkgs[*]}"
    if omarchy pkg drop "${pkgs[@]}"; then
      ok "${#pkgs[@]} pacote(s) removido(s)"
      removed=$((removed + ${#pkgs[@]}))
    else
      err "omarchy pkg drop falhou para: ${pkgs[*]}"
    fi
  fi

  # --- 3. Apps da suíte: AppImages, entries, ícones e configs -----------------
  info "Apps da suíte..."
  # Primeiro o que o próprio Launcher registrou ter instalado (vale para uma
  # pasta de instalação personalizada ou app novo no catálogo); depois os globs,
  # para o que ficou de fora ou veio de antes.
  local manifest="$APP_DIR/installed.json" p
  if [[ -f "$manifest" ]] && command -v jq &>/dev/null; then
    while IFS= read -r p; do
      [[ -n "$p" ]] && rm_path "$p"
    done < <(jq -r '.apps[]? | .path, (.files[]? // empty)' "$manifest" 2>/dev/null)
  fi
  local app
  for app in "${CRAFT_APPS[@]}"; do
    for p in "$APPS_DIR/$app"-*.AppImage; do rm_path "$p"; done
    rm_path "$HOME/.local/share/applications/ai.storyteller.$app.desktop"
    for p in "$ICON_DIR"/*/apps/"ai.storyteller.$app".*; do rm_path "$p"; done
    rm_path "$HOME/.var/app/ai.storyteller.$app"
    rm_path "$HOME/.config/$app"
    rm_path "$HOME/.local/share/$app"
    rm_path "$HOME/.local/state/$app"
    rm_path "$HOME/.cache/$app"
  done
  # Pasta criada pelo Launcher; só sai se ficou vazia (pode ter AppImages seus).
  [[ -d "$APPS_DIR" ]] && rmdir --ignore-fail-on-non-empty "$APPS_DIR" 2>/dev/null || true

  # Padrões de abertura: tira só os ids ai.storyteller.* de cada linha, para
  # não levar junto outra associação que divida a linha, e apaga o que ficou
  # vazio. As definições de MIME saem com o banco recompilado.
  # Sem a nossa linha, vale de novo o /usr/share/applications/mimeapps.list,
  # onde o Omarchy deixa os padrões dele (Evince para PDF etc.).
  if [[ -f "$MIMEAPPS" ]] && grep -q 'ai\.storyteller\.' "$MIMEAPPS"; then
    sed -i -E 's/ai\.storyteller\.[a-z-]+\.desktop;?//g; /=$/d' "$MIMEAPPS"
    ok "padrões de abertura removidos de $MIMEAPPS"
    removed=$((removed + 1))
  fi
  local mime_removed=0
  for p in "$MIME_DIR/packages"/ai.storyteller.*.xml; do
    rm_path "$p"
    mime_removed=1
  done
  if (( mime_removed )) && command -v update-mime-database &>/dev/null; then
    update-mime-database "$MIME_DIR" &>/dev/null || true
  fi

  # --- 4. O Launcher ----------------------------------------------------------
  info "ArtCraft Launcher..."
  rm_path "$APPIMAGE"
  rm_path "$DESKTOP_FILE"
  for p in "$ICON_DIR"/*/apps/"$APP_ID".*; do rm_path "$p"; done
  # Abrir no login, se foi ligado nas configurações dele.
  rm_path "$HOME/.config/autostart/$APP_ID.desktop"
  # Registro do que ele instalou (installed.json), downloads e cache de releases.
  rm_path "$APP_DIR"
  rm_path "$HOME/.cache/artcraft-launcher"
  rm_path "$HOME/.config/artcraft-launcher"
  # Preferências e estado da janela (app.ron), gravados pelo id do app.
  rm_path "$HOME/.local/share/$APP_ID"
  rm_path "$HOME/.config/$APP_ID"
  rm_path "$HOME/.cache/$APP_ID"
  rm_path "$HOME/.var/app/$APP_ID"

  # --- 5. Estúdio de IA (identifier Tauri: ai.artcraft.app) -------------------
  rm_path "$HOME/.config/ai.artcraft.app"
  rm_path "$HOME/.local/share/ai.artcraft.app"
  rm_path "$HOME/.cache/ai.artcraft.app"

  # --- 6. Caches do desktop ---------------------------------------------------
  if (( removed )); then
    command -v update-desktop-database &>/dev/null &&
      update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
    command -v gtk-update-icon-cache &>/dev/null &&
      gtk-update-icon-cache -qft "$ICON_DIR" 2>/dev/null || true
    ok "ArtCraft removido ($removed item(ns))."
  else
    skipped "nada do ArtCraft nesta máquina"
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

# O caminho entra na linha Exec e num sed sem escape, como no script do T3.
exec_unsafe='["`$\\|&]'
if [[ $APPIMAGE =~ $exec_unsafe ]]; then
  err "o caminho $APPIMAGE tem caracteres que um .desktop não consegue executar"
  _finish 1
fi

case "$(uname -m)" in
  x86_64|aarch64) arch="$(uname -m)" ;;
  *) err "a release não tem AppImage para $(uname -m)"; _finish 1 ;;
esac

# --- 1. Dependências ----------------------------------------------------------
# O runtime do AppImage monta o squashfs por fusermount3 a cada abertura.
info "Dependências do AppImage..."
pkg_install fuse3 || _finish 1
need_cmd curl || _finish 1

# --- 2. Baixar a release mais recente ----------------------------------------
# Uma vez instalado, o Launcher se atualiza sozinho (e o AppImage novo entra
# por rename em cima deste caminho). ARTCRAFT_FORCE=1 baixa de novo mesmo assim,
# para o caso de um arquivo corrompido.
tmp="$(mktemp -d)"
download="$APP_DIR/.ArtCraft-Launcher.AppImage.download"
trap 'rm -rf "$tmp" "$download"' EXIT

if [[ -x "$APPIMAGE" && "${ARTCRAFT_FORCE:-0}" != "1" ]]; then
  skipped "Launcher já em $APPIMAGE — ele se atualiza sozinho (ARTCRAFT_FORCE=1 rebaixa)"
  src="$APPIMAGE"
else
  info "Consultando a release mais recente..."
  if ! sums="$(curl -fsSL --retry 3 "$RELEASE_URL/SHA256SUMS.txt")"; then
    err "não deu para ler $RELEASE_URL/SHA256SUMS.txt"
    _finish 1
  fi
  # O SHA256SUMS.txt tem o nome do arquivo com a versão, então ele resolve as
  # duas coisas: qual AppImage baixar e com que hash conferir.
  line="$(grep -E "^[0-9a-f]{64}  artcraft-launcher-[0-9A-Za-z.-]+-linux-$arch\.AppImage$" <<<"$sums" | head -1 || true)"
  if [[ -z "$line" ]]; then
    err "a release não lista um AppImage linux-$arch — o layout mudou?"
    _finish 1
  fi
  read -r sha file <<<"$line"
  file_version="${file#artcraft-launcher-}"
  file_version="${file_version%-linux-*}"

  info "Baixando o ArtCraft Launcher $file_version..."
  mkdir -p "$APP_DIR"
  if ! curl -fL --retry 3 --progress-bar -o "$download" "$RELEASE_URL/$file"; then
    err "download falhou"
    _finish 1
  fi
  if [[ "$(sha256sum "$download" | cut -d' ' -f1)" != "$sha" ]]; then
    err "o download não bate com o SHA-256 publicado na release"
    _finish 1
  fi
  chmod 755 "$download"
  ok "download conferido contra o SHA256SUMS.txt da release"
  src="$download"
fi

# --- 3. Entry e ícones de dentro do AppImage ---------------------------------
# --appimage-extract não precisa de FUSE. O entry do upstream traz nome,
# categorias, keywords e StartupWMClass certos; só trocamos o Exec.
info "Extraindo entry e ícones do AppImage..."
if ! (cd "$tmp" &&
      "$src" --appimage-extract "$APP_ID.desktop" >/dev/null &&
      "$src" --appimage-extract "usr/share/icons/hicolor/*/apps/$APP_ID.*" >/dev/null); then
  err "não deu para extrair do AppImage"
  _finish 1
fi
entry_src="$tmp/squashfs-root/$APP_ID.desktop"
if [[ ! -f "$entry_src" ]]; then
  err "$APP_ID.desktop não existe dentro do AppImage — o layout mudou?"
  _finish 1
fi
# A chave é opcional no upstream; na falta dela vale a versão do nome do arquivo.
version="$(sed -n 's/^X-AppImage-Version=//p' "$entry_src")"
version="${version:-${file_version:-desconhecida}}"
ok "AppImage versão $version"

changed=0
for icon in "$tmp"/squashfs-root/usr/share/icons/hicolor/*/apps/"$APP_ID".*; do
  [[ -f "$icon" ]] || continue
  dest="$ICON_DIR/${icon#"$tmp/squashfs-root/usr/share/icons/hicolor/"}"
  cmp -s "$icon" "$dest" 2>/dev/null && continue
  install -Dm644 "$icon" "$dest"
  changed=$((changed + 1))
done
if (( changed )); then
  ok "$changed ícone(s) em $ICON_DIR"
  command -v gtk-update-icon-cache &>/dev/null &&
    gtk-update-icon-cache -qft "$ICON_DIR" 2>/dev/null || true
else
  skipped "ícones já em $ICON_DIR"
fi

# --- 4. Entry no menu ---------------------------------------------------------
# Exec expande códigos %, então um % literal no caminho vira %%. Aspas só se o
# caminho tiver espaço: o xdg-utils (xdg-open, xdg-mime) lê a primeira palavra
# do Exec com as aspas e o `command -v` falha; sem elas tudo funciona, e o GIO
# aceita dos dois jeitos.
exec_path="${APPIMAGE//%/%%}"
if [[ $exec_path == *[[:space:]]* ]]; then
  exec_cmd="\"$exec_path\""
else
  exec_cmd="$exec_path"
fi
# `0,/re/` limita ao primeiro Exec/TryExec, o do grupo [Desktop Entry]: um
# [Desktop Action] que o upstream venha a acrescentar fica com os argumentos dele.
entry_content="$(sed \
  -e "0,/^Exec=/s|^Exec=.*|Exec=$exec_cmd %U|" \
  -e "0,/^TryExec=/s|^TryExec=.*|TryExec=$APPIMAGE|" \
  -e '/^X-AppImage-Version=/d' "$entry_src")"
info "Entry $DESKTOP_FILE..."
if [[ -f "$DESKTOP_FILE" ]] && [[ "$(cat "$DESKTOP_FILE")" == "$entry_content" ]]; then
  skipped "$DESKTOP_FILE já atualizado"
else
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  printf '%s\n' "$entry_content" >"$DESKTOP_FILE"
  ok "$DESKTOP_FILE gerado"
fi

# O validador solta um "hint:" sobre a categoria PackageManager do upstream;
# só erro de verdade (nem warning, nem hint) deve parar o script. A saída é
# capturada antes do grep: com pipefail, o exit 1 do validador num erro real
# derrubaria o pipeline inteiro e o `if` cairia no ramo de sucesso.
if command -v desktop-file-validate &>/dev/null; then
  validate_out="$(desktop-file-validate "$DESKTOP_FILE" 2>&1 || true)"
  if grep -vE ': (warning|hint):' <<<"$validate_out" | grep .; then
    err "desktop-file-validate reportou erros"
    _finish 1
  fi
  ok "entry válido"
fi
command -v update-desktop-database &>/dev/null &&
  update-desktop-database "$(dirname "$DESKTOP_FILE")" 2>/dev/null || true

# --- 5. Ativar o AppImage -----------------------------------------------------
# Por último: com o arquivo no lugar, entry e ícones já existem.
if [[ "$src" == "$download" ]]; then
  mv -f "$download" "$APPIMAGE"
  ok "ArtCraft Launcher $version instalado em $APPIMAGE"
fi

# --- 6. Padrões de abertura ---------------------------------------------------
# `xdg-mime default` torna cada app da tabela o padrão dos seus tipos. Para um
# app que o Launcher ainda não instalou, só dos tipos que hoje não têm padrão
# nenhum (planilha, DOCX, PPTX numa Omarchy limpa): o GIO ignora um padrão cujo
# .desktop não existe, e no instante em que o Launcher escreve o entry (o id é
# sempre ai.storyteller.<app>.desktop) o padrão passa a valer, sem rodar isto
# de novo. Um tipo que já tem dono (PDF no Evince) só muda com o app instalado,
# senão o GIO cairia em qualquer outro handler do cache. A definição de MIME de
# dentro do AppImage (os formatos próprios, como .pcraft) só dá para copiar com
# o app instalado; o que faltar entra na próxima rodada. Tudo na home, sem sudo.
#
# O Launcher escreve o Exec dos entries dele entre aspas, e o xdg-utils
# (xdg-open, xdg-mime) não entende aspas: o GIO abre certo, o xdg-open não.
# Com o app instalado, tiramos as aspas quando o caminho não tem espaço. O
# Launcher regrava o entry ao atualizar o app, e a rodada seguinte conserta de
# novo; até lá só o xdg-open fica de fora.
info "Padrões de abertura..."
need_cmd xdg-mime "omarchy pkg add xdg-utils" || _finish 1

# mime_default_is <mime> <entry> — o entry já é o padrão desse tipo?
# Lê o mimeapps.list direto: o `xdg-mime query default` valida o Exec do entry
# e tropeça nas aspas que o Launcher escreve, devolvendo vazio.
mime_default_is() {
  awk -F= -v m="$1" -v e="$2" '
    index($0, "[") == 1 { indefault = ($0 == "[Default Applications]"); next }
    indefault && $1 == m { v = $2; sub(/;$/, "", v); if (v == e) found = 1 }
    END { exit !found }
  ' "$MIMEAPPS" 2>/dev/null
}

# mime_has_default <mime> — algum app instalado de verdade já é o padrão?
# O GIO só responde com um .desktop que existe, que é o que importa.
mime_has_default() {
  LANG=C gio mime "$1" 2>/dev/null | grep -q '^Default application'
}

mime_changed=0
for app in "${CRAFT_APPS[@]}"; do
  [[ -n "${MIME_DEFAULTS[$app]:-}" ]] || continue
  entry="ai.storyteller.$app.desktop"
  entry_file="$HOME/.local/share/applications/$entry"
  installed=0
  [[ -f "$entry_file" ]] && installed=1

  if (( installed )) && grep -qE '^Exec="[^"[:space:]\\$`]+" ' "$entry_file"; then
    sed -i -E 's|^Exec="([^"[:space:]\\$`]+)" |Exec=\1 |' "$entry_file"
    ok "$app: aspas tiradas do Exec do entry, para o xdg-open achar o app"
  fi

  # O AppImage mais novo do app, pelo número de versão no nome.
  appimage="$(ls -1 "$APPS_DIR/$app"-*.AppImage 2>/dev/null | sort -V | tail -1 || true)"
  xml="usr/share/mime/packages/ai.storyteller.$app.xml"
  if [[ -x "$appimage" ]]; then
    rm -rf "$tmp/squashfs-root"
    if (cd "$tmp" && "$appimage" --appimage-extract "$xml" >/dev/null 2>&1) &&
       [[ -f "$tmp/squashfs-root/$xml" ]] &&
       ! cmp -s "$tmp/squashfs-root/$xml" "$MIME_DIR/packages/ai.storyteller.$app.xml"; then
      install -Dm644 "$tmp/squashfs-root/$xml" "$MIME_DIR/packages/ai.storyteller.$app.xml"
      mime_changed=1
    fi
  fi

  set_n=0 kept=0 left=0
  for mime in ${MIME_DEFAULTS[$app]}; do
    if mime_default_is "$mime" "$entry"; then
      kept=$((kept + 1))
    elif (( installed )) || ! mime_has_default "$mime"; then
      xdg-mime default "$entry" "$mime"
      set_n=$((set_n + 1))
    else
      left=$((left + 1))
    fi
  done
  if (( set_n )); then
    ok "$app é o padrão de $set_n tipo(s) novo(s)$( (( kept )) && echo " ($kept já era)")"
  elif (( kept )); then
    skipped "$app já é o padrão dos seus $kept tipos"
  fi
  if (( ! installed )); then
    skipped "$app ainda não foi instalado no Launcher — o padrão vale assim que ele instalar$( (( left )) && echo "; $left tipo(s) com dono ficam como estão até lá")"
  fi
done
if (( mime_changed )); then
  if command -v update-mime-database &>/dev/null && update-mime-database "$MIME_DIR" &>/dev/null; then
    ok "definições de MIME dos apps registradas em $MIME_DIR"
  else
    err "update-mime-database falhou — os formatos próprios (.pcraft etc.) não serão reconhecidos"
  fi
fi

# --- 7. Estúdio de IA (opcional) ---------------------------------------------
if [[ "${ARTCRAFT_STUDIO:-0}" == "1" ]]; then
  info "Estúdio ArtCraft (AUR, build demorado)..."
  aur_install artcraft || _finish 1
  ok "estúdio instalado — abre com 'artcraft' no terminal (o pacote não traz entry no menu)"
else
  skipped "estúdio de IA não instalado (ARTCRAFT_STUDIO=1 instala o pacote artcraft do AUR)"
fi

ok "Pronto. Abra o ArtCraft Launcher pelo menu e instale só os apps que quiser."
echo ""
info "Os apps vão para ~/Applications como AppImage e são atualizados pelo próprio Launcher."
info "Para tirar tudo: $(basename "$0") --uninstall"
