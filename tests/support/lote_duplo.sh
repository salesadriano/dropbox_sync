#!/usr/bin/env bash
# lote_duplo.sh — emulacao, para os duplos de `curl` da suite, das rotas em lote
# da fase 9 (F-08; RF-136, RF-137): `files/delete_batch` (+`/check`),
# `upload_session/start` e `upload_session/finish_batch_v2`.
#
# E CARREGADO PELO DUPLO (processo do `curl` falso), nunca pelo `dbx`. Uso:
#
#   . "$DBX_HARNESS_RAIZ/tests/support/lote_duplo.sh"
#   lote_responder "$url" "$corpo_arquivo" && { ...usar $codigo e $corpo...; }
#
# Entradas: `base` (diretorio do cenario, global do duplo), a URL e o arquivo do
# corpo (`--data-binary @arquivo`). Saidas: `codigo` e `corpo`. Devolve 1 quando
# a URL nao e de lote, para o duplo seguir com as suas regras.
#
# Controles, por arquivo em `$base/lote/` (todos opcionais):
#   fila_check            uma resposta por linha, consumida a cada `check`:
#                         `in_progress`, `failed` ou `complete` (padrao: complete)
#   lancar_codigo         codigo HTTP do `delete_batch` (padrao 200)
#   entradas_max          o `complete` devolve so as N primeiras entradas
#   excluir_falha/<nome>  a entrada do arquivo <nome> vem `failure`; o conteudo e
#                         `not_found` (padrao) ou `outro`
#   envio_falha/<nome>    a entrada do arquivo <nome> vem `failure` no finish
#   envio_hash/<nome>     o conteudo do arquivo e o `content_hash` que a entrada
#                         `success` do arquivo <nome> devolve (padrao: nao devolve)
#   start_falha_marca     o `start` cujo conteudo contem este texto vem 400 (falha so dele)
#   finish_codigo         codigo HTTP do `finish_batch_v2` (padrao 200)
#   start_atraso          segundos que o `start` demora (prova de simultaneidade)
#   delete_erro (em $base, nao em lote/)  codigo de erro de exclusao dos testes de
#                         sync: 409 vira falha POR ITEM no `check` (`not_found` se
#                         `erro_corpo` o cita, senao `other`), como o servidor faz;
#                         outro codigo e a falha do `delete_batch` (fatia inteira)
# Compatibilidade (LOTE_ECOA_V2=sim, definido pelo duplo antes de carregar): cada
# entrada de um `delete_batch` aceito acrescenta a `$base/chamadas` uma linha
# `files/delete_v2<TAB>{"path":"<caminho>"}` por item que o `check` confirma, para
# os testes que contam exclusoes por item sem mudar a asserção (a exclusao e a mesma;
# so o transporte e o lote). Nao e chamada de rede: o `delete_v2` real nao e usado.
# Com LOTE_ECOA_CAMPO definido (mesmo vazio), a linha ecoada ganha o campo do meio,
# `files/delete_v2<TAB>$LOTE_ECOA_CAMPO<TAB>{"path":...}`: o formato de 3 campos
# (`endpoint<TAB>limite<TAB>corpo`) dos duplos que registram o limite de banda.
# Rastros: `lote/chamadas` (uma linha `rota<TAB>corpo` por chamada), `lote/pico`
# (simultaneidade do `start`), `enviado<caminho>` (conteudo publicado no finish).

# shellcheck disable=SC2034,SC2154
# Justificativa: `codigo`, `corpo` e `base` sao globais do duplo que carrega este arquivo.
_lote_caminhos() { # <corpo> — um `path` por linha
  local resto=$1 re='"path":"([^"]*)"(.*)$'
  while [[ $resto =~ $re ]]; do
    printf '%s\n' "${BASH_REMATCH[1]}"
    resto=${BASH_REMATCH[2]}
  done
}

lote_responder() {
  local url=$1 arquivo=${2:-} pedido='' n caminho nome tipo linha entradas='' total=0 maximo
  # Rota que nao e de lote: sai sem tocar em nada (nem `codigo`, nem `corpo`).
  case $url in
    */files/delete_batch/check | */files/delete_batch | */upload_session/start | */upload_session/finish_batch_v2) ;;
    *) return 1 ;;
  esac
  mkdir -p "$base/lote/excluir_falha" "$base/lote/envio_falha" "$base/lote/envio_hash"
  [[ -n $arquivo && -r $arquivo ]] && IFS= read -r -d '' pedido <"$arquivo"
  codigo=200
  case $url in
    */files/delete_batch/check)
      printf 'check\t%s\n' "$pedido" >>"$base/lote/chamadas"
      local job=''
      [[ $pedido =~ \"async_job_id\":\"([^\"]*)\" ]] && job=${BASH_REMATCH[1]}
      linha=complete
      if [[ -s $base/lote/fila_check ]]; then
        IFS= read -r linha <"$base/lote/fila_check"
        tail -n +2 "$base/lote/fila_check" >"$base/lote/fila_check.n"
        mv -f "$base/lote/fila_check.n" "$base/lote/fila_check"
      fi
      case $linha in
        in_progress) corpo='{".tag":"in_progress"}' ;;
        failed) corpo='{".tag":"failed","failed":{".tag":"other"}}' ;;
        *)
          maximo=999999
          [[ -r $base/lote/entradas_max ]] && IFS= read -r maximo <"$base/lote/entradas_max"
          while IFS= read -r caminho; do
            total=$((total + 1))
            ((total > maximo)) && break
            nome=${caminho##*/}
            if [[ -f $base/lote/excluir_falha/$nome || -r $base/delete_erro ]]; then
              tipo=outro
              [[ -f $base/lote/excluir_falha/$nome ]] && tipo=$(<"$base/lote/excluir_falha/$nome")
              if [[ -r $base/delete_erro ]]; then
                tipo=outro
                [[ $(<"$base/erro_corpo") == *not_found* ]] && tipo=not_found
              fi
              if [[ $tipo == outro ]]; then
                entradas+="${entradas:+,}{\".tag\":\"failure\",\"failure\":{\".tag\":\"other\"}}"
              else
                entradas+="${entradas:+,}{\".tag\":\"failure\",\"failure\":{\".tag\":\"path_lookup\",\"path_lookup\":{\".tag\":\"not_found\"}}}"
              fi
            else
              if [[ ${LOTE_ECOA_V2:-} == sim ]]; then
                if [[ -n ${LOTE_ECOA_CAMPO+x} ]]; then
                  printf 'files/delete_v2\t%s\t{"path":"%s"}\n' "$LOTE_ECOA_CAMPO" "$caminho" >>"$base/chamadas"
                else
                  printf 'files/delete_v2\t{"path":"%s"}\n' "$caminho" >>"$base/chamadas"
                fi
              fi
              entradas+="${entradas:+,}{\".tag\":\"success\",\"metadata\":{\".tag\":\"file\",\"name\":\"$nome\",\"path_lower\":\"$caminho\",\"path_display\":\"$caminho\",\"id\":\"id:$nome\",\"rev\":\"0123456789abcdef\",\"size\":1}}"
            fi
          done <"$base/lote/job.${job#JOB-}"
          corpo="{\".tag\":\"complete\",\"entries\":[$entradas]}"
          ;;
      esac
      ;;
    */files/delete_batch)
      printf 'delete_batch\t%s\n' "$pedido" >>"$base/lote/chamadas"
      if [[ -r $base/lote/lancar_codigo ]]; then
        IFS= read -r codigo <"$base/lote/lancar_codigo"
        corpo='{"error_summary":"too_many_write_operations/.."}'
        return 0
      fi
      if [[ -r $base/delete_erro && $(<"$base/delete_erro") != 409 ]]; then
        IFS= read -r codigo <"$base/delete_erro"
        corpo=$(<"$base/erro_corpo")
        return 0
      fi
      n=$(find "$base/lote" -maxdepth 1 -name 'job.*' | wc -l)
      n=$((n + 1))
      _lote_caminhos "$pedido" >"$base/lote/job.$n"
      corpo="{\".tag\":\"async_job_id\",\"async_job_id\":\"JOB-$n\"}"
      ;;
    */upload_session/start)
      # Acrescimo (RF-137): com `--paralelo` os starts correm juntos; a numeracao
      # da sessao e reservada sob trava (criacao exclusiva por noclobber; o mkdir nao e atomico neste sistema de arquivos) e o arquivo da sessao e
      # criado antes de soltar a trava, para dois starts nunca pegarem o mesmo n.
      until (set -C; : >"$base/lote/trava") 2>/dev/null; do :; done
      n=$(find "$base/lote" -maxdepth 1 -name 'sessao.*' | wc -l)
      n=$((n + 1))
      : >"$base/lote/sessao.$n"
      unlink "$base/lote/trava"
      printf 'start\t%s\n' "$n" >>"$base/lote/chamadas"
      local marca="$base/lote/vivo.$$"
      : >"$marca"
      printf '%s\n' "$(find "$base/lote" -maxdepth 1 -name 'vivo.*' | wc -l)" >>"$base/lote/pico"
      [[ -r $base/lote/start_atraso ]] && sleep "$(<"$base/lote/start_atraso")"
      cp "$arquivo" "$base/lote/sessao.$n" 2>/dev/null || : >"$base/lote/sessao.$n"
      rm -f "$marca"
      if [[ -r $base/lote/start_falha_marca ]] && [[ $(<"$arquivo") == *"$(<"$base/lote/start_falha_marca")"* ]]; then
        codigo=400
        corpo='{"error_summary":"payload_too_large/.."}'
        return 0
      fi
      corpo="{\"session_id\":\"S-$n\"}"
      ;;
    */upload_session/finish_batch_v2)
      printf 'finish_batch\t%s\n' "$pedido" >>"$base/lote/chamadas"
      if [[ -r $base/lote/finish_codigo ]]; then
        IFS= read -r codigo <"$base/lote/finish_codigo"
        corpo='{"error_summary":"too_many_write_operations/.."}'
        return 0
      fi
      local resto=$pedido hash_devolvido
      local -a sessoes=()
      while [[ $resto =~ \"session_id\":\"S-([0-9]+)\"(.*)$ ]]; do
        sessoes+=("${BASH_REMATCH[1]}")
        resto=${BASH_REMATCH[2]}
      done
      n=0
      while IFS= read -r caminho; do
        nome=${caminho##*/}
        if [[ -f $base/lote/envio_falha/$nome ]]; then
          entradas+="${entradas:+,}{\".tag\":\"failure\",\"failure\":{\".tag\":\"path\",\"path\":{\".tag\":\"conflict\",\"conflict\":{\".tag\":\"file\"}}}}"
        else
          mkdir -p "$base/enviado${caminho%/*}"
          cp "$base/lote/sessao.${sessoes[n]}" "$base/enviado$caminho"
          hash_devolvido=''
          [[ -r $base/lote/envio_hash/$nome ]] && hash_devolvido=",\"content_hash\":\"$(<"$base/lote/envio_hash/$nome")\""
          entradas+="${entradas:+,}{\".tag\":\"success\",\"name\":\"$nome\",\"path_lower\":\"$caminho\",\"path_display\":\"$caminho\",\"id\":\"id:$nome\",\"rev\":\"0123456789abcdef\",\"size\":1$hash_devolvido}"
        fi
        n=$((n + 1))
      done < <(_lote_caminhos "$pedido")
      corpo="{\"entries\":[$entradas]}"
      ;;
    *) return 1 ;;
  esac
  return 0
}
