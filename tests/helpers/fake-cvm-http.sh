#!/usr/bin/env bash
# Fake nomeado do GET HTTP do Informe Diario CVM. Nao faz I/O de rede.
set -euo pipefail

url="${1:-}"
if [ -z "$url" ]; then
  echo "fake-cvm-http: recebido URL vazia, esperado https://dados.cvm.gov.br/dados/FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_YYYYMM.zip" >&2
  exit 1
fi

if [ -n "${CVM_FETCH_LOG:-}" ]; then
  printf '%s\n' "$url" >> "$CVM_FETCH_LOG"
fi

if [[ ! "$url" =~ ^https://dados\.cvm\.gov\.br/dados/FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_[0-9]{6}\.zip$ ]]; then
  echo "fake-cvm-http: URL fora do contrato CVM: recebido '$url', esperado https://dados.cvm.gov.br/dados/FI/DOC/INF_DIARIO/DADOS/inf_diario_fi_YYYYMM.zip" >&2
  exit 1
fi

if [ -n "${CVM_FAKE_ZIP:-}" ]; then
  cat "$CVM_FAKE_ZIP"
  exit 0
fi

workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
month=$(printf '%s' "$url" | sed -E 's/.*inf_diario_fi_([0-9]{6})\.zip$/\1/')
csv="$workdir/inf_diario_fi_${month}.csv"

cat > "$csv" <<'EOF'
TP_FUNDO_CLASSE;CNPJ_FUNDO_CLASSE;ID_SUBCLASSE;DT_COMPTC;VL_TOTAL;VL_QUOTA;VL_PATRIM_LIQ;CAPTC_DIA;RESG_DIA;NR_COTST
FI;12.345.678/0001-90;;2026-08-27;1000.00;1.100000000000;900.00;10.00;4.00;80
FI;12.345.678/0001-90;;2026-08-28;1100.00;1.234567890000;999.50;20.00;5.00;81
FI;98.765.432/0001-10;;2026-08-28;2000.00;2.000000000000;1999.00;0.00;0.00;50
EOF

(cd "$workdir" && zip -q - "inf_diario_fi_${month}.csv")
