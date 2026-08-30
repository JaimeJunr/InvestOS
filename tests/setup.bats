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
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
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
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  run python3 -c "import json,sys; d=json.load(open('acme/.claude/settings.json')); sys.exit(0 if d.get('enabledPlugins') == {} else 1)"
  [ "$status" -eq 0 ]
}

@test "portfolio existente: sem confirmacao explicita, nao sobrescreve" {
  printf 'n\nn\nn\nn\nBR\n' | "$SCRIPT" ./acme
  echo "SENTINELA" >> acme/CLAUDE.md
  run bash -c "echo n | '$SCRIPT' ./acme"
  [ "$status" -ne 0 ]
  grep -q "SENTINELA" acme/CLAUDE.md
}

@test "portfolio existente: com confirmacao explicita (y), sobrescreve" {
  printf 'n\nn\nn\nn\nBR\n' | "$SCRIPT" ./acme
  echo "SENTINELA" >> acme/CLAUDE.md
  run bash -c "printf 'y\nn\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  ! grep -q "SENTINELA" acme/CLAUDE.md
}

# Testes de wg-US-002: setup interativo pergunta dominios e mercado.

@test "dominios respondidos com y ficam habilitados em settings.json" {
  run bash -c "printf 'y\nn\ny\nn\nUS\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.load(open('acme/.claude/settings.json'))['enabledPlugins']
assert d == {'research': True, 'dados-mercado': True}, d
"
  [ "$status" -eq 0 ]
}

@test "nenhum dominio habilitado mantem enabledPlugins vazio" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.load(open('acme/.claude/settings.json'))
assert d['enabledPlugins'] == {}, d
"
  [ "$status" -eq 0 ]
}

@test "mercado escolhido fica registrado em portfolio.json" {
  run bash -c "printf 'n\nn\nn\nn\nambos\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.load(open('acme/portfolio.json'))
assert d['mercado'] == 'ambos', d
"
  [ "$status" -eq 0 ]
}

@test "mercado aceita somente o enum com comparacao case-insensitive e normaliza para minusculas" {
  index=0
  for entry in "BR:br" "Br:br" "br:br" "US:us" "uS:us" "ambos:ambos" "AMBOS:ambos"; do
    input="${entry%%:*}"
    expected="${entry##*:}"
    slug="portfolio-${input,,}-$index"
    index=$((index + 1))

    run bash -c "printf 'n\nn\nn\nn\n%s\n' '$input' | '$SCRIPT' './$slug'"
    [ "$status" -eq 0 ]
    run jq -e --arg expected "$expected" '.mercado == $expected' "$slug/portfolio.json"
    [ "$status" -eq 0 ]
  done
}

@test "mercado fora do enum e rejeitado com valor recebido e valores aceitos" {
  run bash -c "printf 'n\nn\nn\nn\nbrasil\n' | '$SCRIPT' ./acme"
  [ "$status" -ne 0 ]
  [[ "$output" == *"brasil"* ]]
  [[ "$output" == *"br"* ]]
  [[ "$output" == *"us"* ]]
  [[ "$output" == *"ambos"* ]]
  [ ! -d "acme" ]
}

# Testes de wg-US-003: slug normalizado e validado na criacao.

@test "slug com espacos e maiusculas e normalizado (slugify) antes de criar a pasta" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' './Meu Portfolio'"
  [ "$status" -eq 0 ]
  [ -d "meu-portfolio" ]
  [ ! -d "Meu Portfolio" ]
}

@test "slug com acentos e normalizado (translit) antes de criar a pasta" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' './Ações Tech'"
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
  bash -c "printf 'y\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  bash -c "printf 'n\nn\nn\ny\nUS\n' | '$SCRIPT' ./beta"

  echo "SEGREDO-ACME" > acme/.env
  echo "MEMORIA-ACME" > acme/_memoria/nota.md

  [ -f "beta/.env" ]
  [ -d "beta/_memoria" ]
  grep -q "PLAID_" "beta/.env"
  ! grep -q "SEGREDO-ACME" "beta/.env"
  [ ! -e "beta/_memoria/nota.md" ]
}

@test "cada portfolio tem seu proprio settings.json com enabledPlugins independente" {
  bash -c "printf 'y\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  bash -c "printf 'n\nn\nn\ny\nUS\n' | '$SCRIPT' ./beta"

  run python3 -c "
import json
acme = json.load(open('acme/.claude/settings.json'))['enabledPlugins']
beta = json.load(open('beta/.claude/settings.json'))['enabledPlugins']
assert acme == {'research': True}, acme
assert beta == {'corretora-banco': True}, beta
"
  [ "$status" -eq 0 ]
}

# Testes de mdr-US-001: integra Alpha Vantage para mercado US/global.

@test "mercado us gera MCP Alpha Vantage somente com dados de mercado habilitado" {
  run bash -c "printf 'n\nn\ny\nn\nus\n' | '$SCRIPT' ./com-dominio"
  [ "$status" -eq 0 ]
  [ -f "com-dominio/.mcp.json" ]
  run jq -e '
    .mcpServers["alpha-vantage"] == {
      "type": "http",
      "url": "https://mcp.alphavantage.co/mcp?apikey=${ALPHA_VANTAGE_API_KEY}"
    }
  ' "com-dominio/.mcp.json"
  [ "$status" -eq 0 ]
  grep -qx 'ALPHA_VANTAGE_API_KEY=' "com-dominio/.env"

  run bash -c "printf 'n\nn\nn\nn\nus\n' | '$SCRIPT' ./sem-dominio"
  [ "$status" -eq 0 ]
  [ ! -e "sem-dominio/.mcp.json" ]
  [ ! -s "sem-dominio/.env" ]
}

@test "mercado ambos gera MCP Alpha Vantage e mercado br nao gera" {
  run bash -c "printf 'n\nn\ny\nn\nambos\n' | '$SCRIPT' ./global"
  [ "$status" -eq 0 ]
  [ -f "global/.mcp.json" ]
  run jq -e '.mcpServers["alpha-vantage"].url | contains("${ALPHA_VANTAGE_API_KEY}")' "global/.mcp.json"
  [ "$status" -eq 0 ]
  grep -qx 'ALPHA_VANTAGE_API_KEY=' "global/.env"

  run bash -c "printf 'y\nn\nn\ny\nn\nbr\n' | '$SCRIPT' ./global"
  [ "$status" -eq 0 ]
  [ ! -e "global/.mcp.json" ]
  ! grep -q 'ALPHA_VANTAGE_API_KEY' "global/.env"
}

# Testes de mdr-US-002: setup integra o client brapi.dev (token + cache gitignorado).

@test "dados-mercado + mercado br grava BRAPI_TOKEN vazio e ignora _cache/" {
  run bash -c "printf 'n\nn\ny\nn\nbr\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  grep -qx 'BRAPI_TOKEN=' "acme/.env"
  grep -qx '_cache/' "acme/.gitignore"
  [ ! -e "acme/.mcp.json" ]
}

@test "dados-mercado + mercado ambos grava Alpha Vantage e BRAPI_TOKEN" {
  run bash -c "printf 'n\nn\ny\nn\nambos\n' | '$SCRIPT' ./global"
  [ "$status" -eq 0 ]
  grep -qx 'ALPHA_VANTAGE_API_KEY=' "global/.env"
  grep -qx 'BRAPI_TOKEN=' "global/.env"
  grep -qx '_cache/' "global/.gitignore"
  [ -f "global/.mcp.json" ]
}

# Testes de mdr-US-004: 1 skill de research funcional por mercado habilitado.

assert_skill() {
  local path="$1" expected_name="$2" needle="$3"
  [ -f "$path" ]
  grep -q "^name: ${expected_name}$" "$path"
  grep -q "^description: Use when" "$path"
  grep -qi "$needle" "$path"
}

@test "research + mercado br instala so a skill de fundamentals BR" {
  run bash -c "printf 'y\nn\nn\nn\nbr\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  assert_skill "acme/.claude/skills/research-br/SKILL.md" "research-br" "brapi-quote.sh"
  grep -q "cvm-informe.sh" "acme/.claude/skills/research-br/SKILL.md"
  grep -qi "fundamentals" "acme/.claude/skills/research-br/SKILL.md"
  [ ! -e "acme/.claude/skills/research-us" ]
}

@test "research + mercado us instala so a skill de fundamentals US" {
  run bash -c "printf 'y\nn\nn\nn\nus\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  assert_skill "acme/.claude/skills/research-us/SKILL.md" "research-us" "alpha-vantage"
  grep -qi "fundamentals" "acme/.claude/skills/research-us/SKILL.md"
  [ ! -e "acme/.claude/skills/research-br" ]
}

@test "research + mercado ambos instala as duas skills de research" {
  run bash -c "printf 'y\nn\nn\nn\nambos\n' | '$SCRIPT' ./global"
  [ "$status" -eq 0 ]
  assert_skill "global/.claude/skills/research-br/SKILL.md" "research-br" "brapi-quote.sh"
  assert_skill "global/.claude/skills/research-us/SKILL.md" "research-us" "alpha-vantage"
}

@test "sem dominio research nao instala skill mesmo com dados-mercado" {
  run bash -c "printf 'n\nn\ny\nn\nbr\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  [ -f "acme/.claude/settings.json" ]
  [ -f "acme/portfolio.json" ]
  [ ! -e "acme/.claude/skills/research-br" ]
  [ ! -e "acme/.claude/skills/research-us" ]
}

@test "overwrite de ambos para br remove a skill US residual" {
  printf 'y\nn\nn\nn\nambos\n' | "$SCRIPT" ./acme
  [ -f "acme/.claude/skills/research-us/SKILL.md" ]
  run bash -c "printf 'y\ny\nn\nn\nn\nbr\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  assert_skill "acme/.claude/skills/research-br/SKILL.md" "research-br" "brapi-quote.sh"
  [ ! -e "acme/.claude/skills/research-us" ]
}

# Testes de bi-US-001: MCP Plaid read-only via config declarativa.

@test "corretora-banco gera MCP Plaid com placeholder no .env" {
  run bash -c "printf 'n\nn\nn\ny\nbr\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  [ -f "acme/.mcp.json" ]
  run jq -e '
    .mcpServers.plaid.command == "plaid-mcp"
    and .mcpServers.plaid.type == "stdio"
    and .mcpServers.plaid.env.PLAID_CLIENT_ID == "${PLAID_CLIENT_ID}"
    and .mcpServers.plaid.env.PLAID_SECRET == "${PLAID_SECRET}"
  ' "acme/.mcp.json"
  [ "$status" -eq 0 ]
  grep -qx 'PLAID_CLIENT_ID=' "acme/.env"
  grep -qx 'PLAID_SECRET=' "acme/.env"
}

@test "sem dominio corretora-banco nao gera MCP Plaid" {
  run bash -c "printf 'n\nn\nn\nn\nbr\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  [ ! -e "acme/.mcp.json" ]
  ! grep -q 'PLAID_' "acme/.env"
}

@test "dados-mercado us + corretora-banco coexistem no mesmo .mcp.json" {
  run bash -c "printf 'n\nn\ny\ny\nus\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  run jq -e '.mcpServers["alpha-vantage"] and .mcpServers.plaid' "acme/.mcp.json"
  [ "$status" -eq 0 ]
  grep -qx 'ALPHA_VANTAGE_API_KEY=' "acme/.env"
  grep -qx 'PLAID_CLIENT_ID=' "acme/.env"
}

@test "MCP Plaid e estritamente read-only (sem escrita/ordem)" {
  run bash -c "printf 'n\nn\nn\ny\nus\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  run jq -e '.mcpServers.plaid.readOnly == true' "acme/.mcp.json"
  [ "$status" -eq 0 ]
  run jq -e '
    (.mcpServers.plaid | tostring | ascii_downcase)
    | (contains("transfer") or contains("payment") or contains("place_order") or contains("trading"))
    | not
  ' "acme/.mcp.json"
  [ "$status" -eq 0 ]
  run jq -e '.mcpServers.plaid.env.PLAID_OPTIONAL_PRODUCTS | contains("investments")' "acme/.mcp.json"
  [ "$status" -eq 0 ]
}

@test "overwrite corretora on para off remove MCP Plaid residual" {
  printf 'n\nn\nn\ny\nbr\n' | "$SCRIPT" ./acme
  [ -f "acme/.mcp.json" ]
  run bash -c "printf 'y\nn\nn\nn\nn\nbr\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  [ ! -e "acme/.mcp.json" ]
  ! grep -q 'PLAID_' "acme/.env"
}

@test "gera .claude/commands/instalar.md e status.md sempre, mesmo sem nenhum dominio habilitado" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  [ -f "acme/.claude/commands/instalar.md" ]
  [ -f "acme/.claude/commands/status.md" ]
}

@test "instalar.md referencia os 3 arquivos de dados do portfolio" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  grep -q "holdings.json" "acme/.claude/commands/instalar.md"
  grep -q "alocacao-alvo.json" "acme/.claude/commands/instalar.md"
  grep -q "watchlist-fundos.json" "acme/.claude/commands/instalar.md"
}

@test "instalar.md faz diagnostico de perfil/objetivos/reserva/custos antes de perguntar posicoes" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  grep -qi "perfil" "acme/.claude/commands/instalar.md"
  grep -qi "conservador" "acme/.claude/commands/instalar.md"
  grep -qi "reserva de emergencia" "acme/.claude/commands/instalar.md"
  grep -q "perfil-investidor.json" "acme/.claude/commands/instalar.md"
  grep -qi "prazo" "acme/.claude/commands/instalar.md"
}

@test "status.md e read-only: nao instrui escrever holdings.json nem alocacao-alvo.json" {
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' ./acme"
  [ "$status" -eq 0 ]
  [ -f "acme/.claude/commands/status.md" ]
  ! grep -qiE "grav(e|ar)|escrev(a|er)|crie|atualiz(e|ar)" "acme/.claude/commands/status.md"
}

# Portfolio criado fora da pasta do InvestOS (mesmo padrao do bin/setup.sh do BizOS):
# nome puro -> $INVESTOS_PORTFOLIOS_DIR/investos-<slug> (default: ~/Documents);
# caminho explicito (contem "/", comeca com "." ou "~") -> respeitado literalmente.

@test "nome puro (sem caminho) cria em INVESTOS_PORTFOLIOS_DIR/investos-<slug>, nao no cwd" {
  EXTERNAL="$(mktemp -d)"
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | INVESTOS_PORTFOLIOS_DIR='$EXTERNAL' '$SCRIPT' acme-externo"
  [ "$status" -eq 0 ]
  [ ! -e "acme-externo" ]
  [ -f "$EXTERNAL/investos-acme-externo/CLAUDE.md" ]
  rm -rf "$EXTERNAL"
}

@test "sem INVESTOS_PORTFOLIOS_DIR, nome puro cai no default (\$HOME/Documents)" {
  FAKE_HOME="$(mktemp -d)"
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | HOME='$FAKE_HOME' '$SCRIPT' acme-default"
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/Documents/investos-acme-default/CLAUDE.md" ]
  rm -rf "$FAKE_HOME"
}

@test "caminho absoluto explicito e respeitado literalmente, sem prefixo investos-" {
  EXTERNAL="$(mktemp -d)"
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | '$SCRIPT' '$EXTERNAL/algum/lugar/carteira'"
  [ "$status" -eq 0 ]
  [ -f "$EXTERNAL/algum/lugar/carteira/CLAUDE.md" ]
  [ ! -d "$EXTERNAL/algum/lugar/investos-carteira" ]
  rm -rf "$EXTERNAL"
}

@test "til (~) no caminho e expandido para o HOME" {
  FAKE_HOME="$(mktemp -d)"
  run bash -c "printf 'n\nn\nn\nn\nBR\n' | HOME='$FAKE_HOME' '$SCRIPT' '~/carteira-til'"
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/carteira-til/CLAUDE.md" ]
  rm -rf "$FAKE_HOME"
}
