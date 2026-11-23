#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
source "$ROOT/setup/lib/common.sh"

file="$TEST_TMP/config"

# --- append_block
printf 'original\n' >"$file"
append_block "$file" "meu/arquivo" 'dofile("meu/arquivo")' >/dev/null
append_block "$file" "meu/arquivo" 'dofile("meu/arquivo")' >/dev/null
[[ "$(grep -c 'meu/arquivo' "$file")" == 1 ]] || fail "append_block é idempotente" "$(cat "$file")"
grep -qx 'original' "$file" || fail "append_block preserva o arquivo" "$(cat "$file")"
pass "append_block acrescenta uma vez só"

if append_block "$TEST_TMP/nao-existe" m b >/dev/null 2>&1; then
  fail "append_block recusa arquivo ausente"
fi
[[ ! -e "$TEST_TMP/nao-existe" ]] || fail "append_block não cria arquivo ausente"
pass "append_block recusa arquivo ausente"

# --- insert_block_after: âncora literal, só a primeira ocorrência
printf 'a\nf(x.y)\nb\nf(x.y)\n' >"$file"
insert_block_after "$file" 'f(x.y)' 'NOVO' 'NOVO' >/dev/null
[[ "$(cat "$file")" == $'a\nf(x.y)\n\nNOVO\nb\nf(x.y)' ]] ||
  fail "insert_block_after insere depois da primeira âncora" "$(cat "$file")"
insert_block_after "$file" 'f(x.y)' 'NOVO' 'NOVO' >/dev/null
[[ "$(grep -c NOVO "$file")" == 1 ]] || fail "insert_block_after é idempotente" "$(cat "$file")"
pass "insert_block_after insere uma vez, depois da primeira âncora"

printf 'a\n' >"$file"
insert_block_after "$file" 'sumiu' 'NOVO' 'NOVO' >/dev/null
[[ "$(tail -n1 "$file")" == NOVO ]] || fail "insert_block_after cai para o fim sem a âncora" "$(cat "$file")"
pass "insert_block_after sem âncora cai para o fim"

# --- mimeapps_remove
printf '[Default Applications]\ntext/plain=a.desktop;meu-x.desktop;\nimage/png=meu-x.desktop;\ntext/html=\n' >"$file"
mimeapps_remove "$file" 'meu-.*\.desktop' || fail "mimeapps_remove acha as entradas"
[[ "$(cat "$file")" == $'[Default Applications]\ntext/plain=a.desktop;\ntext/html=' ]] ||
  fail "mimeapps_remove tira só o que casa" "$(cat "$file")"
if mimeapps_remove "$file" 'meu-.*\.desktop'; then
  fail "mimeapps_remove retorna 1 sem nada a remover"
fi
pass "mimeapps_remove tira só as entradas que casam"
