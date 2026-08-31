#!/usr/bin/env bats
# Testes de registro de proventos (dividendos/JCP/rendimentos) em proventos.json.
# Espelha o mesmo padrao de bin/transacao.sh (registrar) + um modo importar em lote.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/provento.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
  : > "$1/.env"
}

@test "sem argumentos: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "registrar grava um provento novo em proventos.json" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 dividendo acoes 6.13 6.13 2026-12-21
  [ "$status" -eq 0 ]
  run jq -e '. == [{data: "2026-12-21", ticker: "PETR4", tipo: "dividendo", classe: "acoes", valorBruto: 6.13, valorLiquido: 6.13}]' acme/proventos.json
  [ "$status" -eq 0 ]
}

@test "registrar sem data usa a data de hoje" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar HGLG11 rendimento fiis 1.5 1.5
  [ "$status" -eq 0 ]
  hoje="$(date +%Y-%m-%d)"
  run jq -e --arg hoje "$hoje" '.[0].data == $hoje' acme/proventos.json
  [ "$status" -eq 0 ]
}

@test "tipo invalido e rejeitado com valor recebido e esperado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 bonus acoes 1 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"bonus"* ]]
  [[ "$output" == *"dividendo"* ]]
  [ ! -e "acme/proventos.json" ]
}

@test "valorBruto ou valorLiquido invalido (zero, negativo, nao-numero) e rejeitado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 dividendo acoes 0 0
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar PETR4 dividendo acoes -1 -1
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar PETR4 dividendo acoes abacate 1
  [ "$status" -ne 0 ]
  [ ! -e "acme/proventos.json" ]
}

@test "valorLiquido maior que valorBruto e rejeitado (retencao nao pode ser negativa)" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 jcp acoes 5.0 6.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [ ! -e "acme/proventos.json" ]
}

@test "jcp com retencao (liquido menor que bruto) e aceito normalmente" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar WEGE3 jcp acoes 10.0 8.5 2026-11-01
  [ "$status" -eq 0 ]
  run jq -e '.[0].valorBruto == 10.0 and .[0].valorLiquido == 8.5' acme/proventos.json
  [ "$status" -eq 0 ]
}

@test "segundo registrar acumula, nao sobrescreve o primeiro" {
  seed_portfolio acme
  "$SCRIPT" acme registrar PETR4 dividendo acoes 6.13 6.13 2026-12-21
  run "$SCRIPT" acme registrar VALE3 dividendo acoes 3.0 3.0 2026-12-22
  [ "$status" -eq 0 ]
  run jq -e 'length == 2' acme/proventos.json
  [ "$status" -eq 0 ]
}

@test "importar grava multiplos eventos de um arquivo.json" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [
    {"ticker": "PETR4", "tipo": "dividendo", "classe": "acoes", "valorBruto": 6.13, "valorLiquido": 6.13, "data": "2026-12-21"},
    {"ticker": "CMIG4", "tipo": "jcp", "classe": "acoes", "valorBruto": 2.0, "valorLiquido": 1.7, "data": "2026-11-15"},
    {"ticker": "HGLG11", "tipo": "rendimento", "classe": "fiis", "valorBruto": 1.5, "valorLiquido": 1.5, "data": "2026-10-01"},
]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run jq -e 'length == 3' acme/proventos.json
  [ "$status" -eq 0 ]
  run jq -e '[.[] | .ticker] | sort == ["CMIG4", "HGLG11", "PETR4"]' acme/proventos.json
  [ "$status" -eq 0 ]
}

@test "importar e idempotente: reimportar o mesmo arquivo nao duplica eventos" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [{"ticker": "PETR4", "tipo": "dividendo", "classe": "acoes", "valorBruto": 6.13, "valorLiquido": 6.13, "data": "2026-12-21"}]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run jq -e 'length == 1' acme/proventos.json
  [ "$status" -eq 0 ]
}

@test "importar rejeita item invalido no array, nao grava nada (all-or-nothing)" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [
    {"ticker": "PETR4", "tipo": "dividendo", "classe": "acoes", "valorBruto": 6.13, "valorLiquido": 6.13, "data": "2026-12-21"},
    {"ticker": "RUIM3", "tipo": "invalido", "classe": "acoes", "valorBruto": 1.0, "valorLiquido": 1.0, "data": "2026-12-01"},
]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"RUIM3"* ]] || [[ "$output" == *"invalido"* ]]
  [ ! -e "acme/proventos.json" ]
}

@test "portfolio invalido e rejeitado" {
  run "$SCRIPT" nao-existe registrar PETR4 dividendo acoes 1 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
}
