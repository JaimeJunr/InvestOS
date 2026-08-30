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

# Testes de pc-US-002: entradas declaram credencial exigida (sim/nao) e as de
# credencial variavel carregam disclaimer explicando a variabilidade.

@test "entradas de dados-mercado e corretora-banco (nao-gap) exigem credencial" {
  run jq -e '[.domains[] | select(.id == "dados-mercado" or .id == "corretora-banco") | .entries[] | select(.gap != true) | select(.credencial == true)] | length' "$CATALOG"
  [ "$status" -eq 0 ]
  total=$(jq '[.domains[] | select(.id == "dados-mercado" or .id == "corretora-banco") | .entries[] | select(.gap != true)] | length' "$CATALOG")
  [ "$output" = "$total" ]
}

@test "entradas de research com credencial variavel declaram disclaimer explicito" {
  run jq -e '[.domains[].entries[] | select(.name == "claude-trading-skills" or .name == "quant_investing_skills" or .name == "family-office") | select(.credencial == false and (.disclaimer | type == "string") and (.disclaimer | contains("vari")))] | length == 4' "$CATALOG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

# Teste de pc-US-003: gap de dados de mercado BR registrado explicitamente,
# nao omitido e nao maquiado como "em breve".

@test "gap BR de dados-mercado tem disclaimer visivel e nao maquiado como em breve" {
  run jq -e '.domains[] | select(.id == "dados-mercado") | .entries[] | select(.gap == true) | select((.disclaimer | type == "string") and (.disclaimer | length > 0) and (.disclaimer | ascii_downcase | contains("em breve") | not))' "$CATALOG"
  [ "$status" -eq 0 ]
}
