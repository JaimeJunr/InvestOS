#!/usr/bin/env bats
# Testes de bi-US-003: desconexao e fallback de corretora sem quebrar holdings.json.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/holdings-sync.sh"
  ALOCACAO="$ROOT/bin/alocacao.sh"
  REBAL="$ROOT/bin/rebalanceamento.sh"
  FAKE="$ROOT/tests/helpers/fake-plaid-holdings.sh"
  FAKE_QUOTE="$ROOT/tests/helpers/fake-alocacao-quote.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export HOLDINGS_FETCH="$FAKE"
  export PLAID_HOLDINGS_LOG="$WORKDIR/plaid-fetch.log"
  export ALOCACAO_QUOTE="$FAKE_QUOTE"
  export ALOCACAO_QUOTE_PRICES="$WORKDIR/prices.json"
  export ALOCACAO_QUOTE_LOG="$WORKDIR/quote.log"
  : > "$PLAID_HOLDINGS_LOG"
  : > "$ALOCACAO_QUOTE_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
  : > "$1/.env"
}

write_env() {
  local slug="$1"
  cat > "$slug/.env"
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

write_broker_fixture() {
  python3 - "$1" <<'PY'
import json, sys
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 7, "classe": "acoes", "mercado": "br"},
        {"ticker": "HGLG11", "quantidade": 50, "classe": "fiis", "mercado": "br"},
        {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"},
    ]
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

write_alvo() {
  python3 - "$1" <<'PY'
import json, sys
payload = {
    "porClasse": {"acoes": 0.6, "fiis": 0.4},
    "porMercado": {"br": 0.7, "us": 0.3},
    "threshold": 0.05,
}
with open(f"{sys.argv[1]}/alocacao-alvo.json", "w", encoding="utf-8") as fh:
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

fingerprint_holdings() {
  sha256sum "$1/holdings.json"
}

assert_no_secret() {
  [[ "$output" != *"segredo-plaid"* ]]
  [[ "$output" != *"id-plaid"* ]]
}

@test "uso sem args: falha com mensagem de uso citando holdings.json" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"holdings.json"* ]]
}

@test "remover credencial do .env volta a holdings.json manual e nao quebra alocacao/rebalanceamento" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme
  write_prices
  write_env acme <<'EOF'
PLAID_CLIENT_ID=id-plaid
PLAID_SECRET=segredo-plaid
EOF
  before=$(fingerprint_holdings acme)

  write_env acme <<'EOF'
PLAID_CLIENT_ID=
PLAID_SECRET=
EOF

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  assert_no_secret
  [ ! -s "$PLAID_HOLDINGS_LOG" ]
  after=$(fingerprint_holdings acme)
  [ "$before" = "$after" ]
  jq -e '.posicoes | length == 3 and .[0].quantidade == 100' acme/holdings.json

  run "$ALOCACAO" acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"porClasse"* ]]

  run "$REBAL" acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"executaOrdem"* ]]
}

@test "token expirado mantem ultimo holdings.json, avisa idade e nao zera nem trava" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme
  write_prices
  write_env acme <<'EOF'
PLAID_CLIENT_ID=id-plaid
PLAID_SECRET=segredo-plaid
EOF
  write_broker_fixture "$WORKDIR/broker.json"
  export PLAID_HOLDINGS_FIXTURE="$WORKDIR/broker.json"
  export HOLDINGS_NOW=1000

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  jq -e '.posicoes[0].quantidade == 7' acme/holdings.json
  synced=$(fingerprint_holdings acme)

  export PLAID_HOLDINGS_FAIL=1
  export HOLDINGS_NOW=4600
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  assert_no_secret
  [[ "$output" == *"aviso"* ]]
  [[ "$output" == *"idade"* ]]
  [[ "$output" == *"3600"* ]]
  after=$(fingerprint_holdings acme)
  [ "$synced" = "$after" ]
  jq -e '.posicoes | length == 3 and .[0].quantidade == 7' acme/holdings.json
  [ "$(jq '.posicoes | length' acme/holdings.json)" != "0" ]

  run "$ALOCACAO" acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"porClasse"* ]]
}

@test "falha de conexao sem sync previo nao zera holdings.json manual e avisa idade" {
  seed_portfolio acme
  write_holdings acme
  write_alvo acme
  write_prices
  write_env acme <<'EOF'
PLAID_CLIENT_ID=id-plaid
PLAID_SECRET=segredo-plaid
EOF
  before=$(fingerprint_holdings acme)
  export PLAID_HOLDINGS_FAIL=1
  export HOLDINGS_NOW=2000

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  assert_no_secret
  [[ "$output" == *"aviso"* ]]
  [[ "$output" == *"idade"* ]]
  after=$(fingerprint_holdings acme)
  [ "$before" = "$after" ]
  jq -e '.posicoes | length == 3 and .[0].ticker == "PETR4" and .[0].quantidade == 100' acme/holdings.json

  run "$ALOCACAO" acme
  [ "$status" -eq 0 ]
}

@test "sync preserva precoManual/liquidez de posicoes casadas por ticker+mercado e mantem posicao ausente do payload da corretora" {
  seed_portfolio acme
  write_env acme <<'EOF'
PLAID_CLIENT_ID=id-plaid
PLAID_SECRET=segredo-plaid
EOF
  python3 - acme <<'PY'
import json, sys
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br", "liquidez": "D+1"},
        {"ticker": "HGLG11", "quantidade": 50, "classe": "fiis", "mercado": "br"},
        {"ticker": "TESOURO2029", "quantidade": 4, "classe": "renda-fixa", "mercado": "br",
         "precoManual": 1005.74, "liquidez": "D+30"},
    ]
}
with open(f"{sys.argv[1]}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  python3 - "$WORKDIR/broker.json" <<'PY'
import json, sys
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 120, "classe": "acoes", "mercado": "br"},
        {"ticker": "HGLG11", "quantidade": 50, "classe": "fiis", "mercado": "br"},
        {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"},
    ]
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  export PLAID_HOLDINGS_FIXTURE="$WORKDIR/broker.json"
  export HOLDINGS_NOW=1000

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  assert_no_secret

  # PETR4 veio atualizado da corretora (quantidade), mas o liquidez manual sobrevive.
  jq -e '.posicoes[] | select(.ticker == "PETR4") | .quantidade == 120 and .liquidez == "D+1"' acme/holdings.json

  # TESOURO2029 nao existe no payload da corretora (renda-fixa sem ticker cotavel) -
  # precisa ser preservado, nao descartado, com precoManual e liquidez intactos.
  jq -e '.posicoes[] | select(.ticker == "TESOURO2029") | .precoManual == 1005.74 and .liquidez == "D+30"' acme/holdings.json
  [[ "$output" == *"TESOURO2029"* ]]
  [[ "$output" == *"ausente"* ]]
}

@test "corretora envia precoManual conflitante - local sempre vence e conflito e avisado" {
  seed_portfolio acme
  write_env acme <<'EOF'
PLAID_CLIENT_ID=id-plaid
PLAID_SECRET=segredo-plaid
EOF
  python3 - acme <<'PY'
import json, sys
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 100, "classe": "acoes", "mercado": "br", "precoManual": 10.0},
    ]
}
with open(f"{sys.argv[1]}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  python3 - "$WORKDIR/broker.json" <<'PY'
import json, sys
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 120, "classe": "acoes", "mercado": "br", "precoManual": 99.0},
    ]
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
  export PLAID_HOLDINGS_FIXTURE="$WORKDIR/broker.json"
  export HOLDINGS_NOW=1000

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  assert_no_secret

  jq -e '.posicoes[] | select(.ticker == "PETR4") | .precoManual == 10.0 and .quantidade == 120' acme/holdings.json
  [[ "$output" == *"conflito"* ]]
  [[ "$output" == *"PETR4"* ]]
}
