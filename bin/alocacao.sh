#!/usr/bin/env bash
# Relatorio de alocacao atual vs. alocacao-alvo a partir de holdings.json.
#
# Uso:
#   bin/alocacao.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/alocacao.sh <slug>

Compara a alocacao atual do portfolio com a alocacao-alvo.
Posicoes manuais em <slug>/holdings.json
({"posicoes": [{"ticker","quantidade","classe","mercado","precoManual?"}]}).
precoManual (opcional) e o preco unitario pra posicoes sem ticker cotavel
(ex.: Tesouro Direto) - quando presente, nao tenta cotar externamente.
Alvo em <slug>/alocacao-alvo.json
({"porClasse": {<classe>: peso}, "porMercado": {"br"|"us": peso}}, pesos somam 1).
Valoriza BR via brapi-quote.sh; US/global exige ALOCACAO_QUOTE injetado
(MCP Alpha Vantage e so config declarativa, sem client HTTP first-party).
EOF
}

require_file() {
  local file="$1" expected="$2"
  if [ ! -f "$file" ]; then
    echo "Arquivo invalido: recebido path inexistente '$file', esperado $expected." >&2
    exit 1
  fi
}

quote_payload() {
  local slug="$1" ticker="$2" mercado="$3" raw
  if [ -n "${ALOCACAO_QUOTE:-}" ]; then
    "$ALOCACAO_QUOTE" "$slug" "$ticker" "$mercado"
    return
  fi
  if [ "$mercado" = "br" ]; then
    raw=$("$REPO_ROOT/bin/brapi-quote.sh" "$slug" "$ticker")
    jq -ce '{preco: .results[0].data.regularMarketPrice}' <<<"$raw"
    return
  fi
  echo "Cotacao indisponivel: recebido mercado '$mercado' ticker '$ticker', esperado mercado 'br' (brapi.dev) ou ALOCACAO_QUOTE injetado (MCP US e config declarativa, sem client HTTP)." >&2
  exit 1
}

collect_quotes() {
  local slug="$1" holdings="$2" dest="$3"
  local tickers ticker mercado preco_manual payload preco quotes
  quotes="{}"
  tickers=$(jq -c '.posicoes[] | {ticker: (.ticker|ascii_upcase), mercado: (.mercado|ascii_downcase), precoManual: (.precoManual // null)}' "$holdings")
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    ticker=$(jq -r '.ticker' <<<"$row")
    mercado=$(jq -r '.mercado' <<<"$row")
    if jq -e --arg t "$ticker" 'has($t)' <<<"$quotes" >/dev/null; then
      continue
    fi
    preco_manual=$(jq -r '.precoManual // empty' <<<"$row")
    if [ -n "$preco_manual" ]; then
      quotes=$(jq --arg t "$ticker" --argjson p "$preco_manual" '.[$t] = $p' <<<"$quotes")
      continue
    fi
    payload=$(quote_payload "$slug" "$ticker" "$mercado")
    preco=$(jq -er '.preco' <<<"$payload")
    quotes=$(jq --arg t "$ticker" --argjson p "$preco" '.[$t] = $p' <<<"$quotes")
  done <<<"$tickers"
  printf '%s\n' "$quotes" > "$dest"
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
ALVO="$SLUG/alocacao-alvo.json"
require_file "$HOLDINGS" 'JSON {"posicoes": [{ticker, quantidade, classe, mercado}, ...]}'
require_file "$ALVO" 'JSON {"porClasse": {<classe>: peso}, "porMercado": {br|us: peso}} com pesos somando 1'

QUOTES=$(mktemp)
trap 'rm -f "$QUOTES"' EXIT
collect_quotes "$SLUG" "$HOLDINGS" "$QUOTES"
python3 "$SCRIPT_DIR/alocacao-report.py" "$HOLDINGS" "$ALVO" "$QUOTES"
