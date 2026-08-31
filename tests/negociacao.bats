#!/usr/bin/env bats
# Testes de registro de negociacoes B3 em negociacoes.json.
# Espelha o padrao de bin/provento.sh (registrar + importar all-or-nothing/idempotente).

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/negociacao.sh"
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

@test "registrar grava uma negociacao nova em negociacoes.json" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 compra 100 32.50 2026-03-10
  [ "$status" -eq 0 ]
  run jq -e '. == [{ticker: "PETR4", tipo: "compra", quantidade: 100, precoUnitario: 32.5, data: "2026-03-10", oferta: null}]' acme/negociacoes.json
  [ "$status" -eq 0 ]
}

@test "registrar com oferta preenche o campo opcional" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar VALE3 compra 50 60.00 2026-03-12 follow-on-vale
  [ "$status" -eq 0 ]
  run jq -e '.[0].oferta == "follow-on-vale" and .[0].ticker == "VALE3"' acme/negociacoes.json
  [ "$status" -eq 0 ]
}

@test "tipo invalido e rejeitado com valor recebido e esperado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 bonus 100 32.50 2026-03-10
  [ "$status" -ne 0 ]
  [[ "$output" == *"bonus"* ]]
  [[ "$output" == *"compra"* ]]
  [ ! -e "acme/negociacoes.json" ]
}

@test "quantidade ou precoUnitario invalido (zero, negativo, nao-numero) e rejeitado" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 compra 0 32.50 2026-03-10
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar PETR4 compra -10 32.50 2026-03-10
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar PETR4 compra 100 0 2026-03-10
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar PETR4 compra 100 -1 2026-03-10
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme registrar PETR4 compra abacate 32.50 2026-03-10
  [ "$status" -ne 0 ]
  [ ! -e "acme/negociacoes.json" ]
}

@test "data invalida e rejeitada (esperado AAAA-MM-DD)" {
  seed_portfolio acme
  run "$SCRIPT" acme registrar PETR4 compra 100 32.50 10/03/2026
  [ "$status" -ne 0 ]
  [[ "$output" == *"10/03/2026"* ]]
  [[ "$output" == *"AAAA-MM-DD"* ]]
  [ ! -e "acme/negociacoes.json" ]
}

@test "segundo registrar acumula, nao sobrescreve o primeiro" {
  seed_portfolio acme
  "$SCRIPT" acme registrar PETR4 compra 100 32.50 2026-03-10
  run "$SCRIPT" acme registrar PETR4 venda 30 35.00 2026-03-15
  [ "$status" -eq 0 ]
  run jq -e 'length == 2' acme/negociacoes.json
  [ "$status" -eq 0 ]
}

@test "importar grava multiplas negociacoes de um arquivo.json" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [
    {"ticker": "PETR4", "tipo": "compra", "quantidade": 100, "precoUnitario": 32.50, "data": "2026-03-10"},
    {"ticker": "VALE3", "tipo": "compra", "quantidade": 50, "precoUnitario": 60.00, "data": "2026-03-12", "oferta": "follow-on-vale"},
]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run jq -e 'length == 2' acme/negociacoes.json
  [ "$status" -eq 0 ]
  run jq -e '[.[] | .ticker] | sort == ["PETR4", "VALE3"]' acme/negociacoes.json
  [ "$status" -eq 0 ]
  run jq -e '.[] | select(.ticker == "PETR4") | .oferta == null' acme/negociacoes.json
  [ "$status" -eq 0 ]
  run jq -e '.[] | select(.ticker == "VALE3") | .oferta == "follow-on-vale"' acme/negociacoes.json
  [ "$status" -eq 0 ]
}

@test "importar e idempotente: reimportar o mesmo arquivo nao duplica" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [{"ticker": "PETR4", "tipo": "compra", "quantidade": 100, "precoUnitario": 32.50, "data": "2026-03-10"}]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run "$SCRIPT" acme importar import.json
  [ "$status" -eq 0 ]
  run jq -e 'length == 1' acme/negociacoes.json
  [ "$status" -eq 0 ]
}

@test "importar acumula sobre negociacoes.json ja nao-vazio: segundo lote com negociacoes genuinamente novas nao e descartado" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [{"ticker": "PETR4", "tipo": "compra", "quantidade": 100, "precoUnitario": 32.50, "data": "2026-03-10"}]
with open("lote1.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  run "$SCRIPT" acme importar lote1.json
  [ "$status" -eq 0 ]

  python3 - <<'PY'
import json
payload = [{"ticker": "VALE3", "tipo": "venda", "quantidade": 20, "precoUnitario": 61.0, "data": "2026-04-01"}]
with open("lote2.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  run "$SCRIPT" acme importar lote2.json
  [ "$status" -eq 0 ]

  run jq -e 'length == 2' acme/negociacoes.json
  [ "$status" -eq 0 ]
  run jq -e '[.[] | .ticker] | sort == ["PETR4", "VALE3"]' acme/negociacoes.json
  [ "$status" -eq 0 ]
}

@test "importar rejeita item invalido no array, nao grava nada (all-or-nothing)" {
  seed_portfolio acme
  python3 - <<'PY'
import json
payload = [
    {"ticker": "PETR4", "tipo": "compra", "quantidade": 100, "precoUnitario": 32.50, "data": "2026-03-10"},
    {"ticker": "RUIM3", "tipo": "invalido", "quantidade": 1, "precoUnitario": 1.0, "data": "2026-03-01"},
]
with open("import.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme importar import.json
  [ "$status" -ne 0 ]
  [[ "$output" == *"RUIM3"* ]] || [[ "$output" == *"invalido"* ]]
  [ ! -e "acme/negociacoes.json" ]
}

@test "portfolio invalido e rejeitado" {
  run "$SCRIPT" nao-existe registrar PETR4 compra 100 32.50 2026-03-10
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
}
