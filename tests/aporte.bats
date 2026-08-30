#!/usr/bin/env bats
# Testes de gestao de aportes novos: sugere onde colocar dinheiro novo sem
# precisar vender nada, priorizando classes/mercados underweight.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/aporte.sh"
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
  mkdir -p "$1"
  : > "$1/.env"
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
  # $1=slug $2=peso-acoes $3=peso-fiis $4=peso-br $5=peso-us
  python3 - "$1" "$2" "$3" "$4" "$5" <<'PY'
import json, sys
slug, acoes, fiis, br, us = sys.argv[1], *(float(x) for x in sys.argv[2:6])
payload = {
    "porClasse": {"acoes": acoes, "fiis": fiis},
    "porMercado": {"br": br, "us": us},
    "threshold": 0.05,
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

fingerprint() {
  sha256sum "$1/holdings.json" "$1/alocacao-alvo.json"
}

# Fixture: acoes=1500 (60%), fiis=1000 (40%), total 2500; br=2000 (80%), us=500 (20%).

@test "unico bucket underweight por eixo recebe 100% do aporte" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme 0.5 0.5 0.7 0.3
  write_prices

  run "$SCRIPT" acme 1000
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["valorAporte"] == 1000.0, report
assert report["executaOrdem"] is False, report
assert report["porClasse"] == [{"chave": "fiis", "valor": 1000.0}], report
assert report["porMercado"] == [{"chave": "us", "valor": 1000.0}], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "dois buckets underweight (3a classe nao detida) dividem o aporte proporcional ao gap" {
  seed_portfolio acme
  write_holdings acme
  # atual: acoes 0.6, fiis 0.4, renda-fixa 0 (nao detida).
  # alvo: acoes 0.65 (gap .05), fiis 0.15 (overweight, sobra), renda-fixa 0.20 (gap .20).
  # 2 buckets underweight (acoes, renda-fixa) -> aporte 1000 rateado 0.05:0.20 = 200:800
  python3 - acme <<'PY'
import json, sys
slug = sys.argv[1]
payload = {
    "porClasse": {"acoes": 0.65, "fiis": 0.15, "renda-fixa": 0.20},
    "porMercado": {"br": 0.7, "us": 0.3},
    "threshold": 0.05,
}
with open(f"{slug}/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  write_prices

  run "$SCRIPT" acme 1000
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
by_key = {item["chave"]: item["valor"] for item in report["porClasse"]}
assert set(by_key) == {"acoes", "renda-fixa"}, by_key
assert abs(by_key["acoes"] - 200) < 1e-6, by_key
assert abs(by_key["renda-fixa"] - 800) < 1e-6, by_key
' "$output"
  [ "$status" -eq 0 ]
}

@test "nada underweight: aporte segue os pesos-alvo diretamente" {
  seed_portfolio acme
  write_holdings acme
  # alvo == split atual exato -> nenhum desvio negativo em nenhum eixo
  write_alvo acme 0.6 0.4 0.8 0.2
  write_prices

  run "$SCRIPT" acme 1000
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
by_classe = {item["chave"]: item["valor"] for item in report["porClasse"]}
by_mercado = {item["chave"]: item["valor"] for item in report["porMercado"]}
assert abs(by_classe["acoes"] - 600) < 1e-6, by_classe
assert abs(by_classe["fiis"] - 400) < 1e-6, by_classe
assert abs(by_mercado["br"] - 800) < 1e-6, by_mercado
assert abs(by_mercado["us"] - 200) < 1e-6, by_mercado
' "$output"
  [ "$status" -eq 0 ]
}

@test "valor de aporte invalido (zero, negativo ou nao-numero) e rejeitado" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme 0.5 0.5 0.7 0.3
  write_prices

  run "$SCRIPT" acme 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]

  run "$SCRIPT" acme -100
  [ "$status" -ne 0 ]

  run "$SCRIPT" acme "abacate"
  [ "$status" -ne 0 ]
}

@test "sem argumentos: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "nunca sugere vender, nunca executa ordem, nunca altera holdings" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme 0.5 0.5 0.7 0.3
  write_prices
  fingerprint acme > before.sha

  run "$SCRIPT" acme 1000
  [ "$status" -eq 0 ]
  fingerprint acme > after.sha
  cmp before.sha after.sha
  [[ "$output" != *'"acao": "vender"'* ]]
  [[ "$output" != *"enviar ordem"* ]]
  [[ "$output" != *"place_order"* ]]
  ! grep -qiE "place_order|enviar ordem|executar ordem" "$SCRIPT"
}
