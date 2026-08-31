---
name: rebalanceamento
description: Use when suggesting portfolio rebalancing after allocation drifts past a threshold, or when asked to comprar/vender to return to alocacao-alvo.
---

# rebalanceamento

## Orientação de raciocínio para o agente

Esta seção orienta o AGENTE a conversar melhor com o usuário sobre rebalanceamento. O InvestOS
(`bin/*.sh`) continua sem recomendação prescritiva codificada: os scripts só expõem dados e
sugestões mecânicas, e a decisão final é sempre do usuário.

Quando houver capital novo, prefira direcionar 100% do aporte para a classe mais underweight,
evitando vendas, imposto de renda e custo de corretagem. Considere vender apenas quando o desvio
for grande demais para ser corrigido com aportes ou quando não houver capital novo disponível.

Antes de reforçar um ativo que caiu por parecer barato, avalie se a queda veio do mercado em geral
ou de uma piora nos fundamentos do próprio ativo. Nunca recomende comprar mais apenas porque o
preço caiu; esse julgamento pertence à conversa do agente, não a um filtro automático de dados em
`bin/rebalanceamento.sh`.

Se uma venda for necessária, priorize ativos cujos fundamentos ou qualidade pioraram ao longo do
tempo, depois posições excessivamente concentradas no patrimônio total (por exemplo, acima de
~10–15%, como referência flexível) e, por fim, ativos aparentemente supervalorizados. O gatilho
pode ser periódico, como uma revisão semestral ou anual, ou um desvio percentual; ambos são
válidos, e o InvestOS já usa o desvio definido por `threshold` em `alocacao-alvo.json`.

Dentro da classe escolhida para reforço, prefira diluir a concentração existente: reforce o que a
pessoa tem menos, sem empilhar ainda mais no ativo que já domina a classe, mas também sem
pulverizar a carteira em excesso.

Antes de recomendações que dependam do cenário de renda fixa, como pós-fixada versus prefixada ou
CDB versus Tesouro, consulte `bin/macro-brasil.sh <slug>` para obter a Selic/CDI vigente. Busque o
dado real, pois uma taxa lembrada do treinamento pode estar desatualizada.

Rode `bin/rebalanceamento.sh <slug>` a partir da raiz do InvestOS. Threshold fica em `<slug>/alocacao-alvo.json` (campo `threshold`, fracao em (0, 1]).

A skill nunca executa ordem — so sugere. Nao envie ordem, nao chame corretora e nao grave `holdings.json`.

Se `disparou` for false, o desvio esta dentro do threshold. Se true, apresente as sugestoes `comprar`/`vender` do JSON.
