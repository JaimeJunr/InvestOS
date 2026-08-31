#!/usr/bin/env bats
# Testes do relatorio de negociacoes B3: totais, quantidade liquida, ofertas publicas.
# Nao calcula ganho/perda de capital nem IR.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/negociacoes-relatorio.sh"
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

write_negociacoes() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = [
    {"ticker": "PETR4", "tipo": "compra", "quantidade": 100, "precoUnitario": 32.50, "data": "2026-03-10", "oferta": None},
    {"ticker": "PETR4", "tipo": "venda", "quantidade": 30, "precoUnitario": 35.00, "data": "2026-03-15", "oferta": None},
    {"ticker": "VALE3", "tipo": "compra", "quantidade": 50, "precoUnitario": 60.00, "data": "2026-03-12", "oferta": "follow-on-vale"},
    {"ticker": "ITUB4", "tipo": "compra", "quantidade": 20, "precoUnitario": 30.00, "data": "2026-03-20", "oferta": "IPO-ITUB4"},
]
with open(f"{slug}/negociacoes.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

@test "sem argumentos: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "negociacoes.json ausente e rejeitado com mensagem clara" {
  seed_portfolio acme
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]
}

@test "relatorio soma total comprado e total vendido" {
  seed_portfolio acme
  write_negociacoes acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["totalComprado"] - 6850.0) < 1e-9, report
assert abs(report["totalVendido"] - 1050.0) < 1e-9, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio calcula quantidade liquida por ticker" {
  seed_portfolio acme
  write_negociacoes acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
liq = report["quantidadeLiquidaPorTicker"]
assert abs(liq["PETR4"] - 70) < 1e-9, report
assert abs(liq["VALE3"] - 50) < 1e-9, report
assert abs(liq["ITUB4"] - 20) < 1e-9, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio agrupa volume negociado por ticker e por tipo" {
  seed_portfolio acme
  write_negociacoes acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
por_ticker = report["volumePorTicker"]
assert abs(por_ticker["PETR4"]["compra"] - 3250.0) < 1e-9, report
assert abs(por_ticker["PETR4"]["venda"] - 1050.0) < 1e-9, report
assert abs(por_ticker["VALE3"]["compra"] - 3000.0) < 1e-9, report
assert abs(report["volumePorTipo"]["compra"] - 6850.0) < 1e-9, report
assert abs(report["volumePorTipo"]["venda"] - 1050.0) < 1e-9, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio lista negociacoes com oferta agrupadas por oferta" {
  seed_portfolio acme
  write_negociacoes acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
ofertas = report["ofertasPublicas"]
assert "follow-on-vale" in ofertas, report
assert "IPO-ITUB4" in ofertas, report
assert ofertas["follow-on-vale"][0]["ticker"] == "VALE3", report
assert ofertas["IPO-ITUB4"][0]["ticker"] == "ITUB4", report
assert "PETR4" not in {item["ticker"] for grupo in ofertas.values() for item in grupo}, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio avisa que ganho/perda de capital nao e calculado" {
  seed_portfolio acme
  write_negociacoes acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
aviso = report["aviso"].lower()
assert "ganho" in aviso or "perda" in aviso, report
assert "capital" in aviso, report
' "$output"
  [ "$status" -eq 0 ]
}
