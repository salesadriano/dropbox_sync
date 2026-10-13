# Registro de Entrega — Release v1.2.0 e Roteiros de Instalação na Branch Master

> Registro de entrega formal da demanda (Porte M) conforme regra 41 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Geração e publicação de nova release (v1.2.0) e atualização de scripts e roteiros para a branch master |
| Data / Hora | 2026-10-13 15:12 |
| Domínio | Empacotamento / Distribuição / Roteiro de Instalação / Release v1.2.0 |
| Porte | **M (padrão)** — bumping de versão para v1.2.0, atualização de canal de distribuição para `master`, geração de pacote Linux e publicação de release oficial |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `develop` |
| Branch principal | `develop` / `master` |
| Log de prompt | [2026-10-13_1512_release-v120-master-instalacao.md](../prompts/2026-10-13_1512_release-v120-master-instalacao.md) |

---

## Contexto e Modificações

Com a estabilização e integração dos novos recursos na branch `develop` (feedback gráfico em tempo real para upload e download com precisão adaptativa, acompanhamento do andamento no comando `sync`, diagnóstico de integridade e persistência com `dbx config --debug` e compatibilidade BSD/UFS):

1. **Atualização dos Roteiros de Instalação para a Branch `master`:**
   - O instalador oficial `install.sh` teve seu canal padrão alterado de `develop` para `master` (`CANAL_PADRAO="master"`).
   - O comando de instalação rápida via cURL (one-liner) no cabeçalho do `install.sh`, no `README.md` e nas notas de release em `scripts/empacotar.sh` foi atualizado para consumir diretamente `https://raw.githubusercontent.com/salesadriano/dropbox_sync/master/install.sh`.
2. **Incremento de Versão (v1.2.0):**
   - Atualizada a constante `DBX_CLI_VERSAO='1.2.0'` em `lib/cli.sh`.
   - Atualizada a versão do instalador `VERSAO_INSTALADOR="1.2.0"` em `install.sh`.
   - Atualizadas referências do pacote tarball para `dropbox_sync-1.2.0-linux.tar.gz` no `README.md`.
3. **Atualização das Métricas de Qualidade no `README.md`:**
   - Contagem de testes atualizada para 608 casos aprovados em 20 arquivos TAP 13.
4. **Atualização do Script de Empacotamento (`scripts/empacotar.sh`):**
   - Atualizadas as notas de lançamento e título padrão para destacar as novas capacidades da v1.2.0.
   - Ajustada a URL de instalação rápida para a branch `master`.
5. **Geração e Publicação da Release:**
   - Empacotamento do tarball `dist/dropbox_sync-1.2.0-linux.tar.gz` e respectivo `sha256`.
   - Publicação da Release `v1.2.0` no GitHub via GitHub CLI (`gh release`).

---

## Escopo Técnico e Arquivos Modificados

| Arquivo | Natureza | Descrição |
|---|---|---|
| `lib/cli.sh` | Modificado | Bump de versão para `1.2.0` (`DBX_CLI_VERSAO`) |
| `install.sh` | Modificado | Atualização de canal padrão para `master` e versão para `1.2.0` |
| `scripts/empacotar.sh` | Modificado | Atualização de URL para `master` e notas da release v1.2.0 |
| `README.md` | Modificado | Atualização do one-liner para `master`, tarball v1.2.0 e contagem de testes (608) |
| `docs/prompts/2026-10-13_1512_release-v120-master-instalacao.md` | Novo | Log cronológico de prompt e decisões |
| `docs/reviews/2026-10-13-1512-registro-release-v120-master-instalacao.md` | Novo | Registro formal de entrega |

---

## Validação e Evidências

- **Suíte de Testes TAP 13:** 608 casos aprovados (0 falhas) em 20 suítes executadas.
- **ShellCheck:** 0 apontamentos em todos os scripts modificados e novos (`install.sh`, `scripts/empacotar.sh`, `lib/cli.sh`).
- **Geração do Pacote:** `dist/dropbox_sync-1.2.0-linux.tar.gz` gerado com teste de integridade aprovado (`dbx 1.2.0`).
- **Instalador:** `install.sh --version` e `install.sh --help` validados com sucesso exibindo versão 1.2.0 e canal padrão `master`.
