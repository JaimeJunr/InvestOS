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
