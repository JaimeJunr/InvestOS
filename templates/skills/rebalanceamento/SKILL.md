---
name: rebalanceamento
description: Use when suggesting portfolio rebalancing after allocation drifts past a threshold, or when asked to comprar/vender to return to alocacao-alvo.
---

# rebalanceamento

Rode `bin/rebalanceamento.sh <slug>` a partir da raiz do InvestOS. Threshold fica em `<slug>/alocacao-alvo.json` (campo `threshold`, fracao em (0, 1]).

A skill nunca executa ordem — so sugere. Nao envie ordem, nao chame corretora e nao grave `holdings.json`.

Se `disparou` for false, o desvio esta dentro do threshold. Se true, apresente as sugestoes `comprar`/`vender` do JSON.
