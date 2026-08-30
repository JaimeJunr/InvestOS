#!/usr/bin/env bats
# Testes de pr-US-001: relatorio de alocacao atual vs. alocacao-alvo via holdings.json.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/alocacao.sh"
  FAKE_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote.sh"
  FAKE_BRAPI="$ROOT/tests/helpers/fake-brapi-http.sh"
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
}

write_holdings() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
        {"ticker": "HGLG11", "quantidade": 50, "classe": "fiis", "mercado": "br"},
        {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"},
    ]
}
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

write_alvo() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = {
    "porClasse": {"acoes": 0.6, "fiis": 0.4},
    "porMercado": {"br": 0.7, "us": 0.3},
}
with open(f"{slug}/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

write_prices() {
  python3 - "$ALOCACAO_QUOTE_PRICES" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump({"PETR4": 10, "HGLG11": 20, "AAPL": 100}, fh)
PY
}

@test "uso sem args: falha com mensagem de uso citando holdings.json" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"holdings.json"* ]]
}

@test "relatorio compara alocacao atual vs alvo por classe e por mercado a partir de holdings.json" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["total"] == 2500, report
acoes = report["porClasse"]["acoes"]
fiis = report["porClasse"]["fiis"]
assert acoes["valor"] == 1500, acoes
assert fiis["valor"] == 1000, fiis
assert abs(acoes["atual"] - 0.6) < 1e-9, acoes
assert abs(fiis["atual"] - 0.4) < 1e-9, fiis
assert abs(acoes["alvo"] - 0.6) < 1e-9, acoes
assert abs(fiis["alvo"] - 0.4) < 1e-9, fiis
assert abs(acoes["desvio"]) < 1e-9, acoes
assert abs(fiis["desvio"]) < 1e-9, fiis
br = report["porMercado"]["br"]
us = report["porMercado"]["us"]
assert br["valor"] == 2000, br
assert us["valor"] == 500, us
assert abs(br["atual"] - 0.8) < 1e-9, br
assert abs(us["atual"] - 0.2) < 1e-9, us
assert abs(br["alvo"] - 0.7) < 1e-9, br
assert abs(us["alvo"] - 0.3) < 1e-9, us
assert abs(br["desvio"] - 0.1) < 1e-9, br
assert abs(us["desvio"] + 0.1) < 1e-9, us
' "$output"
  [ "$status" -eq 0 ]
}

@test "funciona so com holdings.json manual, sem arquivos de corretora" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ ! -e "acme/.mcp.json" ]
  [ ! -s "acme/.env" ]
  [[ "$output" != *"plaid"* ]]
  [[ "$output" != *"Plaid"* ]]
  [[ "$output" != *"Interactive Brokers"* ]]
  grep -q "PETR4" "$ALOCACAO_QUOTE_LOG"
  grep -q "AAPL" "$ALOCACAO_QUOTE_LOG"
}

@test "holdings.json ausente: rejeita com valor recebido e formato esperado" {
  seed_portfolio acme
  write_alvo acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"acme/holdings.json"* ]]
  [[ "$output" == *"posicoes"* ]]
}

@test "alocacao-alvo.json com pesos que nao somam 1 e rejeitado" {
  seed_portfolio acme
  write_holdings acme
  write_prices
  python3 - <<'PY'
import json
with open("acme/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump({"porClasse": {"acoes": 0.5, "fiis": 0.3}, "porMercado": {"br": 1.0}}, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"0.5"* ]] || [[ "$output" == *"0.8"* ]] || [[ "$output" == *"porClasse"* ]]
  [[ "$output" == *"esperado"* ]]
  [[ "$output" == *"1"* ]]
}

@test "posicoes BR sem ALOCACAO_QUOTE valorizam via brapi-quote.sh" {
  unset ALOCACAO_QUOTE
  export BRAPI_HTTP_GET="$FAKE_BRAPI"
  export BRAPI_FETCH_LOG="$WORKDIR/brapi.log"
  : > "$BRAPI_FETCH_LOG"
  seed_portfolio acme
  python3 - <<'PY'
import json
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
            {"ticker": "VALE3", "quantidade": 100, "classe": "fiis", "mercado": "br"},
        ]
    }, fh)
with open("acme/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump({"porClasse": {"acoes": 0.5, "fiis": 0.5}, "porMercado": {"br": 1.0}}, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  grep -q "PETR4" "$BRAPI_FETCH_LOG"
  grep -q "VALE3" "$BRAPI_FETCH_LOG"
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["total"] == 2100, report
assert report["porClasse"]["acoes"]["valor"] == 1050, report
assert report["porClasse"]["fiis"]["valor"] == 1050, report
assert abs(report["porMercado"]["br"]["atual"] - 1.0) < 1e-9, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "posicao US sem ALOCACAO_QUOTE e rejeitada sem client HTTP de corretora" {
  unset ALOCACAO_QUOTE
  seed_portfolio acme
  python3 - <<'PY'
import json
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"},
        ]
    }, fh)
with open("acme/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump({"porClasse": {"acoes": 1.0}, "porMercado": {"us": 1.0}}, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"AAPL"* ]]
  [[ "$output" == *"us"* ]]
  [[ "$output" == *"esperado"* ]]
}
