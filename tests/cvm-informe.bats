#!/usr/bin/env bats
# Testes de mdr-US-003: parser do Informe Diario CVM filtrado pela watchlist.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/cvm-informe.sh"
  FAKE="$ROOT/tests/helpers/fake-cvm-http.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export CVM_HTTP_GET="$FAKE"
  export CVM_FETCH_LOG="$WORKDIR/fetch.log"
  export CVM_NOW=1788091200
  : > "$CVM_FETCH_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  local slug="$1"
  mkdir -p "$slug"
  : > "$slug/.env"
}

write_watchlist() {
  local slug="$1"
  shift
  python3 - "$slug" "$@" <<'PY'
import json, sys
slug = sys.argv[1]
cnpjs = sys.argv[2:]
with open(f"{slug}/watchlist-fundos.json", "w", encoding="utf-8") as fh:
    json.dump({"cnpjs": cnpjs}, fh)
PY
}

@test "uso sem args: falha com mensagem de uso citando ZIP/CSV da CVM" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"dados.cvm.gov.br"* ]]
  [[ "$output" == *"ZIP"* ]] || [[ "$output" == *"zip"* ]]
}

@test "parser extrai PL, cota, captacao e resgate do CSV/ZIP do informe diario" {
  seed_portfolio acme
  write_watchlist acme "12.345.678/0001-90"

  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
rows = json.loads(sys.argv[1])
assert isinstance(rows, list) and rows, rows
latest = [r for r in rows if r["dtComptc"] == "2026-08-28"]
assert len(latest) == 1, rows
row = latest[0]
assert row["cnpj"] == "12.345.678/0001-90"
assert row["vlQuota"] == 1.23456789
assert row["vlPatrimLiq"] == 999.50
assert row["captcDia"] == 20.00
assert row["resgDia"] == 5.00
' "$output"
  [ "$status" -eq 0 ]
  grep -q "inf_diario_fi_202608.zip" "$CVM_FETCH_LOG"
  grep -q "dados.cvm.gov.br" "$CVM_FETCH_LOG"
}

@test "watchlist filtra so os fundos informados e ignora os demais do ZIP" {
  seed_portfolio acme
  write_watchlist acme "12.345.678/0001-90"

  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  [[ "$output" == *"12.345.678/0001-90"* ]]
  [[ "$output" != *"98.765.432/0001-10"* ]]
}

@test "watchlist com dois CNPJs devolve ambos os fundos do ZIP" {
  seed_portfolio acme
  write_watchlist acme "12.345.678/0001-90" "98.765.432/0001-10"

  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  [[ "$output" == *"12.345.678/0001-90"* ]]
  [[ "$output" == *"98.765.432/0001-10"* ]]
}

@test "CNPJ na watchlist casa sem pontuacao com o CNPJ formatado do CSV" {
  seed_portfolio acme
  write_watchlist acme "12345678000190"

  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  [[ "$output" == *"12.345.678/0001-90"* ]]
  [[ "$output" != *"98.765.432/0001-10"* ]]
}

@test "segunda execucao no mesmo dia reusa o cache e nao dispara HTTP" {
  seed_portfolio acme
  write_watchlist acme "12.345.678/0001-90"

  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CVM_FETCH_LOG")" -eq 1 ]

  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  [[ "$output" == *"12.345.678/0001-90"* ]]
  [ "$(wc -l < "$CVM_FETCH_LOG")" -eq 1 ]
}

@test "execucao no dia seguinte refaz o download (batch diario)" {
  seed_portfolio acme
  write_watchlist acme "12.345.678/0001-90"

  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CVM_FETCH_LOG")" -eq 1 ]

  export CVM_NOW=1788177600
  run "$SCRIPT" acme 202608
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CVM_FETCH_LOG")" -eq 2 ]
}

@test "watchlist ausente ou vazia e rejeitada com valor recebido e formato esperado" {
  seed_portfolio acme
  run "$SCRIPT" acme 202608
  [ "$status" -ne 0 ]
  [[ "$output" == *"watchlist-fundos.json"* ]]
  [[ "$output" == *"cnpjs"* ]]
  [ ! -s "$CVM_FETCH_LOG" ]

  printf '%s\n' '{"cnpjs":[]}' > acme/watchlist-fundos.json
  run "$SCRIPT" acme 202608
  [ "$status" -ne 0 ]
  [[ "$output" == *"[]"* ]] || [[ "$output" == *"vazia"* ]] || [[ "$output" == *"vazio"* ]]
  [[ "$output" == *"cnpjs"* ]]
  [ ! -s "$CVM_FETCH_LOG" ]
}
