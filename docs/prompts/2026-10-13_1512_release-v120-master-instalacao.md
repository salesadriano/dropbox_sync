# Log de Prompt — Release v1.2.0 e Roteiros de Instalação na Branch Master

> Registro cronológico integral de prompts e decisões da demanda conforme regra 42 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Geração e publicação de nova release (v1.2.0) e atualização de scripts e roteiros para a branch master (`gere e publique a uma nova release e atualize as scripts e roteiros de instalação para usar a branch master`) |
| Data / Hora de início | 2026-10-13 15:12 |
| Porte | **M (padrão)** — bumping de versão para v1.2.0, atualização de URLs e branch padrão nos scripts de instalação (`install.sh`, `scripts/empacotar.sh`) e documentação (`README.md`), publicação de release e artefatos |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `develop` |
| Branch principal | `develop` (desenvolvimento) / `master` (produção/releases) |

---

## Prompt 1 (Entrada do Operador)

```
gere e publique a uma nova release e atualize as scripts e roteiros de instalação para usar a branch master
```

### Análise do Tech Lead

1. **Objetivo:**
   - Atualizar todos os scripts e roteiros de instalação (`install.sh`, `scripts/empacotar.sh`, `README.md`) para apontar para a branch estável `master` em vez de `develop`.
   - Incrementar versão do projeto para `1.2.0` (`DBX_CLI_VERSAO` em `lib/cli.sh` e `VERSAO_INSTALADOR` em `install.sh`).
   - Atualizar a contagem de testes no `README.md` (608 casos aprovados).
   - Gerar pacote de distribuição `dropbox_sync-1.2.0-linux.tar.gz` e checksum `sha256`.
   - Sincronizar e mesclar as alterações em `master`.
   - Criar tag `v1.2.0` e publicar a Release oficial no GitHub com notas detalhadas e artefatos.
2. **Componentes Modificados:**
   - `lib/cli.sh`: bump para versão `1.2.0`.
   - `install.sh`: canal padrão ajustado para `master` (`CANAL_PADRAO="master"`), versão `1.2.0`, documentação no cabeçalho e ajuda.
   - `scripts/empacotar.sh`: URL do instalador atualizada para `master`, notas de release da v1.2.0 atualizadas com novas funcionalidades (feedback gráfico, barra de progresso, percentuais adaptativos, diagnóstico `--debug`, compatibilidade BSD/UFS).
   - `README.md`: one-liner de instalação apontando para `master`, nome do arquivo de release atualizado para `1.2.0`, contagem de testes atualizada para 608.
   - `docs/reviews/2026-10-13-1512-registro-release-v120-master-instalacao.md`: registro formal de entrega.
3. **Critérios de Aceite:**
   - Suíte de 608 testes TAP 13 aprovada com 0 falhas.
   - ShellCheck sem nenhum apontamento nos arquivos modificados.
   - Empacotamento executado com sucesso e validação de integridade aprovada.
   - Release `v1.2.0` publicada no GitHub com tarball e sha256 associados.
