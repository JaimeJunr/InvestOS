# Decisão: mecanismo de MCP declarativo e enum de mercado

Este documento registra uma decisão arquitetural real, tomada em produção do próprio processo de
geração do InvestOS — não é um exercício hipotético de design.

## Contexto

O PRD original definia 5 features e 17 user stories. Sete delas (o Gerador de Workspace completo e
o Catálogo de Plugins completo) foram implementadas e passaram sem problema. Na oitava story —
`mdr-US-001`, "Integração com MCP de dados US/global" — o agente de implementação **parou e se
recusou a inventar comportamento**, escrevendo um `BLOCKED.md` explícito em vez de seguir em
frente.

O motivo: o PRD deixava duas coisas em aberto que só ficaram visíveis na hora de codar.

## As duas ambiguidades

**1. O campo `mercado` não tinha um enum.** A story anterior (`wg-US-002`) gravava o valor
digitado pelo usuário como texto livre em `portfolio.json`. Não havia como uma feature consumidora
detectar de forma confiável se "mercado US/global" estava habilitado — o valor podia ser
`"US"`, `"us"`, `"estados unidos"`, ou qualquer outra coisa.

**2. "MCP integrado e funcional" não definia um mecanismo.** Duas leituras razoáveis e
materialmente diferentes eram possíveis:

- **(a)** Config declarativa — o portfólio ganha um `.mcp.json` referenciando o MCP escolhido do
  catálogo, com a credencial como placeholder vazio no `.env`.
- **(b)** Client real — o InvestOS implementa código que de fato chama a API (ex.: Alpha Vantage)
  em tempo de execução.

Nenhuma story anterior estabelecia precedente para nenhuma das duas, e não havia `CLAUDE.md`
nem skills locais no repositório-alvo para consultar. O agente esgotou seu orçamento de consulta
(checou `CLAUDE.md`, `.claude/skills/`, grep por precedente similar) e bloqueou.

## A decisão

Resolvida via uma iteração de PRD tipo `update` (o PRD já estava selado — mudanças pós-aprovação
não reabrem o documento, viram um update):

- **Enum de mercado:** `br | us | ambos`, comparação case-insensitive, sem mapeamento automático
  de sinônimos. Qualquer outro valor é rejeitado com uma mensagem que inclui o valor recebido e os
  3 aceitos. Virou a story retroativa `wg-US-005`.
- **Mecanismo de MCP:** **(a) config declarativa.** "Integrado e funcional" significa que o
  portfólio ganha `.mcp.json` + credencial placeholder no `.env` — o mesmo padrão que o Gerador de
  Workspace já usava para tudo o mais. Testes verificam a estrutura do config gerado, nunca fazem
  uma chamada de API real.

## Por que declarativo, e não client real

- **Consistência com o resto do sistema.** O Gerador de Workspace já resolvia tudo — desde
  credenciais até skills — como arquivos de config gerados, nunca como client HTTP embutido.
  Introduzir um client real só para MCPs de dados quebraria essa uniformidade sem necessidade.
  clara.
- **Testabilidade sem rede.** Um client real exigiria mockar (ou pagar) chamadas de API reais em
  todo teste, ou aceitar testes flaky dependentes de rede/credencial. Config declarativa testa
  estrutura — determinístico, rápido, sem credencial nenhuma.
- **O MCP já faz esse trabalho.** O ponto de um MCP é justamente ser o client — o Claude Code que
  roda dentro do portfólio é quem de fato invoca a chamada, quando a credencial real for
  preenchida pelo usuário. Reimplementar isso dentro do InvestOS seria duplicar o que o MCP já
  oferece.

## Consequência prática no código

Esse "mecanismo declarativo, nunca client HTTP first-party" virou a convenção seguida por toda
integração externa subsequente (`mdr-US-002`, `mdr-US-003`, `bi-US-001`): cada script que
precisaria falar com uma API externa aceita, em vez disso, um **override de fetch injetável** via
variável de ambiente (`RISCO_HISTORY`, `ALOCACAO_QUOTE`, `HOLDINGS_FETCH`) — o mesmo ponto de
extensão que os testes usam para injetar respostas falsas. Ver
[`arquitetura/visao-geral.md`](../arquitetura/visao-geral.md) para o detalhe técnico.

## Se essa decisão quebrar no futuro

Isto é registrado como uma decisão real, não uma hipótese: se o mecanismo declarativo se mostrar
insuficiente (por exemplo, se o InvestOS precisar rodar fora de um agente Claude Code e precisar
de fato falar com as APIs sozinho), a correção é uma nova iteração de PRD tipo `update` — nunca
uma reabertura silenciosa do que já foi decidido aqui.
