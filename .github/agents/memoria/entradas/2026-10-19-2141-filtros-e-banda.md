---
id: 2026-10-19-2141-filtros-e-banda
tipo: decisao
escopo: projeto
titulo: Filtros gitignore protegem o destino no espelhamento; data e tamanho so na origem e sem --espelhar; limite de banda por opcao e variavel
data: 2026-10-19
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-19_2141_backlog-fase-4-filtros-e-banda.md
---

Decidido pelo solicitante em 2026-10-19 (fase 4, F-13 e F-17):
- **Filtros de caminho:** `--excluir PADRAO` e `--incluir PADRAO`, repetíveis, em `sync`, `verificar` e `download` de pasta.
  - Sintaxe gitignore sobre o caminho relativo à raiz: padrão sem `/` casa o nome em qualquer nível; `*` não cruza `/`; `**` cruza.
  - A comparação é sem caixa, como no `sync`, e a exclusão vence a inclusão.
- **Espelhamento:** item filtrado fica fora do escopo nos dois lados, nunca transferido nem apagado. Um filtro novo não apaga o que deixou de fora.
- **Data e tamanho:** `--modificado-desde`/`--modificado-ate` e `--tamanho-min`/`--tamanho-max` avaliam só a origem. Com `--espelhar`, são recusados como uso inválido.
- **Limite de banda:** `--limite-banda TAXA` (alias `--bwlimit`) em `upload`, `download` e `sync`. A variável `DBX_LIMITE_BANDA` é o padrão, e a opção vence. O limite usa o `--limit-rate` do cURL, por transferência.

Divergências do BA decididas pelo Tech Lead:
- **DIV-79 a DIV-94:** todas aceitas como recomendadas no escopo v1.15 (seção 5.12, RF-79..83). Em destaque:
  - **DIV-81:** origem toda filtrada conta como vazia; com `--espelhar`, vale a recusa do RF-41.
  - **DIV-82:** a pasta remota excluída é listada pelo `list_folder` recursivo, mas as entradas dela são descartadas.
  - **DIV-86:** aliases em inglês. O homônimo com `lixeira --excluir` fica, porque a exclusão permanente exige confirmação do caminho.
  - **DIV-87:** número sem unidade é bytes/s.
  - **DIV-88:** piso de 2048 B/s por causa do corte de velocidade mínima do RNF-30.
  - **DIV-92:** filtros ficam fora da identidade da memória.
  - **DIV-94:** `lib/filtro.sh` novo e puro.

Divergências do Senior Developer decididas pelo Tech Lead (todas aceitas):
- **DIV-95:** defeito anterior à fase, corrigido nesta PR com teste de regressão.
  - `lib/http` não limpava `_DBX_HTTP_ARQUIVO_CORPO` nos modos bearer e formulário. Por isso, o `delete_v2` que vinha depois de um envio (`sync --enviar --espelhar`) ou uma renovação de token levava o arquivo como corpo.
- **DIV-96:** o nome `server_modified` mora em `lib/filtro` (`DBX_FILTRO_CAMPO_DATA_REMOTA`).
  - O filtro decide escopo, não comparação, então o RF-39 continua valendo: a data do servidor nunca decide transferência.
  - O QA confere que o campo só alimenta o predicado de escopo.
- **DIV-97:** `/` dentro de `[...]`, e faixa com extremo `[`, `]`, `-` ou `^`, são padrões malformados e saem com 2.
- **DIV-98:** nomes dos campos de saída:
  - `filtros`, `excluir`/`incluir`, `modificado_*`, `tamanho_*`, `filtrados_*` e `limite_banda`;
  - no plano e no `verificar` vêm depois de `travessia_parcial`; no resumo final do `sync`, no fim.
- **DIV-99:** nome local que não é UTF-8 válido é comparado por bytes, para o filtro nunca deixar de proteger o item.
- **DIV-100:** arquivo sem data conhecida não passa num filtro de data.
- **DIV-101:** vínculo simbólico ou entrada especial só deixa de marcar a travessia como parcial quando fica fora do escopo como arquivo e como pasta.
- **DIV-102:** `download --dry-run` com filtro não consulta o tipo do alvo; a recusa de arquivo com filtro (DIV-85) vale só na execução real. O dry-run não faz chamada extra de rede.

Validação independente do QA, ciclo 1: **REPROVADO** (regra 17, a reprovação bloqueia). Decisões do Tech Lead:
- **QA-B4-01 (Alta, P0):** corrigir. Na queda para bytes (DIV-99), o padrão e o caminho têm de passar pela mesma dobra, e `?` e o conjunto negado têm de casar uma sequência UTF-8 ou um byte.
  - Hoje um nome local que não é UTF-8 válido, com padrão fora do ASCII, deixa de ser protegido e é apagado com `--espelhar`.
  - O teste de aceite é o QA-B4-E03.
- **QA-B4-02 (Baixa):** seguir o gitignore. Um `]` logo depois de `[` ou `[!` é literal, então `[]a]` é válido.
- **QA-B4-03 (Baixa):** a ajuda e o README passam a dizer que a comparação não normaliza Unicode (NFC e NFD), como já declara o RF-79(h).
- **DIV-103 (do developer, ciclo 2):** aceita só para `--excluir`. Na comparação por bytes de nome local que não é UTF-8 válido, um conjunto com membro fora do ASCII pode casar a mais, e isso só protege a mais.
  - Para `--incluir` o Tech Lead recusa casar a mais. Uma inclusão maior que a pedida põe item no escopo, e com `--espelhar` esse item pode ser apagado.
  - Por isso, quando a comparação é imprecisa, `--incluir` não casa: o item fica fora do escopo, protegido.
  - Contam como imprecisos: o conjunto negado, o conjunto com membro fora do ASCII e o `?`. O `?` entra porque, por bytes, `??` casaria um único `é`.
- **QA-B4-04 (Info, anterior à fase):** corrigir o `mapa-modulos.md`, que deve incluir `qa_recuperacao_b3` e a contagem certa de testes `qa_*`.
