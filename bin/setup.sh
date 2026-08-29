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
  read -r -p "Portfolio '$SLUG' ja existe. Sobrescrever? [y/N] " CONFIRM
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Cancelado: nada foi alterado." >&2
    exit 1
  fi
fi

mkdir -p "$SLUG/_memoria" "$SLUG/.claude"

cat > "$SLUG/CLAUDE.md" <<EOF
# $SLUG

Portfolio InvestOS. Configure dominios e mercado via setup interativo.
EOF

: > "$SLUG/.env"

cat > "$SLUG/.claude/settings.json" <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "enabledPlugins": {}
}
EOF

cat > "$SLUG/.gitignore" <<'EOF'
.env
EOF

echo "Portfolio '$SLUG' criado em ./$SLUG"
