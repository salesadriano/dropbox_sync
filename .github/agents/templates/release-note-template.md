# Template - Release Note (regra 53)

Um arquivo por versao liberada para producao, em `docs/releases/<versao>.md`. Escrito para quem usa e opera o produto: diz o que muda para a pessoa, nao como foi implementado. Cada item e uma frase e aponta para a PR, a issue e o registro de entrega; nada do registro e copiado (regra 41). Secao sem conteudo e omitida com `Nao aplicavel: <motivo>`, nunca deixada com os marcadores `<...>` do template (regra 41). Sem segredo, credencial, endereco interno ou dado pessoal (regra 2).

```markdown
# <produto> <versao>

- Data da release: <AAAA-MM-DD>
- Intervalo compilado: `<tag ou commit da release anterior>..<commit liberado>` (<n> PRs mescladas)
- Release anterior: [<versao anterior>](<versao-anterior>.md) | Primeira release
- Aprovado pelo solicitante em: <AAAA-MM-DD> (entrada de aceite `<id>`)

## Resumo

<Duas a quatro frases: o que esta versao entrega e para quem.>

## Atencao: exige acao de quem atualiza

<Mudanca incompativel, migracao de dados, variavel de ambiente nova, permissao, passo manual de implantacao. Uma linha por item, com o que fazer.>

## Principais implementacoes

| Implementacao | O que muda para quem usa | Referencias |
|---|---|---|
| <nome curto> | <uma frase> | PR #n, issue #n, [registro](../reviews/<arquivo>.md) |

## Melhorias

- <uma frase>. PR #n.

## Correcoes

- <defeito corrigido, como o usuario o percebia>. PR #n, issue #n.

## Seguranca

- <correcao ou endurecimento, sem detalhe exploravel>. PR #n.

## Dados, configuracao e implantacao

- Migracoes de schema: <lista ou nenhuma>
- Configuracao e variaveis de ambiente: <novas, alteradas, removidas ou nenhuma>
- Ordem de implantacao e rollback: <passos, ou link para o plano>

## Limitacoes conhecidas e o que nao foi validado

- <ressalva aberta dos registros de entrega do intervalo, com owner>

## Validacao

- Suite completa e pipeline do commit liberado: <resultado e link>
- Teste de seguranca no ambiente implantado (Regra 10 de `protocolo-tdd`), quando aplicavel: <resultado>
- Validacao humana (regra 52), quando aplicavel: <o que o solicitante exercitou>

## Fora desta versao

- <PR mesclada no intervalo que nao muda nada para quem usa (documentacao, teste, governanca), em uma linha agregada, e o que foi adiado>
```
