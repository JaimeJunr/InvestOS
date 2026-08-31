#!/usr/bin/env bats
# Testes de fh-US-001: historico diario do valor total da carteira.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/nav-snapshot.sh"
  FAKE_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export ALOCACAO_QUOTE="$FAKE_QUOTE"
  export ALOCACAO_QUOTE_PRICES="$WORKDIR/prices.json"
  export ALOCACAO_QUOTE_LOG="$WORKDIR/quote.log"
  : > "$ALOCACAO_QUOTE_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  local slug="$1"
  mkdir -p "$slug"
  : > "$slug/.env"
  python3 - "$slug" <<'PY'
import json, sys

slug = sys.argv[1]
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
            {"ticker": "HGLG11", "quantidade": 50, "classe": "fiis", "mercado": "br"},
            {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"},
        ]
    }, fh)
with open(f"{slug}/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump({
        "porClasse": {"acoes": 0.6, "fiis": 0.4},
        "porMercado": {"br": 0.7, "us": 0.3},
    }, fh)
PY
}

write_prices() {
  python3 - "$ALOCACAO_QUOTE_PRICES" "$1" "$2" "$3" <<'PY'
import json, sys

path, petr4, hglg11, aapl = sys.argv[1:]
with open(path, "w", encoding="utf-8") as fh:
    json.dump({"PETR4": float(petr4), "HGLG11": float(hglg11), "AAPL": float(aapl)}, fh)
PY
}

@test "primeira execucao grava o valor total real do portfolio no dia" {
  seed_portfolio acme
  write_prices 10 20 100
  [ ! -e "acme/nav-historico.json" ]

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ -f "acme/nav-historico.json" ]

  hoje="$(date +%Y-%m-%d)"
  run jq -e --arg hoje "$hoje" \
    'type == "array" and length == 1 and .[0] == {data: $hoje, valorTotal: 2500}' \
    acme/nav-historico.json
  [ "$status" -eq 0 ]
  grep -q '^acme PETR4 br$' "$ALOCACAO_QUOTE_LOG"
  grep -q '^acme HGLG11 br$' "$ALOCACAO_QUOTE_LOG"
  grep -q '^acme AAPL us$' "$ALOCACAO_QUOTE_LOG"
}

@test "--valor e --data registram um ponto historico real, sem consultar cotacao" {
  seed_portfolio acme

  run "$SCRIPT" acme --valor 31433 --data 2023-01-01
  [ "$status" -eq 0 ]
  run jq -e '. == [{data: "2023-01-01", valorTotal: 31433}]' acme/nav-historico.json
  [ "$status" -eq 0 ]
  [ ! -s "$ALOCACAO_QUOTE_LOG" ]
}

@test "pontos historicos em datas diferentes acumulam, nao sobrescrevem" {
  seed_portfolio acme

  run "$SCRIPT" acme --valor 0 --data 2023-01-01
  [ "$status" -eq 0 ]
  run "$SCRIPT" acme --valor 31433 --data 2026-08-30
  [ "$status" -eq 0 ]

  run jq -e 'length == 2 and (map(.data) | sort) == ["2023-01-01", "2026-08-30"]' acme/nav-historico.json
  [ "$status" -eq 0 ]
}

@test "--valor/--data no mesmo dia ja registrado sobrescreve (idempotente, mesma politica do snapshot automatico)" {
  seed_portfolio acme

  run "$SCRIPT" acme --valor 100 --data 2026-08-30
  [ "$status" -eq 0 ]
  run "$SCRIPT" acme --valor 200 --data 2026-08-30
  [ "$status" -eq 0 ]

  run jq -e '. == [{data: "2026-08-30", valorTotal: 200}]' acme/nav-historico.json
  [ "$status" -eq 0 ]
}

@test "--valor sem --data (ou vice-versa) e rejeitado com mensagem clara" {
  seed_portfolio acme

  run "$SCRIPT" acme --valor 31433
  [ "$status" -ne 0 ]
  [[ "$output" == *"--data"* ]]

  run "$SCRIPT" acme --data 2023-01-01
  [ "$status" -ne 0 ]
  [[ "$output" == *"--valor"* ]]
}

@test "--valor zero e permitido (patrimonio comecando do zero); negativo ou nao-numero e rejeitado" {
  seed_portfolio acme

  run "$SCRIPT" acme --valor 0 --data 2023-01-01
  [ "$status" -eq 0 ]
  rm acme/nav-historico.json

  run "$SCRIPT" acme --valor -100 --data 2023-01-01
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]

  run "$SCRIPT" acme --valor abacate --data 2023-01-01
  [ "$status" -ne 0 ]
}

@test "--data em formato invalido e rejeitado" {
  seed_portfolio acme

  run "$SCRIPT" acme --valor 100 --data 30-08-2026
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"AAAA-MM-DD"* ]]
}

@test "duas execucoes no mesmo dia atualizam o snapshot sem duplicar" {
  seed_portfolio acme
  write_prices 10 20 100

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run jq -e '. | length == 1 and .[0].valorTotal == 2500' acme/nav-historico.json
  [ "$status" -eq 0 ]

  write_prices 11 22 110
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]

  hoje="$(date +%Y-%m-%d)"
  run jq -e --arg hoje "$hoje" \
    'type == "array" and length == 1 and .[0] == {data: $hoje, valorTotal: 2750}' \
    acme/nav-historico.json
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$ALOCACAO_QUOTE_LOG")" -eq 6 ]
}
