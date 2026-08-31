#!/usr/bin/env bash
# Relatorio de diagnostico da carteira atual (concentracao, mercado, liquidez, DY 12m).
#
# Uso:
#   bin/diagnostico.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/diagnostico.sh <slug>

Reporta concentracao no maior ativo, exposicao por mercado (br/us),
percentual em liquidez D+0/D+1 e dividend yield 12m por posicao.
Posicoes em <slug>/holdings.json
({"posicoes": [{"ticker","quantidade","classe","mercado","liquidez?"}]}).
Campo liquidez e opcional (D+0 ou D+1). DY 12m vem da brapi quando o
campo dividendYield existe; senao marca "indisponivel".
Valoriza BR via brapi-quote.sh; US/global exige ALOCACAO_QUOTE injetado.
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

brapi_dividend_yield() {
  local slug="$1" ticker="$2" raw
  if ! raw=$(BRAPI_STATISTICS=1 "$REPO_ROOT/bin/brapi-quote.sh" "$slug" "$ticker" 2>/dev/null); then
    return 0
  fi
  jq -r '.results[0].data.dividendYield // empty' <<<"$raw"
}

merge_quote() {
  local quotes="$1" ticker="$2" preco="$3" dy="$4"
  if [ -n "$dy" ]; then
    jq --arg t "$ticker" --argjson p "$preco" --argjson d "$dy" \
      '.[$t] = {preco: $p, dividendYield: $d}' <<<"$quotes"
    return
  fi
  jq --arg t "$ticker" --argjson p "$preco" '.[$t] = {preco: $p}' <<<"$quotes"
}

resolve_dividend_yield() {
  local slug="$1" ticker="$2" mercado="$3" payload="$4" dy
  dy=$(jq -r '.dividendYield // empty' <<<"$payload")
  if [ -z "$dy" ] && [ "$mercado" = "br" ]; then
    dy=$(brapi_dividend_yield "$slug" "$ticker")
  fi
  printf '%s' "$dy"
}

append_quote() {
  local slug="$1" ticker="$2" mercado="$3" quotes="$4" payload preco dy
  payload=$(quote_payload "$slug" "$ticker" "$mercado")
  preco=$(jq -er '.preco' <<<"$payload")
  dy=$(resolve_dividend_yield "$slug" "$ticker" "$mercado" "$payload")
  merge_quote "$quotes" "$ticker" "$preco" "$dy"
}

collect_quotes() {
  local slug="$1" holdings="$2" dest="$3"
  local tickers ticker mercado quotes
  quotes="{}"
  tickers=$(jq -c '.posicoes[] | {ticker: (.ticker|ascii_upcase), mercado: (.mercado|ascii_downcase)}' "$holdings")
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    ticker=$(jq -r '.ticker' <<<"$row")
    mercado=$(jq -r '.mercado' <<<"$row")
    if jq -e --arg t "$ticker" 'has($t)' <<<"$quotes" >/dev/null; then
      continue
    fi
    quotes=$(append_quote "$slug" "$ticker" "$mercado" "$quotes")
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
require_file "$HOLDINGS" 'JSON {"posicoes": [{ticker, quantidade, classe, mercado, liquidez?}, ...]}'

QUOTES=$(mktemp)
trap 'rm -f "$QUOTES"' EXIT
collect_quotes "$SLUG" "$HOLDINGS" "$QUOTES"
python3 "$SCRIPT_DIR/diagnostico-report.py" "$HOLDINGS" "$QUOTES"
