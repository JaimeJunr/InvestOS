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
   alvo e se o desvio já passou do threshold (rebalanceamento por desvio).
2. `bin/risco.sh <slug>` — VaR histórico, Sharpe e max drawdown. Se algum ativo tiver aviso de
   histórico insuficiente, mencione isso no resumo.
3. `bin/rebalanceamento.sh <slug>` — se o desvio (passo 1) tiver disparado, mostre a sugestão de
   comprar/vender. Deixe claro que é sugestão, não ordem executada.
4. Se o usuário mencionar que tem dinheiro novo pra investir (aporte), rode
   `bin/aporte.sh <slug> <valor>` em vez de esperar o próximo desvio — é a forma de rebalancear sem
   custo de venda.
5. Se `holdings.json` tiver alguma posição com `precoMedio`, rode `bin/perdas.sh <slug>` e mencione
   os candidatos a tax-loss harvesting, se houver — deixando claro que é informativo (o relatório já
   carrega o aviso legal) e que decisão fiscal é com um contador, não com o InvestOS.

### Revisão periódica (calendário, além do desvio)

Leia `perfil-investidor.json`, se existir:

- Se `ultimaRevisao` estiver ausente, ou tiver mais de 180 dias (seis meses) atrás, sugira rodar
  `/instalar` de novo só pra revisar o diagnóstico (perfil de risco, objetivos, situação
  financeira) — não é preciso mexer em `holdings.json`.
- Se algum objetivo tiver `anoAlvo` a menos de ~2 anos da data de hoje, avise que pode ser hora de
  migrar gradualmente esse objetivo pra ativos mais conservadores (aproximação de meta) — sugestão,
  não execução automática.
- Se `perfil-investidor.json` não existir, não invente um lembrete — apenas não mencione revisão
  periódica.

Termine com um resumo curto (poucas linhas) e uma recomendação do que fazer em seguida — não
despeje os relatórios crus sem síntese.
