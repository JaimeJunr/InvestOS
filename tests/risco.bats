#!/usr/bin/env bats
# Testes de pr-US-002: VaR historico, Sharpe e max drawdown a partir do historico.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/risco.sh"
  FAKE_HISTORY="$ROOT/tests/helpers/fake-risco-history.sh"
  FAKE_BRAPI_HISTORY="$ROOT/tests/helpers/fake-brapi-history.sh"
  FAKE_CVM="$ROOT/tests/helpers/fake-cvm-http.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
  export RISCO_HISTORY="$FAKE_HISTORY"
  export RISCO_HISTORY_SERIES="$WORKDIR/series.json"
  export RISCO_HISTORY_LOG="$WORKDIR/history.log"
  : > "$RISCO_HISTORY_LOG"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
  : > "$1/.env"
}

write_holdings() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = {
    "posicoes": [
        {"ticker": "PETR4", "quantidade": 1, "classe": "acoes", "mercado": "br"},
    ]
}
with open(f"{slug}/holdings.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

write_petr4_series() {
  python3 - "$RISCO_HISTORY_SERIES" <<'PY'
import json, sys
payload = {
    "PETR4": [
        {"date": "2026-01-02", "close": 100},
        {"date": "2026-01-05", "close": 110},
        {"date": "2026-01-06", "close": 100},
        {"date": "2026-01-07", "close": 90},
        {"date": "2026-01-08", "close": 100},
    ]
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

assert_petr4_metrics() {
  python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["varHistorico"] - 0.09863636363636362) < 1e-9, report
assert abs(report["sharpe"] - 0.6899612646906116) < 1e-9, report
assert abs(report["maxDrawdown"] - 0.18181818181818182) < 1e-9, report
assert abs(report["varConfianca"] - 0.95) < 1e-9, report
' "$1"
}

@test "uso sem args: falha com mensagem de uso citando VaR e holdings.json" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
  [[ "$output" == *"VaR"* ]] || [[ "$output" == *"var"* ]]
  [[ "$output" == *"holdings.json"* ]]
}

@test "relatorio calcula VaR historico, Sharpe e max drawdown a partir do historico" {
  seed_portfolio acme
  write_holdings acme
  write_petr4_series

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run assert_petr4_metrics "$output"
  [ "$status" -eq 0 ]
}

@test "posicao com precoManual nao busca historico externo, entra como historico insuficiente" {
  seed_portfolio acme
  python3 - <<'PY'
import json
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "PETR4", "quantidade": 1, "classe": "acoes", "mercado": "br"},
            {"ticker": "NTN-B mai/2055", "quantidade": 4, "classe": "renda-fixa", "mercado": "br", "precoManual": 1005.74},
        ]
    }, fh)
with open("series.json", "w", encoding="utf-8") as fh:
    json.dump({
        "PETR4": [
            {"date": "2026-01-02", "close": 100},
            {"date": "2026-01-05", "close": 110},
            {"date": "2026-01-06", "close": 100},
            {"date": "2026-01-07", "close": 90},
            {"date": "2026-01-08", "close": 100},
        ],
    }, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
tickers = {item["ticker"] for item in report["ativos"]}
assert "NTN-B MAI/2055" in tickers, report
manual = next(item for item in report["ativos"] if item["ticker"] == "NTN-B MAI/2055")
assert manual["incluido"] is False, manual
' "$output"
  [ "$status" -eq 0 ]
  ! grep -qi "ntn-b" "$RISCO_HISTORY_LOG"
}

@test "historico insuficiente gera aviso explicito e nao trava nem omite o ativo" {
  seed_portfolio acme
  python3 - <<'PY'
import json
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "PETR4", "quantidade": 1, "classe": "acoes", "mercado": "br"},
            {"ticker": "NOVO11", "quantidade": 1, "classe": "acoes", "mercado": "br"},
        ]
    }, fh)
with open("series.json", "w", encoding="utf-8") as fh:
    json.dump({
        "PETR4": [
            {"date": "2026-01-02", "close": 100},
            {"date": "2026-01-05", "close": 110},
            {"date": "2026-01-06", "close": 100},
            {"date": "2026-01-07", "close": 90},
            {"date": "2026-01-08", "close": 100},
        ],
        "NOVO11": [{"date": "2026-01-08", "close": 999}],
    }, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["varHistorico"] - 0.09863636363636362) < 1e-9, report
assert abs(report["sharpe"] - 0.6899612646906116) < 1e-9, report
assert abs(report["maxDrawdown"] - 0.18181818181818182) < 1e-9, report
tickers = {item["ticker"] for item in report["ativos"]}
assert "NOVO11" in tickers, report
assert "PETR4" in tickers, report
avisos = report["avisos"]
assert avisos, report
joined = json.dumps(avisos)
assert "NOVO11" in joined, avisos
assert "999" not in joined.replace("NOVO11", ""), avisos
assert "suficiente" in joined.lower() or "insuficiente" in joined.lower(), avisos
novo = next(item for item in report["ativos"] if item["ticker"] == "NOVO11")
assert novo["incluido"] is False, novo
' "$output"
  [ "$status" -eq 0 ]
}

@test "posicao BR sem RISCO_HISTORY busca historico via brapi com range" {
  unset RISCO_HISTORY
  export BRAPI_HTTP_GET="$FAKE_BRAPI_HISTORY"
  export BRAPI_FETCH_LOG="$WORKDIR/brapi.log"
  : > "$BRAPI_FETCH_LOG"
  seed_portfolio acme
  write_holdings acme

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  grep -q "PETR4" "$BRAPI_FETCH_LOG"
  grep -q "range=" "$BRAPI_FETCH_LOG"
  grep -q "interval=1d" "$BRAPI_FETCH_LOG"
  run assert_petr4_metrics "$output"
  [ "$status" -eq 0 ]
}

@test "fundo BR com CNPJ busca historico via CVM Informe Diario" {
  unset RISCO_HISTORY
  export CVM_HTTP_GET="$FAKE_CVM"
  export CVM_FETCH_LOG="$WORKDIR/cvm.log"
  export CVM_FAKE_ZIP="$WORKDIR/cvm.zip"
  export CVM_NOW=1768478400
  : > "$CVM_FETCH_LOG"
  seed_portfolio acme
  python3 - <<'PY'
import json, zipfile
from pathlib import Path
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {
                "ticker": "12.345.678/0001-90",
                "quantidade": 1,
                "classe": "fundos",
                "mercado": "br",
            }
        ]
    }, fh)
with open("acme/watchlist-fundos.json", "w", encoding="utf-8") as fh:
    json.dump({"cnpjs": ["12.345.678/0001-90"]}, fh)
rows = [
    "TP_FUNDO_CLASSE;CNPJ_FUNDO_CLASSE;ID_SUBCLASSE;DT_COMPTC;VL_TOTAL;VL_QUOTA;VL_PATRIM_LIQ;CAPTC_DIA;RESG_DIA;NR_COTST",
    "FI;12.345.678/0001-90;;2026-01-02;1000.00;1.000000000000;900.00;0.00;0.00;80",
    "FI;12.345.678/0001-90;;2026-01-05;1100.00;1.100000000000;990.00;0.00;0.00;80",
    "FI;12.345.678/0001-90;;2026-01-06;1000.00;1.000000000000;900.00;0.00;0.00;80",
    "FI;12.345.678/0001-90;;2026-01-07;900.00;0.900000000000;810.00;0.00;0.00;80",
    "FI;12.345.678/0001-90;;2026-01-08;1000.00;1.000000000000;900.00;0.00;0.00;80",
]
csv_name = "inf_diario_fi_202601.csv"
Path(csv_name).write_text("\n".join(rows) + "\n", encoding="latin-1")
with zipfile.ZipFile("cvm.zip", "w") as zf:
    zf.write(csv_name)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  grep -q "dados.cvm.gov.br" "$CVM_FETCH_LOG"
  grep -q "inf_diario_fi_202601.zip" "$CVM_FETCH_LOG"
  run assert_petr4_metrics "$output"
  [ "$status" -eq 0 ]
}

@test "posicao US sem RISCO_HISTORY gera aviso e nao trava o relatorio" {
  unset RISCO_HISTORY
  seed_portfolio acme
  python3 - <<'PY'
import json
with open("acme/holdings.json", "w", encoding="utf-8") as fh:
    json.dump({
        "posicoes": [
            {"ticker": "AAPL", "quantidade": 5, "classe": "acoes", "mercado": "us"},
        ]
    }, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  report="$output"
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["varHistorico"] is None, report
assert report["sharpe"] is None, report
assert report["maxDrawdown"] is None, report
joined = json.dumps(report["avisos"])
assert "AAPL" in joined, report
assert "us" in joined.lower(), report
' "$report"
  [ "$status" -eq 0 ]
}
