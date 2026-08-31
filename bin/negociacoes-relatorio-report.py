#!/usr/bin/env python3
"""Relatorio de negociacoes: totais, quantidade liquida, volume, ofertas publicas.

Nao calcula ganho/perda de capital em vendas — nao e objetivo do InvestOS calcular IR.
"""

from __future__ import annotations

import json
import sys
from decimal import Decimal
from typing import Any

AVISO = (
    "Ganho/perda de capital em vendas nao e calculado aqui — nao e objetivo do "
    "InvestOS calcular Imposto de Renda."
)
TIPOS_VALIDOS = {"compra", "venda"}


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


def load_negociacoes(path: str) -> list[dict[str, Any]]:
    expected = '[{"ticker","tipo","quantidade","precoUnitario","data","oferta?"}, ...]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"Negociacoes invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    events = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            die(f"Evento invalido: recebido {item!r} no indice {index}, esperado objeto {expected}.")
        ticker = str(item.get("ticker") or "").strip()
        tipo = str(item.get("tipo") or "").strip()
        quantidade = as_decimal(item.get("quantidade"), "quantidade", item)
        preco = as_decimal(item.get("precoUnitario"), "precoUnitario", item)
        if not ticker or tipo not in TIPOS_VALIDOS:
            die(
                f"Evento invalido: recebido {item!r} no indice {index}, esperado ticker "
                f"nao-vazio e tipo um de: {sorted(TIPOS_VALIDOS)}."
            )
        oferta_raw = item.get("oferta")
        if oferta_raw is None or str(oferta_raw).strip() == "":
            oferta = None
        else:
            oferta = str(oferta_raw).strip()
        events.append(
            {
                "ticker": ticker,
                "tipo": tipo,
                "quantidade": quantidade,
                "precoUnitario": preco,
                "data": str(item.get("data") or ""),
                "oferta": oferta,
            }
        )
    return events


def as_float(value: Decimal) -> float:
    return float(value)


def serialize_event(event: dict[str, Any]) -> dict[str, Any]:
    return {
        "ticker": event["ticker"],
        "tipo": event["tipo"],
        "quantidade": as_float(event["quantidade"]),
        "precoUnitario": as_float(event["precoUnitario"]),
        "data": event["data"],
        "oferta": event["oferta"],
    }


def build_report(events: list[dict[str, Any]]) -> dict[str, Any]:
    total_comprado = Decimal(0)
    total_vendido = Decimal(0)
    liquida: dict[str, Decimal] = {}
    volume_por_ticker: dict[str, dict[str, Decimal]] = {}
    volume_por_tipo: dict[str, Decimal] = {"compra": Decimal(0), "venda": Decimal(0)}
    ofertas: dict[str, list[dict[str, Any]]] = {}

    for event in events:
        volume = event["quantidade"] * event["precoUnitario"]
        ticker = event["ticker"]
        tipo = event["tipo"]
        liquida.setdefault(ticker, Decimal(0))
        bucket = volume_por_ticker.setdefault(ticker, {"compra": Decimal(0), "venda": Decimal(0)})
        bucket[tipo] += volume
        volume_por_tipo[tipo] += volume
        if tipo == "compra":
            total_comprado += volume
            liquida[ticker] += event["quantidade"]
        else:
            total_vendido += volume
            liquida[ticker] -= event["quantidade"]
        if event["oferta"]:
            ofertas.setdefault(event["oferta"], []).append(serialize_event(event))

    return {
        "totalComprado": as_float(total_comprado),
        "totalVendido": as_float(total_vendido),
        "quantidadeLiquidaPorTicker": {ticker: as_float(qty) for ticker, qty in liquida.items()},
        "volumePorTicker": {
            ticker: {"compra": as_float(v["compra"]), "venda": as_float(v["venda"])}
            for ticker, v in volume_por_ticker.items()
        },
        "volumePorTipo": {
            "compra": as_float(volume_por_tipo["compra"]),
            "venda": as_float(volume_por_tipo["venda"]),
        },
        "ofertasPublicas": ofertas,
        "aviso": AVISO,
    }


def main() -> None:
    if len(sys.argv) != 2:
        die(f"Uso invalido: recebido {sys.argv!r}, esperado negociacoes-relatorio-report.py <negociacoes.json>")
    events = load_negociacoes(sys.argv[1])
    report = build_report(events)
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
