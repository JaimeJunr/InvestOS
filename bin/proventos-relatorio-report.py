#!/usr/bin/env python3
"""Relatorio de proventos: totais, por ticker/classe/tipo, DY realizado 12m.

Opcionalmente inclui proventos provisionados (anunciados, ainda nao pagos).
Informativo apenas - nao calcula Imposto de Renda devido. Retencao na fonte
varia por tipo de provento e situacao do investidor.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import date, timedelta
from decimal import Decimal
from typing import Any

AVISO_LEGAL = (
    "Informativo apenas - nao e calculo de Imposto de Renda devido. Retencao na fonte "
    "varia por tipo de provento e situacao do investidor. Consulte um contador."
)
AVISO_PROJECAO = (
    "Projecao: mistura provento ja recebido (liquido) com provento anunciado e ainda "
    "nao pago (bruto, sem retencao na fonte). O valor anunciado pode ser alterado ou "
    "cancelado pela empresa ate a data de pagamento. Nao e garantia."
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


def load_provisionados(path: str) -> list[dict[str, Any]]:
    expected = '[{"ticker","tipo","classe","valorBruto","dataPrevisao"}, ...]'
    payload = load_json(path, expected)
    if not isinstance(payload, list):
        die(f"Provisionados invalido: recebido {payload!r} em '{path}', esperado {expected}.")
    events = []
    for index, item in enumerate(payload):
        if not isinstance(item, dict):
            die(f"Evento invalido: recebido {item!r} no indice {index}, esperado objeto {expected}.")
        ticker = str(item.get("ticker") or "").strip().upper()
        tipo = str(item.get("tipo") or "").strip()
        classe = str(item.get("classe") or "").strip()
        bruto = as_decimal(item.get("valorBruto"), "valorBruto", item)
        data_previsao = str(item.get("dataPrevisao") or "").strip()
        if not ticker or tipo not in TIPOS_VALIDOS or not classe:
            die(
                f"Evento invalido: recebido {item!r} no indice {index}, esperado ticker/classe "
                f"nao-vazios e tipo um de: {sorted(TIPOS_VALIDOS)}."
            )
        if bruto <= 0:
            die(f"Evento invalido: recebido {item!r} no indice {index}, esperado valorBruto > 0.")
        if parse_date(data_previsao) is None:
            die(
                f"Evento invalido: recebido {item!r} no indice {index}, esperado dataPrevisao AAAA-MM-DD."
            )
        events.append(
            {
                "ticker": ticker,
                "tipo": tipo,
                "classe": classe,
                "valorBruto": bruto,
                "dataPrevisao": data_previsao,
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


def group_sum_bruto(events: list[dict[str, Any]], key: str) -> dict[str, dict[str, float]]:
    acc: dict[str, Decimal] = {}
    for event in events:
        bucket = event[key]
        acc[bucket] = acc.get(bucket, Decimal(0)) + event["valorBruto"]
    return {bucket: {"bruto": float(total)} for bucket, total in acc.items()}


def por_ticker_bruto(events: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
    acc: dict[str, dict[str, Any]] = {}
    for event in events:
        entry = acc.setdefault(event["ticker"], {"bruto": Decimal(0), "eventos": 0})
        entry["bruto"] += event["valorBruto"]
        entry["eventos"] += 1
    return {ticker: {"bruto": float(v["bruto"]), "eventos": v["eventos"]} for ticker, v in acc.items()}


def janela_provisionados(events: list[dict[str, Any]], hoje: date) -> list[dict[str, Any]]:
    fim = hoje + timedelta(days=JANELA_DIAS)
    janela = []
    for event in events:
        parsed = parse_date(event["dataPrevisao"])
        if parsed is not None and hoje <= parsed <= fim:
            janela.append(event)
    return janela


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


def dy_projetado(
    events: list[dict[str, Any]],
    provisionados_janela: list[dict[str, Any]],
    nav: list[dict[str, Any]],
    hoje: date,
) -> float | str:
    limite = hoje - timedelta(days=JANELA_DIAS)
    janela_eventos = [e for e in events if (parse_date(e["data"]) or limite) >= limite]
    janela_nav = [n["valorTotal"] for n in nav if (parse_date(n["data"]) or limite) >= limite]
    if len(janela_nav) < 2:
        return "dado insuficiente"
    media_nav = sum(janela_nav, Decimal(0)) / len(janela_nav)
    if media_nav <= 0:
        return "dado insuficiente"
    total_liquido = sum((e["valorLiquido"] for e in janela_eventos), Decimal(0))
    total_provisionado = sum((e["valorBruto"] for e in provisionados_janela), Decimal(0))
    return float((total_liquido + total_provisionado) / media_nav)


def build_report(
    events: list[dict[str, Any]],
    nav: list[dict[str, Any]],
    provisionados: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    hoje = date.today()
    total_bruto = sum((e["valorBruto"] for e in events), Decimal(0))
    total_liquido = sum((e["valorLiquido"] for e in events), Decimal(0))
    report: dict[str, Any] = {
        "totalBruto": float(total_bruto),
        "totalLiquido": float(total_liquido),
        "retidoNaFonte": float(total_bruto - total_liquido),
        "porTicker": por_ticker(events),
        "porClasse": group_sum(events, "classe"),
        "porTipo": group_sum(events, "tipo"),
        "dyRealizado12m": dy_realizado(events, nav, hoje),
        "avisoLegal": AVISO_LEGAL,
    }
    if provisionados is not None:
        janela = janela_provisionados(provisionados, hoje)
        report["provisionadoProximos12m"] = {
            "totalBruto": float(sum((e["valorBruto"] for e in janela), Decimal(0))),
            "porTicker": por_ticker_bruto(janela),
            "porClasse": group_sum_bruto(janela, "classe"),
            "porTipo": group_sum_bruto(janela, "tipo"),
        }
        report["dyProjetado12m"] = dy_projetado(events, janela, nav, hoje)
        report["avisoProjecao"] = AVISO_PROJECAO
    return report


def classify_optional_path(path: str) -> str:
    name = os.path.basename(path)
    if name == "proventos-provisionados.json":
        return "provisionados"
    return "nav"


def main() -> None:
    if len(sys.argv) not in (2, 3, 4):
        die(
            f"Uso invalido: recebido {sys.argv!r}, esperado "
            "proventos-relatorio-report.py <proventos.json> [nav-historico.json] "
            "[proventos-provisionados.json]"
        )
    events = load_proventos(sys.argv[1])
    nav: list[dict[str, Any]] = []
    provisionados: list[dict[str, Any]] | None = None
    for path in sys.argv[2:]:
        if not path:
            continue
        if classify_optional_path(path) == "provisionados":
            provisionados = load_provisionados(path)
        else:
            nav = load_nav(path)
    report = build_report(events, nav, provisionados)
    json.dump(report, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
