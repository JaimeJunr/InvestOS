#!/usr/bin/env bats
# Testes de fh-US-006: Beta, Alfa, R-quadrado e Tracking Error vs. benchmark.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/contra-benchmark.sh"
  FAKE_HISTORY="$ROOT/tests/helpers/fake-brapi-history.sh"
  FAKE_BENCHMARK="$ROOT/tests/helpers/fake-benchmark-quote.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export BRAPI_HTTP_GET="$FAKE_HISTORY"
  export BRAPI_FETCH_LOG="$WORKDIR/brapi.log"
  export BRAPI_NOW=1767225600
  : > "$BRAPI_FETCH_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  local slug="$1" mercado="${2:-br}"
  mkdir -p "$slug"
  : > "$slug/.env"
  printf '{"mercado":"%s"}\n' "$mercado" > "$slug/portfolio.json"
  if [ "$mercado" != "us" ]; then
    printf 'BRAPI_TOKEN=segredo-teste\n' > "$slug/.env"
  fi
}

write_nav() {
  python3 - "$1" <<'PY'
import json, sys

slug = sys.argv[1]
rows = [
    {"data": "2026-01-02", "valorTotal": 100},
    {"data": "2026-01-05", "valorTotal": 110},
    {"data": "2026-01-06", "valorTotal": 100},
    {"data": "2026-01-07", "valorTotal": 90},
    {"data": "2026-01-08", "valorTotal": 105},
]
with open(f"{slug}/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump(rows, fh)
PY
}

write_gspc_payload() {
  python3 - "$1" <<'PY'
import json, sys
from datetime import datetime, timezone

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
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump({"results": [{"symbol": "^GSPC", "data": {"historicalDataPrice": bars}}]}, fh)
PY
}

assert_known_metrics() {
  python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["mercado"] == sys.argv[2], report
assert report["benchmark"] == sys.argv[3], report
assert abs(report["beta"] - 1.145458667069669) < 1e-9, report
assert abs(report["alfa"] - 0.013154249156213795) < 1e-9, report
assert abs(report["rQuadrado"] - 0.9733051910208158) < 1e-9, report
assert abs(report["trackingError"] - 0.02777777777777779) < 1e-9, report
' "$1" "$2" "$3"
}

assert_insuficiente() {
  python3 -c '
import json, sys
report = json.loads(sys.argv[1])
for key in ("beta", "alfa", "rQuadrado", "trackingError"):
    assert report[key] == "historico insuficiente", (key, report)
    assert not isinstance(report[key], (int, float)), (key, report)
' "$1"
}

@test "uso sem args: falha com mensagem de uso citando nav-historico e benchmark" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"nav-historico.json"* ]]
  [[ "$output" == *"benchmark"* ]]
}

@test "relatorio calcula Beta, Alfa, R-quadrado e Tracking Error vs Ibovespa no mesmo periodo" {
  seed_portfolio acme br
  write_nav acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run assert_known_metrics "$output" br '^BVSP'
  [ "$status" -eq 0 ]
  grep -q "symbols=^BVSP" "$BRAPI_FETCH_LOG"
  grep -q "range=3mo" "$BRAPI_FETCH_LOG"
}

@test "data de NAV fora do historico do benchmark e ignorada (mesmo periodo)" {
  seed_portfolio acme br
  write_nav acme
  python3 - <<'PY'
import json
with open("acme/nav-historico.json", encoding="utf-8") as fh:
    rows = json.load(fh)
rows.append({"data": "2026-01-09", "valorTotal": 999})
with open("acme/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump(rows, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  [[ "$output" != *"999"* ]]
  run assert_known_metrics "$output" br '^BVSP'
  [ "$status" -eq 0 ]
}

@test "mercado us calcula as metricas vs S&P 500 via BENCHMARK_QUOTE" {
  seed_portfolio acme us
  write_nav acme
  export BENCHMARK_QUOTE="$FAKE_BENCHMARK"
  export BENCHMARK_QUOTE_LOG="$WORKDIR/benchmark.log"
  export BENCHMARK_QUOTE_PAYLOAD="$WORKDIR/gspc.json"
  write_gspc_payload "$BENCHMARK_QUOTE_PAYLOAD"

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run assert_known_metrics "$output" us '^GSPC'
  [ "$status" -eq 0 ]
  [ "$(cat "$BENCHMARK_QUOTE_LOG")" = "acme ^GSPC us" ]
  [ ! -s "$BRAPI_FETCH_LOG" ]
}

@test "duas observacoes de NAV reportam historico insuficiente em vez de numero" {
  seed_portfolio acme br
  python3 - <<'PY'
import json
with open("acme/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump([
        {"data": "2026-01-02", "valorTotal": 100},
        {"data": "2026-01-08", "valorTotal": 110},
    ], fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report"
  [ "$status" -eq 0 ]
  [[ "$report" == *"historico insuficiente"* ]]
}

@test "nav-historico.json ausente reporta historico insuficiente sem inventar numero" {
  seed_portfolio acme br

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run assert_insuficiente "$report"
  [ "$status" -eq 0 ]
  [[ "$report" == *"historico insuficiente"* ]]
}
