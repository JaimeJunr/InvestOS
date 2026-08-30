#!/usr/bin/env bash
# Fake nomeado do fetch de holdings da corretora. Nao faz I/O de rede.
set -euo pipefail

slug="${1:-}"
if [ -z "$slug" ]; then
  echo "fake-plaid-holdings: recebido slug vazio, esperado <slug>." >&2
  exit 1
fi

if [ -n "${PLAID_HOLDINGS_LOG:-}" ]; then
  printf '%s\n' "$slug" >> "$PLAID_HOLDINGS_LOG"
fi

if [ "${PLAID_HOLDINGS_FAIL:-}" = "1" ]; then
  echo "fake-plaid-holdings: conexao falhou (token expirado)." >&2
  exit 1
fi

fixture="${PLAID_HOLDINGS_FIXTURE:-}"
if [ -z "$fixture" ] || [ ! -f "$fixture" ]; then
  echo "fake-plaid-holdings: recebido PLAID_HOLDINGS_FIXTURE='$fixture', esperado arquivo JSON {\"posicoes\": [...]}." >&2
  exit 1
fi

cat "$fixture"
