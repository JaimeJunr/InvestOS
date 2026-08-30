#!/usr/bin/env bash
# Le credenciais de corretora so do .env local do portfolio.
#
# Uso:
#   bin/credencial.sh <slug> has <KEY>
#
# KEY aceitas: PLAID_CLIENT_ID, PLAID_SECRET.
# Nunca imprime o valor. Nao usa o ambiente do processo. Nao da source no .env.

set -euo pipefail

ALLOWED_KEYS="PLAID_CLIENT_ID PLAID_SECRET"

usage() {
  cat <<EOF >&2
Uso: bin/credencial.sh <slug> has <KEY>

KEY aceitas: PLAID_CLIENT_ID, PLAID_SECRET.
Credencial lida so de <slug>/.env; o valor nunca e impresso.
EOF
}

is_allowed_key() {
  local key="$1"
  [[ " $ALLOWED_KEYS " == *" $key "* ]]
}

read_env_key() {
  local envfile="$1" key="$2"
  if [ ! -f "$envfile" ]; then
    return 0
  fi
  grep -E "^${key}=" "$envfile" | tail -1 | cut -d= -f2- || true
}

SLUG="${1:-}"
CMD="${2:-}"
KEY="${3:-}"

if [ -z "$SLUG" ] || [ -z "$CMD" ] || [ -z "$KEY" ]; then
  usage
  exit 1
fi

if [ "$CMD" != "has" ]; then
  echo "Comando invalido: recebido '$CMD', esperado has." >&2
  usage
  exit 1
fi

if ! is_allowed_key "$KEY"; then
  echo "Chave invalida: recebido '$KEY', esperado um de: PLAID_CLIENT_ID ou PLAID_SECRET." >&2
  exit 1
fi

VALUE=$(read_env_key "$SLUG/.env" "$KEY")
if [ -z "$VALUE" ]; then
  exit 1
fi
exit 0
