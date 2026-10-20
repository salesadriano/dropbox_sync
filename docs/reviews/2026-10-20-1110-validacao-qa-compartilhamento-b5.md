# Validacao independente do QA — Link temporario e link compartilhado (fase 5)

## Identificacao

- Projeto: `dropbox_sync` (`dbx`), CLI em Bash para a API Dropbox v2
- Demanda: F-15 e F-16; porte **G** (validacao independente e adversarial, regra 40)
- Agent: QA Expert; data 2026-10-20; ciclos: 3
- Branch / base: `feature/compartilhamento-b5` sobre `develop` @ `e42168f`, sem commit
- Registro de entrega: [2026-10-20-1110-registro-compartilhamento-b5.md](2026-10-20-1110-registro-compartilhamento-b5.md)
- Pareceres do desenvolvedor: [TDD](2026-10-20-1110-parecer-tdd-compartilhamento-b5.md) e [conformidade](2026-10-20-1110-parecer-conformidade-compartilhamento-b5.md)
- Fontes do QA: escopo v1.18, secao 5.13 (RF-84..92); memoria `2026-10-20-1110-compartilhamento`; RSK-57..61; pareceres do developer
- Fonte deste documento: relatorio dos tres ciclos do QA repassado pelo Tech Lead, resumido aqui. As tabelas de achados seguem o relatorio do QA.

## Suite do QA

`tests/integracao/qa_compartilhamento_b5_test.sh`, 43 casos na versao final. Qualquer mudanca na suite volta para a aprovacao do solicitante (regra 12).

| Versao | sha256 (prefixo) | Casos | Mudanca |
|---|---|---|---|
| Ciclo 1 | `72f035f8...` | 32 | Suite inicial: senha (s01..s10), `--revogar` (r01..r05), visibilidade (v01..v03), reuso (x01..x04), confinamento (l01..l05), erros e auditoria (e01, e02, d01, d02, a01) |
| Ciclo 2 | `97935ad1...` | 40 | c01..c08 novos; o duble registra `umask` e o modo do arquivo de corpo |
| Ciclo 3 (final) | `8adf68023874b67e2fb51de3b946d43b489b2a5952621b3b01203e4ecb566a76` | 43 | c09..c11 novos; `c02` ajustado pela DIV-128; o duble ganhou `@HM@` |

**Aprovacao do solicitante (regra 12):** em 2026-10-20 ("Aprovo"), para a versao final, `8adf6802...`, com 43 casos. O log de prompt registra so essa aprovacao.

## Ciclo 1 — REPROVADO

Os dois P0 centrais passam: a senha nao vaza por argv, ambiente, `-K -`, saida normal ou disco, e o `--revogar` nao sai da raiz. Cada caso foi provado contra mutante (35 mutantes, todos mortos).

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B5-01 | Maior (P0-4) | `modify` com 200 que mantem o link `public` saia 0 como `modificado`, sem `visibilidade_pedida` nem aviso; com `--senha`, `senha_redefinida=sim` ao lado de `senha=nao` | Corrigido no ciclo 2 (comparacao do RF-85(i) tambem no modify) |
| QA-B5-02 | Maior (P0-1) | `error_summary` em JSON com a senha chegava cru ao stderr | Corrigido no ciclo 2 (mascara por valor); a correcao abriu QA-B5-08 e QA-B5-09 |
| QA-B5-03 | Maior (P0-5) | `has_more` com pagina vazia e cursor sempre novo fazia o `--listar` girar sem fim | Corrigido no ciclo 2 (pagina vazia com `has_more` sai 10) |
| QA-B5-04 | Menor | A recusa de URL citava a credencial embutida (`user:pw@`) | Corrigido no ciclo 2; restou a forma com `/` (QA-B5-11) |
| QA-B5-05 | Menor | O arquivo de corpo com a senha nascia 0644 pela `umask` herdada; resta depois de SIGKILL | Corrigido no ciclo 2 (nasce 0600); o resto apos SIGKILL, dentro do diretorio 0700, fica declarado no RSK-58 |
| QA-B5-06 | Menor | `link-temporario` com `\n` no `link` saia 0 sem nada | Corrigido no ciclo 2 (sai 10) |
| QA-B5-07 | Menor | `create` 200 com `{}` saia 0 com `url=` vazio | Corrigido no ciclo 2 (sai 10, tambem no modify) |

Observacao sem defeito: o `modify` age sobre a `url` do item listado cujo `path_lower` e igual ao alvo, o mesmo modelo de confianca do `--revogar`. Limite do teste: o SIGINT so pode ser testado com processo em disposicao padrao.

Spec `files.stone` (dropbox-api-spec, `main`, `f4e029d`): `email_not_verified` (sai 6) e `path/not_file` (sai 2) confirmados; o † da secao 5.13 pode ser retirado.

## Ciclo 2 — REPROVADO

Confirmadas as correcoes de QA-B5-01, 03, 05, 06 e 07; a suite do ciclo 1 passa 32/32. Oito casos novos (c01..c08).

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B5-08 | Maior | A mascara rodava antes da classificacao: senha que e trecho da tag mudava o desfecho (reuso virava 7) e `shared_[REDIGIDO]_already_exists` revelava a senha pelo contexto | Corrigido no ciclo 3 (classifica pelo resumo original) |
| QA-B5-09 | Maior | Senha em pedacos: corte de 120 bytes antes da mascara e forma escapada do JSON | Corrigido no ciclo 3 (com a senha no pedido, nenhum texto do servico e citado) |
| QA-B5-11 | Maior, seguranca | Credencial com `/` na senha ainda vazava pelo host | Corrigido no ciclo 3 (host e esquema citados so por padrao fechado) |
| QA-B5-12 | Maior | 2xx com corpo malformado em create, modify e revoke saia 0 (ja existia no ciclo 1) | Corrigido no ciclo 3 (sai 10) |
| QA-B5-13 | Menor | Reuso de link listado sem `url` saia 0 | Corrigido no ciclo 3 (sai 10) |
| QA-B5-14 | Menor | `--listar` sem fim com paginas nao vazias so de omitidos | Corrigido no ciclo 3 (teto de 1000 paginas, sai 10) |
| QA-B5-15 | Menor | `link-temporario` aceitava `link` com espaco | Corrigido no ciclo 3 (sai 10); restou o espaco Unicode (QA-B5-18) |
| QA-B5-16 | Menor | `password` com `require_password false` saia 0 | Corrigido no ciclo 3 (sai 10); restaram outras incoerencias (QA-B5-19) |
| OBS | Menor (teste do developer) | `lst06` pendurava com o mutante "sem cursor visto" em vez de reprovar | Corrigido no ciclo 3 (`timeout` em `_rodar`) |

## Ciclo 3 — APROVADO com tres ressalvas Menores

A DIV-128 tirou do `c02` a exigencia de texto do servico no stderr; ficaram as assercoes de segredo ausente. Ataque as correcoes: nenhum vazamento em 96 combinacoes de modo e resposta com a senha no pedido (`c09` cobre 60); host hostil sempre omitido (`c10`); teto de 1000 paginas nos dois lados do limite (`c11`).

| Id | Severidade | Achado | Desfecho |
|---|---|---|---|
| QA-B5-17 | Menor | Se a senha for igual a uma tag da tabela e o servico devolver essa tag, a mensagem cita a tag, igual a senha | Corrigido no ciclo 4 do developer (tag igual a senha nao e citada) |
| QA-B5-18 | Menor | Espaco Unicode (U+00A0, U+2028) no `link` ou na `url` passava | Corrigido no ciclo 4 (`^[!-~]+$`, fora disso 10) |
| QA-B5-19 | Menor | Outras incoerencias entre `resolved_visibility` e `require_password` saiam 0 | Corrigido no ciclo 4 (coerencia geral, 10 na criacao, no modify e no reuso; DIV-129) |

Mutantes do ciclo 3: MC9, MC10, MC11 e MC11b mortos; MC5, MC6 e MC8 seguem mortos. O MC2 (mascara com o padrao sem aspas) ficou vivo no `c02`, por ser equivalente na saida observavel: pela DIV-128, nenhum texto do servico chega a mensagem com a senha no pedido, e a mascara virou segunda barreira.

Resultado da suite do QA no ciclo 3: 43 de 43, caso a caso e pelo runner. Runner: `qa_compartilhamento` 43, `compartilh` 141, `json` 62, `http` 53, `qa_` 290, todos aprovados. shellcheck limpo e `verificar-remocao-de-casos` sem reducao. No ciclo 4 do developer, a suite do QA, intacta, passou inteira (`qa_` 13 arquivos, 290 casos).

**Veredito do QA: APROVADO, 2026-10-20 (ciclo 3), com as ressalvas QA-B5-17..19 corrigidas pelo developer no ciclo 4, antes do commit.**
