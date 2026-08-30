#!/usr/bin/env bash
# Cria a estrutura padrao de um portfolio novo do InvestOS.
#
# Uso:
#   bin/setup.sh <slug>
#
# Se <slug>/ ja existir, pede confirmacao explicita (y/N) antes de sobrescrever.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_TEMPLATE="$REPO_ROOT/templates/skills"

slugify() {
  local input="$1" slug
  slug=$(printf '%s' "$input" | iconv -f utf8 -t ascii//TRANSLIT 2>/dev/null || printf '%s' "$input")
  slug=$(printf '%s' "$slug" | tr '[:upper:]' '[:lower:]')
  slug=$(printf '%s' "$slug" | sed -E 's/[^a-z0-9/-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')
  printf '%s' "$slug"
}

RAW_SLUG="${1:-}"

if [ -z "$RAW_SLUG" ]; then
  echo "Uso: bin/setup.sh <slug>" >&2
  exit 1
fi

SLUG="$(slugify "$RAW_SLUG")"

if [[ ! "$SLUG" =~ ^[a-z0-9][a-z0-9/-]{0,78}[a-z0-9]$ ]] || [[ "$SLUG" == *".."* ]] || [[ "$SLUG" == *"//"* ]]; then
  echo "Slug invalido: recebido '$RAW_SLUG' (normalizado para '$SLUG'), esperado formato ^[a-z0-9][a-z0-9/-]{0,78}[a-z0-9]\$, sem // nem .., max. 80 caracteres." >&2
  exit 1
fi

if [ -d "$SLUG" ]; then
  read -r -p "Portfolio '$SLUG' ja existe. Sobrescrever? [y/N] " CONFIRM || CONFIRM=""
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cancelado: nada foi alterado." >&2
    exit 1
  fi
fi

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

mkdir -p "$SLUG/_memoria" "$SLUG/.claude"

cat > "$SLUG/CLAUDE.md" <<EOF
# $SLUG

Portfolio InvestOS. Configure dominios e mercado via setup interativo.
EOF

: > "$SLUG/.env"
rm -f "$SLUG/.mcp.json"

if jq -e '.["dados-mercado"] == true' <<<"$ENABLED_PLUGINS" >/dev/null &&
  [ "$MERCADO" != "br" ]; then
  printf 'ALPHA_VANTAGE_API_KEY=\n' >> "$SLUG/.env"
  jq -n '
    {
      "mcpServers": {
        "alpha-vantage": {
          "type": "http",
          "url": "https://mcp.alphavantage.co/mcp?apikey=${ALPHA_VANTAGE_API_KEY}"
        }
      }
    }
  ' > "$SLUG/.mcp.json"
fi

if jq -e '.["dados-mercado"] == true' <<<"$ENABLED_PLUGINS" >/dev/null &&
  [ "$MERCADO" != "us" ]; then
  printf 'BRAPI_TOKEN=\n' >> "$SLUG/.env"
fi

jq -n --argjson plugins "$ENABLED_PLUGINS" \
  '{"$schema": "https://json.schemastore.org/claude-code-settings.json", "enabledPlugins": $plugins}' \
  > "$SLUG/.claude/settings.json"

jq -n --arg mercado "$MERCADO" '{mercado: $mercado}' > "$SLUG/portfolio.json"

rm -rf "$SLUG/.claude/skills"
if jq -e '.["research"] == true' <<<"$ENABLED_PLUGINS" >/dev/null; then
  mkdir -p "$SLUG/.claude/skills"
  if [ "$MERCADO" != "us" ]; then
    cp -r "$SKILLS_TEMPLATE/research-br" "$SLUG/.claude/skills/"
  fi
  if [ "$MERCADO" != "br" ]; then
    cp -r "$SKILLS_TEMPLATE/research-us" "$SLUG/.claude/skills/"
  fi
fi

cat > "$SLUG/.gitignore" <<'EOF'
.env
_cache/
EOF

echo "Portfolio '$SLUG' criado em ./$SLUG"
