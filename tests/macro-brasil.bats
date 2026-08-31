#!/usr/bin/env bats
# Testes do client BCB SGS com cache local por portfolio.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/macro-brasil.sh"
  FAKE="$ROOT/tests/helpers/fake-bcb-sgs.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export MACRO_HTTP_GET="$FAKE"
  export MACRO_FETCH_LOG="$WORKDIR/fetch.log"
  export MACRO_NOW=1000
  : > "$MACRO_FETCH_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
}

@test "consulta Selic e CDI e normaliza datas no JSON informativo" {
  seed_portfolio acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run jq -e '
    .metaSelicAnual == 15 and
    .metaSelicData == "2026-08-29" and
    .cdiDiario == 0.05 and
    .cdiData == "2026-08-30" and
    .fonte == "BCB SGS" and
    .aviso == "Dado informativo, nao e recomendacao de investimento." and
    ((keys | sort) == ["aviso", "cdiData", "cdiDiario", "fonte", "metaSelicAnual", "metaSelicData"])
  ' <<< "$output"
  [ "$status" -eq 0 ]
  [ -f "acme/_cache/macro/selic-cdi.json" ]
  [ "$(wc -l < "$MACRO_FETCH_LOG")" -eq 2 ]
}

@test "segunda chamada dentro do TTL reutiliza o cache" {
  seed_portfolio acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MACRO_FETCH_LOG")" -eq 2 ]

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [[ "$output" == *'"metaSelicAnual":15'* ]]
  [ "$(wc -l < "$MACRO_FETCH_LOG")" -eq 2 ]
}

@test "cache expirado refaz a consulta das duas series" {
  seed_portfolio acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  export MACRO_NOW=87401

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$MACRO_FETCH_LOG")" -eq 4 ]
}

@test "falha de fetch propaga erro claro e nao cria cache" {
  seed_portfolio acme
  export MACRO_FAKE_FAIL=1

  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]
  [[ "$output" == *"BCB SGS"* ]]
  [ ! -e "acme/_cache/macro/selic-cdi.json" ]
}

@test "portfolio invalido e rejeitado antes do fetch" {
  run "$SCRIPT" inexistente
  [ "$status" -ne 0 ]
  [[ "$output" == *"Portfolio invalido"* ]]
  [[ "$output" == *"recebido 'inexistente'"* ]]
  [[ "$output" == *"esperado diretorio de portfolio existente"* ]]
  [ ! -s "$MACRO_FETCH_LOG" ]
}
