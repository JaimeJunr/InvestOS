#!/usr/bin/env python3
"""Filtra o CSV do Informe Diario CVM pelos CNPJs da watchlist."""

from __future__ import annotations

import csv
import io
import json
import re
import sys
from typing import Any


def digits_only(value: str) -> str:
    return re.sub(r"\D", "", value or "")


def load_wanted_cnpjs(watch_path: str) -> set[str]:
    with open(watch_path, encoding="utf-8") as handle:
        payload: dict[str, Any] = json.load(handle)
    wanted = {digits_only(item) for item in payload.get("cnpjs", [])}
    wanted.discard("")
    return wanted


def parse_rows(csv_text: str, wanted: set[str]) -> list[dict[str, Any]]:
    reader = csv.DictReader(io.StringIO(csv_text), delimiter=";")
    rows: list[dict[str, Any]] = []
    for rec in reader:
        cnpj = rec.get("CNPJ_FUNDO_CLASSE", "")
        if digits_only(cnpj) not in wanted:
            continue
        rows.append(
            {
                "cnpj": cnpj,
                "dtComptc": rec["DT_COMPTC"],
                "vlQuota": float(rec["VL_QUOTA"]),
                "vlPatrimLiq": float(rec["VL_PATRIM_LIQ"]),
                "captcDia": float(rec["CAPTC_DIA"]),
                "resgDia": float(rec["RESG_DIA"]),
            }
        )
    return rows


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            f"Uso invalido: recebido {sys.argv!r}, esperado cvm-informe-parse.py <watchlist.json>"
        )
    wanted = load_wanted_cnpjs(sys.argv[1])
    csv_text = sys.stdin.buffer.read().decode("latin-1")
    json.dump(parse_rows(csv_text, wanted), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
