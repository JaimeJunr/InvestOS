#!/usr/bin/env python3
"""Monta sugestao de rebalanceamento a partir do relatorio de alocacao."""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

AXES = ("porClasse", "porMercado")


def die(message: str) -> None:
    raise SystemExit(message)


def load_json(path: str, expected: str) -> Any:
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        die(f"Arquivo invalido: recebido path inexistente '{path}', esperado {expected}.")
    except json.JSONDecodeError as exc:
        die(f"Arquivo invalido: recebido JSON invalido em '{path}' ({exc}), esperado {expected}.")


def as_decimal(value: Any, field: str, received: Any) -> Decimal:
    try:
        return Decimal(str(value))
    except Exception:
        die(f"Numero invalido: recebido {field}={value!r} em {received!r}, esperado numero.")


def load_threshold(path: str) -> Decimal:
    expected = 'JSON com campo "threshold" numero em (0, 1]'
    payload = load_json(path, expected)
    raw = payload.get("threshold") if isinstance(payload, dict) else None
    if raw is None:
        die(f"Threshold invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    value = as_decimal(raw, "threshold", payload)
    if value <= 0 or value > 1:
        die(f"Threshold invalido: recebido {raw!r}, esperado numero em (0, 1].")
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


def suggestion_for(eixo: str, chave: str, bucket: Any, total: Decimal, threshold: Decimal) -> dict[str, Any] | None:
    if not isinstance(bucket, dict) or "desvio" not in bucket:
        die(f"Fatia invalida: recebido {bucket!r} em {eixo}.{chave}, esperado objeto com desvio.")
    desvio = as_decimal(bucket["desvio"], "desvio", bucket)
    if abs(desvio) <= threshold:
        return None
    return {
        "eixo": eixo,
        "chave": chave,
        "acao": "vender" if desvio > 0 else "comprar",
        "valor": float(abs(desvio) * total),
        "desvio": float(desvio),
    }


def collect_suggestions(alocacao: dict[str, Any], threshold: Decimal) -> list[dict[str, Any]]:
    total = as_decimal(alocacao["total"], "total", alocacao)
    items: list[dict[str, Any]] = []
    for eixo in AXES:
        for chave in sorted(alocacao[eixo]):
            item = suggestion_for(eixo, chave, alocacao[eixo][chave], total, threshold)
            if item is not None:
                items.append(item)
    return items


def build_report(alocacao: dict[str, Any], threshold: Decimal) -> dict[str, Any]:
    sugestoes = collect_suggestions(alocacao, threshold)
    return {
        "threshold": float(threshold),
        "disparou": bool(sugestoes),
        "executaOrdem": False,
        "sugestoes": sugestoes,
    }


def main() -> None:
    if len(sys.argv) != 2:
        die(f"Uso invalido: recebido {sys.argv!r}, esperado rebalanceamento-report.py <alocacao-alvo.json>")
    report = build_report(load_alocacao(), load_threshold(sys.argv[1]))
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
