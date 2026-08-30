#!/usr/bin/env bats
# Testes de pr-US-003: sugestao de rebalanceamento quando o desvio ultrapassa o threshold.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/rebalanceamento.sh"
  SETUP="$ROOT/bin/setup.sh"
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
  python3 - "$1" "$2" <<'PY'
import json, sys
slug, threshold = sys.argv[1], float(sys.argv[2])
payload = {
    "porClasse": {"acoes": 0.5, "fiis": 0.5},
    "porMercado": {"br": 0.7, "us": 0.3},
    "threshold": threshold,
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

@test "desvio acima do threshold gera sugestao comprar/vender para voltar ao alvo" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme 0.05
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["disparou"] is True, report
assert report["threshold"] == 0.05, report
by_key = {(s["eixo"], s["chave"]): s for s in report["sugestoes"]}
acoes = by_key[("porClasse", "acoes")]
fiis = by_key[("porClasse", "fiis")]
br = by_key[("porMercado", "br")]
us = by_key[("porMercado", "us")]
assert acoes["acao"] == "vender" and abs(acoes["valor"] - 250) < 1e-6, acoes
assert fiis["acao"] == "comprar" and abs(fiis["valor"] - 250) < 1e-6, fiis
assert br["acao"] == "vender" and abs(br["valor"] - 250) < 1e-6, br
assert us["acao"] == "comprar" and abs(us["valor"] - 250) < 1e-6, us
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio dentro do threshold nao gera sugestao" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme 0.15
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["disparou"] is False, report
assert report["sugestoes"] == [], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "desvio igual ao threshold nao ultrapassa e nao dispara" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme 0.1
  write_prices

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["disparou"] is False, report
assert report["sugestoes"] == [], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "threshold e configuravel por portfolio: mesmo holdings, desfechos diferentes" {
  seed_portfolio alpha
  seed_portfolio beta
  write_holdings alpha
  write_holdings beta
  write_alvo alpha 0.05
  write_alvo beta 0.15
  write_prices

  run "$SCRIPT" alpha
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["disparou"] is True, report
assert report["sugestoes"], report
' "$output"
  [ "$status" -eq 0 ]

  run "$SCRIPT" beta
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["disparou"] is False, report
assert report["sugestoes"] == [], report
' "$output"
  [ "$status" -eq 0 ]
}

@test "nunca executa ordem: so sugere e nao altera holdings" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme 0.05
  write_prices
  fingerprint acme > before.sha

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  fingerprint acme > after.sha
  cmp before.sha after.sha
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["executaOrdem"] is False, report
' "$output"
  [ "$status" -eq 0 ]
  [[ "$output" != *"enviar ordem"* ]]
  [[ "$output" != *"place_order"* ]]
  ! grep -qiE "place_order|enviar ordem|executar ordem" "$SCRIPT"
}

@test "skill de rebalanceamento declara que nunca executa ordem, so sugere" {
  SKILL="$ROOT/templates/skills/rebalanceamento/SKILL.md"
  [ -f "$SKILL" ]
  grep -q "^name: rebalanceamento" "$SKILL"
  grep -q "Use when" "$SKILL"
  grep -qi "nunca executa ordem" "$SKILL"
  grep -qi "so sugere" "$SKILL"

  run bash -c "printf 'n\ny\nn\nn\nbr\n' | '$SETUP' acme"
  [ "$status" -eq 0 ]
  [ -f "acme/.claude/skills/rebalanceamento/SKILL.md" ]
  grep -qi "nunca executa ordem" "acme/.claude/skills/rebalanceamento/SKILL.md"
  grep -qi "bin/rebalanceamento.sh" "acme/.claude/skills/rebalanceamento/SKILL.md"
}

@test "threshold ausente ou invalido e rejeitado com valor recebido e esperado" {
  seed_portfolio acme
  write_holdings acme
  write_prices
  python3 - <<'PY'
import json
with open("acme/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump({"porClasse": {"acoes": 0.5, "fiis": 0.5}, "porMercado": {"br": 0.7, "us": 0.3}}, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"threshold"* ]]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]

  python3 - <<'PY'
import json
with open("acme/alocacao-alvo.json", "w", encoding="utf-8") as fh:
    json.dump({
        "porClasse": {"acoes": 0.5, "fiis": 0.5},
        "porMercado": {"br": 0.7, "us": 0.3},
        "threshold": -0.05,
    }, fh)
PY
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"-0.05"* ]]
  [[ "$output" == *"esperado"* ]]
}
