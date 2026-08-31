#!/usr/bin/env bash
# Cria a estrutura padrao de um portfolio novo do InvestOS, fora da pasta do
# InvestOS (mesmo padrao do bin/setup.sh do BizOS).
#
# Uso:
#   bin/setup.sh <nome>       # cria em $INVESTOS_PORTFOLIOS_DIR/investos-<nome>
#                              # (default de INVESTOS_PORTFOLIOS_DIR: ~/Documents)
#   bin/setup.sh <caminho>    # caminho explicito (contem "/", comeca com "." ou "~")
#
# Override do diretorio base dos portfolios (nome puro, sem caminho):
#   INVESTOS_PORTFOLIOS_DIR=/outro/lugar bin/setup.sh <nome>
#
# Se o portfolio ja existir, pede confirmacao explicita (y/N) antes de sobrescrever.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_TEMPLATE="$REPO_ROOT/templates/skills"
COMMANDS_TEMPLATE="$REPO_ROOT/templates/commands"
PORTFOLIOS_BASE="${INVESTOS_PORTFOLIOS_DIR:-$HOME/Documents}"

slugify() {
  local input="$1" slug
  slug=$(printf '%s' "$input" | iconv -f utf8 -t ascii//TRANSLIT 2>/dev/null || printf '%s' "$input")
  slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')
  slug=$(printf '%s' "$slug" | sed -E 's/[^a-z0-9/-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')
  printf '%s' "$slug"
}

RAW_ARG="${1:-}"

if [ -z "$RAW_ARG" ]; then
  echo "Uso: bin/setup.sh <nome> | bin/setup.sh <caminho>" >&2
  exit 1
fi

if [[ "$RAW_ARG" == */* || "$RAW_ARG" == .* || "$RAW_ARG" == "~"* ]]; then
  EXPANDED_ARG="${RAW_ARG/#\~/$HOME}"
  DIR_PART="$(dirname "$EXPANDED_ARG")"
  RAW_NAME="$(basename "$EXPANDED_ARG")"
  DIR_PREFIX=""
else
  DIR_PART="$PORTFOLIOS_BASE"
  RAW_NAME="$RAW_ARG"
  DIR_PREFIX="investos-"
fi

SLUG="$(slugify "$RAW_NAME")"

if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9/-]{0,78}[a-z0-9]$ ]] || [[ "$SLUG" == *".."* ]] || [[ "$SLUG" == *"//"* ]]; then
  echo "Slug invalido: recebido '$RAW_ARG' (normalizado para '$SLUG'), esperado formato ^[a-z0-9][a-z0-9/-]{0,78}[a-z0-9]\$, sem // nem .., max. 80 caracteres." >&2
  exit 1
fi

TARGET_DIR="$DIR_PART/$DIR_PREFIX$SLUG"

if [ -d "$TARGET_DIR" ]; then
  read -r -p "Portfolio '$TARGET_DIR' ja existe. Sobrescrever? [y/N] " CONFIRM || CONFIRM=""
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cancelado: nada foi alterado." >&2
    exit 1
  fi
fi

mkdir -p "$DIR_PART"

DOMAINS=(research risco dados-mercado corretora-banco)
ENABLED_PLUGINS="{}"
for domain in "${DOMAINS[@]}"; do
  read -r -p "Habilitar dominio '$domain'? [y/N] " resp || resp=""
  if [ "$resp" = "y" ] || [ "$resp" = "Y" ]; then
    ENABLED_PLUGINS=$(jq --arg d "$domain" '.[$d] = true' <<<"$ENABLED_PLUGINS")
  fi
done

read -r -p "Mercado (BR/US/ambos): " RAW_MERCADO || RAW_MERCADO=""
MERCADO="${RAW_MERCADO,,}"

case "$MERCADO" in
  br | us | ambos) ;;
  *)
    echo "Mercado invalido: recebido '$RAW_MERCADO', esperado um de: br, us ou ambos (comparacao case-insensitive)." >&2
    exit 1
    ;;
esac

mkdir -p "$TARGET_DIR/relatorios" "$TARGET_DIR/.claude/commands"
cp "$COMMANDS_TEMPLATE/instalar.md" "$COMMANDS_TEMPLATE/status.md" "$TARGET_DIR/.claude/commands/"

cat > "$TARGET_DIR/CLAUDE.md" <<EOF
# $SLUG

Portfolio InvestOS. Configure dominios e mercado via setup interativo.

## Memoria e relatorios

Use a memoria nativa do Claude Code (quando disponivel nesta maquina) pra lembrar fatos
duraveis sobre o investidor entre sessoes - perfil de risco, vieses conhecidos, planos de
venda/consolidacao - em vez de inventar um arquivo proprio pra isso.

Analises pontuais (ex.: retorno por ativo, ranking de rentabilidade) sao trabalho seu, nao
do InvestOS - salve como JSON versionavel em analises/ (crie se nao existir), com a
metodologia explicada dentro do proprio arquivo pra nao ser confundido com dado oficial dos
scripts bin/*.sh.

Relatorios formais que o investidor pediu pra guardar (PDF, XML) vao em relatorios/ -
formatar o documento tambem e trabalho seu, o InvestOS so reserva o lugar.
EOF

: > "$TARGET_DIR/.env"
rm -f "$TARGET_DIR/.mcp.json"
MCP_SERVERS='{}'

if jq -e '.["dados-mercado"] == true' <<<"$ENABLED_PLUGINS" >/dev/null &&
  [ "$MERCADO" != "br" ]; then
  printf 'ALPHA_VANTAGE_API_KEY=\n' >> "$TARGET_DIR/.env"
  MCP_SERVERS=$(jq '. + {
      "alpha-vantage": {
        "type": "http",
        "url": "https://mcp.alphavantage.co/mcp?apikey=${ALPHA_VANTAGE_API_KEY}"
      }
    }' <<<"$MCP_SERVERS")
fi

if jq -e '.["dados-mercado"] == true' <<<"$ENABLED_PLUGINS" >/dev/null &&
  [ "$MERCADO" != "us" ]; then
  printf 'BRAPI_TOKEN=\n' >> "$TARGET_DIR/.env"
fi

if jq -e '.["corretora-banco"] == true' <<<"$ENABLED_PLUGINS" >/dev/null; then
  printf 'PLAID_CLIENT_ID=\nPLAID_SECRET=\n' >> "$TARGET_DIR/.env"
  MCP_SERVERS=$(jq '. + {
      "plaid": {
        "type": "stdio",
        "command": "plaid-mcp",
        "readOnly": true,
        "env": {
          "PLAID_CLIENT_ID": "${PLAID_CLIENT_ID}",
          "PLAID_SECRET": "${PLAID_SECRET}",
          "PLAID_ENV": "sandbox",
          "PLAID_PRODUCTS": "transactions",
          "PLAID_OPTIONAL_PRODUCTS": "investments"
        }
      }
    }' <<<"$MCP_SERVERS")
fi

if [ "$MCP_SERVERS" != '{}' ]; then
  jq -n --argjson servers "$MCP_SERVERS" '{mcpServers: $servers}' > "$TARGET_DIR/.mcp.json"
fi

jq -n --argjson plugins "$ENABLED_PLUGINS" \
  '{"$schema": "https://json.schemastore.org/claude-code-settings.json", "enabledPlugins": $plugins}' \
  > "$TARGET_DIR/.claude/settings.json"

jq -n --arg mercado "$MERCADO" '{mercado: $mercado}' > "$TARGET_DIR/portfolio.json"

rm -rf "$TARGET_DIR/.claude/skills"
if jq -e '.["research"] == true' <<<"$ENABLED_PLUGINS" >/dev/null; then
  mkdir -p "$TARGET_DIR/.claude/skills"
  if [ "$MERCADO" != "us" ]; then
    cp -r "$SKILLS_TEMPLATE/research-br" "$TARGET_DIR/.claude/skills/"
  fi
  if [ "$MERCADO" != "br" ]; then
    cp -r "$SKILLS_TEMPLATE/research-us" "$TARGET_DIR/.claude/skills/"
  fi
fi
if jq -e '.["risco"] == true' <<<"$ENABLED_PLUGINS" >/dev/null; then
  mkdir -p "$TARGET_DIR/.claude/skills"
  cp -r "$SKILLS_TEMPLATE/rebalanceamento" "$TARGET_DIR/.claude/skills/"
  cp -r "$SKILLS_TEMPLATE/proventos" "$TARGET_DIR/.claude/skills/"
  cp -r "$SKILLS_TEMPLATE/extratos-b3" "$TARGET_DIR/.claude/skills/"
fi

cat > "$TARGET_DIR/.gitignore" <<'EOF'
.env
_cache/
relatorios/
analises/
EOF

cat <<EOF
Portfolio '$SLUG' criado em $TARGET_DIR

Abra o Claude Code dentro do portfolio:

    cd "$TARGET_DIR" && claude

Depois, rode dentro do Claude Code:

    /instalar     # entrevista guiada (diagnostico + posicoes + alocacao-alvo)
EOF
