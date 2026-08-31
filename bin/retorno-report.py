#!/usr/bin/env python3
"""Monta o relatorio de TWR e MWR."""

from __future__ import annotations

import json
import sys
from datetime import date, datetime
from typing import Any

INSUFFICIENT = "dado insuficiente"
MIN_NAV = 2
EXTERNAL = {"aporte": 1.0, "resgate": -1.0}


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


def load_transactions(path: str) -> list[dict[str, Any]]:
    expected = 'JSON [{"data": "AAAA-MM-DD", "tipo": "aporte|resgate|compra|venda", "valor": ...}]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"Transacoes invalidas: recebido {payload!r} em '{path}', esperado {expected}.")
    rows = []
    for item in payload:
        parsed = parse_transaction(item)
        if parsed is not None:
            rows.append(parsed)
    return sorted(rows, key=lambda row: row["date"])


def parse_transaction(item: Any) -> dict[str, Any] | None:
    expected = "{data, tipo, valor}"
    if not isinstance(item, dict):
        die(f"Transacao invalida: recebido {item!r}, esperado objeto {expected}.")
    kind = str(item.get("tipo") or "").strip().lower()
    if kind not in {"aporte", "resgate", "compra", "venda"}:
        die(f"Tipo invalido: recebido {item.get('tipo')!r}, esperado um de: aporte, resgate, compra ou venda.")
    if kind not in EXTERNAL:
        return None
    value = as_float(item.get("valor"), "valor", item)
    if value <= 0:
        die(f"Valor invalido: recebido {item!r}, esperado valor > 0.")
    return {"date": parse_day(item.get("data"), item), "flow": EXTERNAL[kind] * value}


def insufficient_payload() -> dict[str, str]:
    return {"twr": INSUFFICIENT, "mwr": INSUFFICIENT}


def net_flow(rows: list[dict[str, Any]], start: str, end: str) -> float:
    return sum(row["flow"] for row in rows if start < row["date"] <= end)


def subperiod_return(start_value: float, end_value: float, cash_flow: float) -> float:
    if start_value <= 0:
        die(f"NAV inicial invalido: recebido {start_value!r}, esperado valorTotal > 0.")
    return (end_value - cash_flow) / start_value - 1.0


def chain_twr(nav: list[dict[str, Any]], rows: list[dict[str, Any]]) -> float:
    product = 1.0
    for index in range(1, len(nav)):
        cash_flow = net_flow(rows, nav[index - 1]["date"], nav[index]["date"])
        product *= 1.0 + subperiod_return(nav[index - 1]["value"], nav[index]["value"], cash_flow)
    return product - 1.0


def as_date(day: str) -> date:
    return datetime.strptime(day, "%Y-%m-%d").date()


def mwr_flows(nav: list[dict[str, Any]], rows: list[dict[str, Any]]) -> list[tuple[date, float]]:
    last_day = nav[-1]["date"]
    flows = [(as_date(row["date"]), -row["flow"]) for row in rows if row["date"] <= last_day]
    flows.append((as_date(last_day), nav[-1]["value"]))
    return flows


def npv(rate: float, points: list[tuple[float, float]]) -> float:
    return sum(cash / (1.0 + rate) ** tau for tau, cash in points)


def npv_derivative(rate: float, points: list[tuple[float, float]]) -> float:
    return sum(cash * (-tau) / (1.0 + rate) ** (tau + 1.0) for tau, cash in points)


def holding_period_irr(flows: list[tuple[date, float]]) -> float | None:
    if not flows:
        return None
    start = min(day for day, _ in flows)
    end = max(day for day, _ in flows)
    span = (end - start).days
    if span <= 0:
        return None
    points = [((day - start).days / span, cash) for day, cash in flows]
    if not any(cash < 0 for _, cash in points) or not any(cash > 0 for _, cash in points):
        return None
    return newton_irr(points)


def newton_irr(points: list[tuple[float, float]]) -> float | None:
    rate = 0.0
    for _ in range(50):
        if rate <= -1.0:
            return None
        deriv = npv_derivative(rate, points)
        if deriv == 0:
            return None
        step = npv(rate, points) / deriv
        rate -= step
        if abs(step) < 1e-12:
            return rate
    return None


def build_report(nav: list[dict[str, Any]], rows: list[dict[str, Any]]) -> dict[str, Any]:
    if len(nav) < MIN_NAV or not rows:
        return insufficient_payload()
    money = holding_period_irr(mwr_flows(nav, rows))
    if money is None:
        return insufficient_payload()
    return {"twr": chain_twr(nav, rows), "mwr": money}


def main() -> None:
    if len(sys.argv) != 3:
        die(
            f"Uso invalido: recebido {sys.argv!r}, esperado "
            "retorno-report.py <nav-historico.json> <transacoes.json>"
        )
    report = build_report(load_nav(sys.argv[1]), load_transactions(sys.argv[2]))
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
