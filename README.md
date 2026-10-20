# dropbox_sync (`dbx`)

[![Licença MIT](https://img.shields.io/badge/licença-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/shellcheck-pass-brightgreen.svg)](#qualidade-e-conformidade)
[![Testes Automatizados](https://img.shields.io/badge/testes-TAP%2013-brightgreen.svg)](#testes-e-qualidade)
[![Piso de Shell](https://img.shields.io/badge/bash-4.4%2B-informational.svg)](#requisitos)

**`dbx`** é uma ferramenta de linha de comando (CLI) determinística, segura e de alto desempenho para interação com a **Dropbox API v2** em ambientes Linux/POSIX.

Projetada com arquitetura modular e aderência estrita a contratos de rede e integridade, a ferramenta tem o `cURL` como **única dependência externa**, além do `bash` 4.4+ e dos utilitários da instalação base listados em [Requisitos do Sistema](#requisitos-do-sistema) — dispensando interpretadores de linguagens de alto nível e analisadores de JSON externos (`jq`).

---

## Principais Recursos

- **Zero Dependências Pesadas:** A única dependência externa é o `cURL` padrão do sistema; o resto é `bash` 4.4+ e utilitários da instalação base, conferidos pela verificação prévia de cada comando.
- **Suporte Transparente a Arquivos e Pastas:** `upload` e `download` operam nativamente tanto com arquivos individuais quanto com pastas inteiras recursivamente.
- **Cache Local Único de `content_hash` (`lib/state.sh`), sem dependência adicional:**
  - Guarda em `~/.local/state/dbx/` (diretório `0700`, arquivos `0600`) o `content_hash` já calculado de cada arquivo, para não reler o que não mudou: `memoria-*` para o `sync` e `upload-*` para o `upload` de arquivo.
  - O reaproveitamento exige a identidade inteira do arquivo (`mtime` e `ctime` com nanossegundos, dispositivo, inode e tamanho); o cache nunca decide nada sozinho.
  - O `upload` só dispensa o envio (`status=dispensado`) quando o `content_hash` **remoto**, consultado na hora, é igual ao do arquivo local — inclusive com `--modo overwrite`. Remoto ausente ou consulta com falha levam ao envio; `--forcar`/`--force`, `--rev` e a entrada padrão (`-`) sempre enviam.
  - **Legado:** versões anteriores mantinham um cache SQLite em `~/.local/state/dbx/dbx.db` (com `dbx.db-wal` e `dbx.db-shm`). Ele ficou obsoleto: nada mais o lê, escreve, migra ou apaga. O arquivo **contém caminhos absolutos de arquivos enviados** e pode ser removido à mão com `rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/dbx/dbx.db"*`; o `dbx unlink` o remove junto com o diretório de estado. `sqlite3` e `python3` não são usados.
- **Integridade Ponta a Ponta:** Cálculo e conferência do algoritmo de resumo oficial (`content_hash`) do Dropbox para uploads, downloads e sincronizações.
- **Progresso de Operações em Tempo Real (`-p` / `--progresso`):**
  - Acompanhamento visual de status e etapas de transferência em `upload`, `download` e `sync`.
  - Emissão estrita pelo descritor de erro (`stderr` / `>&2`), preservando a saída padrão (`stdout` / `>&1`) 100% limpa para pipelines e saídas JSON estruturadas.
  - Ativação explícita (`--progresso`, `--progress`, `-p`), silenciamento forçado (`--sem-progresso`, `--no-progress`) e detecção automática de terminal interativo (`auto`).
- **Criação Automática de Diretórios:** Em `sync --receber` e `download`, cria automaticamente pastas locais de destino e subdiretórios intermediários que ainda não existam.
- **Upload em Partes e Streaming (`stdin`):**
  - Transferência por requisição única para arquivos até 150 MiB.
  - Sessão sequencial em partes de 4 MiB para arquivos maiores.
  - Consumo direto de fluxos pela entrada padrão (`dbx upload - /destino`), mantendo ocupação máxima de disco limitada a um único bloco de 4 MiB.
- **Sincronização Direcional Determinística (`sync`):**
  - Sentido explícito e obrigatório (`--enviar` ou `--receber`), com a origem atuando sempre como autoridade incondicional.
  - Decisões baseadas exclusivamente em `content_hash` — nunca em data ou carimbo de tempo.
  - Travessia em profundidade resistente a links simbólicos e diretórios ilegíveis.
- **Contrato de Automação:**
  - Modos `--json` (saída estruturada em linha única) e `--null` (terminador `\0` para caminhos com quebra de linha).
  - Modo simulação `--dry-run` para pré-visualização de operações sem efeito colateral.
  - Taxonomia padronizada de erros com códigos de saída previsíveis.
- **Segurança Reforçada:**
  - Credenciais persistidas em `~/.config/dbx/credencial.json` com permissão estrita `0600` sob diretório `0700`.
  - Parâmetros sensíveis passados via corpo/fluxo, prevenindo exposição de segredos na tabela de processos (`ps`).

---

## Requisitos do Sistema

- **Sistema Operacional:** Linux (POSIX compatível).
- **Interpretador:** GNU Bash 4.4 ou superior.
- **Rede:** `cURL` com suporte a HTTPS e TLS 1.2+ (única dependência externa).
- **Utilitários da instalação base** (a verificação prévia nomeia o que faltar): `mktemp`, `mv`, `rm`, `chmod`, `mkdir`, `stat`, `head`, `tail`, `wc`, `readlink`, `dirname`, `find`, `cat`, `sleep`, `df`, `ln`, `rmdir` e um utilitário de resumo SHA-256: `sha256sum`, `shasum` ou `openssl`.
- **Opcionais, só no diagnóstico de `dbx config --debug`:** `mount`, `grep`, `getenforce` e `lsattr`; na falta deles, a linha correspondente do relatório é omitida.

---

## Instalação e Configuração

### 1. Instalação no Linux (Recomendado)

#### Opção A: Instalação Rápida via cURL (One-liner)
Para instalar diretamente no espaço do usuário (`~/.local/bin/dbx` e `~/.local/share/dropbox_sync`):
```bash
curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/master/install.sh | bash
```

#### Opção B: Instalação a partir do Repositório
```bash
git clone https://github.com/salesadriano/dropbox_sync.git
cd dropbox_sync
./install.sh                # Instalação no espaço do usuário (~/.local/bin)
# ou para todos os usuários do sistema:
sudo ./install.sh --system   # Instalação global (/usr/local/bin)
```

#### Opção C: Instalação a partir do Tarball de Release
Baixe o arquivo `dropbox_sync-1.2.0-linux.tar.gz` da aba de [Releases](https://github.com/salesadriano/dropbox_sync/releases):
```bash
tar -xzf dropbox_sync-1.2.0-linux.tar.gz
./install.sh
```

> **Vínculo de instalação e utilitários:** o `install.sh` cria `~/.local/bin/dbx` como vínculo simbólico para `~/.local/share/dropbox_sync/bin/dbx`. O ponto de entrada acha a própria raiz só com recursos do shell, mas o bash não lê o alvo de um vínculo: chamado pelo vínculo, o `dbx` usa `readlink` e, se ele faltar, `find -printf %l`; sem os dois, recusa com código `3` e diz o que instalar. Chamar `~/.local/share/dropbox_sync/bin/dbx` pelo caminho real não depende de nenhum deles. O `dbx diagnostico` aponta essa dependência na linha `dependencias`.

#### Desinstalação
```bash
./uninstall.sh            # Remove o executável, bibliotecas e o autocompletar (preserva credenciais)
./uninstall.sh --purge    # Remove executável, bibliotecas e credenciais locais
./install.sh --uninstall  # Equivalente pelo instalador; com --prefix <DIR>, remove dali
```

### 2. Autenticação Inicial (`config`)
O comando interativo orienta a vinculação OAuth2 segura:
```bash
dbx config

# Para diagnosticar o ambiente e investigar falhas de persistência em servidores ou containers:
dbx config --debug
# ou via variável de ambiente:
DBX_DEBUG=1 dbx config
```
- A ferramenta solicitará a sua **App Key** e **App Secret** da sua aplicação Dropbox.
- Abra o link gerado no navegador, autorize o aplicativo e cole o código de autorização fornecido.
- A credencial é persistida com permissões restritas (`0600`) em `~/.config/dbx/credencial.json` (ou no caminho customizado por `$XDG_CONFIG_HOME`).

#### Diagnóstico e Solução de Problemas em Ambientes Restritos (Root / Containers)
Em ambientes de produção, containers Docker/Kubernetes ou quando executado como `root`, certas condições do sistema podem impedir a gravação da credencial:
- **Sistema de arquivos somente-leitura (`read-only`):** Em containers com `readOnlyRootFilesystem: true`, o diretório raiz `/root` não permite criação de arquivos.
- **Permissões ou volumes compartilhados (ex.: NFS `root_squash`):** Restrições na criação de arquivos com permissões `0600` ou no renomeio atômico de temporários.
- **Diagnóstico com `--debug`:** Ao invocar `dbx config --debug` (ou com `DBX_DEBUG=1`), a ferramenta emite em `stderr` um relatório completo do ambiente operacional:
  - Processo (`PID`, `UID`, `EUID`, `USER`) e variáveis (`HOME`, `XDG_CONFIG_HOME`).
  - Estado e permissões dos diretórios e arquivos alvo (`stat`).
  - Teste efetivo de escrita no diretório base.
  - Espaço em disco e inodes livres (`df -h`, `df -i`).
  - Pontos de montagem relevantes (`mount`) e atributos de sistema de arquivos (`lsattr`).
  - Mensagem de erro exata emitida pelo sistema operacional caso `mktemp` ou a movimentação falhe.
  - **Segurança estrita:** Segredos, chaves de aplicação e tokens de autorização **nunca** são emitidos na saída nem nos registros de diagnóstico.
- **Redefinição do diretório de configuração:** Caso o `$HOME` padrão não seja gravável, aponte `XDG_CONFIG_HOME` para uma área gravável:
  ```bash
  export XDG_CONFIG_HOME="/caminho/gravavel/config"
  dbx config --debug
  ```
- **Atenção ao Código de Autorização:** O código OAuth2 gerado no navegador expira rapidamente e **serve apenas uma única vez**. Se a autorização na rede foi concluída com sucesso mas a gravação local falhou, o código já foi consumido pelo Dropbox. Para tentar novamente, abra novamente a URL informada para obter um código novo.

Opções do `config` (o alias em inglês tem o mesmo efeito): `--substituir` / `--replace` troca uma credencial existente (o refresh token anterior **não** é revogado; prefira `dbx unlink` antes); `--raiz` / `--root <caminho>` define a raiz remota gravada na credencial (padrão `/`).

Para desvincular a conta e revogar o token:
```bash
dbx unlink --confirmar          # ou: dbx unlink --yes
dbx unlink --yes --keep-app     # preserva app key e app secret (--manter-aplicativo)
```

Com `sync` ou `verificar` em curso neste host, o `unlink` recusa com código `7` sem apagar nada. Trava órfã, ilegível ou de outro host não é apagada: o resto do estado sai e cada trava mantida gera um aviso em `stderr`.

---

## Guia de Comandos

### Opções Globais
As opções globais podem ser informadas antes do comando (ou nos comandos operacionais específicos):
```bash
dbx [--json] [--null] [--dry-run] [--progresso] [--sem-progresso] [--debug] <comando> [argumentos]
```
- `--debug`: Ativa o modo de depuração operacional com diagnóstico de ambiente e erro detalhado do sistema operacional em `stderr` (equivalente à variável `DBX_DEBUG=1`). Preserva integralmente a confidencialidade de tokens e credenciais.
- `--progresso`, `--progress`, `-p`: Ativa explicitamente a exibição de progresso em tempo real em `stderr` (útil para scripts e visualização interativa). Durante a análise dos arquivos, lista cada arquivo e o resultado detalhado da análise (resumo reaproveitado do cache em memória (`lib/state`), hash calculado, idêntico/dispensado, modificado, novo ou ausente na origem).
- `--sem-progresso`, `--no-progress`: Desativa explicitamente a exibição de progresso (modo silencioso forçado mesmo em terminais interativos).
- `--json`: Formata a saída padrão em objetos JSON estruturados.
- `--null`: Utiliza o terminador `\0` (compatível com `xargs -0`).
- `--dry-run`: Simula a execução sem alterar o estado local ou remoto.
- `--help`: Exibe a ajuda geral ou específica de comandos.
- `--version`: Exibe a versão instalada.

### Variáveis de Ambiente de Rede (Timeouts e Retentativa)
Toda requisição tem tempo limite e falhas transitórias são repetidas com recuo exponencial. Os padrões podem ser ajustados por variável de ambiente; o valor precisa ser um inteiro positivo, sem zero à esquerda. Valor inválido (vazio, não numérico, zero ou negativo) é recusado como uso inválido (código de saída `2`) antes de qualquer chamada de rede.

| Variável | Padrão | Efeito |
|---|---|---|
| `DBX_HTTP_CONNECT_TIMEOUT_S` | `15` | Tempo máximo, em segundos, para estabelecer a conexão |
| `DBX_HTTP_VELOCIDADE_MINIMA_BPS` | `1024` | Velocidade mínima, em bytes por segundo, abaixo da qual a transferência é cortada... |
| `DBX_HTTP_VELOCIDADE_JANELA_S` | `60` | ...se durar esta janela, em segundos |
| `DBX_HTTP_TENTATIVAS_MAXIMAS` | `5` | Tentativas por requisição ou parte de envio, contando a primeira |
| `DBX_HTTP_ESPERA_BASE_MS` | `1000` | Base do recuo: a espera n é `base × 2^(n-1)` mais variação aleatória de até `base` |
| `DBX_HTTP_ESPERA_TETO_MS` | `60000` | Teto de cada espera do recuo |
| `DBX_HTTP_RETRY_AFTER_TETO_S` | `300` | Teto do `Retry-After` informado pelo servidor, que prevalece sobre o recuo quando presente (só em segundos inteiros; formato de data cai no recuo) |

Timeout conta como falha transitória de rede e só é repetido em operação idempotente. No envio em partes, cada retomada por deslocamento incorreto (`incorrect_offset`) consome uma das tentativas.

```bash
# Rede lenta: mais tempo para conectar e mais tentativas
DBX_HTTP_CONNECT_TIMEOUT_S=30 DBX_HTTP_TENTATIVAS_MAXIMAS=8 dbx upload backup.tgz /backups/backup.tgz
```

---

### 1. `upload` — Envio de Arquivos e Pastas
Envia arquivos locais, pastas completas ou fluxos da entrada padrão para o Dropbox:

```bash
# Upload de arquivo local com progresso em tempo real (-p)
dbx upload -p ./relatorio.pdf /documentos/relatorio.pdf

# Upload de pasta inteira recursivamente
dbx upload -p /mnt/h/Bkps/PeOuro /PeOuro

# Upload dispensado automaticamente se o arquivo local estiver inalterado
dbx upload ./relatorio.pdf /documentos/relatorio.pdf

# Forçar envio mesmo se inalterado (pula também a checagem de espaço livre)
dbx upload --forcar ./relatorio.pdf /documentos/relatorio.pdf

# Upload forçando sobrescrita remota
dbx upload --modo overwrite ./backup.sql /backups/backup.sql

# Upload de fluxo via stdin (-)
tar czf - /dados | dbx upload - /backups/dados.tar.gz
```

> **Importante para Streaming (`RSK-36`):** Ao encadear comandos em pipes (`tar ... | dbx upload - ...`), ative **`set -o pipefail`** no seu shell para garantir que falhas no processo produtor sejam capturadas pelo encadeamento.

> **Espaço livre (`RF-67`):** antes de enviar, o `upload` consulta uma vez o espaço da conta (`users/get_space_usage`). Se o arquivo não cabe na folga (alocado menos usado; em conta de equipe, a menor folga entre equipe e membro), o envio é **recusado com código `12`, sem escrever nada**, e a mensagem traz o necessário, o livre e a diferença. `--forcar` (`--force`) pula a checagem; com `--dry-run` o resultado só anuncia `recusaria=...`; a entrada padrão (`-`) não é checada; e falha na consulta (ou alocação desconhecida) só gera um aviso em `stderr`. A saída estruturada ganha `espaco_necessario`, `espaco_livre` e `espaco_verificado` (`sim`, `nao` ou `pulado`).

---

### 2. `download` — Recebimento de Arquivos e Pastas
Baixa um arquivo individual ou uma pasta remota inteira para o disco local ou para a saída padrão (`stdout`):

```bash
# Download de arquivo individual com acompanhamento de progresso (-p)
dbx download -p /documentos/relatorio.pdf ./relatorio.pdf

# Download de pasta remota inteira recursivamente (cria a pasta de destino automaticamente)
dbx download -p /PeOuro /mnt/h/Bkps/

# Download para stdout e descompactação em pipe (progresso emitido em stderr sem corromper o fluxo binário)
dbx download -p /backups/dados.tar.gz - | tar xzf - -C /restauracao/
```

---

### 3. `sync` — Sincronização Direcional
Sincroniza uma pasta local com uma pasta remota. A origem é a autoridade absoluta:

```bash
# Enviar alterações locais com progresso etapa a etapa [X/N]
dbx sync -p --enviar --origem /meus_dados --destino /pasta_remota

# Receber alterações remotas para o diretório local (cria destino se inexistente)
dbx sync -p --receber --origem /pasta_remota --destino /meus_dados

# Sincronização com espelhamento (exclui no destino itens ausentes na origem)
dbx sync -p --enviar --origem /dados --destino /backup --espelhar

# Os mesmos comandos com os nomes em inglês (estilo rsync/git), que podem ser misturados aos em português
dbx sync -p --push --source /dados --dest /backup --mirror
dbx sync --pull --origem /pasta_remota --dest /meus_dados
```

Cada opção do `sync` tem um nome em português e um alias em inglês, com o mesmo efeito e as mesmas recusas:

| Português | Inglês | Efeito |
|---|---|---|
| `--origem <dir>` | `--source <dir>` | Lado que manda (obrigatório) |
| `--destino <dir>` | `--dest <dir>` | Lado que recebe (obrigatório) |
| `--enviar` | `--push` | Origem local, destino remoto |
| `--receber` | `--pull` | Origem remota, destino local |
| `--espelhar` | `--mirror` | Apaga no destino o que não existe na origem |
| `--confirmar` | `--yes` | Reconhece a primeira execução com espelhamento |
| `--permitir-origem-vazia` | `--allow-empty-source` | Permite espelhar uma origem vazia |
| `--forcar` | `--force` | Só com `--enviar`: pula a checagem de espaço livre (com `--receber` é uso inválido, código `2`) |
| `--esperar <s>` | `--wait <s>` | Espera até `<s>` segundos (inteiro de `0` a `3600`) pela trava do par; inválido sai com `2` |

No `--enviar`, a soma dos arquivos a transferir (omitidos e exclusões não contam; sobrescrita conta o arquivo novo inteiro) é conferida com o espaço livre da conta numa única consulta: se não cabe, o plano sai e a execução é recusada com código `12` **antes de qualquer escrita**, inclusive das exclusões do `--espelhar` e da gravação da memória. Com `--dry-run`, o plano só anuncia `recusaria=...`. O `--forcar` não muda a decisão por `content_hash`: arquivo idêntico continua omitido.

Repetir uma opção, ainda que pelos dois nomes, segue a mesma regra: opção com valor vale o último valor dado (`--origem a --source b` usa `b`); opção sem valor é idempotente; um segundo sentido (`--enviar --push`, `--push --pull`) é recusado como uso inválido.

> **Origem vazia com `--espelhar`:** se a origem está vazia (`--enviar`: a raiz local não tem nenhum arquivo; `--receber`: a listagem remota está vazia) e há algo a apagar no destino, a execução é **recusada inteira, antes de qualquer escrita**, haja ou não memória do par — é o caso de uma montagem que não subiu. Nos dois sentidos o plano sai antes, com `recusada=origem vazia`, e o código de saída é `14`. Só `--permitir-origem-vazia` (`--allow-empty-source`) libera; `--confirmar` (`--yes`) não basta. Com `--dry-run`, o plano anuncia `recusaria=origem vazia`, não lista exclusões e sai com `0`. Origem vazia sem nada a apagar no destino, ou sem `--espelhar`, é uma operação vazia que sai com `0`; uma raiz local inexistente continua recusada.
>
> **Primeira execução com `--espelhar`:** sobre um par de raízes ainda não visto, o `sync` exige `--dry-run` antes ou `--confirmar`. **Se a identificação da conta falhar** (`users/get_current_account`), o `sync` segue sem memória auxiliar e, com `--espelhar`, as **exclusões ficam desabilitadas naquela execução**, nos dois sentidos: envios e recebimentos acontecem, o motivo sai no relatório (`exclusao_desabilitada=conta nao identificada` na saída estruturada) e o código de saída é diferente de `0`. O `--confirmar` **não** reabilita as exclusões — sem a memória não há linha de base, e uma origem que ficou parcial por engano apagaria o que faltou nela.
>
> **Trava de concorrência:** só um `sync` ou `verificar` por vez para o mesmo par — a conta, a raiz local e a raiz remota (sem caixa), **em qualquer sentido**: `--enviar A B` e `--receber B A` se excluem. Pares diferentes rodam juntos, e os outros comandos não travam. A trava vale também com `--dry-run` e é adquirida antes de qualquer chamada à API, escrita ou leitura da memória. Ocupada, a execução é **recusada na hora com código `7`**, dizendo o pid, o host, o início (UTC) e o comando de quem a tem; com `--esperar N` (`--wait N`) ela tenta a cada segundo por até `N` segundos e, esgotado o tempo, recusa dizendo quanto esperou. Fica em `${XDG_STATE_HOME:-~/.local/state}/dbx/trava-<resumo>` (`0600`) e sai em todo término, inclusive por `INT`, `TERM` e `HUP` (código `14`). Trava de processo que morreu **neste host** (ou de antes de um reinício) é retomada com aviso; de **outro host** ou **ilegível**, nunca: o `dbx diagnostico` a mostra com o remédio (`rm` do arquivo, depois de confirmar que nada está em curso). Com o diretório de estado de outro usuário, a execução segue sem trava, com aviso. Num diretório de estado em **NFS**, a exclusão entre máquinas é **melhor esforço**; prefira um `XDG_STATE_HOME` local.
>
> **Caixa e localidade:** a Dropbox não diferencia caixa, e o `sync` também não: `Foto.JPG` e `foto.jpg` são o mesmo arquivo. Para letras acentuadas (`É`/`é`), a comparação usa a localidade `C.UTF-8`, fixada só dentro dela, mesmo com `LC_ALL=C` no ambiente. Se a localidade não existir no sistema, a comparação vale só no ASCII e o `sync` avisa uma vez em `stderr`, sem recusar a execução.

---

### 4. `list` — Listagem de Conteúdo
Lista arquivos e pastas remotas com paginação automática:

```bash
# Listagem padrão
dbx list /documentos

# Listagem recursiva limitada
dbx list --recursivo --limite 100 /documentos

# Listagem estruturada em JSON
dbx --json list /documentos

# Listagem delimitada por byte nulo para scripts
dbx --null list /documentos
```

---

### 5. `delete` — Exclusão de Itens
Remove arquivos ou pastas no Dropbox com proteção contra exclusões acidentais:

```bash
# Exclusão com confirmação explícita (--confirmar ou --yes)
dbx delete --confirmar /documentos/antigo.pdf

# Exclusão condicionada à revisão específica (proteção contra conflito)
dbx delete --confirmar --rev 5a9b8c7d /documentos/versao.pdf
```

---

### 6. `info` — Metadados de Itens
Exibe detalhes de metadados de arquivos ou pastas:

```bash
dbx info /documentos/relatorio.pdf
```

---

### 7. `space` — Consulta de Cota e Espaço
Verifica o uso e a capacidade total de armazenamento da conta:

```bash
# Exibição em bytes
dbx space

# Exibição legível para humanos (--humano ou -H)
dbx space --humano
```

---

### 8. `verificar` (`verify`) — Auditoria sem Transferência
Compara a árvore local e a remota por `content_hash`, com os mesmos papéis e sentido do `sync` (`--origem`/`--source`, `--destino`/`--dest`, `--enviar`/`--push`, `--receber`/`--pull`), sem transferir nem gravar nada — nem a memória de `~/.local/state/dbx/`:

```bash
dbx verificar --enviar --origem /dados --destino /backup
dbx verify --pull --source /backup --dest /dados
```

Cada arquivo sai uma vez como `igual`, `diferente` (com `motivo=conteudo` ou `motivo=tipo`, quando é arquivo de um lado e pasta do outro), `so_origem` ou `so_destino`, na ordem do caminho sem caixa, com as contagens `iguais`, `diferentes`, `so_origem`, `so_destino` e `total` ao fim. Código de saída: `0` só quando tudo é igual; `11` quando há divergência (mensagem própria, nada foi transferido); `14` com travessia local parcial; erro de execução (rede `9`, autenticação `5`, limite de taxa `8`, ...) prevalece. `--espelhar`, `--confirmar`, `--permitir-origem-vazia` e `--forcar` (e os aliases) são recusados com `2`. O `verificar` trava o par como o `sync` (código `7` se ocupada) e aceita `--esperar`/`--wait`; o arquivo de trava é a única escrita, e o diretório de estado termina exatamente como estava.

---

### 9. `diagnostico` (`doctor`) — Checagem do Ambiente
Checa, sem parar no primeiro item e sem passar pela verificação prévia, oito pontos: `dependencias`, `credencial`, `conectividade` (`check/user`), `escopos`, `espaco`, `localidade`, `estado` e `trava` (uma linha por trava de `sync`/`verificar`: `viva`, `orfa`, `outro-host` ou `ilegivel`, com o remédio; trava nunca reprova, e diretório de estado em NFS gera aviso). Cada checagem sai numa linha, com `ok`, `aviso` ou `falha`, a mensagem e o remédio sugerido:

```bash
dbx diagnostico
dbx --json doctor
```

Os escopos exigidos são `account_info.read`, `files.metadata.read`, `files.content.read` e `files.content.write`; se a resposta de renovação do token não os informar, a checagem é `aviso`. O comando nunca imprime segredo (a credencial é conferida por nome de campo), não cria nem corrige nada e só chama a renovação do token, `check/user` e `get_space_usage`. Código de saída: `0` sem falha (aviso não reprova) e `3` com ao menos uma falha.

---

### 10. `completar` (`completion`) — Autocompletar do Bash
O `install.sh` instala o autocompletar em `~/.local/share/bash-completion/completions/dbx` (sem `sudo` e sem alterar o `.bashrc`; com `--prefix <DIR>`, em `<DIR>/share/bash-completion/completions/dbx`). Ele completa comandos, aliases, opções de cada comando em português e inglês e caminhos **locais**; não usa rede nem credencial. Para ativar na sessão corrente:

```bash
source <(dbx completar bash)
```

---

### 11. Recuperação: `revisoes` (`revisions`), `restaurar` (`restore`) e `lixeira` (`trash`)
Os três comandos não usam a memória de `~/.local/state/dbx/`, não travam e confinam todo caminho à raiz remota antes de qualquer chamada (código `13`).

**Revisões de um arquivo**, da mais recente para a mais antiga, com os campos de `info` e, ao fim, `apagado`, `apagado_em`, `mais` e `total` (só leitura; arquivo apagado também é listado):

```bash
dbx revisoes /docs/relatorio.txt
dbx revisions --limit 50 --by-id /docs/relatorio.txt   # --limite de 1 a 100 (padrão 10); --por-id segue movimentos
```

**Restauração de arquivo**, por `--rev` (o `rev` precisa constar do histórico do próprio arquivo; senão `4`) ou `--antes-de`/`--before` (`AAAA-MM-DD`, fim do dia UTC, ou `AAAA-MM-DDTHH:MM:SSZ`). Arquivo apagado sem seleção volta na última revisão; arquivo vivo exige uma das duas. Restaurar sobre arquivo existente é direto: a versão atual vira revisão anterior, e a saída traz `rev_substituida` e `para_desfazer` com o comando que desfaz (`dbx restaurar <caminho> --rev <rev_substituida>`). `--dry-run` só lê.

```bash
dbx restaurar --antes-de 2026-10-01 /docs/relatorio.txt
dbx restore --rev 0123456789abcdef /docs/relatorio.txt
```

**Restauração de pasta apagada**: tudo o que está apagado sob ela volta, arquivo por arquivo, na última revisão; item vivo não é tocado. Cada item sai com `rev`, `apagado_em` e `resultado`, e o resumo traz `restaurados`, `falhas`, `sem_revisao` e `total`. Falha de item ou listagem parcial sai com `14` e diz o que faltou; rodar de novo restaura só o que ainda está apagado. Pasta apagada vazia não é recriada.

```bash
dbx --dry-run restaurar /docs/pasta-apagada
dbx restaurar /docs/pasta-apagada
```

**Lixeira**: lista os itens apagados da pasta (padrão: a raiz remota) com `name`, `path_display` e `restauravel`; a API não informa tipo nem data de exclusão, e a saída não os inventa. `-R` desce nas subpastas vivas.

```bash
dbx lixeira -R /docs
```

**Exclusão permanente** (`--excluir`, alias `--purge`): **irreversível** e só existe em contas **Dropbox Business**. Exige o escopo opcional `files.permanent_delete`: habilite-o no **App Console** do aplicativo e reautorize com `dbx unlink` seguido de `dbx config`. Só item já apagado é aceito (apague antes com `dbx delete`; a checagem é feita na API), e nem a raiz da conta nem a raiz remota podem ser alvo. Com terminal, o operador digita o caminho para confirmar; sem terminal, `--confirmar-caminho` precisa repetir o alvo. Não há `--yes`. Conta pessoal sai com `6` (use `dbx delete`: o item fica na lixeira pelo prazo da conta); escopo ausente sai com `5`. O `dbx diagnostico` mostra o escopo opcional na linha `escopos`, sem reprovar.

```bash
dbx lixeira --excluir /docs/velho.txt --confirmar-caminho /docs/velho.txt
```

A tabela de códigos de saída não muda: os três comandos usam só os códigos já existentes.

> O `--excluir` da `lixeira` é o **expurgo definitivo**, e não o filtro `--excluir` de `sync`, `verificar` e `download` descrito abaixo; a `lixeira` não aceita filtros.

---

## Filtros

`--excluir PADRAO` (`--exclude`) e `--incluir PADRAO` (`--include`) valem em `sync` (os dois sentidos, com ou sem `--espelhar` e `--dry-run`), `verificar` e `download` de **pasta**. São **repetíveis** e acumulam; a ordem na linha de comando não importa. Com um arquivo remoto, o `download` com filtro sai com `2` sem escrever nada. É também por `sync --enviar --excluir` que se faz o envio recursivo com padrões de exclusão (RF-12).

```bash
dbx sync --enviar --origem ./projeto --destino /backup/projeto --excluir '*.tmp' --excluir 'node_modules/'
dbx sync --receber --origem /fotos --destino ./fotos --incluir '*.jpg' --modificado-desde 2026-10-01
dbx verificar --enviar --origem ./projeto --destino /backup/projeto --excluir 'build/'
dbx download /docs ./docs --exclude '*.bak'
```

Sintaxe do `.gitignore`, comparada **sem caixa** (como o `sync`) com o caminho relativo à raiz, nos dois lados:

| Padrão | Casa |
|---|---|
| `*.log` (sem `/`) | o nome em qualquer nível: `a.log`, `x/y/a.log` |
| `/build`, `doc/a.txt` (`/` no início ou no meio) | ancorado na raiz: só `build`, só `doc/a.txt` |
| `logs/` (`/` no fim) | só a **pasta** `logs`, em qualquer nível, e tudo abaixo dela |
| `*`, `?`, `[a-c]`, `[!0-9]` | `*` e `?` nunca cruzam `/`; conjunto com faixa e negação por `!` ou `^` |
| `**/tmp`, `build/**`, `a/**/b` | `**` cruza pastas no início, no fim (descendentes, não a pasta) e no meio |
| `\*`, `\[`, `\!`, `\ ` | `\` torna literal o caractere seguinte |

**Exclusão vence inclusão**: `--incluir '*.pdf' --excluir 'velho/'` deixa `velho/a.pdf` de fora. Com algum `--incluir`, só o que casa entra (as pastas são percorridas para achar o arquivo incluído em qualquer nível; pasta sem arquivo no escopo não é criada). Pasta excluída **não é percorrida**: erro dentro dela não torna a travessia parcial.

**Desvios do gitignore:** sem negação `!` (recusada com `2`: use `--incluir`); `#` inicial e espaços finais são literais; `[` sem `]`, `[]`, faixa invertida e classe `[[:alpha:]]` são malformados. Até 64 padrões de até 1024 bytes. Padrão malformado sai com `2` antes da trava, da rede e de qualquer escrita. Padrão que não casou nada e origem toda filtrada geram aviso em stderr.

**Com `--espelhar`, item filtrado nunca é apagado**, nem no remoto nem no local: fica fora do escopo dos dois lados. Um filtro novo não apaga o que deixou de fora; **remover um filtro devolve os itens ao escopo**, e eles voltam a seguir a regra normal, inclusive a exclusão do espelhamento. Origem com arquivos todos filtrados conta como **origem vazia** e cai na recusa de `--permitir-origem-vazia`.

> **Sem normalização Unicode:** a comparação não normaliza NFC e NFD. `é` composto (NFC) e `e` + acento combinante (NFD) são grafias distintas, então `--excluir 'café'` (NFC) **não** protege um `café` local gravado em NFD: ele fica no escopo e, com `--espelhar`, pode ser apagado. Escreva o padrão na mesma forma do nome ou use curinga (`caf*`).

> **Atenção:** um backup com filtro é parcial — o que ficou de fora não está no destino.

**Data e tamanho** (`sync` e `download` de pasta): `--modificado-desde`/`--modified-since` e `--modificado-ate`/`--modified-until` (`AAAA-MM-DD` ou `AAAA-MM-DDTHH:MM:SSZ`, UTC, inclusivos; local pelo `mtime`, remoto pelo `server_modified`), `--tamanho-min`/`--min-size` e `--tamanho-max`/`--max-size` (bytes ou `K`, `M`, `G` em base 1024, inclusivos). Avaliam **só a origem** e são **recusados com `--espelhar`** (`2`), porque fariam o espelhamento apagar no destino. O `verificar` também os recusa.

O plano (inclusive no `--dry-run`) e o resumo trazem `filtros=sim|nao`, os padrões ativos e `filtrados_origem`/`filtrados_destino` (pasta excluída conta `1`), como acréscimo compatível da saída.

## Limite de banda

`--limite-banda TAXA` (alias `--bwlimit`) em `upload`, `download` e `sync`, em **bytes/s** (número sem sufixo é bytes/s, não KiB/s como no `rsync`), com sufixo `K`, `M` ou `G` em base 1024. O limite vale **por transferência**, só nas requisições de conteúdo (envio, partes de sessão, recebimento), e não nas de metadado; duas execuções simultâneas somam.

```bash
dbx upload --limite-banda 512K backup.tar.gz /backups/backup.tar.gz
export DBX_LIMITE_BANDA=2M   # padrão quando a opção não é dada
env -u DBX_LIMITE_BANDA dbx sync --enviar --origem ./a --destino /a   # sem o padrão numa chamada
```

O piso é **2 × `DBX_HTTP_VELOCIDADE_MINIMA_BPS`** (2048 bytes/s no padrão): abaixo dele o corte por velocidade mínima abortaria a transferência, e o valor é recusado com `2`. A variável `DBX_LIMITE_BANDA` vale quando a opção está ausente; a opção vence. Variável presente e inválida (inclusive vazia) sai com `2` em `upload`, `download` e `sync` sem a opção; os demais comandos a ignoram. O resultado (bytes, `content_hash`, código) não muda; a saída ganha `limite_banda` (vazio sem limite).

## Compartilhamento

Dois comandos expõem arquivo ou pasta para fora da conta. Os dois recusam caminho fora da `raiz_remota` (`13`) antes de qualquer chamada, não gravam nada em `lib/state` e não usam trava.

**`dbx link-temporario <arquivo>`** (alias `temp-link`): URL direta de download (`files/get_temporary_link`). **O link temporário vale 4 horas, não pode ser revogado e dá acesso a quem o tiver.** Só arquivo (pasta sai com `2`). A saída traz `link`, `validade_segundos=14400` e `expira_em_estimado` (relógio local mais 4 h, em UTC: o serviço não informa a hora exata). Com `--dry-run` o link **não** é gerado. Usa o escopo `files.content.read`, já exigido.

```bash
dbx link-temporario /docs/relatorio.pdf
```

**`dbx compartilhar <caminho>`** (alias `share`): link compartilhado, com a visibilidade **sempre explícita** — **nada é publicado por omissão**: sem `--publico`, `--equipe` ou `--senha`, o comando sai com `2`.

| Opção | Quem acessa | Pedido à API |
|---|---|---|
| `--publico` (`--public`) | qualquer pessoa com o link | `audience public`, sem senha |
| `--equipe` (`--team`) | só membros da equipe | `audience team`, sem senha |
| `--senha` (`--password`) / `--senha-stdin` (`--password-stdin`) | quem tiver o link **e** a senha | `audience public` + `require_password` |

> **Atenção:** com `--publico`, qualquer pessoa que receba o link acessa o item, sem login. Prefira `--equipe` ou `--senha` quando possível, e `--expira` para limitar o tempo.

- **Senha:** nunca na linha de comando nem em variável de ambiente. `--senha` pergunta no terminal, sem eco, duas vezes (diferentes: `14`, nada feito); `--senha-stdin` lê a primeira linha da entrada (`pass show dbx/link | dbx compartilhar --senha-stdin /docs`). Senha vazia, com caractere de controle (inclusive o `\r` de fim de linha CRLF), acima de 1024 bytes ou fora do UTF-8 é recusada com `2`. A senha só vai no corpo da requisição, por arquivo temporário `0700` removido no fim e em sinal, e nunca aparece em saída, erro ou `--debug`.
- **`--expira`** (`--expires`): `AAAA-MM-DD` (fim do dia UTC), `AAAA-MM-DDTHH:MM:SSZ` ou duração `<N>h` (1 a 8760) / `<N>d` (1 a 3650), ao menos 60 s no futuro.
- **Link existente:** igual ao pedido, é devolvido sem escrita (`situacao=existente`); diferente, é modificado (`situacao=modificado`) com `antes_*` e `depois_*`. Com senha pedida a senha é sempre redefinida; exposição ampliada gera aviso em `stderr`. Mais de um link para o mesmo item sai com `7` e as URLs.
- **`--listar [pasta]`** (`--list`): os links dentro da pasta (padrão: a `raiz_remota`), confinados pelo `path_lower` que o serviço devolve; o que está fora da raiz ou fora da sua Dropbox é omitido (`omitidos`).
- **`dbx compartilhar --revogar <url>`** (`--revoke`): **revogação confinada** — só revoga link cujo `path_lower`, lido do próprio link na mesma execução, está dentro da `raiz_remota`; ausente ou fora sai com `13` sem revogar, inclusive com a raiz `/`. Não pede confirmação (revogar reduz a exposição e o link pode ser recriado). Link temporário não é revogável.

```bash
dbx compartilhar --equipe --expira 7d /docs/relatorio.pdf
dbx compartilhar --listar /docs
dbx compartilhar --revogar 'https://www.dropbox.com/scl/fi/...'
```

**Escopos e plano.** Criar, modificar e revogar exigem o escopo opcional `sharing.write`; listar, reusar link existente e revogar exigem `sharing.read`. Sem eles o comando sai com `5` nomeando o escopo: habilite-o no **App Console** do aplicativo e reautorize com `dbx unlink` seguido de `dbx config`. O `dbx diagnostico` mostra os dois na linha `escopos`, sem reprovar. **Senha, equipe e expiração dependem do plano da conta:** no plano Basic só há link público, sem senha e sem expiração, e o pedido sai com `6`.

---

## Testes e Qualidade

O projeto conta com uma suíte abrangente de testes automatizados com saída **TAP 13**, cobrindo cenários unitários e de integração com dublês de rede e auditorias adversariais:

```bash
# Executar a bateria completa de testes (para no primeiro erro)
bash tests/run.sh < /dev/null

# Executar análise estática (linter)
shellcheck lib/*.sh commands/*.sh bin/* scripts/*.sh

# Executar bateria bats dos utilitários
npx --yes bats@1.13.0 scripts/tests/
```

---

## Licença

Este projeto é licenciado sob a **Licença MIT** — consulte o arquivo [LICENSE](LICENSE) para mais detalhes.

Copyright (c) 2026 Adriano Sales Santos.
