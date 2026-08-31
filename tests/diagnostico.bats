#!/usr/bin/env bats
# Testes de fh-US-005: concentracao, exposicao cambial, liquidez D+0/D+1 e DY 12m.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/diagnostico.sh"
  FAKE_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote.sh"
  FAKE_BRAPI="$ROOT/tests/helpers/fake-brapi-http.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export ALOCACAO_QUOTE="$FAKE_QUOTE"
  export ALOCACAO_QUOTE_PRICES="$WORKDIR/prices.json"
  export ALOCACAO_QUOTE_LOG="$WORKDIR/quote.log"
  export BRAPI_HTTP_GET="$FAKE_BRAPI"
  export BRAPI_FETCH_LOG="$WORKDIR/brapi.log"
  export BRAPI_DIVIDEND_YIELDS="$WORKDIR/dividends.json"
  : > "$ALOCACAO_QUOTE_LOG"
  : > "$BRAPI_FETCH_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
  : > "$1/.env"
}

write_prices() {
  python3 - "$ALOCACAO_QUOTE_PRICES" <<'PY'
import json, sys
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump({"PETR4": 15, "HGLG11": 10, "AAPL": 100, "CAIXA": 1}, fh)
PY
}

write_mixed_holdings() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br", "liquidez": "D+1"},
        {"ticker": "HGLG11", "quantidade": 50, "classe": "fiis", "mercado": "br", "liquidez": "D+1"},
        {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us", "liquidez": "D+1"},
        {"ticker": "CAIXA", "quantidade": 400, "classe": "renda-fixa", "mercado": "br", "liquidez": "D+0"},
    ]
}
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

assert_sem_prescricao() {
  local output="$1"
  [[ "$output" != *"nao deveria"* ]]
  [[ "$output" != *"não deveria"* ]]
  [[ "$output" != *"recomend"* ]]
  [[ "$output" != *"Recomend"* ]]
  [[ "$output" != *"limite"* ]]
  [[ "$output" != *"Limite"* ]]
}

@test "uso sem args: falha com mensagem de uso citando holdings.json" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"holdings.json"* ]]
}

@test "holdings.json ausente: rejeita com valor recebido e formato esperado" {
  seed_portfolio acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"acme/holdings.json"* ]]
  [[ "$output" == *"posicoes"* ]]
}

@test "relatorio informa concentracao no maior ativo e percentual por mercado" {
  seed_portfolio acme
  write_mixed_holdings acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
# PETR4=1500, HGLG11=500, AAPL=500, CAIXA=400, total=2900
assert report["concentracao"]["ticker"] == "PETR4", report
assert abs(report["concentracao"]["percentual"] - 1500 / 2900) < 1e-9, report
assert report["concentracao"]["valor"] == 1500, report
br = report["porMercado"]["br"]
us = report["porMercado"]["us"]
assert br["valor"] == 2400, br
assert us["valor"] == 500, us
assert abs(br["percentual"] - 2400 / 2900) < 1e-9, br
assert abs(us["percentual"] - 500 / 2900) < 1e-9, us
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio informa percentual em liquidez D+0 e D+1 a partir do campo opcional" {
  seed_portfolio acme
  write_mixed_holdings acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
d0 = report["porLiquidez"]["D+0"]
d1 = report["porLiquidez"]["D+1"]
assert d0["valor"] == 400, d0
assert d1["valor"] == 2500, d1
assert abs(d0["percentual"] - 400 / 2900) < 1e-9, d0
assert abs(d1["percentual"] - 2500 / 2900) < 1e-9, d1
' "$output"
  [ "$status" -eq 0 ]
}

@test "posicao sem liquidez nao entra em D+0 nem D+1; buckets continuam presentes" {
  seed_portfolio acme
  write_prices
  python3 - <<'PY'
import json
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
        ]
    }, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["porLiquidez"]["D+0"]["valor"] == 0, report
assert report["porLiquidez"]["D+1"]["valor"] == 0, report
assert report["porLiquidez"]["D+0"]["percentual"] == 0, report
assert report["porLiquidez"]["D+1"]["percentual"] == 0, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "DY 12m vem da brapi quando o campo dividendYield existe" {
  unset ALOCACAO_QUOTE
  seed_portfolio acme
  python3 - <<'PY'
import json
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
        ]
    }, fh)
with open("dividends.json", "w", encoding="utf-8") as fh:
    json.dump({"PETR4": 12.5}, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  grep -q "PETR4" "$BRAPI_FETCH_LOG"
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
rows = {row["ticker"]: row["dividendYield"] for row in report["dividendYield12m"]}
assert rows["PETR4"] == 12.5, rows
' "$output"
  [ "$status" -eq 0 ]
}

@test "DY ausente na brapi e posicao US marcam indisponivel, sem inventar numero" {
  seed_portfolio acme
  write_mixed_holdings acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
rows = {row["ticker"]: row["dividendYield"] for row in report["dividendYield12m"]}
assert rows["HGLG11"] == "indisponivel", rows
assert rows["AAPL"] == "indisponivel", rows
assert rows["CAIXA"] == "indisponivel", rows
assert not isinstance(rows["HGLG11"], (int, float)), rows
assert not isinstance(rows["AAPL"], (int, float)), rows
' "$output"
  [ "$status" -eq 0 ]
}

@test "output nao traz limite recomendado nem interpretacao prescritiva" {
  seed_portfolio acme
  write_mixed_holdings acme
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  assert_sem_prescricao "$output"
}

@test "posicao com precoManual entra na concentracao/mercado sem chamar cotacao ou DY externos, DY marca indisponivel" {
  seed_portfolio acme
  python3 - acme <<'PY'
import json, sys
slug = sys.argv[1]
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br"},
        {"ticker": "NTN-B mai/2055", "quantidade": 4, "classe": "renda-fixa", "mercado": "br", "precoManual": 1005.74},
    ]
}
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["total"] - (1500 + 4022.96)) < 1e-6, report
rows = {row["ticker"]: row["dividendYield"] for row in report["dividendYield12m"]}
assert rows["NTN-B MAI/2055"] == "indisponivel", rows
' "$output"
  [ "$status" -eq 0 ]
  ! grep -qi "ntn-b" "$ALOCACAO_QUOTE_LOG"
  ! grep -qi "ntn-b" "$BRAPI_FETCH_LOG"
}
