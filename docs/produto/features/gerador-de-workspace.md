[← voltar para Visão e motivação](../visao-e-motivacao.md)

# Gerador de Workspace

**Prioridade:** P0 — fundacional. Toda outra área depende da estrutura que esta gera.

## O que faz

`bin/setup.sh <nome-ou-caminho>` cria uma pasta de portfólio nova, isolada, **fora da pasta do
InvestOS** (mesmo padrão do [BizOS](https://github.com/JaimeJunr/BizOS)), a partir de um setup
interativo.

```bash
bin/setup.sh minha-carteira
# → cria em ~/Documents/investos-minha-carteira (override: INVESTOS_PORTFOLIOS_DIR=/outro/lugar)
# Habilitar dominio 'research'? [y/N]
# Habilitar dominio 'risco'? [y/N]
# Habilitar dominio 'dados-mercado'? [y/N]
# Habilitar dominio 'corretora-banco'? [y/N]
# Mercado (BR/US/ambos):
```

Um argumento que contenha `/`, comece com `.` ou `~` é tratado como caminho explícito e respeitado
literalmente (`bin/setup.sh ~/carteiras/pessoal`, `bin/setup.sh ./aqui-mesmo`) — sem o prefixo
`investos-` nem a pasta base `~/Documents`.

O nome (ou o último componente do caminho) é normalizado automaticamente (`Meu Portfolio` vira
`meu-portfolio`) e só é rejeitado se, mesmo após a normalização, ainda violar o formato de slug
(minúsculas, números, hífen, até 80 caracteres). Rodar o comando de novo sobre um portfólio
existente pede confirmação explícita antes de sobrescrever — nada é perdido por acidente.

## O que é gerado

```
minha-carteira/
├── CLAUDE.md
├── _memoria/
├── .env                      # vazio, gitignored — credenciais entram aqui manualmente
├── .gitignore                # já inclui .env e _cache/
├── .mcp.json                 # só se algum domínio com MCP foi habilitado
├── .claude/
│   ├── settings.json         # enabledPlugins por domínio escolhido
│   ├── skills/                # copiadas de templates/skills/, conforme domínio + mercado
│   └── commands/
│       ├── instalar.md        # entrevista guiada — grava holdings.json, alocacao-alvo.json, watchlist-fundos.json
│       └── status.md          # briefing read-only (alocação, risco, rebalanceamento)
└── portfolio.json            # {"mercado": "br" | "us" | "ambos"}
```

`/instalar` e `/status` são sempre copiados, independente de quais domínios foram habilitados —
sem eles, os arquivos de dados do portfólio (`holdings.json`, `alocacao-alvo.json`) teriam que ser
escritos manualmente, sem nenhuma entrevista guiada. `/instalar` começa por um diagnóstico de
perfil de risco/objetivos/reserva de emergência (grava `perfil-investidor.json`) antes de
perguntar posições — mesmo processo que um profissional de finanças segue antes de montar uma
carteira, adaptado pra uma entrevista de poucos minutos.

## O enum de mercado

O campo `mercado` aceita exatamente três valores — `br`, `us`, `ambos` — comparação
case-insensitive, sem mapeamento automático de sinônimos (`"brasil"` não é aceito). Toda feature
consumidora (dados de mercado, corretora/banco) trata esse valor como contrato fixo. Essa decisão
foi retroativa — ver [a decisão registrada](../decisao-mecanismo-mcp-e-enum-mercado.md) sobre por
que isso precisou de uma iteração de PRD depois da primeira implementação.

## Isolamento entre portfólios

Dois portfólios gerados lado a lado nunca compartilham `_memoria/`, `.env` ou
`.claude/settings.json`. A estrutura já suporta N portfólios simultâneos — o v1 só não exige que
mais de um esteja de fato populado com dados reais.
