#!/usr/bin/env bats
# Testes de registro de eventos corporativos em eventos-corporativos.json.
# Log informativo: nao ajusta holdings.json.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/evento-corporativo.sh"
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

@test "registrar grava um evento novo em eventos-corporativos.json" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 desdobramento 2026-05-01 2
  [ "$status" -eq 0 ]
  run jq -e '. == [{ticker: "PETR4", tipo: "desdobramento", data: "2026-05-01", fator: 2, quantidadeRecebida: null, observacao: null}]' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "registrar so com ticker tipo data deixa opcionais nulos" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar WEGE3 outro 2026-03-01
  [ "$status" -eq 0 ]
  run jq -e '.[0].fator == null and .[0].quantidadeRecebida == null and .[0].observacao == null' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "registrar aceita quantidadeRecebida sem fator" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 bonificacao 2026-06-01 "" 10
  [ "$status" -eq 0 ]
  run jq -e '.[0].fator == null and .[0].quantidadeRecebida == 10 and .[0].tipo == "bonificacao"' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "registrar aceita observacao independente dos numericos" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar ITUB4 incorporacao 2026-07-01 "" "" "cisao parcial"
  [ "$status" -eq 0 ]
  run jq -e '.[0].observacao == "cisao parcial" and .[0].fator == null and .[0].quantidadeRecebida == null' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "tipo invalido e rejeitado com valor recebido e esperado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 split 2026-05-01
  [ "$status" -ne 0 ]
  [[ "$output" == *"split"* ]]
  [[ "$output" == *"desdobramento"* ]]
  [ ! -e "acme/eventos-corporativos.json" ]
}

@test "fator ou quantidadeRecebida <= 0 e rejeitado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 desdobramento 2026-05-01 0
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar PETR4 bonificacao 2026-05-01 "" -1
  [ "$status" -ne 0 ]
  [ ! -e "acme/eventos-corporativos.json" ]
}

@test "data invalida e rejeitada (esperado AAAA-MM-DD)" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 desdobramento 01-05-2026
  [ "$status" -ne 0 ]
  [[ "$output" == *"01-05-2026"* ]]
  [[ "$output" == *"AAAA-MM-DD"* ]]
  [ ! -e "acme/eventos-corporativos.json" ]
}

@test "segundo registrar acumula, nao sobrescreve o primeiro" {
  seed_portfolio acme
  "$SCRIPT" acme registrar PETR4 desdobramento 2026-05-01 2
  run "$SCRIPT" acme registrar VALE3 grupamento 2026-04-01 0.1
  [ "$status" -eq 0 ]
  run jq -e 'length == 2' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "importar grava multiplos eventos e opcionais independentes" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [
    {"ticker": "PETR4", "tipo": "desdobramento", "data": "2026-05-01", "fator": 2},
    {"ticker": "PETR4", "tipo": "bonificacao", "data": "2026-06-01", "quantidadeRecebida": 10},
    {"ticker": "WEGE3", "tipo": "outro", "data": "2026-03-01", "observacao": "cisao"},
]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run jq -e 'length == 3' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
  run jq -e '.[] | select(.tipo == "desdobramento") | .fator == 2 and .quantidadeRecebida == null' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
  run jq -e '.[] | select(.tipo == "bonificacao") | .quantidadeRecebida == 10 and .fator == null' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
  run jq -e '.[] | select(.tipo == "outro") | .observacao == "cisao" and .fator == null' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "importar e idempotente: reimportar o mesmo arquivo nao duplica" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [{"ticker": "PETR4", "tipo": "desdobramento", "data": "2026-05-01", "fator": 2}]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run jq -e 'length == 1' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "importar acumula sobre eventos-corporativos.json ja nao-vazio: segundo lote com eventos genuinamente novos nao e descartado" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [{"ticker": "PETR4", "tipo": "desdobramento", "data": "2026-05-01", "fator": 2}]
with open("lote1.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  run "$SCRIPT" acme importar lote1.json
  [ "$status" -eq 0 ]

  python3 - <<'PY'
import json
payload = [{"ticker": "VALE3", "tipo": "grupamento", "data": "2026-04-01", "fator": 0.1}]
with open("lote2.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  run "$SCRIPT" acme importar lote2.json
  [ "$status" -eq 0 ]

  run jq -e 'length == 2' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
  run jq -e '[.[] | .ticker] | sort == ["PETR4", "VALE3"]' acme/eventos-corporativos.json
  [ "$status" -eq 0 ]
}

@test "importar rejeita item invalido no array, nao grava nada (all-or-nothing)" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [
    {"ticker": "PETR4", "tipo": "desdobramento", "data": "2026-05-01", "fator": 2},
    {"ticker": "RUIM3", "tipo": "split", "data": "2026-03-01"},
]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"RUIM3"* ]] || [[ "$output" == *"split"* ]]
  [ ! -e "acme/eventos-corporativos.json" ]
}

@test "portfolio invalido e rejeitado" {
  run "$SCRIPT" nao-existe registrar PETR4 desdobramento 2026-05-01
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
}
