#!/usr/bin/env bash
# Fake nomeado do GET historico da brapi.dev v2 (range/interval). Nao faz I/O de rede.
set -euo pipefail

url="${1:-}"
token="${2:-}"
if [ -z "$url" ]; then
  echo "fake-brapi-history: recebido URL vazia, esperado .../v2/stocks/historical?symbols=<ticker>&range=3mo&interval=1d" >&2
  exit 1
fi

if [ -n "${BRAPI_FETCH_LOG:-}" ]; then
  printf '%s\n' "$url" >> "$BRAPI_FETCH_LOG"
  if [ -n "$token" ]; then
    printf 'Authorization: Bearer %s\n' "$token" >> "$BRAPI_FETCH_LOG"
  fi
fi

ticker=$(printf '%s' "$url" | sed -E 's/.*[?&]symbols=([^&]+).*/\1/')
if [ -z "$ticker" ] || [ "$ticker" = "$url" ]; then
  echo "fake-brapi-history: nao extraiu ticker de URL '$url', esperado .../v2/stocks/historical?symbols=<ticker>&range=..." >&2
  exit 1
fi

python3 - "$ticker" <<'PY'
import json, sys
from datetime import datetime, timezone

ticker = sys.argv[1]
days = [
    ("2026-01-02", 100.0),
    ("2026-01-05", 110.0),
    ("2026-01-06", 100.0),
    ("2026-01-07", 90.0),
    ("2026-01-08", 100.0),
]
bars = [
    {
        "date": int(datetime.strptime(day, "%Y-%m-%d").replace(tzinfo=timezone.utc).timestamp()),
        "close": close,
        "adjustedClose": close,
    }
    for day, close in days
]
json.dump({"results": [{"symbol": ticker, "data": {"historicalDataPrice": bars}}]}, sys.stdout)
print()
PY
