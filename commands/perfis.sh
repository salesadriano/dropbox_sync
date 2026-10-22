#!/usr/bin/env bash
# perfis — lista os perfis de credencial e se cada um esta completo (RF-126,
# F-18, fase 8). Alias em ingles: `profiles`.
#
# SO LE, E NUNCA MOSTRA SEGREDO
#
#   Sem rede, sem escrita, sem criar diretorio, sem trava e sem renovar token.
#   Cada perfil e lido UM POR VEZ por `lib/config`, que esvazia os canais
#   `DBX_CONFIG_*` entre eles; o que sai e o NOME, o veredito (`completa`,
#   `incompleta`, `ilegivel`, `permissao`, `ligacao_simbolica`), se esta ativo
#   e o caminho do arquivo. Nem valor de campo nem a identidade `cred-`.
#
# O requisito e `ambiente` (DIV-242): a leitura usa `stat` e `lib/json`, e o
# requisito `nenhum` dispensaria o preflight que os verifica. Perfil quebrado
# nao muda o `0`: o comando RELATA a quebra, quem reprova e o `diagnostico`.
# Entradas anomalas de `perfis/` (DIV-243) nunca viram campo de resultado: so
# entram num aviso de uma linha, ja escapado.

dbx_cmd_perfis_requisitos() { printf 'ambiente'; }

dbx_cmd_perfis_executar() {
  dbx_carregar_camada_de_credencial

  while [[ $# -gt 0 ]]; do
    case ${1-} in
      '') ;;
      -*)
        dbx_cmd_falhar uso_invalido "opcao nao reconhecida: $1"
        return $?
        ;;
      *)
        dbx_cmd_falhar uso_invalido "argumento inesperado: $1"
        return $?
        ;;
    esac
    shift
  done

  dbx_config_perfis_listar || {
    dbx_cmd_falhar configuracao \
      "nao foi possivel determinar o diretorio de configuracao: $DBX_CONFIG_MOTIVO"
    return $?
  }

  local ativo=${DBX_CONFIG_PERFIL:-$DBX_CONFIG_PERFIL_PADRAO} indice marca total=0
  for indice in "${!DBX_CONFIG_PERFIS_NOME[@]}"; do
    marca='nao'
    [[ ${DBX_CONFIG_PERFIS_NOME[indice]} == "$ativo" ]] && marca='sim'
    dbx_cmd_iniciar_saida
    dbx_output_campo perfil "${DBX_CONFIG_PERFIS_NOME[indice]}"
    dbx_output_campo credencial "${DBX_CONFIG_PERFIS_CREDENCIAL[indice]}"
    dbx_output_campo ativo "$marca"
    dbx_cmd_campo_caminho arquivo "${DBX_CONFIG_PERFIS_ARQUIVO[indice]}"
    dbx_output_render
    total=$((total + 1))
  done

  if [[ ${#DBX_CONFIG_PERFIS_IGNORADAS[@]} -gt 0 ]]; then
    local lista='' nome contados=0
    for nome in "${DBX_CONFIG_PERFIS_IGNORADAS[@]}"; do
      contados=$((contados + 1))
      [[ $contados -le 5 ]] || break
      dbx_cmd_caminho_exibivel "$nome"
      lista+="${lista:+, }$DBX_CMD_EXIBIDO"
    done
    [[ ${#DBX_CONFIG_PERFIS_IGNORADAS[@]} -gt 5 ]] && lista+=', ...'
    dbx_cmd_iniciar_saida
    dbx_output_diagnostico aviso \
      "${#DBX_CONFIG_PERFIS_IGNORADAS[@]} entrada(s) ignorada(s) em perfis/: $lista"
    dbx_output_render_diagnostico >&2
  fi

  dbx_cmd_iniciar_saida
  dbx_output_campo total "$total"
  dbx_output_render
  return 0
}
