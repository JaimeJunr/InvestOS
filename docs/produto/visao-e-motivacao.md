# Visão e motivação

InvestOS é um "sistema operacional" para investimentos construído sobre Claude Code — no mesmo
espírito do [BizOS](https://github.com/JaimeJunr/BizOS) (harness para pequenos negócios
brasileiros), mas para o domínio de investimento pessoal.

## O problema

Montar um ambiente de investimento assistido por IA hoje significa escolher e integrar
manualmente dezenas de plugins, skills e MCPs fragmentados pelo ecossistema — cada um com seu
próprio README, seu próprio mecanismo de instalação, sua própria cobertura de mercado. Não existe
um jeito estruturado de dizer "quero um portfólio novo, com research e dados de mercado ligados,
mercado BR" e simplesmente receber uma pasta pronta.

## A ideia

Uma pasta por portfólio — igual ao padrão que o BizOS já usa por cliente — gerada por um setup
interativo que pergunta quais domínios habilitar (research, risco, dados de mercado,
corretora/banco) e qual mercado (BR, US, ou ambos). O InvestOS não parte do zero: ele **cura** e
integra plugins/skills/MCPs já públicos do ecossistema Claude Code voltados a finanças e
investimento, com [`anthropics/financial-services`](https://github.com/anthropics/financial-services)
como referência mais madura entre dezenas de repositórios de trading/quant/dados de mercado
pesquisados (ver [`decisao-mecanismo-mcp-e-enum-mercado.md`](decisao-mecanismo-mcp-e-enum-mercado.md)
para a decisão de como essa integração de fato acontece).

## Escopo do v1

Uso inicial é pessoal — uma única carteira, gerenciada por quem está lendo isso. A estrutura já
nasce **multi-portfólio** (o gerador suporta N pastas isoladas desde o primeiro dia), mas
gerenciar vários portfólios populados ao mesmo tempo não é um objetivo do v1 — só precisa estar
pronto para quando for.

## O que o InvestOS explicitamente não faz

- **Não recomenda investimento nem executa ordens de compra/venda.** Todo relatório é read-only;
  toda sugestão de rebalanceamento é texto, nunca uma ordem enviada.
- **Não constrói plugins novos do zero para cada domínio.** Cura e integra o que já existe
  publicamente.
- **Não expõe credenciais fora do `.env` local de cada portfólio.**

## As 5 áreas do produto

| Área | Prioridade | O que faz |
|------|------------|-----------|
| [Gerador de Workspace](features/gerador-de-workspace.md) | P0 | Cria a pasta de um portfólio novo, com setup interativo. |
| [Catálogo de Plugins](features/catalogo-de-plugins.md) | P0 | Lista curada de plugins/skills/MCPs de investimento, por domínio. |
| [Dados de Mercado e Pesquisa](features/dados-de-mercado-e-pesquisa.md) | P1 | Cotação, fundamentals e research — BR e US/global. |
| [Gestão de Portfólio e Risco](features/gestao-de-portfolio-e-risco.md) | P1 | Alocação, métricas de risco (VaR/Sharpe/drawdown), rebalanceamento. |
| [Integração com Corretora/Banco](features/integracao-corretora-banco.md) | P2 | Leitura read-only de posições reais via Plaid/Interactive Brokers. |

## Como isso foi construído

Todo o escopo acima nasceu de um PRD formal (framework CRIA: Contexto, Requisitos, Impacto
esperado, Alinhamento) e foi implementado por um loop autônomo de implementação — cada user story
passou por TDD (red→green), lint, typecheck, e um GATE final de revisor independente com mutation
testing antes de ser considerada pronta. O processo completo, incluindo o momento em que a
implementação travou por uma ambiguidade real no PRD e como isso foi resolvido, está documentado
em [`decisao-mecanismo-mcp-e-enum-mercado.md`](decisao-mecanismo-mcp-e-enum-mercado.md).
