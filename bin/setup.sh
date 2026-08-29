#!/usr/bin/env bash
# Cria a estrutura padrao de um portfolio novo do InvestOS.
#
# Uso:
#   bin/setup.sh <slug>
#
# Se <slug>/ ja existir, pede confirmacao explicita (y/N) antes de sobrescrever.

set -euo pipefail

SLUG="${1:-}"

if [ -z "$SLUG" ]; then
  echo "Uso: bin/setup.sh <slug>" >&2
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

read -r -p "Mercado (BR/US/ambos): " MERCADO || MERCADO=""

mkdir -p "$SLUG/_memoria" "$SLUG/.claude"

cat > "$SLUG/CLAUDE.md" <<EOF
# $SLUG

Portfolio InvestOS. Configure dominios e mercado via setup interativo.
EOF

: > "$SLUG/.env"

jq -n --argjson plugins "$ENABLED_PLUGINS" \
  '{"$schema": "https://json.schemastore.org/claude-code-settings.json", "enabledPlugins": $plugins}' \
  > "$SLUG/.claude/settings.json"

jq -n --arg mercado "$MERCADO" '{mercado: $mercado}' > "$SLUG/portfolio.json"

cat > "$SLUG/.gitignore" <<'EOF'
.env
EOF

echo "Portfolio '$SLUG' criado em ./$SLUG"
