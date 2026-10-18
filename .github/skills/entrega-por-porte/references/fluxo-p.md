# Fluxo P: criterios, execucao e amostragem do QA

O porte P da regra 40 do `AGENTS.md` ("pontual: nenhum gatilho de M ou G e alteracao localizada") e qualitativo e, por isso, raramente aplicado. Este fluxo o torna objetivo. E mais curto que o ciclo do developer, e so vale quando **todos** os criterios abaixo se cumprem.

## 1. Criterios

| Criterio | Como medir |
|---|---|
| Ate **50 linhas de codigo** no diff | `git diff --numstat origin/<base>` somando adicoes e remocoes dos arquivos de producao e de teste; documentacao, memoria e logs de prompt nao contam. O projeto pode registrar outro limite. |
| Nao toca **contrato publico** | rota, payload, contrato OpenAPI ou equivalente, evento publicado, CLI exposta |
| Nao toca **schema ou migration** | qualquer arquivo de migracao, modelo de dados ou definicao de tabela |
| Nao toca **autenticacao ou autorizacao** | guards, decorators, matriz de papeis, sessao, politicas de acesso |
| Nao toca **segredo ou dado sensivel** | configuracao de segredos, campos pessoais, mascaramento |
| Nao toca **fronteira arquitetural** | camada, modulo, porta ou adaptador novo; mudanca de dependencia entre camadas |
| Nao toca **pipeline, congelamento ou dependencia** | `.github/workflows/`, arquivo de versoes congeladas do projeto, manifestos e lockfiles |
| Nao e **defeito de alta criticidade** | seguranca, perda ou corrupcao de dado, indisponibilidade, impacto financeiro ou regulatorio |

Falhou um, e M. Sobe para M **ao primeiro sinal**, em qualquer ponto da demanda, sem justificativa; descer de M para P exige justificativa no log de prompt (regra 40). O projeto registra na entrada de adocao a lista concreta de caminhos que tiram a demanda de P (a matriz de autorizacao, o arquivo de congelamento, os diretorios de migration).

## 2. Execucao

1. O Tech Lead classifica P no log de prompt, com os criterios conferidos em uma linha cada.
2. O **proprio Tech Lead implementa**, sem delegar ao Senior Developer, sob `protocolo-tdd` (red-green nos itens afetados) e `protocolo-conformidade` sobre o diff.
3. Testes: so os arquivos de teste dos itens afetados (Regra 8), com parada no primeiro erro (Regra 9). O que **nao se compacta**: a Regra 6 quando o diff tocar rota, guard, sessao ou entrada de usuario, e a Regra 9.
4. Os dois gates fecham num **parecer combinado**: a secao *Gates* do registro curto, com uma linha por gate (skills aplicadas, achados com severidade e arquivo:linha, veredito). `Reprovado` em qualquer linha bloqueia, como sempre.
5. Tres abordagens dispensadas: uma linha na secao *Causa ou decisao* com a causa raiz e por que a solucao e unica.
6. Registro: um arquivo pelo template curto; `documentation-writer` e `commit-writer` opcionais; aprovacao do Tech Lead em uma linha na secao *Links e aceites*; memoria so se houver decisao duravel.
7. `sh scripts/alteracoes-externas.sh --detectar` antes de cada gate, commit e push, como em qualquer porte (regra 48).

## 3. QA por amostragem

O QA Expert **nao valida toda entrega P**. Valida 1 em cada N (padrao **N = 5**; o projeto registra outro N na entrada de adocao):

- o Tech Lead conta os registros curtos com `Porte: P` em `docs/reviews/` desde a ultima validacao do QA em P; na N-esima, aciona o QA;
- o QA valida **por evidencia**: audita o parecer combinado, reexecuta os testes dos itens afetados, acrescenta os cenarios de risco que faltarem; **sem mutantes nem arquivo `qa-*`**; o resultado entra na secao *QA* do mesmo registro;
- o Tech Lead pode acionar o QA fora da contagem quando julgar o risco maior; isso reinicia a contagem;
- o registro declara `QA: amostragem <n> de <N> - validada em <data>` ou `QA: amostragem <n> de <N> - nao validada`.

Reprovacao do QA numa amostra devolve a demanda ao passo 2 e, se o achado for de classe (criterio de P mal aplicado, teste ausente em padrao repetido), o Tech Lead revisa as demais P desde a ultima amostra e registra o resultado na memoria do projeto.

## 4. O que P nao dispensa

Log de prompt, os dois gates (combinados, nao omitidos), registro de entrega, `--detectar`, commit com `Prompt:` e `Registro:` no corpo, e a aprovacao do Tech Lead. Regularizacao de intervencao humana (regra 48) nunca e P.
