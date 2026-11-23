#!/bin/bash
# Base dos testes: `source` no começo de cada *-test.sh. Mesmo contrato do
# base-test.sh do Omarchy: pass/skip/fail, e fail encerra o arquivo.

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "use com source a partir de um *-test.sh" >&2
  exit 1
fi

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
export ROOT

# HOME descartável. A sessão exporta os XDG apontando para a home de verdade, e
# um script sob teste apagaria arquivos reais por eles; sem os XDG, seguem HOME.
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
export HOME="$TEST_TMP/home"
# Comandos falsos ficam aqui, na frente do PATH.
STUBS="$TEST_TMP/bin"
mkdir -p "$HOME" "$STUBS"
export TEST_TMP
export PATH="$STUBS:$PATH"

pass() { printf 'ok - %s\n' "$1"; }
skip() { printf 'ok - %s # SKIP\n' "$1"; }
fail() {
  [[ -n "${2:-}" ]] && printf '%s\n' "$2" >&2
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

# stub <caminho> — cria um executável com o corpo lido do stdin
stub() {
  mkdir -p "$(dirname "$1")"
  { echo '#!/bin/bash'; cat; } >"$1"
  chmod +x "$1"
}
