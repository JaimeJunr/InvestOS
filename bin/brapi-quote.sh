#!/usr/bin/env bash
# Consulta cotacao/historico/estatisticas BR via brapi.dev v2, com cache local por portfolio.
#
# Uso:
#   bin/brapi-quote.sh <slug> <ticker>

set -euo pipefail

FREE_TICKERS="PETR4 VALE3 MGLU3 ITUB4"
BRAPI_BASE_URL="${BRAPI_BASE_URL:-https://brapi.dev/api/v2/stocks}"
CACHE_TTL="${BRAPI_CACHE_TTL_SECONDS:-3600}"

usage() {
  cat <<EOF
Uso: bin/brapi-quote.sh <slug> <ticker>

Consulta cotacao de acoes/ETFs/FIIs BR via brapi.dev v2 (free tier, 15.000 req/mes).
Tickers gratuitos sem token: PETR4, VALE3, MGLU3, ITUB4.
Demais tickers exigem BRAPI_TOKEN no <slug>/.env (cadastro gratuito em brapi.dev),
enviado como header Authorization: Bearer (nunca na URL).
Cache local em <slug>/_cache/brapi/ evita estourar a quota (TTL ${CACHE_TTL}s).

Modos (via env, mesma interface do endpoint de cotacao):
  BRAPI_RANGE=<janela> BRAPI_INTERVAL=<intervalo>  -> GET /v2/stocks/historical
  BRAPI_STATISTICS=1                                -> GET /v2/stocks/statistics
  (nenhum dos dois)                                 -> GET /v2/stocks/quote

Fallback opcional via yfinance com sufixo .SA (ex.: PETR4.SA), sem quota garantida.
EOF
}

now_epoch() {
  if [ -n "${BRAPI_NOW:-}" ]; then
    printf '%s' "$BRAPI_NOW"
  else
    date +%s
  fi
}

read_token() {
  local envfile="$1"
  if [ ! -f "$envfile" ]; then
    return 0
  fi
  grep -E '^BRAPI_TOKEN=' "$envfile" | tail -1 | cut -d= -f2- || true
}

is_free_ticker() {
  local ticker="$1"
  [[ " $FREE_TICKERS " == *" $ticker "* ]]
}

http_get() {
  local url="$1" token="$2"
  if [ -n "${BRAPI_HTTP_GET:-}" ]; then
    "$BRAPI_HTTP_GET" "$url" "$token"
  elif [ -n "$token" ]; then
    curl -fsS -H "Authorization: Bearer $token" "$url"
  else
    curl -fsS "$url"
  fi
}

read_fresh_cache() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi
  jq -ce --argjson now "$(now_epoch)" --argjson ttl "$CACHE_TTL" \
    'select($now - .fetchedAt < $ttl) | .payload' "$file"
}

write_cache() {
  local file="$1" payload="$2"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$payload" | jq -c --argjson fetched "$(now_epoch)" \
    '{fetchedAt: $fetched, payload: .}' > "$file"
}

build_quote_url() {
  local ticker="$1"
  if [ -n "${BRAPI_STATISTICS:-}" ]; then
    printf '%s/statistics?symbols=%s' "$BRAPI_BASE_URL" "$ticker"
    return
  fi
  if [ -n "${BRAPI_RANGE:-}" ]; then
    printf '%s/historical?symbols=%s&range=%s&interval=%s' \
      "$BRAPI_BASE_URL" "$ticker" "$BRAPI_RANGE" "${BRAPI_INTERVAL:-1d}"
    return
  fi
  printf '%s/quote?symbols=%s' "$BRAPI_BASE_URL" "$ticker"
}

cache_path() {
  local slug="$1" ticker="$2"
  if [ -n "${BRAPI_STATISTICS:-}" ]; then
    printf '%s/_cache/brapi/%s-statistics.json' "$slug" "$ticker"
    return
  fi
  if [ -n "${BRAPI_RANGE:-}" ]; then
    printf '%s/_cache/brapi/%s-%s-%s.json' "$slug" "$ticker" "$BRAPI_RANGE" "${BRAPI_INTERVAL:-1d}"
    return
  fi
  printf '%s/_cache/brapi/%s.json' "$slug" "$ticker"
}

SLUG="${1:-}"
RAW_TICKER="${2:-}"

if [ -z "$SLUG" ] || [ -z "$RAW_TICKER" ]; then
  usage >&2
  exit 1
fi

if [ ! -d "$SLUG" ]; then
  echo "Portfolio invalido: recebido '$SLUG', esperado diretorio de portfolio existente." >&2
  exit 1
fi

TICKER=$(printf '%s' "$RAW_TICKER" | tr '[:lower:]' '[:upper:]')
TOKEN=$(read_token "$SLUG/.env")
CACHE=$(cache_path "$SLUG" "$TICKER")

if payload=$(read_fresh_cache "$CACHE"); then
  printf '%s\n' "$payload"
  exit 0
fi

if [ -z "$TOKEN" ] && ! is_free_ticker "$TICKER"; then
  echo "Ticker nao-gratuito: recebido '$TICKER', esperado um de: $FREE_TICKERS (sem token) ou BRAPI_TOKEN no $SLUG/.env (cadastro gratuito)." >&2
  exit 1
fi

payload=$(http_get "$(build_quote_url "$TICKER")" "$TOKEN")
write_cache "$CACHE" "$payload"
printf '%s\n' "$payload"
