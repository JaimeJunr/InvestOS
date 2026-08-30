[← voltar para Visão e motivação](../visao-e-motivacao.md)

# Catálogo de Plugins

**Prioridade:** P0 — o inventário curado que fundamenta as escolhas do setup interativo.

## O que faz

`catalog.json`, na raiz do repositório, é o resultado de uma pesquisa deliberada pelo ecossistema
público de plugins/skills/agents/MCPs de Claude Code voltados a investimento, organizada por
domínio:

- **research** — `anthropics/financial-services`, `tradermonty/claude-trading-skills`,
  `openalphalab/quant_investing_skills`, `acantrell0523/family-office`.
- **risco/portfólio** — `openalphalab/quant_investing_skills`.
- **dados de mercado** — Alpha Vantage MCP (oficial), `stock-scanner-mcp`, `financekit-mcp`,
  `himself65/finance-skills`.
- **corretora/banco** — `plaid-mcp`, `plaid-cli-mcp-server`, `ScientiaCapital/skills` (Interactive
  Brokers), `nkrvivek/traderkit`.

Cada entrada registra nome, repositório, tipo (plugin marketplace / skill / MCP) e se exige
credencial de terceiro.

## Critério de entrada

> Repositório público com `marketplace.json` válido (plugins) OU instalação documentada
> (skills/MCPs). Sem exigência de teste prévio de qualidade — é catálogo de research, não
> certificação.

Não há core obrigatório: todo item do catálogo, incluindo `anthropics/financial-services`, é
opcional e escolhido pelo usuário no momento do setup, por domínio.

## O gap de dados BR

A pesquisa que gerou este catálogo não encontrou nenhum MCP/skill público equivalente ao que
existe para o mercado US para dados de mercado brasileiro (B3, fundos, ANBIMA) — isso está
registrado explicitamente em `catalog.json` como uma entrada `"gap": true`, em vez de ser omitido
ou apresentado como "em breve" sem previsão real.

Esse gap **não ficou sem solução** — só não foi resolvido por um plugin de terceiro. A feature
[Dados de Mercado e Pesquisa](dados-de-mercado-e-pesquisa.md) cobre o mercado BR com uma
implementação própria (brapi.dev + CVM Dados Abertos), validada por um spike técnico dedicado.
