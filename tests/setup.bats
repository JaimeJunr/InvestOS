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
