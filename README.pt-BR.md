# InvestOS

**Um harness Claude Code para portfólios de investimento pessoal.**

[English](README.md)

InvestOS gera pastas de portfólio isoladas e autocontidas — uma por portfólio — cada uma
equipada com um conjunto curado de plugins, skills e MCPs públicos do Claude Code para pesquisa de
investimento, dados de mercado, gestão de portfólio/risco e integração read-only com corretora.
Sem servidor, sem banco de dados: toda operação é um script standalone rodado contra uma pasta de
portfólio.

Construído no espírito do [BizOS](https://github.com/JaimeJunr/BizOS) (harness Claude Code para
pequenos negócios), mas para investimento pessoal.

## O que faz

- **Gera um portfólio novo** com um comando interativo — escolha quais domínios habilitar
  (research, risco, dados de mercado, corretora) e qual mercado (Brasil, US/global ou ambos).
- **Cura plugins/MCPs externos** em vez de construir tudo do zero — ver
  [`catalog.json`](catalog.json).
- **Cobre dados de mercado brasileiro diretamente** ([brapi.dev](https://brapi.dev) para
  ações/ETFs/FIIs, [CVM Dados Abertos](https://dados.cvm.gov.br) para fundos) — não existia MCP
  público pronto para isso, então o InvestOS implementa.
- **Calcula métricas de risco reais** — VaR histórico, Sharpe, max drawdown, desvio de alocação,
  sugestão de rebalanceamento — nunca executa uma ordem.
- **Lê posições de corretora em modo read-only** via MCP declarativo (Plaid / Interactive
  Brokers), com credenciais isoladas por portfólio e fallback seguro para holdings manual.

## O que explicitamente não faz

- Dar recomendação de investimento ou executar ordens.
- Construir plugins novos do zero para cada domínio — cura o que já existe publicamente.
- Guardar credencial em qualquer lugar além do `.env` do próprio portfólio.

## Começando

```bash
git clone https://github.com/JaimeJunr/InvestOS.git
cd InvestOS
bin/setup.sh minha-carteira     # criado fora deste clone — default: ~/Documents/investos-minha-carteira
cd ~/Documents/investos-minha-carteira && claude
```

Dentro do Claude Code, rode `/instalar` — uma entrevista guiada que configura suas posições,
alocação-alvo e threshold de rebalanceamento. `/status` dá um briefing read-only depois disso.

Ver [`docs/instalacao/comecando.md`](docs/instalacao/comecando.md) para o passo a passo completo
(requisitos, primeiros comandos, configuração de credenciais).

## Documentação

Documentação completa em [`docs/`](docs/INDEX.md):

- [Começando](docs/instalacao/comecando.md)
- [Arquitetura](docs/arquitetura/visao-geral.md)
- [Desenvolvendo e contribuindo](docs/desenvolvimento/contribuindo.md)
- [Visão de produto e as 5 features](docs/produto/visao-e-motivacao.md)

## Como isso foi construído

O InvestOS foi especificado por um PRD formal (framework CRIA) e implementado ponta a ponta por
um loop autônomo de TDD — cada user story passou por testes red→green, lint, typecheck e um gate
de revisor independente com mutation testing antes de ser considerada pronta. No meio do caminho,
o loop encontrou uma ambiguidade arquitetural real (sem enum para o campo "mercado", sem mecanismo
definido para "MCP integrado e funcional") e corretamente parou em vez de chutar — a ambiguidade
foi resolvida via uma iteração de PRD, documentada em
[`docs/produto/decisao-mecanismo-mcp-e-enum-mercado.md`](docs/produto/decisao-mecanismo-mcp-e-enum-mercado.md).

## Licença

[MIT](LICENSE)
