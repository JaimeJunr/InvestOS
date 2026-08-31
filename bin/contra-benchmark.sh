#!/usr/bin/env bash
# Relatorio de Beta, Alfa, R-quadrado e Tracking Error vs. o benchmark do mercado.
#
# Uso:
#   bin/contra-benchmark.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/contra-benchmark.sh <slug>

Calcula Beta, Alfa, R-quadrado e Tracking Error da carteira contra o
benchmark equivalente (br=^BVSP via benchmark-quote.sh, us=^GSPC via
BENCHMARK_QUOTE), no mesmo periodo dos snapshots em
<slug>/nav-historico.json. Mercado lido de <slug>/portfolio.json.
Com historico insuficiente reporta a string "historico insuficiente"
em vez de um numero instavel.
EOF
}

require_file() {
  local file="$1" expected="$2"
  if [ ! -f "$file" ]; then
    echo "Arquivo invalido: recebido path inexistente '$file', esperado $expected." >&2
    exit 1
  fi
}

ticker_for() {
  case "$1" in
    br) printf '%s\n' '^BVSP' ;;
    us) printf '%s\n' '^GSPC' ;;
    *)
      echo "Mercado invalido: recebido '$1', esperado 'br|us'." >&2
      exit 1
      ;;
  esac
}

markets_for() {
  case "$1" in
    br | us) printf '%s\n' "$1" ;;
    ambos)
      printf '%s\n' br
      printf '%s\n' us
      ;;
    *)
      echo "Mercado invalido: recebido '$1', esperado 'br|us|ambos'." >&2
      exit 1
      ;;
  esac
}

normalize_series() {
  jq -c \
    '(.results[0].data.historicalDataPrice // []) | map({date: ((.date | todateiso8601)[0:10]), close: (.adjustedClose // .close)}) | sort_by(.date)' \
    <<<"$1"
}

fetch_series() {
  local slug="$1" mercado="$2" raw
  raw=$("$REPO_ROOT/bin/benchmark-quote.sh" "$slug" "$mercado")
  normalize_series "$raw"
}

collect_benchmarks() {
  local slug="$1" mercado="$2" dest="$3"
  local bundle market ticker series
  bundle="{}"
  while IFS= read -r market; do
    [ -n "$market" ] || continue
    ticker=$(ticker_for "$market")
    series=$(fetch_series "$slug" "$market")
    bundle=$(jq --arg m "$market" --arg t "$ticker" --argjson s "$series" \
      '.[$m] = {ticker: $t, pontos: $s}' <<<"$bundle")
  done < <(markets_for "$mercado")
  printf '%s\n' "$bundle" > "$dest"
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

PORTFOLIO="$SLUG/portfolio.json"
require_file "$PORTFOLIO" 'JSON {"mercado": "br"|"us"|"ambos"}'
MERCADO=$(jq -r '.mercado // empty' "$PORTFOLIO")
if [ -z "$MERCADO" ]; then
  echo "Mercado invalido: recebido '$MERCADO' em '$PORTFOLIO', esperado 'br|us|ambos'." >&2
  exit 1
fi

NAV="$SLUG/nav-historico.json"
NAV_INPUT=$(mktemp)
BENCH=$(mktemp)
trap 'rm -f "$NAV_INPUT" "$BENCH"' EXIT
if [ -f "$NAV" ]; then
  cat "$NAV" > "$NAV_INPUT"
else
  printf '%s\n' '[]' > "$NAV_INPUT"
fi
collect_benchmarks "$SLUG" "$MERCADO" "$BENCH"
python3 "$SCRIPT_DIR/contra-benchmark-report.py" "$NAV_INPUT" "$BENCH" "$MERCADO"
