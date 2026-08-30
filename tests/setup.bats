#!/usr/bin/env bats
# Testes de wg-US-001: bin/setup.sh gera a estrutura padrao de um portfolio novo.

setup() {
  SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/bin/setup.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

@test "sem slug: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "cria estrutura padrao para portfolio novo" {
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [ -f "acme/CLAUDE.md" ]
  [ -d "acme/_memoria" ]
  [ -f "acme/.env" ]
  [ ! -s "acme/.env" ]
  [ -f "acme/.claude/settings.json" ]
  [ -f "acme/.gitignore" ]
  grep -qx ".env" "acme/.gitignore"
}

@test "settings.json gerado com enabledPlugins vazio" {
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.load(open('acme/.claude/settings.json')); sys.exit(0 if d.get('enabledPlugins') == {} else 1)"
  [ "$status" -eq 0 ]
}

@test "portfolio existente: sem confirmacao explicita, nao sobrescreve" {
  "$SCRIPT" acme
  echo "SENTINELA" >> acme/CLAUDE.md
  run bash -c "echo n | '$SCRIPT' acme"
  [ "$status" -ne 0 ]
  grep -q "SENTINELA" acme/CLAUDE.md
}

@test "portfolio existente: com confirmacao explicita (y), sobrescreve" {
  "$SCRIPT" acme
  echo "SENTINELA" >> acme/CLAUDE.md
  run bash -c "echo y | '$SCRIPT' acme"
  [ "$status" -eq 0 ]
  ! grep -q "SENTINELA" acme/CLAUDE.md
}

# Testes de wg-US-002: setup interativo pergunta dominios e mercado.

@test "dominios respondidos com y ficam habilitados em settings.json" {
  run bash -c "printf 'y\nn\ny\nn\nUS\n' | '$SCRIPT' acme"
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.load(open('acme/.claude/settings.json'))['enabledPlugins']
assert d == {'research': True, 'dados-mercado': True}, d
"
  [ "$status" -eq 0 ]
}

@test "nenhum dominio habilitado mantem enabledPlugins vazio" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' acme"
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.load(open('acme/.claude/settings.json'))
assert d['enabledPlugins'] == {}, d
"
  [ "$status" -eq 0 ]
}

@test "mercado escolhido fica registrado em portfolio.json" {
  run bash -c "printf 'n\nn\nn\nn\nambos\n' | '$SCRIPT' acme"
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.load(open('acme/portfolio.json'))
assert d['mercado'] == 'ambos', d
"
  [ "$status" -eq 0 ]
}

# Testes de wg-US-003: slug normalizado e validado na criacao.

@test "slug com espacos e maiusculas e normalizado (slugify) antes de criar a pasta" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' 'Meu Portfolio'"
  [ "$status" -eq 0 ]
  [ -d "meu-portfolio" ]
  [ ! -d "Meu Portfolio" ]
}

@test "slug com acentos e normalizado (translit) antes de criar a pasta" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' 'Ações Tech'"
  [ "$status" -eq 0 ]
  [ -d "acoes-tech" ]
}

@test "slug que so vira invalido apos normalizacao e rejeitado com mensagem explicativa" {
  run "$SCRIPT" "!!!"
  [ "$status" -ne 0 ]
  [[ "$output" == *"!!!"* ]]
  [[ "$output" == *"^[a-z0-9]"* ]]
}

# Testes de wg-US-004: isolamento entre portfolios gerados lado a lado.

@test "dois portfolios nao compartilham _memoria nem .env" {
  bash -c "printf 'y\nn\nn\nn\nBR\n' | '$SCRIPT' acme"
  bash -c "printf 'n\nn\nn\ny\nUS\n' | '$SCRIPT' beta"

  echo "SEGREDO-ACME" > acme/.env
  echo "MEMORIA-ACME" > acme/_memoria/nota.md

  [ -f "beta/.env" ] && [ ! -s "beta/.env" ]
  [ -d "beta/_memoria" ]
  ! grep -q "SEGREDO-ACME" "beta/.env" 2>/dev/null
  [ ! -e "beta/_memoria/nota.md" ]
}

@test "cada portfolio tem seu proprio settings.json com enabledPlugins independente" {
  bash -c "printf 'y\nn\nn\nn\nBR\n' | '$SCRIPT' acme"
  bash -c "printf 'n\nn\nn\ny\nUS\n' | '$SCRIPT' beta"

  run python3 -c "
import json
acme = json.load(open('acme/.claude/settings.json'))['enabledPlugins']
beta = json.load(open('beta/.claude/settings.json'))['enabledPlugins']
assert acme == {'research': True}, acme
assert beta == {'corretora-banco': True}, beta
"
  [ "$status" -eq 0 ]
}
