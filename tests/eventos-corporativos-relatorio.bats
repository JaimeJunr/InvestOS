#!/usr/bin/env bats
# Testes do relatorio de eventos corporativos: listagem agrupada, sem calculo de retorno.

setup() {
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$ROOT/bin/eventos-corporativos-relatorio.sh"
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

write_eventos() {
  python3 - "$1" <<'PY'
import json, sys
slug = sys.argv[1]
payload = [
    {"ticker": "PETR4", "tipo": "desdobramento", "data": "2026-05-01", "fator": 2, "quantidadeRecebida": None, "observacao": None},
    {"ticker": "VALE3", "tipo": "grupamento", "data": "2026-04-01", "fator": 0.1, "quantidadeRecebida": None, "observacao": None},
    {"ticker": "PETR4", "tipo": "bonificacao", "data": "2026-06-01", "fator": None, "quantidadeRecebida": 10, "observacao": None},
    {"ticker": "WEGE3", "tipo": "outro", "data": "2026-03-01", "fator": None, "quantidadeRecebida": None, "observacao": "cisao"},
]
with open(f"{slug}/eventos-corporativos.json", "w", encoding="utf-8") as fh:
    json.dump(payload, fh)
PY
}

@test "sem argumentos: falha com mensagem de uso" {
  run "$SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Uso:"* ]]
}

@test "eventos-corporativos.json ausente e rejeitado com mensagem clara" {
  seed_portfolio acme
  run "$SCRIPT" acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"recebido"* ]]
  [[ "$output" == *"esperado"* ]]
}

@test "relatorio lista eventos ordenados por data" {
  seed_portfolio acme
  write_eventos acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
datas = [e["data"] for e in report["eventos"]]
assert datas == sorted(datas), report
assert datas[0] == "2026-03-01", report
assert datas[-1] == "2026-06-01", report
' "$output"
  [ "$status" -eq 0 ]
}

@test "relatorio agrupa por ticker e por tipo" {
  seed_portfolio acme
  write_eventos acme
  run "$SCRIPT" acme
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
report = json.loads(sys.argv[1])
assert len(report["porTicker"]["PETR4"]) == 2, report
assert len(report["porTicker"]["VALE3"]) == 1, report
assert len(report["porTicker"]["WEGE3"]) == 1, report
assert len(report["porTipo"]["desdobramento"]) == 1, report
assert len(report["porTipo"]["grupamento"]) == 1, report
assert len(report["porTipo"]["bonificacao"]) == 1, report
assert len(report["porTipo"]["outro"]) == 1, report
assert report["porTipo"]["outro"][0]["ticker"] == "WEGE3", report
' "$output"
  [ "$status" -eq 0 ]
}
