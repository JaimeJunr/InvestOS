#!/usr/bin/env python3
"""Monta o relatorio de risco (VaR historico, Sharpe, max drawdown)."""

from __future__ import annotations

import json
import math
import statistics
import sys
from typing import Any

MERCADOS = {"br", "us"}
# PRD nao fixa confianca/rf/janela; convencao: VaR 95% interpolado, rf=0, min. 3 precos.
VAR_CONFIDENCE = 0.95
MIN_PRICES = 3
TRADING_DAYS = 252


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


def validate_holding(item: Any, index: int) -> dict[str, Any]:
    expected = "{ticker, quantidade, classe, mercado}"
    if not isinstance(item, dict):
        die(f"Posicao invalida: recebido {item!r} no indice {index}, esperado objeto {expected}.")
    ticker = str(item.get("ticker") or "").strip().upper()
    classe = str(item.get("classe") or "").strip()
    mercado = str(item.get("mercado") or "").strip().lower()
    quantidade = as_float(item.get("quantidade"), "quantidade", item)
    if not ticker or not classe or mercado not in MERCADOS or quantidade <= 0:
        die(
            f"Posicao invalida: recebido {item!r}, esperado ticker nao-vazio, "
            f"quantidade > 0, classe nao-vazia e mercado um de: br, us."
        )
    return {"ticker": ticker, "quantidade": quantidade, "classe": classe, "mercado": mercado}


def load_holdings(path: str) -> list[dict[str, Any]]:
    payload = load_json(path, 'JSON {"posicoes": [{ticker, quantidade, classe, mercado}, ...]}')
    rows = payload.get("posicoes") if isinstance(payload, dict) else None
    if not isinstance(rows, list) or not rows:
        die(
            f"Holdings invalido: recebido {payload!r} em '{path}', "
            'esperado JSON {"posicoes": [...]} com pelo menos 1 posicao.'
        )
    return [validate_holding(item, index) for index, item in enumerate(rows)]


def normalize_points(ticker: str, rows: Any) -> list[dict[str, Any]]:
    if not isinstance(rows, list):
        die(f"Historico invalido: recebido {ticker}={rows!r}, esperado lista de {{date, close}}.")
    points = []
    for item in rows:
        if not isinstance(item, dict):
            die(f"Ponto invalido: recebido {item!r} em {ticker}, esperado objeto {{date, close}}.")
        day = str(item.get("date") or "").strip()
        close = as_float(item.get("close"), "close", item)
        if not day or close <= 0:
            die(f"Ponto invalido: recebido {item!r} em {ticker}, esperado date nao-vazio e close > 0.")
        points.append({"date": day[:10], "close": close})
    return sorted(points, key=lambda point: point["date"])


def load_history(path: str, tickers: list[str]) -> dict[str, list[dict[str, Any]]]:
    expected = 'JSON {"TICKER": [{"date","close"}]}'
    payload = load_json(path, expected)
    if not isinstance(payload, dict):
        die(f"Historico invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    history = {}
    for ticker in tickers:
        rows = payload.get(ticker)
        if rows is None:
            rows = payload.get(ticker.upper(), [])
        history[ticker] = normalize_points(ticker, rows)
    return history


def percentile(data: list[float], p: float) -> float:
    ordered = sorted(data)
    rank = (len(ordered) - 1) * p
    low = math.floor(rank)
    high = math.ceil(rank)
    if low == high:
        return ordered[int(rank)]
    return ordered[low] * (high - rank) + ordered[high] * (rank - low)


def daily_returns(values: list[float]) -> list[float]:
    return [values[index] / values[index - 1] - 1.0 for index in range(1, len(values))]


def historical_var(returns: list[float], confidence: float) -> float:
    return -percentile(returns, 1.0 - confidence)


def sharpe_ratio(returns: list[float]) -> float:
    spread = statistics.stdev(returns)
    if spread == 0:
        die(f"Sharpe indefinido: recebido desvio padrao 0 a partir de {returns!r}, esperado variancia > 0.")
    return (statistics.fmean(returns) / spread) * math.sqrt(TRADING_DAYS)


def max_drawdown(values: list[float]) -> float:
    peak = values[0]
    worst = 0.0
    for value in values:
        peak = max(peak, value)
        worst = max(worst, (peak - value) / peak)
    return worst


def series_by_date(points: list[dict[str, Any]]) -> dict[str, float]:
    return {point["date"]: float(point["close"]) for point in points}


def aligned_values(positions: list[dict[str, Any]], history: dict[str, list[dict[str, Any]]]) -> list[float]:
    priced = [series_by_date(history[item["ticker"]]) for item in positions]
    common = set(priced[0])
    for item in priced[1:]:
        common &= set(item)
    values = []
    for day in sorted(common):
        total = 0.0
        for position, closes in zip(positions, priced):
            total += float(position["quantidade"]) * closes[day]
        values.append(total)
    return values


def limitation_aviso(ticker: str, mercado: str, count: int) -> dict[str, str]:
    return {
        "ticker": ticker,
        "motivo": (
            f"historico insuficiente: recebido ticker '{ticker}' mercado '{mercado}' "
            f"com {count} precos, esperado no minimo {MIN_PRICES} precos "
            f"({MIN_PRICES - 1} retornos)."
        ),
    }


def classify_assets(
    positions: list[dict[str, Any]], history: dict[str, list[dict[str, Any]]]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, str]]]:
    included: list[dict[str, Any]] = []
    ativos: list[dict[str, Any]] = []
    avisos: list[dict[str, str]] = []
    for item in positions:
        ticker = item["ticker"]
        count = len(history.get(ticker) or [])
        ok = count >= MIN_PRICES
        ativos.append({"ticker": ticker, "incluido": ok, "pontos": count})
        if ok:
            included.append(item)
            continue
        avisos.append(limitation_aviso(ticker, item["mercado"], count))
    return included, ativos, avisos


def empty_metrics(ativos: list[dict[str, Any]], avisos: list[dict[str, str]]) -> dict[str, Any]:
    return {
        "varHistorico": None,
        "sharpe": None,
        "maxDrawdown": None,
        "varConfianca": VAR_CONFIDENCE,
        "ativos": ativos,
        "avisos": avisos,
    }


def metrics_payload(
    values: list[float], ativos: list[dict[str, Any]], avisos: list[dict[str, str]]
) -> dict[str, Any]:
    returns = daily_returns(values)
    return {
        "varHistorico": historical_var(returns, VAR_CONFIDENCE),
        "sharpe": sharpe_ratio(returns),
        "maxDrawdown": max_drawdown(values),
        "varConfianca": VAR_CONFIDENCE,
        "ativos": ativos,
        "avisos": avisos,
    }


def build_report(
    positions: list[dict[str, Any]], history: dict[str, list[dict[str, Any]]]
) -> dict[str, Any]:
    included, ativos, avisos = classify_assets(positions, history)
    if not included:
        return empty_metrics(ativos, avisos)
    values = aligned_values(included, history)
    if len(values) < MIN_PRICES:
        for item in included:
            avisos.append(limitation_aviso(item["ticker"], item["mercado"], len(values)))
        return empty_metrics(ativos, avisos)
    return metrics_payload(values, ativos, avisos)


def main() -> None:
    if len(sys.argv) != 3:
        die(f"Uso invalido: recebido {sys.argv!r}, esperado risco-report.py <holdings.json> <history.json>")
    positions = load_holdings(sys.argv[1])
    tickers = [item["ticker"] for item in positions]
    report = build_report(positions, load_history(sys.argv[2], tickers))
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
