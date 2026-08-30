#!/usr/bin/env bats
# Testes de bi-US-002: credenciais de corretora lidas so do .env local do portfolio.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/credencial.sh"
  SETUP="$ROOT/bin/setup.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_env() {
  local slug="$1"
  mkdir -p "$slug"
  cat > "$slug/.env"
}

assert_no_secret() {
  local secret="$1"
  [[ "$output" != *"$secret"* ]]
}

@test "uso sem args: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "has PLAID_SECRET le so o .env local e nao imprime a credencial" {
  seed_env acme <<'EOF'
PLAID_CLIENT_ID=id-acme
PLAID_SECRET=segredo-local
EOF
  run "$SCRIPT" acme has PLAID_SECRET
  [ "$status" -eq 0 ]
  assert_no_secret "segredo-local"
  assert_no_secret "id-acme"
}

@test "placeholder vazio no .env local conta como credencial ausente" {
  seed_env acme <<'EOF'
PLAID_CLIENT_ID=
PLAID_SECRET=
EOF
  run "$SCRIPT" acme has PLAID_SECRET
  [ "$status" -eq 1 ]
  [[ "$output" != *"PLAID_SECRET="* ]]
}

@test "PLAID_SECRET no ambiente do processo e ignorado" {
  seed_env acme <<'EOF'
PLAID_CLIENT_ID=
PLAID_SECRET=
EOF
  export PLAID_SECRET="segredo-processo"
  run "$SCRIPT" acme has PLAID_SECRET
  [ "$status" -eq 1 ]
  assert_no_secret "segredo-processo"
}

@test "credenciais de um portfolio nao vazam para outro nem para stdout" {
  seed_env acme <<'EOF'
PLAID_CLIENT_ID=id-acme
PLAID_SECRET=segredo-acme
EOF
  seed_env beta <<'EOF'
PLAID_CLIENT_ID=
PLAID_SECRET=
EOF
  export PLAID_SECRET="segredo-processo"

  run "$SCRIPT" acme has PLAID_SECRET
  [ "$status" -eq 0 ]
  assert_no_secret "segredo-acme"
  assert_no_secret "segredo-processo"

  run "$SCRIPT" beta has PLAID_SECRET
  [ "$status" -eq 1 ]
  assert_no_secret "segredo-acme"
  assert_no_secret "segredo-processo"
}

@test "setup nao grava a credencial preenchida em config; has nao vaza no output" {
  printf 'n\nn\nn\ny\nbr\n' | "$SETUP" acme
  printf 'PLAID_CLIENT_ID=id-preenchido\nPLAID_SECRET=segredo-preenchido\n' > acme/.env

  run grep -R "segredo-preenchido" acme/.mcp.json acme/.claude/settings.json acme/portfolio.json acme/CLAUDE.md
  [ "$status" -ne 0 ]

  run jq -e '.mcpServers.plaid.env.PLAID_SECRET == "${PLAID_SECRET}"' acme/.mcp.json
  [ "$status" -eq 0 ]

  run "$SCRIPT" acme has PLAID_SECRET
  [ "$status" -eq 0 ]
  assert_no_secret "segredo-preenchido"
  assert_no_secret "id-preenchido"
}

@test "chave desconhecida e rejeitada com valor recebido e formato esperado" {
  seed_env acme <<'EOF'
PLAID_SECRET=segredo-local
EOF
  run "$SCRIPT" acme has BRAPI_TOKEN
  [ "$status" -eq 1 ]
  [[ "$output" == *"BRAPI_TOKEN"* ]]
  [[ "$output" == *"PLAID_CLIENT_ID"* ]]
  [[ "$output" == *"PLAID_SECRET"* ]]
  assert_no_secret "segredo-local"
}

@test "has PLAID_CLIENT_ID e independente de PLAID_SECRET" {
  seed_env acme <<'EOF'
PLAID_CLIENT_ID=id-sozinho
PLAID_SECRET=
EOF
  run "$SCRIPT" acme has PLAID_CLIENT_ID
  [ "$status" -eq 0 ]
  assert_no_secret "id-sozinho"

  run "$SCRIPT" acme has PLAID_SECRET
  [ "$status" -eq 1 ]
}

@test ".env e lido como texto, nao executado como shell" {
  seed_env acme <<'EOF'
PLAID_SECRET=ok
pwned=$(touch pwned)
EOF
  run "$SCRIPT" acme has PLAID_SECRET
  [ "$status" -eq 0 ]
  [ ! -e pwned ]
}
