# Validacao independente do QA: fase 8, perfis nomeados de credencial (F-18)

Porte G. Papel: QA Expert. Suite: `tests/integracao/qa_perfis_b8_test.sh`
(sha256 `9e6617c358b02608124dfd721e711226f5c5ca3e2b47b1da7ef44515b05932d7`).
Executavel real `bin/dbx`, duplo de `curl` proprio, sem rede real.

## Comandos e contagens literais

| Comando | Resultado |
|---|---|
| `bash tests/run.sh qa_perfis_b8 < /dev/null` | casos aprovados 34, reprovados 0, pulados 0; APROVADA |
| `bash tests/run.sh json < /dev/null` | casos aprovados 62, reprovados 0, pulados 0; APROVADA |
| `bash tests/run.sh harness < /dev/null` | casos aprovados 22, reprovados 0, pulados 0; APROVADA |
| `sh scripts/lint.sh tests/integracao/qa_perfis_b8_test.sh` | exit 0 |

Nota: a primeira execucao de `json` reprovou (guarda de massa adversarial por
substituicao de comando) por defeito da PROPRIA suite do QA; corrigido com
`printf -v`, depois verde. Nao e achado de producao.

## Cenarios (34)

- Nome (qpf01-05): 17 nomes hostis (`..`, `../fora`, `a/b`, `/etc/passwd`, maiusculas, `-x`, `_x`, `a.b`, espaco, unicode, newline, 33 caracteres, `.json`, `a.json`) em `space`, `unlink`, `config`, `perfis` e opcao global: sempre exit 2, zero chamadas de rede, disco byte a byte intacto; limites 32/33; `padrao` explicito usa `credencial.json` e ignora `perfis/padrao.json` plantado (inclusive no `unlink`).
- Symlink e permissao (qpf06-08): link no lugar de `perfis/<nome>.json` e de `perfis/` recusado, alvo nunca lido nem apagado; arquivo 644, `perfis/` 755 e `dbx/` 777 recusados (exit 3).
- Selecao (qpf09-13): `DBX_PERFIL` com segredo/longo recusado sem ecoar o valor; vazio vale como nao definido; opcao repetida (alias, global + depois do subcomando, `config`) exit 2 sem tocar nada (DIV-241); sem valor; inexistente exit 3 sem rede e sem recuo ao padrao (opcao e ambiente).
- `unlink` (qpf14-23): identidade compartilhada com o padrao e do padrao com perfil nao revoga nem toca estado; credencial ilegivel (JSON quebrado, modo 000) nao remove estado; ultimo perfil, remocao total preservando `trava-par`; comparacao por cabecalho `cred-`, nunca por grafia do nome; estado simbolico nao seguido; trava viva exit 7 sem remover/revogar; `--dry-run` e sem `--confirmar` nao alteram.
- `perfis` (qpf24-25): nenhum segredo (refresh, secret, `cred-`) em saida normal, json, debug, verbose; anomalos (maiuscula, diretorio, link) nao entram como perfil e o link nao e seguido.
- Trava de raiz (qpf26-29): dois perfis e o padrao na mesma raiz (inclusive por `..`) exit 7 sem escrever e sem perfil/identidade na mensagem; `--esperar 10` conclui; `--esperar 1` esgota com 7; raizes distintas nao se bloqueiam.
- CNF-03 (qpf30-33): ver achado.

## Achados

| ID | Severidade | Local | Descricao | Prova |
|---|---|---|---|---|
| QA-PF-01 (= CNF-03, CONFIRMADO) | Menor | `lib/config.sh:576-620` (ramo `$# -eq 2`; guardas em 593 e 614) | `dbx_config_carregar <arquivo> <nome>` nao revalida `<nome>`: nome hostil (`../x`) devolve rc=0; com o rotulo `padrao` e arquivo de `perfis/`, a cadeia `dbx/`->`perfis/` nao e conferida (so o diretorio imediato): `dbx/` 777 passa. Sem exploracao pela CLI, pois so `perfis` e `unlink` chamam, com caminho de `caminho_de_perfil`; e defesa em profundidade (RNF-37). O link em `perfis/` com rotulo `padrao` e recusado (rc=3) pelo `-f`/modo. | qpf31 e qpf33 (caracterizam o comportamento ATUAL; invertem ao corrigir); qpf30 e qpf32 verdes |
| QA-PF-02 | Informativo | `lib/cmd.sh` (unlink de credencial ilegivel) | Credencial ilegivel e removida do disco com exit 14 e erro "removida sem que a revogacao fosse emitida"; estado preservado. Comportamento declarado e coerente com DIV-253; registrado so para ciencia: o token pode continuar valido na Dropbox. | qpf16, qpf17, qpf34 |

Recomendacao QA-PF-01: chamar `dbx_config_perfil_validar "$nome"` no ramo de 2
argumentos e aplicar a cadeia completa por `[[ -f ... perfis/ ]]` em vez do rotulo
(correcao a cargo do Senior Developer, a criterio do Tech Lead; nao bloqueia).

Sem achado bloqueante ou maior. Divergencias entre PRD/ARD e implementacao: nenhuma encontrada.

## Ciclo 2 (correcao de QA-PF-01)

O Senior Developer corrigiu `dbx_config_carregar` em `lib/config.sh`: o ramo de 2 argumentos valida o nome antes do disco e confere a cadeia pelo caminho. qpf31 e qpf33 foram invertidos para afirmar a recusa: nome `../x` -> `rc=2 motivo=perfil_invalido`; `dbx/` 777 com rotulo `padrao` -> `rc=3`. Ambos reprovavam/aceitavam o defeito antes e agora passam. **QA-PF-01: corrigido e verificado.**

Reexecucao (sha256 novo acima), `< /dev/null`:
- `bash tests/run.sh qa_perfis_b8`: casos aprovados 34, reprovados 0, pulados 0; APROVADA.
- `bash tests/run.sh json`: casos aprovados 62, reprovados 0, pulados 0; APROVADA.
- `bash tests/run.sh harness`: casos aprovados 22, reprovados 0, pulados 0; APROVADA.
- `sh scripts/lint.sh tests/integracao/qa_perfis_b8_test.sh`: exit 0.

## Veredito

**Veredito final (ciclo 2): Aprovado.** Resta apenas QA-PF-02 (informativo, comportamento declarado). Aceite do solicitante pendente
sobre o conjunto `qa_perfis_b8_test.sh` (sha acima).
