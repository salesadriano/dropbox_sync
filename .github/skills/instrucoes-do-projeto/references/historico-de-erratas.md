# Historico de erratas: formato e conferencia do verbatim

Arquivo `docs/historico/<assunto>.md`, um por assunto do arquivo de instrucoes que acumulava erratas (contagem de um contrato, estado de uma integracao, decisao revista varias vezes). Criado na compactacao e alimentado dali em diante: errata nova entra no fim da secao do assunto, e o bloco de estado do arquivo de instrucoes e atualizado na mesma entrega.

## Cabecalho

```markdown
# Erratas historicas do <arquivo de instrucoes>

Blocos de errata movidos **verbatim e na ordem original** do `<arquivo>` em <data>, por decisao de
<solicitante> (literal: *"<literal>"*). Origem: `<arquivo>` em `<branch>` @ `<sha>`; o intervalo de
linhas de cada secao e o daquele arquivo. **Nada foi apagado nem editado**: cada bloco descreve o
estado do repositorio na data em que foi escrito, e oracoes como *"nao esta mesclada"* valem para
aquela data. O estado vigente esta no `<arquivo>`, secao *<bloco de estado>*. **Errata nova entra
aqui, no fim da secao do assunto, e atualiza aquele bloco; o `<arquivo>` nao acumula mais.**

Registro da mudanca: `docs/reviews/<registro-de-entrega>.md`.

## 1. <Assunto> (secao *<secao de origem>*)

*`<arquivo>` @ `<sha>`, linhas <inicio>-<fim>.*

> <bloco 1, verbatim>

> <bloco 2, verbatim>
```

## Conferencia do verbatim

Para cada secao, recortar o intervalo declarado do arquivo original e comparar com o trecho do historico. Exemplo com o intervalo 29-1205:

```sh
git show <sha>:<arquivo> | sed -n '29,1205p' > /tmp/origem.txt
awk '/^## 1\. /{p=1; next} /^## 2\. /{p=0} p' docs/historico/<assunto>.md | sed '1,2d' > /tmp/historico.txt
diff /tmp/origem.txt /tmp/historico.txt && echo "VERBATIM OK secao 1"
```

O `sed '1,2d'` descarta a linha de origem (`*...linhas...*`) e a linha em branco que a segue; ajustar se o cabecalho da secao tiver outro tamanho. A conferencia e feita pelo autor antes do gate de conformidade e, de forma independente, pelo QA; as duas saidas (`VERBATIM OK` por secao) vao para os pareceres.

## O que nao vai para o historico

- Norma vigente: decisao do solicitante que ainda vale, regra de testes, ordem da pipeline, restricao de ambiente. Fica no arquivo de instrucoes mesmo que seja longa.
- Segredo, credencial, token, cookie, chave ou dado pessoal: sanitizado antes de mover. O que nao puder ser sanitizado e descrito em uma linha, nunca copiado.
- Conteudo que ja vive num registro de entrega: o historico aponta por link, nao repete.

## Bloco de estado vigente

No arquivo de instrucoes, no lugar das erratas, um bloco por assunto, curto e com fontes:

```markdown
### <Assunto>: estado vigente

<Numero ou estado vigente>, conferido em `<branch>` @ `<sha>` (<data>). Fonte: `<constante ou arquivo>`.
Ultima medicao: `docs/reviews/<registro>.md`, secao *<secao>*. Historico das mudancas:
`docs/historico/<assunto>.md`. Regra: <como e quando o numero e remedido; ver `superficie-de-contrato`>.
```
