#!/usr/bin/env bash
# Relatorio informativo de ganho/perda nao realizada por posicao, a partir do
# precoMedio opcional em holdings.json. Nunca recomenda vender, nunca calcula
# Imposto de Renda devido - so aponta candidatos a considerar com um contador.
#
# Uso:
#   bin/perdas.sh <slug>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
Uso: bin/perdas.sh <slug>

Reporta ganho/perda nao realizada por posicao em <slug>/holdings.json que
tiver o campo opcional "precoMedio". Marca como candidato a tax-loss
harvesting toda posicao com preco atual abaixo do precoMedio - informativo
apenas, nunca recomenda vender nem calcula IR devido. BR via brapi-quote.sh;
US/global exige PERDAS_QUOTE injetado (MCP Alpha Vantage e so config
declarativa). Posicao sem precoMedio e listada a parte, sem calculo.
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
  if [ -n "${PERDAS_QUOTE:-}" ]; then
    "$PERDAS_QUOTE" "$slug" "$ticker" "$mercado"
    return
  fi
  if [ "$mercado" = "br" ]; then
    raw=$("$REPO_ROOT/bin/brapi-quote.sh" "$slug" "$ticker")
    jq -ce '{preco: .results[0].data.regularMarketPrice}' <<<"$raw"
    return
  fi
  echo "Cotacao indisponivel: recebido mercado '$mercado' ticker '$ticker', esperado mercado 'br' (brapi.dev) ou PERDAS_QUOTE injetado (MCP US e config declarativa, sem client HTTP)." >&2
  exit 1
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
require_file "$HOLDINGS" 'JSON {"posicoes": [{ticker, quantidade, classe, mercado, precoMedio?}, ...]}'

QUOTES=$(mktemp)
trap 'rm -f "$QUOTES"' EXIT

python3 - "$HOLDINGS" > /dev/null <<'PY'
# Valida holdings.json cedo (mesma politica de mensagem de erro das outras stories).
import json, sys
try:
    payload = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as exc:
    sys.exit(f"Holdings invalido: recebido erro '{exc}' em '{sys.argv[1]}', esperado JSON valido.")
if not isinstance(payload, dict) or not isinstance(payload.get("posicoes"), list):
    sys.exit(f"Holdings invalido: recebido {payload!r}, esperado JSON com chave 'posicoes' (lista).")
PY

COM_PRECO=$(jq -c '[.posicoes[] | select(has("precoMedio"))]' "$HOLDINGS")
QUOTES_MAP="{}"
while IFS= read -r row; do
  [ -n "$row" ] || continue
  ticker=$(jq -r '.ticker' <<<"$row" | tr '[:lower:]' '[:upper:]')
  mercado=$(jq -r '.mercado' <<<"$row" | tr '[:upper:]' '[:lower:]')
  payload=$(quote_payload "$SLUG" "$ticker" "$mercado")
  preco=$(jq -er '.preco' <<<"$payload")
  QUOTES_MAP=$(jq --arg t "$ticker" --argjson p "$preco" '.[$t] = $p' <<<"$QUOTES_MAP")
done < <(jq -c '.[]' <<<"$COM_PRECO")

printf '%s\n' "$QUOTES_MAP" > "$QUOTES"
python3 "$SCRIPT_DIR/perdas-report.py" "$HOLDINGS" "$QUOTES"
