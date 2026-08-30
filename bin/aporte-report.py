#!/usr/bin/env python3
"""Sugere como distribuir um aporte novo entre classes/mercados underweight."""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

AXES = ("porClasse", "porMercado")


def die(message: str) -> None:
    raise SystemExit(message)


def as_decimal(value: Any, field: str, received: Any) -> Decimal:
    try:
        return Decimal(str(value))
    except Exception:
        die(f"Numero invalido: recebido {field}={value!r} em {received!r}, esperado numero.")


def load_valor(raw: str) -> Decimal:
    value = as_decimal(raw, "valor", raw)
    if value <= 0:
        die(f"Valor invalido: recebido '{raw}', esperado valor de aporte > 0.")
    return value


def load_alocacao() -> dict[str, Any]:
    raw = sys.stdin.read()
    try:
        report = json.loads(raw)
    except json.JSONDecodeError as exc:
        die(f"Alocacao invalida: recebido JSON invalido ({exc}), esperado relatorio de bin/alocacao.sh.")
    if not isinstance(report, dict) or "total" not in report:
        die(f"Alocacao invalida: recebido {report!r}, esperado relatorio com total, porClasse e porMercado.")
    for axis in AXES:
        if not isinstance(report.get(axis), dict):
            die(f"Alocacao invalida: recebido {axis}={report.get(axis)!r}, esperado objeto de fatias.")
    return report


def split_for_axis(bucket: dict[str, Any], valor_aporte: Decimal) -> list[dict[str, Any]]:
    underweight: dict[str, Decimal] = {}
    alvo_pesos: dict[str, Decimal] = {}
    for chave, info in bucket.items():
        if not isinstance(info, dict) or "desvio" not in info or "alvo" not in info:
            die(f"Fatia invalida: recebido {info!r} em {chave!r}, esperado objeto com desvio e alvo.")
        desvio = as_decimal(info["desvio"], "desvio", info)
        alvo_pesos[chave] = as_decimal(info["alvo"], "alvo", info)
        if desvio < 0:
            underweight[chave] = -desvio

    total_gap = sum(underweight.values(), Decimal("0"))
    if total_gap > 0:
        return [
            {"chave": chave, "valor": float(valor_aporte * gap / total_gap)}
            for chave, gap in sorted(underweight.items())
        ]

    # Nada underweight: distribui o aporte pelos pesos-alvo diretamente.
    total_alvo = sum(alvo_pesos.values(), Decimal("0"))
    if total_alvo <= 0:
        return []
    return [
        {"chave": chave, "valor": float(valor_aporte * peso / total_alvo)}
        for chave, peso in sorted(alvo_pesos.items())
        if peso > 0
    ]


def build_report(alocacao: dict[str, Any], valor_aporte: Decimal) -> dict[str, Any]:
    return {
        "valorAporte": float(valor_aporte),
        "executaOrdem": False,
        "porClasse": split_for_axis(alocacao["porClasse"], valor_aporte),
        "porMercado": split_for_axis(alocacao["porMercado"], valor_aporte),
    }


def main() -> None:
    if len(sys.argv) != 2:
        die(f"Uso invalido: recebido {sys.argv!r}, esperado aporte-report.py <valor>")
    valor = load_valor(sys.argv[1])
    report = build_report(load_alocacao(), valor)
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
