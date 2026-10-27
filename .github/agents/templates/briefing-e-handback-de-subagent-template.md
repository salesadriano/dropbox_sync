# Template - Briefing e hand-back de subagent descartavel (regra 49)

Um subagent por tarefa fechada. O briefing e tudo o que ele vai saber alem do que o hook de criacao injeta (estado do repositorio, caminhos confirmados, extrato de memoria do papel); o hand-back e tudo o que volta ao Tech Lead. Nenhum dos dois transcreve o que ja esta em arquivo: aponta.

Antes de delegar, o Tech Lead grava os termos da demanda para o hook ordenar o extrato:

```sh
printf '%s\n' "<termos da demanda, separados por espaco>" > "$(git rev-parse --git-common-dir)/agentes-termos-da-demanda"
```

## Briefing (o Tech Lead escreve; ate 60 linhas)

```markdown
Papel: <senior-developer | qa-expert | ux-expert | dba | business-analyst | documentation-writer | commit-writer>
Demanda: <slug do log de prompt> | Porte: <P | M | G> | Log: docs/prompts/<arquivo>.md
Issues: <`#n`/`owner/repo#n` do log, ou nenhuma; cite `Refs` nos commits que preparar, nao comente na issue>
Worktree: <caminho absoluto> (branch `<branch>` sobre `origin/<base>` @ <sha>)

Objetivo (uma frase): <o que entregar>
Criterio de pronto (mensuravel, uma linha cada):
- <ex.: testes dos itens afetados verdes pelo comando X, contagem literal no registro>
- <ex.: parecer de conformidade na secao 5 do registro docs/reviews/<arquivo>.md>

Arquivos do escopo: <lista; o que esta fora do escopo nao e tocado>
Requisito ou decisao que governa a tarefa: <id da entrada de memoria ou caminho do documento; o extrato ja chegou pelo hook, so cite o que falta nele>
Secoes do AGENTS.md a ler: <ex.: Ciclo do developer, passos 2 e 3> (nao ler o arquivo inteiro)
Skills a aplicar: <SKILL.md por caminho; abrir references/ so no trecho necessario, regra 37>

Limites:
- Nao delegar a outro subagent (salvo documentation-writer e commit-writer, quando o porte exigir).
- Nao falar com o solicitante: pergunta vai no hand-back.
- Nao rodar memoria-index.sh, nao ler AGENTS.md inteiro nem persona de outro papel.
- Registrar o que alterar: `sh scripts/alteracoes-externas.sh --registrar <arquivos>` a cada passo.
- <limite proprio da tarefa: ex.: sem commit; sem push; sem alterar o arquivo X>

Numeros no briefing: <"(a medir)" onde o Tech Lead nao mediu; o subagent mede e contesta o que recebeu>

Hand-back esperado: ate 40 linhas, no formato abaixo.
```

## Hand-back (o subagent escreve; ate 40 linhas)

```markdown
Resultado: <Concluido | Concluido com ressalvas | Bloqueado | Reprovado no gate>
Arquivos escritos (caminho e, para teste do QA, sha256):
- <docs/reviews/<arquivo>.md, secoes N a M>
- <caminho do teste> sha256 <hash>
Evidencia (uma linha por comando, contagem literal): <comando> -> <total/aprovados/falhos/duracao>
Decisoes que tomei (uma linha cada, com o porque): <...>
Divergencia do briefing (o que medi diferente do que recebi): <... | nenhuma>
Pendencias e perguntas ao Tech Lead: <... | nenhuma>
Registrado no detector: <sim, arquivos | nao, motivo>
```

O que **nao** entra no hand-back: diff, saida completa de teste, texto de parecer, transcricao do briefing, relato de passos intermediarios. Isso vive nos arquivos citados.
