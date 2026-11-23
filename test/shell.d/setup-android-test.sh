#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

if [[ ! -w /dev/kvm ]]; then
  skip "sem /dev/kvm, o setup-android.sh para antes do que é testado aqui"
  exit 0
fi

SCRIPT="$ROOT/setup/setup-android.sh"
SDK="$HOME/Android/Sdk"
AVD_HOME="$HOME/.android/avd"
IMAGE_DIR="system-images/android-36/google_apis_playstore/x86_64"
LAUNCHER="$HOME/.local/bin/android-emu"
export CALLS="$TEST_TMP/calls" SDK AVD_HOME IMAGE_DIR

# As bordas do script: pacotes, Java e rede. Cada chamada fica registrada.
stub "$STUBS/pacman" <<<'exit 0'
stub "$STUBS/mise" <<<'echo "mise $*" >>"$CALLS"; [[ $1 == where ]] && echo "$HOME/java"; exit 0'
stub "$STUBS/curl" <<'STUB'
echo "curl $*" >>"$CALLS"
while (( $# )); do [[ $1 == -o ]] && cp "$TEST_TMP/tools.zip" "$2"; shift; done
STUB

# Zip válido e com o layout certo, para só o SHA-256 poder recusá-lo.
stub "$TEST_TMP/zip/cmdline-tools/bin/sdkmanager" <<<'exit 0'
stub "$TEST_TMP/zip/cmdline-tools/bin/avdmanager" <<<'exit 0'
bsdtar -C "$TEST_TMP/zip" --format zip -cf "$TEST_TMP/tools.zip" cmdline-tools

reset() {
  rm -rf "${HOME:?}"
  mkdir -p "$HOME"
  : >"$CALLS"
}

fake_tools() {
  stub "$SDK/cmdline-tools/latest/bin/sdkmanager" <<'STUB'
echo "sdkmanager $*" >>"$CALLS"
[[ ${SDK_BROKEN:-} ]] && exit 0
mkdir -p "$SDK/licenses" "$SDK/.sdk"
echo hash >"$SDK/licenses/android-sdk-license"
for dir in platform-tools emulator "$IMAGE_DIR"; do
  mkdir -p "$SDK/$dir" && touch "$SDK/$dir/package.xml"
done
printf '#!/bin/bash\necho "adb $*" >>"$CALLS"\n[[ $* == *getprop* ]] && echo 1\nexit 0\n' >"$SDK/platform-tools/adb"
chmod +x "$SDK/platform-tools/adb"
STUB
  stub "$SDK/cmdline-tools/latest/bin/avdmanager" <<'STUB'
echo "avdmanager $*" >>"$CALLS"
mkdir -p "$AVD_HOME/pixel.avd"
printf 'hw.keyboard=no\nhw.keyboard.lid=yes\nhw.lcd.width=1080\n' >"$AVD_HOME/pixel.avd/config.ini"
touch "$AVD_HOME/pixel.ini"
STUB
}

run() { bash "$SCRIPT" "$@" >"$TEST_TMP/out" 2>&1; }
out() { cat "$TEST_TMP/out" "$CALLS"; }

# --- licença
for answer in "" n; do
  reset
  if run <<<"$answer"; then
    fail "sem aceitar a licença o script falha (resposta '$answer')" "$(out)"
  fi
  [[ ! -s "$CALLS" && ! -e "$SDK" ]] || fail "sem licença nada é baixado" "$(out)"
done
reset
if run </dev/null; then
  fail "sem terminal o script não aceita a licença sozinho" "$(out)"
fi
[[ ! -s "$CALLS" ]] || fail "sem terminal nada é baixado" "$(out)"
pass "licença não aceita: para antes de baixar qualquer coisa"

# --- download adulterado
reset
if run <<<s; then
  fail "download que não bate com o SHA-256 é recusado" "$(out)"
fi
grep -q '^curl ' "$CALLS" || fail "o caso do SHA-256 chegou ao download" "$(out)"
[[ ! -e "$SDK/cmdline-tools/latest" ]] || fail "download recusado não é instalado"
[[ -z "$(find "$SDK" -name '.setup.*')" ]] || fail "download recusado não deixa sobras"
pass "download adulterado é recusado e não deixa sobras"

# --- sdkmanager sai com 0 sem instalar
reset
fake_tools
if SDK_BROKEN=1 run <<<s; then
  fail "pacote faltando depois do sdkmanager é falha" "$(out)"
fi
[[ ! -e "$LAUNCHER" ]] || fail "sem os pacotes o android-emu não é gerado"
pass "sdkmanager que não instala nada é detectado"

# --- instalação
reset
fake_tools
run <<<s || fail "instala com a licença aceita" "$(out)"
config="$AVD_HOME/pixel.avd/config.ini"
[[ "$(sort "$config")" == "$(printf '%s\n' hw.cpu.ncore=4 hw.keyboard.lid=yes hw.keyboard=yes hw.lcd.width=1080 hw.ramSize=3072 | sort)" ]] ||
  fail "config do celular: troca só as chaves pedidas" "$(cat "$config")"
[[ -x "$LAUNCHER" ]] && bash -n "$LAUNCHER" || fail "android-emu é executável e válido"
pass "instala, configura o celular e gera o android-emu"

# --- rodar de novo
echo 'hw.lcd.width=1440' >"$config"
: >"$CALLS"
run </dev/null || fail "rodar de novo funciona sem perguntar" "$(out)"
if grep -qE '^(curl|sdkmanager|avdmanager|mise install)' "$CALLS"; then
  fail "rodar de novo não reinstala nada" "$(out)"
fi
[[ "$(cat "$config")" == 'hw.lcd.width=1440' ]] || fail "rodar de novo preserva a config do celular"
pass "rodar de novo só confere"

# --- android-emu
# O `adb shell` passa a linha para o shell do celular, então uma aspa na URL
# não pode fechar a string.
: >"$CALLS"
"$LAUNCHER" "https://x.test/?a=1&b='; reboot; '" >/dev/null
grep -qF "am start -a android.intent.action.VIEW -d 'https://x.test/?a=1&b=%27; reboot; %27' com.android.chrome" "$CALLS" ||
  fail "android-emu escapa aspas na URL" "$(cat "$CALLS")"
pass "android-emu abre a URL com as aspas escapadas"

# --- uninstall
for shared in "$SDK/platforms/android-36" "$SDK/system-images/android-35/google_apis/x86_64" "$AVD_HOME/outro.ini"; do
  reset
  fake_tools
  run <<<s || fail "instala para o uninstall" "$(out)"
  if [[ "$shared" == *.ini ]]; then touch "$shared"; else mkdir -p "$shared"; fi
  run --uninstall || fail "--uninstall funciona com $shared" "$(out)"
  [[ -d "$SDK" && -e "$shared" ]] || fail "--uninstall mantém o SDK usado por ${shared#"$HOME"/}" "$(out)"
  [[ ! -e "$AVD_HOME/pixel.avd" && ! -e "$AVD_HOME/pixel.ini" && ! -e "$LAUNCHER" ]] ||
    fail "--uninstall tira o celular e o comando mesmo mantendo o SDK"
done
pass "--uninstall mantém o SDK que tem outro uso"

reset
fake_tools
run <<<s || fail "instala para o uninstall" "$(out)"
run --uninstall || fail "--uninstall funciona" "$(out)"
[[ ! -e "$SDK" ]] || fail "--uninstall remove o SDK sem outro uso" "$(out)"
pass "--uninstall remove o SDK que só este script usa"
