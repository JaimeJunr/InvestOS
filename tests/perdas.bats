#!/usr/bin/env bats
# Testes de eficiencia fiscal (tax-loss harvesting): reporta ganho/perda nao
# realizada por posicao a partir do precoMedio opcional em holdings.json.
# Informativo apenas - nunca recomenda vender, nunca calcula IR devido.
#
# Fake HTTP da brapi.dev sempre retorna regularMarketPrice=10.5 (ver
# tests/helpers/fake-brapi-http.sh) - por isso os fixtures usam precoMedio
# acima de 10.5 (perda) ou abaixo (ganho) pra exercitar os dois casos.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/perdas.sh"
  FAKE_HTTP="$ROOT/tests/helpers/fake-brapi-http.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export BRAPI_HTTP_GET="$FAKE_HTTP"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
  printf 'BRAPI_TOKEN=segredo-teste\n' > "$1/.env"
}

write_holdings() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br", "precoMedio": 12.0},
        {"ticker": "HGLG11", "quantidade": 50, "classe": "fiis", "mercado": "br", "precoMedio": 8.0},
        {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"},
    ]
}
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

@test "posicao com precoMedio acima do preco atual e candidata a tax-loss harvesting" {
  seed_portfolio acme
  write_holdings acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
by_ticker = {p["ticker"]: p for p in report["posicoes"]}
petr4 = by_ticker["PETR4"]
assert petr4["precoMedio"] == 12.0, petr4
assert petr4["precoAtual"] == 10.5, petr4
assert abs(petr4["ganhoValor"] - (100 * (10.5 - 12.0))) < 1e-6, petr4
assert petr4["perdaNaoRealizada"] is True, petr4
assert "PETR4" in report["candidatosTaxLossHarvesting"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "posicao com ganho nao entra nos candidatos" {
  seed_portfolio acme
  write_holdings acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
by_ticker = {p["ticker"]: p for p in report["posicoes"]}
hglg11 = by_ticker["HGLG11"]
assert hglg11["precoMedio"] == 8.0, hglg11
assert hglg11["precoAtual"] == 10.5, hglg11
assert hglg11["perdaNaoRealizada"] is False, hglg11
assert hglg11["ganhoValor"] > 0, hglg11
assert "HGLG11" not in report["candidatosTaxLossHarvesting"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "posicao sem precoMedio e listada separadamente, sem calculo de ganho/perda" {
  seed_portfolio acme
  write_holdings acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
tickers = {p["ticker"] for p in report["posicoes"]}
assert "AAPL" not in tickers, report
assert "AAPL" in report["posicoesSemPrecoMedio"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio inclui aviso de que e informativo, nao recomendacao de venda nem calculo de IR" {
  seed_portfolio acme
  write_holdings acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
aviso = report["avisoLegal"].lower()
assert "nao" in aviso and ("recomend" in aviso or "venda" in aviso), report
assert "ir" in aviso or "imposto" in aviso, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "nenhuma posicao com precoMedio: nenhum candidato, sem erro" {
  seed_portfolio acme
  python3 - acme <<'PY'
import json, sys
slug = sys.argv[1]
payload = {"posicoes": [{"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"}]}
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["posicoes"] == [], report
assert report["candidatosTaxLossHarvesting"] == [], report
assert report["posicoesSemPrecoMedio"] == ["AAPL"], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "portfolio invalido ou holdings ausente e rejeitado com mensagem clara" {
  run "$SCRIPT" nao-existe
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]

  seed_portfolio acme
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"holdings.json"* ]]
}

@test "nunca sugere vender no texto, so classifica como candidato informativo" {
  seed_portfolio acme
  write_holdings acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [[ "$output" != *'"acao": "vender"'* ]]
  ! grep -qiE "^\s*venda\b|place_order|enviar ordem" "$SCRIPT"
}
