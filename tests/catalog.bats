#!/usr/bin/env bats
# Testes de pc-US-001: catalogo central de plugins por dominio.

setup() {
  CATALOG="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/catalog.json"
}

@test "catalog.json existe e e JSON valido" {
  [ -f "$CATALOG" ]
  run jq empty "$CATALOG"
  [ "$status" -eq 0 ]
}

@test "catalog cobre os 4 dominios exigidos" {
  run jq -r '.domains[].id' "$CATALOG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"research"* ]]
  [[ "$output" == *"risco-portfolio"* ]]
  [[ "$output" == *"dados-mercado"* ]]
  [[ "$output" == *"corretora-banco"* ]]
}

@test "toda entrada tem nome, repo, tipo e credencial declarados" {
  run jq -e '[.domains[].entries[] | select(.gap != true) | select((.name and .repo and .type and (.credencial | type == "boolean")) | not)] | length == 0' "$CATALOG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "dominio dados-mercado registra explicitamente o gap BR" {
  run jq -e '.domains[] | select(.id == "dados-mercado") | .entries[] | select(.gap == true and (.credencial == false))' "$CATALOG"
  [ "$status" -eq 0 ]
}
