#!/usr/bin/env bash
# scripts/empacotar.sh — Gera o pacote de distribuicao .tar.gz para Linux e checksums.
#
# Uso:
#   bash scripts/empacotar.sh [--publicar]
#
set -euo pipefail

RAIZ_PROJETO=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$RAIZ_PROJETO"

PUBLICAR="nao"
while [[ $# -gt 0 ]]; do
  case ${1-} in
    --publicar) PUBLICAR="sim" ;;
    *) printf 'Opcao nao reconhecida: %s\n' "$1" >&2; exit 1 ;;
  esac
  shift
done

# Extrair versao do lib/cli.sh
VERSAO=$(grep -E "^readonly DBX_CLI_VERSAO=" "$RAIZ_PROJETO/lib/cli.sh" | cut -d"'" -f2)
[[ -n $VERSAO ]] || { printf 'Erro: Nao foi possivel identificar a versao em lib/cli.sh\n' >&2; exit 1; }

printf '==> Empacotando dropbox_sync v%s para Linux...\n' "$VERSAO"

DIR_DIST="$RAIZ_PROJETO/dist"
mkdir -p -- "$DIR_DIST"

NOME_PACOTE="dropbox_sync-${VERSAO}-linux"
ARQUIVO_TAR="${DIR_DIST}/${NOME_PACOTE}.tar.gz"
ARQUIVO_SHA="${DIR_DIST}/${NOME_PACOTE}.tar.gz.sha256"

# Area de preparacao limpa
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/dbx-pack.XXXXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT

mkdir -p "$STAGING/bin" "$STAGING/lib" "$STAGING/commands"

# Copiar arquivos de runtime
cp -p "$RAIZ_PROJETO/bin/dbx" "$STAGING/bin/dbx"
cp -p "$RAIZ_PROJETO/lib/"*.sh "$STAGING/lib/"
cp -p "$RAIZ_PROJETO/commands/"*.sh "$STAGING/commands/"
cp -p "$RAIZ_PROJETO/install.sh" "$STAGING/install.sh"
cp -p "$RAIZ_PROJETO/uninstall.sh" "$STAGING/uninstall.sh"
cp -p "$RAIZ_PROJETO/README.md" "$STAGING/README.md"
cp -p "$RAIZ_PROJETO/LICENSE" "$STAGING/LICENSE"

# Permissoes estritas
chmod 755 "$STAGING/bin/dbx" "$STAGING/install.sh" "$STAGING/uninstall.sh"
chmod 644 "$STAGING/lib/"*.sh "$STAGING/commands/"*.sh "$STAGING/README.md" "$STAGING/LICENSE"

# Gerar tarball
tar -czf "$ARQUIVO_TAR" -C "$STAGING" .
printf '[ok] Pacote gerado: %s (%s bytes)\n' "$ARQUIVO_TAR" "$(stat -c '%s' "$ARQUIVO_TAR")"

# Gerar checksum
(cd "$DIR_DIST" && sha256sum "$(basename "$ARQUIVO_TAR")" > "$ARQUIVO_SHA")
printf '[ok] Checksum SHA256: %s\n' "$ARQUIVO_SHA"
cat "$ARQUIVO_SHA"

# Teste de integridade do pacote gerado
TESTE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dbx-test-unpack.XXXXXXXX")
tar -xzf "$ARQUIVO_TAR" -C "$TESTE_DIR"
TESTE_VERSAO=$("$TESTE_DIR/bin/dbx" --version)
rm -rf -- "$TESTE_DIR"

if [[ $TESTE_VERSAO == "dbx $VERSAO" ]]; then
  printf '[ok] Teste de execucao do pacote: %s (aprovado)\n' "$TESTE_VERSAO"
else
  printf '[erro] Teste do pacote falhou: esperado "dbx %s", obtido "%s"\n' "$VERSAO" "$TESTE_VERSAO" >&2
  exit 1
fi

if [[ $PUBLICAR == "sim" ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    printf '[aviso] GitHub CLI (gh) nao disponivel para publicacao automatica.\n' >&2
    exit 0
  fi

  TAG="v${VERSAO}"
  printf '==> Publicando Release %s no GitHub via gh release...\n' "$TAG"
  if gh release view "$TAG" >/dev/null 2>&1; then
    printf '==> Release %s ja existe, enviando artefatos atualizados...\n' "$TAG"
    gh release upload "$TAG" "$ARQUIVO_TAR" "$ARQUIVO_SHA" --clobber
  else
    printf '==> Criando nova Release %s no GitHub...\n' "$TAG"
    gh release create "$TAG" "$ARQUIVO_TAR" "$ARQUIVO_SHA" \
      --title "Release v${VERSAO} — Suporte a Pastas, Cache SQLite e Progresso" \
      --notes "## O que ha de novo na v${VERSAO}

- **Suporte transparente a pastas em upload e download:** envio e download recursivo automatico de arvores inteiras.
- **Cache local SQLite de metadados e operacoes:** aceleracao de analises locais com dispensacao inteligente de arquivos inalterados.
- **Feedback detalhado em modo progresso (-p):** listagem de arquivos e resultado apurado da analise (em cache, hash calculado, identico, novo, modificado).
- **Scripts de instalacao e desinstalacao oficiais:** instalador portavel 'install.sh' para Linux.

### Instalacao rapida no Linux:
\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/salesadriano/dropbox_sync/develop/install.sh | bash
\`\`\`
"
  fi
  printf '[ok] Release %s publicada com sucesso no GitHub!\n' "$TAG"
fi
