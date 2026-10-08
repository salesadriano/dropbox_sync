# Registro de Entrega — Pacote de Instalacao e Scripts para Linux (v1.1.0)

> Registro de entrega formal da demanda (Porte M) conforme regra 41 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Pacote de instalacao e scripts para instalacao no Linux |
| Data / Hora | 2026-10-08 17:48 |
| Domínio | Empacotamento / Distribuicao / Instalador Linux / Release v1.1.0 |
| Porte | **M (padrão)** — criacao de instalador, desinstalador, script de distribuicao e bump de versao para v1.1.0 |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `develop` |
| Branch principal | `develop` / `master` |
| Log de prompt | [2026-10-08_1748_pacote-instalacao-linux.md](../prompts/2026-10-08_1748_pacote-instalacao-linux.md) |

---

## Contexto e Modificações

Para simplificar a adoção e utilização do `dbx` em ambientes Linux/POSIX:
1. **Instalador Oficial (`install.sh`):**
   - Suporta instalação sem privilégios de superusuário (`--user`, padrão) em `~/.local/bin` e `~/.local/share/dropbox_sync`.
   - Suporta instalação em nível de sistema (`--system`) em `/usr/local/bin` e `/usr/local/share/dropbox_sync`.
   - Suporta prefixos customizados (`--prefix <DIR>`).
   - Suporta execução via pipe direto (`curl -fsSL ... | bash`).
   - Valida pré-requisitos: `bash 4.4+`, `curl`, coreutils essenciais, e alerta para recomendação do `sqlite3`.
   - Verifica se o diretório bin está no `$PATH` e fornece instruções textuais de configuração de shell.
2. **Desinstalador Oficial (`uninstall.sh`):**
   - Remove o executável e a pasta de bibliotecas de forma limpa.
   - Preserva por padrão os dados de configuração/credenciais (`~/.config/dropbox_sync/`), com opção `--purge` para exclusão completa.
3. **Resolução de Symlinks (`bin/dbx`):**
   - Atualizado para resolver links simbólicos recursivamente em `BASH_SOURCE[0]`, permitindo que o binário seja symlinkado para qualquer local do `$PATH` sem perder suas bibliotecas relativas.
4. **Gerador de Pacote de Distribuição (`scripts/empacotar.sh`):**
   - Produz `dist/dropbox_sync-1.1.0-linux.tar.gz` e `dist/dropbox_sync-1.1.0-linux.tar.gz.sha256`.
   - Executa teste de integridade descompactando e executando `--version` em sandbox isolada.
   - Suporta publicação automatizada via GitHub CLI (`--publicar`).
5. **Bump de Versão:**
   - Atualizada para `1.1.0` em `lib/cli.sh`.
6. **Documentação Oficial:**
   - Seção de instalação no `README.md` atualizada com o instalador do Linux.

---

## Escopo Técnico e Arquivos Modificados

| Arquivo | Natureza | Descrição |
|---|---|---|
| `install.sh` | Novo | Script oficial de instalação no Linux com verificação de pré-requisitos |
| `uninstall.sh` | Novo | Script oficial de desinstalação |
| `scripts/empacotar.sh` | Novo | Automação de geração de tarball `.tar.gz`, checksum SHA256 e teste de integridade |
| `bin/dbx` | Modificado | Resolução robusta de links simbólicos para detecção da raiz de instalação |
| `lib/cli.sh` | Modificado | Atualização da versão `DBX_CLI_VERSAO` para `1.1.0` |
| `.gitignore` | Modificado | Inclusão de `dist/` para ignorar tarballs locais gerados |
| `README.md` | Modificado | Instruções completas de instalação no Linux e desinstalação |
| `docs/prompts/2026-10-08_1748_pacote-instalacao-linux.md` | Novo | Log de prompt da demanda |
| `docs/reviews/2026-10-08-1748-registro-pacote-instalacao-linux.md` | Novo | Este registro formal de entrega |

---

## Validação e Evidências

- **Suíte de Testes TAP:** 586 casos aprovados em 20 arquivos TAP (0 falhas).
- **ShellCheck:** 0 apontamentos em todos os scripts modificados e novos (`install.sh`, `uninstall.sh`, `scripts/empacotar.sh`, `bin/dbx`).
- **Teste Funcional de Instalação e Desinstalação:** Validados com sucesso em sandbox temporária (`/tmp/dbx-test-install-dir`).
- **Pacote e Checksum:** Gerados e validados com sucesso em `dist/`.
