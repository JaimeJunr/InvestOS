#!/usr/bin/env bats
# Testes do relatorio de proventos: totais, por ticker/classe/tipo, DY realizado.
# Informativo apenas - nao calcula Imposto de Renda devido.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/proventos-relatorio.sh"
  WORKDIR="$(mktemp -d)"
  cd "$WORKDIR"
}

teardown() {
  rm -rf "$WORKDIR"
}

seed_portfolio() {
  mkdir -p "$1"
  : > "$1/.env"
}

write_proventos() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = [
    {"ticker": "PETR4", "tipo": "dividendo", "classe": "acoes", "valorBruto": 6.13, "valorLiquido": 6.13, "data": "2026-06-21"},
    {"ticker": "CMIG4", "tipo": "jcp", "classe": "acoes", "valorBruto": 2.0, "valorLiquido": 1.7, "data": "2026-07-15"},
    {"ticker": "HGLG11", "tipo": "rendimento", "classe": "fiis", "valorBruto": 1.5, "valorLiquido": 1.5, "data": "2026-08-01"},
]
with open(f"{slug}/proventos.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

@test "sem argumentos: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "proventos.json ausente e rejeitado com mensagem clara" {
  seed_portfolio acme
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]
}

@test "relatorio soma totais bruto/liquido e retido na fonte" {
  seed_portfolio acme
  write_proventos acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["totalBruto"] - 9.63) < 1e-9, report
assert abs(report["totalLiquido"] - 9.33) < 1e-9, report
assert abs(report["retidoNaFonte"] - 0.30) < 1e-9, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio agrupa por ticker, classe e tipo" {
  seed_portfolio acme
  write_proventos acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["porTicker"]["PETR4"]["eventos"] == 1, report
assert abs(report["porTicker"]["CMIG4"]["liquido"] - 1.7) < 1e-9, report
assert abs(report["porClasse"]["acoes"]["bruto"] - 8.13) < 1e-9, report
assert abs(report["porClasse"]["fiis"]["liquido"] - 1.5) < 1e-9, report
assert abs(report["porTipo"]["jcp"]["bruto"] - 2.0) < 1e-9, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "sem nav-historico.json, DY realizado marca dado insuficiente" {
  seed_portfolio acme
  write_proventos acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert report["dyRealizado12m"] == "dado insuficiente", report
' "$output"
  [ "$status" -eq 0 ]
}

@test "com nav-historico.json recente o suficiente, DY realizado e calculado como numero" {
  seed_portfolio acme
  write_proventos acme
  python3 - acme <<'PY'
import json, sys
from datetime import date, timedelta
slug = sys.argv[1]
hoje = date.today()
payload = [
    {"data": (hoje - timedelta(days=300)).isoformat(), "valorTotal": 10000.0},
    {"data": (hoje - timedelta(days=150)).isoformat(), "valorTotal": 11000.0},
    {"data": hoje.isoformat(), "valorTotal": 12000.0},
]
with open(f"{slug}/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert isinstance(report["dyRealizado12m"], float), report
assert report["dyRealizado12m"] > 0, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio inclui aviso legal de que nao e calculo de IR devido" {
  seed_portfolio acme
  write_proventos acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
aviso = report["avisoLegal"].lower()
assert "nao" in aviso and ("imposto" in aviso or "ir" in aviso), report
' "$output"
  [ "$status" -eq 0 ]
}

@test "sem proventos-provisionados.json o relatorio nao ganha campos novos" {
  seed_portfolio acme
  write_proventos acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert "provisionadoProximos12m" not in report, report
assert "dyProjetado12m" not in report, report
assert "avisoProjecao" not in report, report
assert set(report.keys()) == {
    "totalBruto", "totalLiquido", "retidoNaFonte",
    "porTicker", "porClasse", "porTipo",
    "dyRealizado12m", "avisoLegal",
}, report
' "$output"
  [ "$status" -eq 0 ]
}

@test "com provisionados e nav, dyProjetado12m soma liquido realizado + bruto provisionado da janela" {
  seed_portfolio acme
  write_proventos acme
  python3 - acme <<'PY'
import json, sys
from datetime import date, timedelta
slug = sys.argv[1]
hoje = date.today()
nav = [
    {"data": (hoje - timedelta(days=300)).isoformat(), "valorTotal": 10000.0},
    {"data": (hoje - timedelta(days=150)).isoformat(), "valorTotal": 11000.0},
    {"data": hoje.isoformat(), "valorTotal": 12000.0},
]
with open(f"{slug}/nav-historico.json", "w", encoding="utf-8") as fh:
    json.dump(nav, fh)
provisionados = [
    {"ticker": "EGIE3", "tipo": "dividendo", "classe": "acoes", "valorBruto": 1.20, "dataPrevisao": (hoje + timedelta(days=30)).isoformat()},
]
with open(f"{slug}/proventos-provisionados.json", "w", encoding="utf-8") as fh:
    json.dump(provisionados, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["provisionadoProximos12m"]["totalBruto"] - 1.20) < 1e-9, report
assert abs(report["provisionadoProximos12m"]["porTicker"]["EGIE3"]["bruto"] - 1.20) < 1e-9, report
assert abs(report["provisionadoProximos12m"]["porClasse"]["acoes"]["bruto"] - 1.20) < 1e-9, report
assert abs(report["provisionadoProximos12m"]["porTipo"]["dividendo"]["bruto"] - 1.20) < 1e-9, report
assert isinstance(report["dyProjetado12m"], float), report
expected = (9.33 + 1.20) / 11000.0
assert abs(report["dyProjetado12m"] - expected) < 1e-9, (report["dyProjetado12m"], expected)
assert report["dyProjetado12m"] > report["dyRealizado12m"], report
aviso = report["avisoProjecao"].lower()
assert "projec" in aviso
assert "bruto" in aviso
assert "nao pago" in aviso or "nao realizado" in aviso or "ainda nao" in aviso
' "$output"
  [ "$status" -eq 0 ]
}

@test "provisionado com dataPrevisao fora da janela de 12 meses futuros nao conta em provisionadoProximos12m" {
  seed_portfolio acme
  write_proventos acme
  python3 - acme <<'PY'
import json, sys
from datetime import date, timedelta
slug = sys.argv[1]
hoje = date.today()
payload = [
    {"ticker": "EGIE3", "tipo": "dividendo", "classe": "acoes", "valorBruto": 1.20, "dataPrevisao": (hoje + timedelta(days=10)).isoformat()},
    {"ticker": "VALE3", "tipo": "dividendo", "classe": "acoes", "valorBruto": 99.0, "dataPrevisao": (hoje + timedelta(days=366)).isoformat()},
    {"ticker": "PETR4", "tipo": "jcp", "classe": "acoes", "valorBruto": 50.0, "dataPrevisao": (hoje - timedelta(days=1)).isoformat()},
]
with open(f"{slug}/proventos-provisionados.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY

  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert abs(report["provisionadoProximos12m"]["totalBruto"] - 1.20) < 1e-9, report
assert "VALE3" not in report["provisionadoProximos12m"]["porTicker"], report
assert "PETR4" not in report["provisionadoProximos12m"]["porTicker"], report
assert "EGIE3" in report["provisionadoProximos12m"]["porTicker"], report
' "$output"
  [ "$status" -eq 0 ]
}
