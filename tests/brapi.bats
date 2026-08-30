#!/usr/bin/env bats
# Testes de mdr-US-002: client brapi.dev com cache local e token opcional.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/brapi-quote.sh"
  FAKE="$ROOT/tests/helpers/fake-brapi-http.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export BRAPI_HTTP_GET="$FAKE"
  export BRAPI_FETCH_LOG="$WORKDIR/fetch.log"
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

@test "uso sem args: falha com mensagem de uso e documenta fallback yfinance .SA" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"yfinance"* ]]
  [[ "$output" == *".SA"* ]]
}

@test "tickers gratuitos PETR4 VALE3 MGLU3 ITUB4 funcionam sem token e gravam cache" {
  seed_portfolio acme
  for ticker in PETR4 VALE3 MGLU3 ITUB4; do
    run "$SCRIPT" acme "$ticker"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$ticker"* ]]
    [ -f "acme/_cache/brapi/${ticker}.json" ]
  done
  [ "$(wc -l < "$BRAPI_FETCH_LOG")" -eq 4 ]
}

@test "segunda consulta do mesmo ticker reusa o cache e nao dispara HTTP" {
  seed_portfolio acme
  run "$SCRIPT" acme PETR4
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BRAPI_FETCH_LOG")" -eq 1 ]

  run "$SCRIPT" acme PETR4
  [ "$status" -eq 0 ]
  [[ "$output" == *"PETR4"* ]]
  [ "$(wc -l < "$BRAPI_FETCH_LOG")" -eq 1 ]
}

@test "ticker nao-gratuito sem token e rejeitado com valor recebido e formato esperado" {
  seed_portfolio acme
  run "$SCRIPT" acme WEGE3
  [ "$status" -ne 0 ]
  [[ "$output" == *"WEGE3"* ]]
  [[ "$output" == *"BRAPI_TOKEN"* ]]
  [ ! -s "$BRAPI_FETCH_LOG" ]
}

@test "ticker nao-gratuito com token consulta a API e nao vaza a credencial no output" {
  seed_portfolio acme
  printf 'BRAPI_TOKEN=segredo-teste\n' > acme/.env
  run "$SCRIPT" acme WEGE3
  [ "$status" -eq 0 ]
  [[ "$output" == *"WEGE3"* ]]
  [[ "$output" != *"segredo-teste"* ]]
  grep -q 'token=segredo-teste' "$BRAPI_FETCH_LOG"
  [ -f "acme/_cache/brapi/WEGE3.json" ]
}

@test "cache e isolado entre portfolios" {
  seed_portfolio acme
  seed_portfolio beta
  run "$SCRIPT" acme PETR4
  [ "$status" -eq 0 ]
  [ -f "acme/_cache/brapi/PETR4.json" ]
  [ ! -e "beta/_cache/brapi/PETR4.json" ]

  run "$SCRIPT" beta PETR4
  [ "$status" -eq 0 ]
  [ -f "beta/_cache/brapi/PETR4.json" ]
  [ "$(wc -l < "$BRAPI_FETCH_LOG")" -eq 2 ]
}
