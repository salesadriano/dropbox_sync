---
id: 2026-10-20-1110-compartilhamento
tipo: decisao
escopo: projeto
titulo: Link temporario e compartilhar em comandos proprios; visibilidade sempre explicita; senha so por terminal ou stdin
data: 2026-10-20
dono: Tech Lead
instancia: myPCWin/Adriano Sales Santos
agentes: tech-lead, senior-developer, qa-expert, business-analyst
status: ativa
ref: docs/prompts/2026-10-20_1110_backlog-fase-5-compartilhamento.md
---

Decidido pelo solicitante em 2026-10-20 (fase 5, F-15 e F-16):
- **Comandos:**
  - `dbx link-temporario <arquivo>` (alias `temp-link`) gera a URL direta de 4 h, por `files/get_temporary_link`.
  - `dbx compartilhar <caminho>` (alias `share`) cria link compartilhado e tem `--listar` e `--revogar <url>`.
- **Visibilidade:** sem `--publico`, `--equipe` ou `--senha`, o `compartilhar` sai com 2. Nunca publica por omissão.
- **Senha:** nunca no argv nem em variável de ambiente. `--senha` pede no terminal, sem eco; `--senha-stdin` lê uma linha da entrada.
- **Link existente:**
  - sem configurações pedidas, devolve o link existente;
  - com configurações diferentes, aplica `modify_shared_link_settings` e mostra o antes e o depois.
- **Escopo OAuth:** os escopos `sharing.write`, `sharing.read` e `files.permanent_delete` já estão habilitados e autorizados na conta do solicitante (2026-10-20). O `sharing.read` foi confirmado pelo solicitante (DIV-106).

Divergências do BA decididas pelo Tech Lead (escopo v1.18, seção 5.13, RF-84..92):
- **DIV-104, 105, 107 a 120:** aceitas como recomendadas. Em destaque:
  - **DIV-104:** "sem configurações pedidas" quer dizer "sem configuração diferente do estado efetivo"; nesse caso o link é reusado sem escrita.
  - **DIV-107:** o reuso vem sempre de `list_shared_links` com `path` e `direct_only`. Mais de um link para o mesmo caminho sai com 7.
  - **DIV-108:** `--senha` sobre link existente sempre redefine a senha.
  - **DIV-109:** no terminal, a senha é digitada duas vezes e, se divergir, sai 14. São recusadas a senha vazia, com caractere de controle ou `\r`, com mais de 1024 bytes ou que não é UTF-8 válido.
  - **DIV-110:** "nunca em variável" vale para variável de ambiente. Uma variável `local` do shell, apagada logo depois do uso, é aceita.
  - **DIV-111:** defeito latente: `link_password` entra nas chaves sensíveis mascaradas de `lib/errors`.
  - **DIV-112:** usar `audience` e `require_password`, não os campos depreciados; `--equipe --senha` sai 2.
  - **DIV-114:** `--revogar` não pede confirmação, porque recriar o link é possível. A URL é validada antes da rede, e `path_lower` ausente ou fora da raiz sai 13, mesmo com raiz `/`. O RNF-20(f) não se aplica: revogar não apaga dado.
  - **DIV-117:** módulo novo `lib/compartilhamento`; a leitura sem eco fica num ponto único de `lib/cli`.
  - **DIV-118:** comparação de `path_lower` fora do ASCII falha fechada.
  - **DIV-120:** o alvo `/` é recusado.
Divergências do Senior Developer decididas pelo Tech Lead:
- **DIV-121:** o teste aprovado `composicao_test` não muda.
  - A grafia `link_temporario`, que é o nome do arquivo, é aceita pelo despacho porque a auditoria aprovada do `cli_test` exige que todo arquivo de `commands/` seja um nome válido.
  - Mesmo assim, ela não é documentada: fica fora da ajuda, do autocompletar e do README.
  - O corpo é montado em `lib/compartilhamento`.
  - O ponto único do `link-temporario` é conferido num caso próprio do `compartilhar_test`.
- **DIV-122:** a mensagem diz "no plano Basic, so link publico, sem senha e sem expiracao", e o BA ajusta o RF-90(b). Sem isso, a redação de `lib/errors` trocaria "Basic <palavra>" por `[REDIGIDO]`.
- **DIV-123:** caminho relativo sai 2 em todos os modos dos comandos novos, inclusive no `--listar`, por coerência com o RF-84(a). O developer corrige o `--listar`.
- **DIV-124:** aceita. `list_shared_links` não tem `limit`, então o RNF-23 não se aplica, e uma página acima de 256 KiB sai 10.
- **DIV-125:** aceita. A saída usa o vocabulário `ResolvedVisibility` da API; `--equipe` corresponde a `team_only`.
- **DIV-126:** aceita. O próprio `read -s` restaura o eco, medido em pseudo-terminal, e um sinal durante a leitura sai 14.
- **DIV-127:** aceita. Criar, modificar e revogar são idempotentes para a retentativa, conforme a DIV-119.
Validação independente do QA, ciclo 1: **REPROVADO** (regra 17). O Tech Lead decidiu corrigir todos os achados:
- **QA-B5-01:** depois do `modify`, a visibilidade resolvida é comparada com a pedida, como no RF-85(i). Se o pedido não foi atendido, sai como na criação, com aviso. A saída não pode dizer `senha_redefinida=sim` ao lado de `senha=nao`.
- **QA-B5-02:** a senha é redigida pelo valor em todo erro e diagnóstico, inclusive dentro de `error_summary` em JSON.
- **QA-B5-03:** página com `has_more` verdadeiro que não traz item nenhum conta como página que não avança e sai 10 (RF-88(b)).
- **QA-B5-04:** a recusa de URL nunca cita credencial embutida (`user:pw@`). Por ser achado de segurança, não fecha por justificativa.
- **QA-B5-05:** o arquivo do corpo nasce 0600. O resíduo depois de SIGKILL, dentro do diretório 0700, fica como limitação declarada no RSK-58.
- **QA-B5-06 e 07:** link com quebra de linha, ou resposta sem `url`, é resposta malformada e sai 10.
Validação do QA, ciclo 2: **REPROVADO**. Decisões do Tech Lead:
- **QA-B5-08 e 09 (senha):** a máscara por valor não basta.
  - Quando a senha é enviada (criar ou modificar com `--senha`/`--senha-stdin`), nenhum texto bruto do serviço vai para stderr nem para `--debug`: nem `error_summary`, nem corpo, nem trecho dele.
  - Aparecem só a mensagem do próprio dbx para a classe, o código HTTP e a tag reconhecida.
  - A classificação usa o resumo original, sem máscara.
  - A máscara por valor continua como segunda barreira.
- **QA-B5-11:** a recusa de URL só cita o host quando ele casa `^[A-Za-z0-9.-]+(:[0-9]+)?$`; fora disso, omite.
- **QA-B5-12 e 13:** resposta 2xx malformada em create, modify ou revoke, ou link reusado sem `url`, sai 10.
- **QA-B5-14:** o `--listar` tem um teto de 1000 páginas; ao passar dele, sai 10 com a mensagem "listagem nao terminou em 1000 paginas".
- **QA-B5-15:** link com espaço ou caractere de controle sai 10.
- **QA-B5-16:** resposta incoerente (`password` com `require_password false`) sai 10, com aviso para conferir com `--listar`.
- **DIV-128:** vale a decisão de QA-B5-08/09.
  - O caso `qa_c02` exigia texto do serviço no stderr quando a senha vai no pedido, e isso contraria a decisão.
  - O QA ajusta o caso para exigir que nenhum texto do serviço apareça; as asserções de segredo ausente ficam.
  - A suíte volta para a aprovação do solicitante.
Validação do QA, ciclo 3: **APROVADO, com três ressalvas Menores**. O Tech Lead decide corrigir as três antes do commit (regra 17: achado de segurança não fecha por justificativa):
- **QA-B5-17:** se a tag reconhecida for igual à senha enviada, ela não é citada.
- **QA-B5-18:** URL ou link devolvido pelo serviço tem de ser ASCII imprimível, `^[!-~]+$`. Fora disso, sai 10.
- **QA-B5-19:** a coerência vale em geral: `resolved_visibility` em {`password`, `team_and_password`} se, e somente se, `require_password` for verdadeiro. Resposta incoerente sai 10, na criação, no modify e no reuso.
- **DIV-129:** aceita a conciliação do developer.
  - Um link existente incoerente nunca é igual ao pedido, por isso nunca é devolvido como está.
  - Em vez disso, ele vai para o modify, cuja resposta é conferida e sai 10 se ainda estiver incoerente. Assim o `qa_x01` continua valendo.
  - O ramo de reuso sem escrita mantém a mesma checagem como guarda redundante.
- **`lst06`:** o developer põe teto de tempo no seu `compartilhar_test`, para o mutante reprovar em vez de pendurar.
- **`files.stone`:** confirma `email_not_verified`, que sai 6, e `path/not_file`, que sai 2.
- **DIV-106:** resolvida pelo solicitante: `sharing.read` está habilitado, e a fase sai completa.
