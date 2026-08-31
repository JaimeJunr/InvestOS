#!/usr/bin/env python3
"""Relatorio de proventos: totais, por ticker/classe/tipo, DY realizado 12m.

Informativo apenas - nao calcula Imposto de Renda devido. Retencao na fonte
varia por tipo de provento e situacao do investidor.
"""

from __future__ import annotations

import json
import sys
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

AVISO_LEGAL = (
    "Informativo apenas - nao e calculo de Imposto de Renda devido. Retencao na fonte "
    "varia por tipo de provento e situacao do investidor. Consulte um contador."
)
TIPOS_VALIDOS = {"dividendo", "jcp", "rendimento"}
JANELA_DIAS = 365


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


def parse_date(raw: str) -> date | None:
    try:
        return date.fromisoformat(raw)
    except (ValueError, TypeError):
        return None


def load_proventos(path: str) -> list[dict[str, Any]]:
    expected = '[{"ticker","tipo","classe","valorBruto","valorLiquido","data"}, ...]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"Proventos invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    events = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            die(f"Evento invalido: recebido {item!r} no indice {index}, esperado objeto {expected}.")
        ticker = str(item.get("ticker") or "").strip().upper()
        tipo = str(item.get("tipo") or "").strip()
        classe = str(item.get("classe") or "").strip()
        bruto = as_decimal(item.get("valorBruto"), "valorBruto", item)
        liquido = as_decimal(item.get("valorLiquido"), "valorLiquido", item)
        if not ticker or tipo not in TIPOS_VALIDOS or not classe:
            die(
                f"Evento invalido: recebido {item!r} no indice {index}, esperado ticker/classe "
                f"nao-vazios e tipo um de: {sorted(TIPOS_VALIDOS)}."
            )
        events.append(
            {
                "ticker": ticker,
                "tipo": tipo,
                "classe": classe,
                "valorBruto": bruto,
                "valorLiquido": liquido,
                "data": str(item.get("data") or ""),
            }
        )
    return events


def load_nav(path: str | None) -> list[dict[str, Any]]:
    if path is None:
        return []
    try:
        with open(path, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (FileNotFoundError, json.JSONDecodeError):
        return []
    if not isinstance(payload, list):
        return []
    points = []
    for item in payload:
        if not isinstance(item, dict):
            continue
        points.append({"data": str(item.get("data") or ""), "valorTotal": as_decimal(item.get("valorTotal"), "valorTotal", item)})
    return points


def group_sum(events: list[dict[str, Any]], key: str) -> dict[str, dict[str, float]]:
    acc: dict[str, tuple[Decimal, Decimal]] = {}
    for event in events:
        bucket = event[key]
        bruto, liquido = acc.get(bucket, (Decimal(0), Decimal(0)))
        acc[bucket] = (bruto + event["valorBruto"], liquido + event["valorLiquido"])
    return {bucket: {"bruto": float(b), "liquido": float(l)} for bucket, (b, l) in acc.items()}


def por_ticker(events: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    acc: dict[str, dict[str, Any]] = {}
    for event in events:
        entry = acc.setdefault(event["ticker"], {"bruto": Decimal(0), "liquido": Decimal(0), "eventos": 0})
        entry["bruto"] += event["valorBruto"]
        entry["liquido"] += event["valorLiquido"]
        entry["eventos"] += 1
    return {
        ticker: {"bruto": float(v["bruto"]), "liquido": float(v["liquido"]), "eventos": v["eventos"]}
        for ticker, v in acc.items()
    }


def dy_realizado(events: list[dict[str, Any]], nav: list[dict[str, Any]], hoje: date) -> float | str:
    limite = hoje - timedelta(days=JANELA_DIAS)
    janela_eventos = [e for e in events if (parse_date(e["data"]) or limite) >= limite]
    janela_nav = [n["valorTotal"] for n in nav if (parse_date(n["data"]) or limite) >= limite]
    if len(janela_nav) < 2 or not janela_eventos:
        return "dado insuficiente"
    total_liquido = sum((e["valorLiquido"] for e in janela_eventos), Decimal(0))
    media_nav = sum(janela_nav, Decimal(0)) / len(janela_nav)
    if media_nav <= 0:
        return "dado insuficiente"
    return float(total_liquido / media_nav)


def build_report(events: list[dict[str, Any]], nav: list[dict[str, Any]]) -> dict[str, Any]:
    total_bruto = sum((e["valorBruto"] for e in events), Decimal(0))
    total_liquido = sum((e["valorLiquido"] for e in events), Decimal(0))
    return {
        "totalBruto": float(total_bruto),
        "totalLiquido": float(total_liquido),
        "retidoNaFonte": float(total_bruto - total_liquido),
        "porTicker": por_ticker(events),
        "porClasse": group_sum(events, "classe"),
        "porTipo": group_sum(events, "tipo"),
        "dyRealizado12m": dy_realizado(events, nav, date.today()),
        "avisoLegal": AVISO_LEGAL,
    }


def main() -> None:
    if len(sys.argv) not in (2, 3):
        die(
            f"Uso invalido: recebido {sys.argv!r}, esperado "
            "proventos-relatorio-report.py <proventos.json> [nav-historico.json]"
        )
    events = load_proventos(sys.argv[1])
    nav = load_nav(sys.argv[2]) if len(sys.argv) == 3 else []
    report = build_report(events, nav)
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
