---
description: Briefing rápido e read-only do portfolio — alocação, risco e sugestão de rebalanceamento, se houver dados.
---

# /status

Comando somente leitura. Não popula, não corrige e não altera nenhum arquivo do portfolio — se
faltar dado, aponte a ausência e recomende `/instalar` em vez de criar algo no lugar.

## Se `holdings.json` não existir

Pare e diga: "Onboarding não concluído — rode `/instalar` primeiro." Não continue para os passos
abaixo.

## Se `holdings.json` existir

Rode, a partir da raiz do InvestOS:

1. `bin/alocacao.sh <slug>` — se `alocacao-alvo.json` também existir. Resuma a alocação atual vs.
   alvo e se o desvio já passou do threshold.
2. `bin/risco.sh <slug>` — VaR histórico, Sharpe e max drawdown. Se algum ativo tiver aviso de
   histórico insuficiente, mencione isso no resumo.
3. `bin/rebalanceamento.sh <slug>` — se o desvio (passo 1) tiver disparado, mostre a sugestão de
   comprar/vender. Deixe claro que é sugestão, não ordem executada.

Termine com um resumo curto (poucas linhas) e uma recomendação do que fazer em seguida — não
despeje os três relatórios crus sem síntese.
