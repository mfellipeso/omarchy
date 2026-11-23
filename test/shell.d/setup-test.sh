#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

for script in "$ROOT"/setup/*.sh "$ROOT"/setup/lib/*.sh; do
  bash -n "$script" 2>"$TEST_TMP/err" || fail "sintaxe de ${script#"$ROOT"/}" "$(cat "$TEST_TMP/err")"
done
pass "todos os scripts têm sintaxe válida"

# Um script fora da lista do setup.sh nunca roda numa máquina nova.
for script in "$ROOT"/setup/setup-*.sh; do
  name="$(basename "$script")"
  [[ -x "$script" ]] || fail "$name é executável"
  grep -qxE " *$name" "$ROOT/setup/setup.sh" || fail "$name está na lista do setup.sh"
done
pass "todo setup-*.sh é executável e está na lista do setup.sh"

while read -r name; do
  [[ -f "$ROOT/setup/$name" ]] || fail "$name, listado no setup.sh, existe"
done < <(grep -oE '^ +setup-[a-z0-9-]+\.sh$' "$ROOT/setup/setup.sh")
pass "todo script listado no setup.sh existe"
