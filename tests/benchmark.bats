#!/usr/bin/env bats
# Testes de fh-US-003: benchmark BR via brapi.dev.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/benchmark-quote.sh"
  FAKE_HISTORY="$ROOT/tests/helpers/fake-brapi-history.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export BRAPI_HTTP_GET="$FAKE_HISTORY"
  export BRAPI_FETCH_LOG="$WORKDIR/fetch.log"
  export BRAPI_NOW=1767225600
  : > "$BRAPI_FETCH_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  local slug="$1"
  mkdir -p "$slug"
  : > "$slug/.env"
}

@test "consulta Ibovespa via brapi com historico de 3 meses, token e cache" {
  seed_portfolio acme
  printf 'BRAPI_TOKEN=segredo-teste\n' > acme/.env

  run "$SCRIPT" acme br
  [ "$status" -eq 0 ]
  first_output="$output"
  [ "$(wc -l < "$BRAPI_FETCH_LOG")" -eq 1 ]
  [ "$(cat "$BRAPI_FETCH_LOG")" = "https://brapi.dev/api/quote/^BVSP?range=3mo&interval=1d&token=segredo-teste" ]
  run python3 -c '
import json, sys
payload = json.loads(sys.argv[1])
assert payload["results"][0]["symbol"] == "^BVSP", payload
assert payload["results"][0]["historicalDataPrice"], payload
' "$first_output"
  [ "$status" -eq 0 ]

  cache="acme/_cache/brapi/^BVSP-3mo-1d.json"
  [ -f "$cache" ]
  run jq -e --argjson expected "$first_output" '.payload == $expected' "$cache"
  [ "$status" -eq 0 ]

  run "$SCRIPT" acme br
  [ "$status" -eq 0 ]
  second_output="$output"
  run python3 -c '
import json, sys
assert json.loads(sys.argv[1]) == json.loads(sys.argv[2])
' "$first_output" "$second_output"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BRAPI_FETCH_LOG")" -eq 1 ]
}

@test "mercado br preserva rejeicao do cliente quando falta BRAPI_TOKEN" {
  seed_portfolio acme

  run "$SCRIPT" acme br
  [ "$status" -ne 0 ]
  [[ "$output" == *"BRAPI_TOKEN"* ]]
  [ ! -s "$BRAPI_FETCH_LOG" ]
  [ ! -e "acme/_cache/brapi/^BVSP-3mo-1d.json" ]
}

@test "mercado diferente de br e rejeitado sem consultar a API" {
  seed_portfolio acme

  run "$SCRIPT" acme us
  [ "$status" -ne 0 ]
  [[ "$output" == *"Mercado invalido"* ]]
  [[ "$output" == *"us"* ]]
  [[ "$output" == *"br"* ]]
  [ ! -s "$BRAPI_FETCH_LOG" ]
}

@test "sem slug e mercado exibe uso do contrato" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso: bin/benchmark-quote.sh <slug> br"* ]]
}
