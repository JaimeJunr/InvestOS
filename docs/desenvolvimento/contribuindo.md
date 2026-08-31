# Desenvolvendo e contribuindo

## Rodando a suíte

```bash
bats tests/*.bats
```

Um arquivo específico:

```bash
bats tests/setup.bats
```

Um teste específico (filtro por nome, substring):

```bash
bats -f "sem slug" tests/setup.bats
```

Não há linter/typechecker instalado no projeto. Os gates equivalentes usados em desenvolvimento
são:

```bash
bash -n bin/<script>.sh          # syntax check
python3 -m py_compile bin/<script>.py
jq empty catalog.json            # valida JSON
```

## Convenções

- **Nenhuma chamada de rede real em teste.** Toda integração externa passa por um override
  injetável (`RISCO_HISTORY`, `ALOCACAO_QUOTE`, `HOLDINGS_FETCH`) ou por uma das três fontes BR
  implementadas diretamente (brapi.dev, CVM, BCB SGS). Os fakes vivem em `tests/helpers/fake-*.sh`.
- **Mensagens de erro incluem o valor recebido e o esperado** — ex.: `"Slug invalido: recebido
  'X', esperado formato ^[a-z0-9]...`. Mantenha esse padrão em código novo.
- **Nunca imprima credencial.** `bin/credencial.sh` só responde sim/não (exit code); nenhum outro
  script deve ler `.env` diretamente para expor um valor.
- **Falha de integração externa nunca apaga dado local.** Ver o padrão de fallback em
  `bin/holdings-sync.sh` (mantém o último `holdings.json` conhecido com aviso de idade) antes de
  escrever um novo ponto de integração.

## Adicionando uma entrada ao catálogo

`catalog.json` é documentação curada, não lido em runtime pelo `bin/setup.sh` (que hoje hardcoda
os MCPs de Alpha Vantage e Plaid diretamente). Para adicionar uma entrada nova ao catálogo em si,
edite o domínio correspondente respeitando o critério de entrada documentado em
[`produto/features/catalogo-de-plugins.md`](../produto/features/catalogo-de-plugins.md) e valide
com `jq empty catalog.json`.

## Processo de mudança de escopo

O produto nasceu de um PRD formal, mantido pelo autor num workspace de planejamento local
(`.ralph/`, fora do controle de versão — gitignored de propósito, nunca publicado) — ver
[`produto/visao-e-motivacao.md`](../produto/visao-e-motivacao.md) para o resumo legível de tudo
que esse processo já produziu. Uma mudança de escopo depois de um PRD selado vira uma iteração `update`
do PRD, nunca uma edição direta do documento aprovado — o mesmo processo que gerou
[a decisão de mecanismo de MCP](../produto/decisao-mecanismo-mcp-e-enum-mercado.md) registrada
neste repositório.
