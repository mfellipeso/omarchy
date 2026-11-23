#!/bin/bash
set -euo pipefail

# =============================================================================
# ANDROID — Pixel 9 virtual com Chrome, para ver sites num Android de verdade
#
# Emulador oficial do Google (QEMU + KVM), sem Android Studio e sem AUR: as
# command line tools vêm direto de dl.google.com e o resto (emulador, adb e a
# imagem do Android com Play Store) sai do sdkmanager delas. Tudo na home.
#
# O Java só é usado pelo sdkmanager e pelo avdmanager, então vem do mise e não
# é ativado em lugar nenhum: o JAVA_HOME existe só dentro deste script.
#
# O sdkmanager atual só mostra a licença do Android SDK e grava o aceite sem
# perguntar, então quem pergunta é este script, uma vez, antes de baixar
# qualquer coisa. Sem terminal para responder, ele para.
#
# O comando `android-emu [URL]` abre o celular, e a URL se vier uma. A janela no
# tamanho do Pixel 9 é regra do Hyprland, em hypr/windows.lua.
#
# Rodar de novo não atualiza nada, só confere; para atualizar, `sdkmanager
# --update`. `setup-android.sh --uninstall` apaga o celular, o comando e o SDK
# (este, só se nada além deste script o usa).
# =============================================================================

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

export ANDROID_HOME="$HOME/Android/Sdk"
# Sem isto o avdmanager pode preferir o XDG_CONFIG_HOME ao ~/.android.
export ANDROID_USER_HOME="$HOME/.android"

# O build das tools é fixado com o SHA-256: elas só servem para o bootstrap, e
# o repositório do Google publica apenas SHA-1.
TOOLS_ZIP="commandlinetools-linux-16111833_latest.zip"
TOOLS_SHA="0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8"
TOOLS_URL="https://dl.google.com/android/repository/$TOOLS_ZIP"
TOOLS_DIR="$ANDROID_HOME/cmdline-tools/latest"

LICENSE_URL="https://developer.android.com/studio/terms"
LICENSE_FILE="$ANDROID_HOME/licenses/android-sdk-license"

JAVA="java@temurin-21"
IMAGE="system-images;android-36;google_apis_playstore;x86_64"
DEVICE="pixel_9"
AVD="pixel"
AVD_DIR="$ANDROID_USER_HOME/avd/$AVD.avd"
AVD_INI="$ANDROID_USER_HOME/avd/$AVD.ini"
LAUNCHER="$HOME/.local/bin/android-emu"

# PIDs do emulador do nosso AVD, aberto a partir do nosso SDK.
emulator_pids() {
  local pid
  # O nome do processo é cortado em 15 caracteres pelo kernel.
  for pid in $(pgrep -x qemu-system-x86 || true); do
    [[ "$(readlink "/proc/$pid/exe" 2>/dev/null)" == "$ANDROID_HOME/"* ]] || continue
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "-avd $AVD " || continue
    echo "$pid"
  done
  return 0
}

uninstall() {
  kill_and_wait emulator_pids "o emulador" || return 1

  rm -rf -- "$AVD_DIR" "$AVD_INI" "$LAUNCHER" "$ANDROID_USER_HOME/$AVD.log"
  ok "celular '$AVD' e $LAUNCHER removidos"

  # O SDK é o mesmo do Android Studio. Outro AVD, ou qualquer pacote que este
  # script não instala (platforms, build-tools, outra imagem...), indica que
  # mais alguém o usa.
  local extra
  extra="$(
    find "$ANDROID_USER_HOME/avd" -mindepth 1 -maxdepth 1 -name '*.ini' 2>/dev/null || true
    find "$ANDROID_HOME" -mindepth 1 -maxdepth 1 -type d ! -name '.*' \
      ! -name cmdline-tools ! -name emulator ! -name licenses \
      ! -name platform-tools ! -name system-images 2>/dev/null || true
    find "$ANDROID_HOME/system-images" -mindepth 3 -maxdepth 3 -type d \
      ! -path "$ANDROID_HOME/${IMAGE//;//}" 2>/dev/null || true
  )"
  if [[ -n "$extra" ]]; then
    skipped "$ANDROID_HOME mantido, há mais coisa usando: ${extra//$'\n'/, }"
  else
    # O servidor do adb roda de dentro do SDK e sobreviveria a ele.
    "$ANDROID_HOME/platform-tools/adb" kill-server 2>/dev/null || true
    rm -rf -- "$ANDROID_HOME"
    rmdir "$(dirname "$ANDROID_HOME")" 2>/dev/null || true
    ok "$ANDROID_HOME removido"
  fi
  skipped "$ANDROID_USER_HOME e o $JAVA do mise ficam (podem ter outro uso)"
}

case "${1:-}" in
  --uninstall)
    uninstall || _finish 1
    _finish 0
    ;;
  "") ;;
  *)
    echo "Uso: $(basename "$0") [--uninstall]" >&2
    _finish 1
    ;;
esac

# --- 1. KVM e dependências ----------------------------------------------------
info "Verificando o KVM..."
if [[ ! -w /dev/kvm ]]; then
  err "/dev/kvm sem acesso — ligue a virtualização (AMD-V/VT-x) na BIOS"
  _finish 1
fi
ok "/dev/kvm acessível"

pkg_install unzip curl || _finish 1
need_cmd mise "vem com o Omarchy" || _finish 1

# --- 2. Licença do Android SDK -------------------------------------------------
info "Verificando a licença do Android SDK..."
if [[ -s "$LICENSE_FILE" ]]; then
  skipped "licença já aceita"
else
  echo "    Leia os termos: $LICENSE_URL"
  answer=""
  read -r -p "    Você aceita a licença do Android SDK? [s/N] " answer || true
  if [[ "${answer,,}" != "s" ]]; then
    err "licença não aceita — nada foi instalado"
    _finish 1
  fi
  # Quem grava o $LICENSE_FILE é o sdkmanager, no passo 5.
fi

# --- 3. Java (mise, sem ativar) -----------------------------------------------
info "Verificando o $JAVA..."
if JAVA_HOME="$(mise where "$JAVA" 2>/dev/null)"; then
  skipped "Java já em $JAVA_HOME"
else
  if ! mise install "$JAVA"; then
    err "mise install $JAVA falhou"
    _finish 1
  fi
  JAVA_HOME="$(mise where "$JAVA")"
  ok "Java instalado em $JAVA_HOME"
fi
export JAVA_HOME

# --- 4. Command line tools ----------------------------------------------------
info "Verificando as command line tools..."
if [[ -x "$TOOLS_DIR/bin/sdkmanager" && -x "$TOOLS_DIR/bin/avdmanager" ]]; then
  skipped "command line tools já em $TOOLS_DIR"
else
  mkdir -p "$(dirname "$TOOLS_DIR")"
  # No mesmo FS do destino, para o mv ser um rename.
  work="$(mktemp -d "$ANDROID_HOME/.setup.XXXXXX")"
  trap 'rm -rf "$work"' EXIT
  if ! curl -fL --retry 3 --progress-bar -o "$work/$TOOLS_ZIP" "$TOOLS_URL"; then
    err "falha ao baixar $TOOLS_URL"
    _finish 1
  fi
  if [[ "$(sha256sum "$work/$TOOLS_ZIP" | cut -d' ' -f1)" != "$TOOLS_SHA" ]]; then
    err "o download não bate com o SHA-256 fixado no script"
    _finish 1
  fi
  if ! unzip -q "$work/$TOOLS_ZIP" -d "$work" || [[ ! -x "$work/cmdline-tools/bin/sdkmanager" ]]; then
    err "sdkmanager não encontrado dentro do $TOOLS_ZIP — o Google mudou o layout?"
    _finish 1
  fi
  rm -rf -- "$TOOLS_DIR"
  mv "$work/cmdline-tools" "$TOOLS_DIR"
  rm -rf "$work"
  trap - EXIT
  ok "command line tools em $TOOLS_DIR"
fi

# --- 5. Emulador, adb e imagem do Android -------------------------------------
# package.xml é gravado pelo sdkmanager no fim de cada pacote: pasta sem ele é
# instalação interrompida.
missing_packages() {
  local pkg
  for pkg in platform-tools emulator "$IMAGE"; do
    [[ -f "$ANDROID_HOME/${pkg//;//}/package.xml" ]] || echo "$pkg"
  done
}

info "Verificando os pacotes do SDK..."
mapfile -t missing < <(missing_packages)
if [[ ${#missing[@]} -eq 0 ]]; then
  skipped "platform-tools, emulator e $IMAGE já instalados"
else
  info "Instalando (até uns 2,4 GB): ${missing[*]}"
  "$TOOLS_DIR/bin/sdkmanager" --sdk_root="$ANDROID_HOME" "${missing[@]}" || true
  # Conferido no disco: o sdkmanager pode sair com 0 sem ter instalado.
  if [[ -n "$(missing_packages)" ]]; then
    err "faltou instalar: $(missing_packages | tr '\n' ' ')(falha de rede?)"
    _finish 1
  fi
  ok "pacotes do SDK instalados"
fi

# --- 6. Celular virtual -------------------------------------------------------
# set_cfg <chave> <valor> — no config.ini do AVD
set_cfg() {
  local re="${1//./\\.}"
  sed -i -E "/^$re *=/d" "$AVD_DIR/config.ini"
  echo "$1=$2" >>"$AVD_DIR/config.ini"
}

info "Verificando o celular '$AVD'..."
if [[ -f "$AVD_INI" && -f "$AVD_DIR/config.ini" ]]; then
  skipped "celular '$AVD' já existe (config mantida)"
else
  # O "no" responde à pergunta do perfil de hardware personalizado.
  if ! "$TOOLS_DIR/bin/avdmanager" create avd -n "$AVD" -k "$IMAGE" -d "$DEVICE" <<<"no" >/dev/null ||
    [[ ! -f "$AVD_DIR/config.ini" ]]; then
    err "avdmanager não criou o celular '$AVD'"
    _finish 1
  fi
  set_cfg hw.keyboard yes
  set_cfg hw.ramSize 3072
  set_cfg hw.cpu.ncore 4
  ok "celular '$AVD' ($DEVICE) criado"
fi

# --- 7. Comando android-emu ---------------------------------------------------
# -gpu host: no automático o emulador desconfia do driver AMD e cai para
# renderização por software.
info "Comando $LAUNCHER..."
launcher_content="$(
  cat <<'EOF'
#!/usr/bin/env bash
# Gerado por setup-android.sh — não edite na mão.
# Abre o Pixel virtual (AVD "pixel"). Uso: android-emu [URL]
set -euo pipefail
export ANDROID_HOME="$HOME/Android/Sdk" ANDROID_USER_HOME="$HOME/.android"
adb="$ANDROID_HOME/platform-tools/adb"
serial=emulator-5554

if ! "$adb" -s "$serial" get-state >/dev/null 2>&1; then
  setsid "$ANDROID_HOME/emulator/emulator" -avd pixel -port 5554 \
    -gpu host -no-boot-anim -no-metrics >"$ANDROID_USER_HOME/pixel.log" 2>&1 </dev/null &
fi

for _ in $(seq 150); do
  [[ $("$adb" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r') == 1 ]] && ok=1 && break
  sleep 2
done
[[ ${ok:-} ]] || { echo "Android não subiu; veja $ANDROID_USER_HOME/pixel.log" >&2; exit 1; }

# mostra o teclado virtual mesmo usando o teclado do PC
"$adb" -s "$serial" shell settings put secure show_ime_with_hard_keyboard 1 </dev/null
if [[ ${1:-} ]]; then
  "$adb" -s "$serial" shell "am start -a android.intent.action.VIEW -d '${1//\'/%27}' com.android.chrome" </dev/null
fi
EOF
)"
if [[ -x "$LAUNCHER" ]] && [[ "$(cat "$LAUNCHER")" == "$launcher_content" ]]; then
  skipped "$LAUNCHER já atualizado"
else
  mkdir -p "$(dirname "$LAUNCHER")"
  printf '%s\n' "$launcher_content" >"$LAUNCHER"
  chmod +x "$LAUNCHER"
  ok "$LAUNCHER gerado"
fi

ok "Pronto. Rode 'android-emu' ou 'android-emu https://exemplo.com'."
info "Site local: http://10.0.2.2:PORTA dentro do celular é o localhost deste PC."
