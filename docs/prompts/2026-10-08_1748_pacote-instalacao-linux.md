# Log de Prompt — Pacote de Instalacao e Scripts para Linux

> Registro cronológico integral de prompts e decisões da demanda conforme regra 42 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Pacote de instalacao e scripts para instalacao no Linux (`publique o pacote de instalação e prepare as scripts para instalação no linux`) |
| Data / Hora de início | 2026-10-08 17:48 |
| Porte | **M (padrão)** — novos scripts de automação de instalação (`install.sh`), desinstalação (`uninstall.sh`) e empacotamento (`scripts/empacotar.sh`), release v1.1.0 e bumping de versão |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `develop` |
| Branch principal | `develop` (desenvolvimento) / `master` (produção/releases) |

---

## Prompt 1 (Entrada do Operador)

```
publique o pacote de instalação e prepare as scripts para instalação no linux
```

### Análise do Tech Lead

1. **Objetivo:**
   - Fornecer uma experiência de instalação oficial, rápida e segura para usuários Linux/POSIX.
   - Disponibilizar pacote de distribuição `.tar.gz` autocontido com verificação de integridade SHA256.
   - Disponibilizar instalador `install.sh` que suporte tanto instalação a partir do clone/tarball quanto via pipe direto (`curl ... | bash`).
   - Disponibilizar desinstalador `uninstall.sh`.
   - Bump de versão de `1.0.0` para `1.1.0` refletindo o acúmulo de novas funcionalidades.
2. **Componentes Desenvolvidos:**
   - `install.sh`: instalador flexível com checagem de dependências, suporte a `--user`, `--system`, `--prefix`, `--uninstall`.
   - `uninstall.sh`: desinstalador idempotente com opção `--purge`.
   - `scripts/empacotar.sh`: gerador automatizado de pacotes em `dist/` com cálculo de checksum SHA256 e teste de integridade.
   - Atualização da versão `DBX_CLI_VERSAO='1.1.0'` em `lib/cli.sh` e resolução de links simbólicos em `bin/dbx`.
   - Atualização de `README.md` com guia passo a passo de instalação.
3. **Critérios de Aceite:**
   - Validação com ShellCheck (0 erros).
   - Suíte de 586 testes TAP aprovada (0 falhas).
   - Pacote `.tar.gz` e checksum gerados em `dist/`.
