#!/usr/bin/env bash
# Relatorio de risco (VaR historico, Sharpe, max drawdown) a partir do historico.
#
# Uso:
#   bin/risco.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/risco.sh <slug>

Calcula VaR historico 95%, Sharpe (rf=0, anualizado 252) e max drawdown
do portfolio a partir do historico de precos em <slug>/holdings.json.
BR acoes/ETFs/FIIs via brapi-quote.sh (range=3mo, interval=1d);
BR fundos (ticker CNPJ 14 digitos) via cvm-informe.sh; US/global exige
RISCO_HISTORY injetado (MCP Alpha Vantage e so config declarativa).
Ativo sem historico suficiente gera aviso e nao trava o relatorio.
Posicao com precoManual (ex.: Tesouro Direto sem ticker cotavel) nao
busca historico externo - entra direto como historico insuficiente.
EOF
}

require_file() {
  local file="$1" expected="$2"
  if [ ! -f "$file" ]; then
    echo "Arquivo invalido: recebido path inexistente '$file', esperado $expected." >&2
    exit 1
  fi
}

# cvm_series/brapi_series/history_payload (e digits_only/is_cnpj) foram
# extraidas para lib-serie.sh: achados.sh (US-003) precisa exatamente das
# mesmas funcoes pra buscar serie por ticker no enriquecimento de
# "concentracao", e RISCO_HISTORY e o mesmo override nos dois lugares (o
# investidor configura um so).
source "$SCRIPT_DIR/lib-serie.sh"

collect_histories() {
  local slug="$1" holdings="$2" dest="$3"
  local ticker mercado preco_manual payload series
  series="{}"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    ticker=$(jq -r '.ticker' <<<"$row")
    mercado=$(jq -r '.mercado' <<<"$row")
    preco_manual=$(jq -r '.precoManual // empty' <<<"$row")
    if [ -n "$preco_manual" ]; then
      continue
    fi
    payload=$(history_payload "$slug" "$ticker" "$mercado")
    series=$(jq --arg t "$ticker" --argjson s "$payload" '.[$t] = $s' <<<"$series")
  done < <(jq -c '.posicoes[] | {ticker: (.ticker|tostring|ascii_upcase), mercado: (.mercado|ascii_downcase), precoManual: (.precoManual // null)}' "$holdings")
  printf '%s\n' "$series" > "$dest"
}

SLUG="${1:-}"

if [ -z "$SLUG" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

HOLDINGS="$SLUG/holdings.json"
require_file "$HOLDINGS" 'JSON {"posicoes": [{ticker, quantidade, classe, mercado, precoManual?}, ...]}'

HISTORY=$(mktemp)
trap 'rm -f "$HISTORY"' EXIT
collect_histories "$SLUG" "$HOLDINGS" "$HISTORY"
python3 "$SCRIPT_DIR/risco-report.py" "$HOLDINGS" "$HISTORY"
