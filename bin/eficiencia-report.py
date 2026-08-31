#!/usr/bin/env python3
"""Monta o relatorio de Sortino, giro e aliquota efetiva de IR."""

from __future__ import annotations

import json
import math
import statistics
import sys
from datetime import datetime
from typing import Any

INSUFFICIENT = "dado insuficiente"
MIN_NAV = 2
TRADE_TYPES = {"compra", "venda"}
KNOWN_TYPES = {"aporte", "resgate", "compra", "venda"}


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


def as_float(value: Any, field: str, received: Any) -> float:
    try:
        number = float(value)
    except (TypeError, ValueError):
        die(f"Numero invalido: recebido {field}={value!r} em {received!r}, esperado numero.")
    return number


def parse_day(raw: Any, received: Any) -> str:
    day = str(raw or "").strip()[:10]
    try:
        datetime.strptime(day, "%Y-%m-%d")
    except ValueError:
        die(f"Data invalida: recebido {raw!r} em {received!r}, esperado AAAA-MM-DD.")
    return day


def load_nav(path: str) -> list[dict[str, Any]]:
    expected = 'JSON [{"data": "AAAA-MM-DD", "valorTotal": ...}]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"NAV invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    points = []
    for item in payload:
        if not isinstance(item, dict):
            die(f"Snapshot invalido: recebido {item!r}, esperado objeto {{data, valorTotal}}.")
        value = as_float(item.get("valorTotal"), "valorTotal", item)
        if value <= 0:
            die(f"Snapshot invalido: recebido {item!r}, esperado data nao-vazia e valorTotal > 0.")
        points.append({"date": parse_day(item.get("data"), item), "value": value})
    return sorted(points, key=lambda point: point["date"])


def optional_amount(item: dict[str, Any], field: str) -> float | None:
    if field not in item or item[field] is None:
        return None
    number = as_float(item.get(field), field, item)
    if number < 0:
        die(f"Numero invalido: recebido {field}={item[field]!r} em {item!r}, esperado numero >= 0.")
    return number


def parse_transaction(item: Any) -> dict[str, Any]:
    expected = "{data, tipo, valor, impostoPago?, ganhoRealizado?}"
    if not isinstance(item, dict):
        die(f"Transacao invalida: recebido {item!r}, esperado objeto {expected}.")
    kind = str(item.get("tipo") or "").strip().lower()
    if kind not in KNOWN_TYPES:
        die(f"Tipo invalido: recebido {item.get('tipo')!r}, esperado um de: aporte, resgate, compra ou venda.")
    value = as_float(item.get("valor"), "valor", item)
    if value <= 0:
        die(f"Valor invalido: recebido {item!r}, esperado valor > 0.")
    return {
        "date": parse_day(item.get("data"), item),
        "kind": kind,
        "value": value,
        "tax_paid": optional_amount(item, "impostoPago"),
        "realized_gain": optional_amount(item, "ganhoRealizado"),
    }


def load_transactions(path: str) -> list[dict[str, Any]]:
    expected = 'JSON [{"data": "AAAA-MM-DD", "tipo": "aporte|resgate|compra|venda", "valor": ...}]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"Transacoes invalidas: recebido {payload!r} em '{path}', esperado {expected}.")
    rows = [parse_transaction(item) for item in payload]
    return sorted(rows, key=lambda row: row["date"])


def nav_returns(nav: list[dict[str, Any]]) -> list[float]:
    return [nav[index]["value"] / nav[index - 1]["value"] - 1.0 for index in range(1, len(nav))]


def downside_deviation(returns: list[float]) -> float:
    squares = [min(item, 0.0) ** 2 for item in returns]
    return math.sqrt(sum(squares) / len(returns))


def sortino_ratio(nav: list[dict[str, Any]]) -> float | str:
    if len(nav) < MIN_NAV:
        return INSUFFICIENT
    returns = nav_returns(nav)
    spread = downside_deviation(returns)
    if spread == 0:
        return INSUFFICIENT
    return statistics.fmean(returns) / spread


def turnover(nav: list[dict[str, Any]], rows: list[dict[str, Any]]) -> float | str:
    if not rows or not nav:
        return INSUFFICIENT
    average = statistics.fmean(point["value"] for point in nav)
    if average <= 0:
        return INSUFFICIENT
    traded = sum(row["value"] for row in rows if row["kind"] in TRADE_TYPES)
    return traded / average


def effective_tax_rate(rows: list[dict[str, Any]]) -> float | str:
    paid = [row["tax_paid"] for row in rows if row["tax_paid"] is not None]
    gains = [row["realized_gain"] for row in rows if row["realized_gain"] is not None]
    total_gain = sum(gains)
    if not paid or not gains or total_gain <= 0:
        return INSUFFICIENT
    return sum(paid) / total_gain


def build_report(nav: list[dict[str, Any]], rows: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "sortino": sortino_ratio(nav),
        "giro": turnover(nav, rows),
        "aliquotaEfetiva": effective_tax_rate(rows),
    }


def main() -> None:
    if len(sys.argv) != 3:
        die(
            f"Uso invalido: recebido {sys.argv!r}, esperado "
            "eficiencia-report.py <nav-historico.json> <transacoes.json>"
        )
    report = build_report(load_nav(sys.argv[1]), load_transactions(sys.argv[2]))
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
