# Log de Prompt — Suporte a Arquivos e Pastas em Download e Upload

> Registro cronológico integral de prompts e decisões da demanda conforme regra 42 do protocolo comum.

## Identificação da demanda

| Campo | Valor |
|---|---|
| Demanda | Suporte a arquivos e pastas em `download` e `upload` (`download e upload devem trabalhar com arquivos e pastas`) |
| Data / Hora de início | 2026-10-08 15:25 |
| Porte | **M (padrão)** — expansão de contrato público operacional dos comandos `upload` e `download` para suporte a diretórios |
| Instância | `myPCWin/Adriano Sales Santos` |
| Branch de trabalho | `feature/suporte-pastas-upload-download` |
| Branch principal | `develop` |

---

## Prompt 1 (Entrada do Operador)

```
@tech-lead download e upload devem trabalhar com arquivos e pastas
```

### Análise do Tech Lead

1. **Situação Atual:**
   - `commands/upload.sh` aceita apenas arquivos regulares (`[[ -f $origem ]]`) ou fluxo via `-`. Ao receber um diretório, recusa com erro `arquivo local inexistente ou ilegivel`.
   - `commands/download.sh` aceita apenas download de arquivos individuais via endpoint `files/download`. Ao apontar para uma pasta remota, a API da Dropbox retorna erro `path/not_file/` e o utilitário falha orientando o operador a usar `sync --receber`.
2. **Novo Comportamento Desejado:**
   - **`dbx upload <origem> <destino>`:**
     - Se `<origem>` for um arquivo regular ou `-`: mantém o comportamento atual de envio individual.
     - Se `<origem>` for um diretório (`[[ -d $origem ]]`): normaliza o destino remoto (anexando o nome base do diretório caso o destino termine com `/` ou seja `/`) e realiza o envio recursivo do diretório e seus arquivos/subpastas, reutilizando o motor `sync --enviar` com integração a metadados SQLite e suporte a progresso.
   - **`dbx download <remoto> <destino>`:**
     - Se `<remoto>` for um arquivo individual: baixa normalmente via `files/download`.
     - Se `<remoto>` for a raiz `/` ou se `files/download` retornar `not_file` (indicando que o caminho remoto é um diretório):
       - Se nenhum destino local for informado (ou `-`): recusa com `uso_invalido` (não é possível emitir diretório em stdout).
       - Se um destino local for informado: ajusta o diretório de destino (preservando o nome da pasta remota quando apropriado) e aciona o motor `sync --receber` recursivo para baixar todos os arquivos e pastas para o disco local.
3. **Critérios de Aceite:**
   - Arquivos individuais continuam funcionando normalmente sem qualquer regressão.
   - Pastas locais enviadas via `upload` sobem recursivamente para a pasta remota correspondente.
   - Pastas remotas baixadas via `download` descem recursivamente para o diretório local correspondente.
   - Modos `--progresso`, `--dry-run` e `--forcar` continuam respeitados.
   - 100% dos testes unitários e de integração existentes continuam passando sem falhas, acompanhados de novos testes de integração específicos para upload e download de diretórios.
