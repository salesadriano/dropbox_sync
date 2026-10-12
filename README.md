# dropbox_sync (`dbx`)

[![Licença MIT](https://img.shields.io/badge/licença-MIT-blue.svg)](LICENSE)
[![ShellCheck](https://img.shields.io/badge/shellcheck-pass-brightgreen.svg)](#qualidade-e-conformidade)
[![Testes Automatizados](https://img.shields.io/badge/testes-591%20pass-brightgreen.svg)](#testes-e-qualidade)
[![Piso de Shell](https://img.shields.io/badge/bash-4.4%2B-informational.svg)](#requisitos)

**`dbx`** é uma ferramenta de linha de comando (CLI) determinística, segura e de alto desempenho para interação com a **Dropbox API v2** em ambientes Linux/POSIX.

Projetada com arquitetura modular e aderência estrita a contratos de rede e integridade, a ferramenta opera sem dependências externas além de `bash` e `cURL` — dispensando interpretadores de linguagens de alto nível e analisadores de JSON externos (`jq`).

---

## Principais Recursos

- **Zero Dependências Pesadas:** Funciona exclusivamente com `bash` 4.4+ e `cURL` padrão do sistema.
- **Suporte Transparente a Arquivos e Pastas:** `upload` e `download` operam nativamente tanto com arquivos individuais quanto com pastas inteiras recursivamente.
- **Cache Local Relacional SQLite (`lib/db.sh`):**
  - Mantém base SQLite em `~/.local/state/dbx/dbx.db` com metadados locais (`tamanho`, `mtime`, `content_hash`) e histórico de operações bem-sucedidas.
  - Dispensa automaticamente envios redundantes no `upload` quando o arquivo local permanece inalterado para o destino (`status=dispensado`, `motivo=inalterado`), economizando banda e tempo.
  - Suporte a re-envio forçado via `--forcar` / `--force`.
  - Motor resiliente híbrido: usa `sqlite3` CLI nativo com fallback automático e transparente para o módulo `sqlite3` do `python3`.
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
- **Rede:** `cURL` 7.68+ com suporte a HTTPS e TLS 1.2+.
- **Utilitários do Coreutils:** `sha256sum` (ou `shasum`), `head`, `tail`, `wc`, `cat`, `rm`, `mkdir`, `chmod`.

---

## Instalação e Configuração

### 1. Instalação no Linux (Recomendado)

#### Opção A: Instalação Rápida via cURL (One-liner)
Para instalar diretamente no espaço do usuário (`~/.local/bin/dbx` e `~/.local/share/dropbox_sync`):
```bash
curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/develop/install.sh | bash
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
Baixe o arquivo `dropbox_sync-1.1.0-linux.tar.gz` da aba de [Releases](https://github.com/salesadriano/dropbox_sync/releases):
```bash
tar -xzf dropbox_sync-1.1.0-linux.tar.gz
./install.sh
```

#### Desinstalação
```bash
./uninstall.sh            # Remove o executável e bibliotecas (preserva credenciais)
./uninstall.sh --purge    # Remove executável, bibliotecas e credenciais locais
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

Para desvincular a conta e revogar o token:
```bash
dbx unlink --confirmar
```

---

## Guia de Comandos

### Opções Globais
As opções globais podem ser informadas antes do comando (ou nos comandos operacionais específicos):
```bash
dbx [--json] [--null] [--dry-run] [--progresso] [--sem-progresso] [--debug] <comando> [argumentos]
```
- `--debug`: Ativa o modo de depuração operacional com diagnóstico de ambiente e erro detalhado do sistema operacional em `stderr` (equivalente à variável `DBX_DEBUG=1`). Preserva integralmente a confidencialidade de tokens e credenciais.
- `--progresso`, `--progress`, `-p`: Ativa explicitamente a exibição de progresso em tempo real em `stderr` (útil para scripts e visualização interativa). Durante a análise dos arquivos, lista cada arquivo e o resultado detalhado da análise (status de cache SQLite/memória, hash calculado, idêntico/dispensado, modificado, novo ou ausente na origem).
- `--sem-progresso`, `--no-progress`: Desativa explicitamente a exibição de progresso (modo silencioso forçado mesmo em terminais interativos).
- `--json`: Formata a saída padrão em objetos JSON estruturados.
- `--null`: Utiliza o terminador `\0` (compatível com `xargs -0`).
- `--dry-run`: Simula a execução sem alterar o estado local ou remoto.
- `--help`: Exibe a ajuda geral ou específica de comandos.
- `--version`: Exibe a versão instalada.

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

# Forçar envio mesmo se inalterado no banco local
dbx upload --forcar ./relatorio.pdf /documentos/relatorio.pdf

# Upload forçando sobrescrita remota
dbx upload --modo overwrite ./backup.sql /backups/backup.sql

# Upload de fluxo via stdin (-)
tar czf - /dados | dbx upload - /backups/dados.tar.gz
```

> **Importante para Streaming (`RSK-36`):** Ao encadear comandos em pipes (`tar ... | dbx upload - ...`), ative **`set -o pipefail`** no seu shell para garantir que falhas no processo produtor sejam capturadas pelo encadeamento.

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
```

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

## Testes e Qualidade

O projeto conta com uma suíte abrangente de testes automatizados com saída **TAP 13**, cobrindo cenários unitários e de integração com dublês de rede e auditorias adversariais:

```bash
# Executar a bateria completa de testes (591 casos aprovados)
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
