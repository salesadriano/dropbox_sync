#!/usr/bin/env bash
# Testes do autocompletar de bash (RF-68, TC-CPL-01..07).
#
# A FONTE UNICA E A AJUDA. O conjunto de comandos e o de opcoes de cada comando
# sao lidos da ajuda REAL (`dbx help` e `dbx help <comando>`) e confrontados com
# o que o script de fato oferece, nos dois sentidos: opcao acrescentada ou
# removida de um lado so reprova. A ajuda, por sua vez, e confrontada com o
# codigo do comando, para que nenhuma opcao documentada seja fantasma.
#
# shellcheck disable=SC2016
# Justificativa: scripts entregues a `bash -c` chegam sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly DBX_EXEC="$DBX_HARNESS_RAIZ/bin/dbx"
readonly SCRIPT="$DBX_HARNESS_RAIZ/completions/dbx.bash"
readonly COMANDOS='upload download list delete info space config unlink sync verificar diagnostico completar'

# _completar <palavra...> — COMPREPLY, um por linha e ordenado, para a linha
# `dbx <palavra...>` com o cursor na ultima palavra. Roda num bash limpo, com
# PATH extra opcional (DBX_PATH_EXTRA) para o duplo de `curl`.
_completar() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/completar.XXXXXX")
  env -i PATH="${DBX_PATH_EXTRA:+$DBX_PATH_EXTRA:}$PATH" HOME="$area" bash -c '
    script=$1; shift
    . "$script"
    funcao=$(complete -p dbx 2>/dev/null)
    funcao=${funcao#*-F }
    funcao=${funcao%% *}
    COMP_WORDS=(dbx "$@")
    COMP_CWORD=$#
    COMP_LINE="dbx $*"
    COMP_POINT=${#COMP_LINE}
    COMPREPLY=()
    "$funcao" dbx "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
    for item in ${COMPREPLY[@]+"${COMPREPLY[@]}"}; do printf "%s\n" "$item"; done
  ' _ "$SCRIPT" "$@" 2>&1 | LC_ALL=C sort -u
}

_ajuda() { # <comando> — saida de `dbx help <comando>`
  env -i PATH="$PATH" HOME="$DBX_TESTES_TMP" bash "$DBX_EXEC" help "$@" 2>&1
}

# _opcoes_da_ajuda <comando> — opcoes das linhas `  -...` da secao `Opcoes` da
# ajuda (ate a primeira linha em branco), so a parte antes da descricao (dois
# espacos), uma por linha e ordenadas. O texto corrido fora da secao pode citar
# opcao sem defini-la.
_opcoes_da_ajuda() {
  local linha secao=nao
  while IFS= read -r linha; do
    [[ $linha == Opcoes* ]] && secao=sim && continue
    [[ -z $linha ]] && secao=nao
    [[ $secao == sim && $linha == '  -'* ]] || continue
    linha=${linha#  }
    linha=${linha%%  *}
    grep -oE '(^|[ ,])-{1,2}[A-Za-z][A-Za-z-]*' <<<"$linha" | tr -d ' ,'
  done < <(_ajuda "$@") | LC_ALL=C sort -u
}

# _opcoes_do_codigo <arquivo> — opcoes que o `case` do comando reconhece.
_opcoes_do_codigo() {
  grep -E '^[[:space:]]+-{1,2}[A-Za-z][-A-Za-z |\\]*\)' "$1" |
    grep -oE -- '-{1,2}[A-Za-z][A-Za-z-]*' | LC_ALL=C sort -u
}

_comandos_da_ajuda() {
  local linha nome dentro=nao
  {
    while IFS= read -r linha; do
      [[ $linha == 'Comandos:' ]] && dentro=sim && continue
      [[ $dentro == sim && -z $linha ]] && break
      [[ $dentro == sim ]] || continue
      nome=${linha#  }
      printf '%s\n' "${nome%% *}"
      [[ $linha =~ \(alias:\ ([a-z]+)\) ]] && printf '%s\n' "${BASH_REMATCH[1]}"
    done < <(_ajuda)
    printf 'help\n'
  } | LC_ALL=C sort -u
}

_opcoes_globais_da_ajuda() {
  local linha
  linha=$(_ajuda | grep '^Opcoes globais:')
  grep -oE -- '-{1,2}[A-Za-z][A-Za-z-]*' <<<"${linha#*:}" | LC_ALL=C sort -u
}

# ---------------------------------------------------------------------------
# TC-CPL-01 — comandos, aliases e opcoes globais
# ---------------------------------------------------------------------------

teste_cpl01_completa_comandos_aliases_e_help_conforme_a_ajuda() {
  local esperados
  esperados=$(_comandos_da_ajuda)
  assert_contem 'verify' "$esperados" 'a ajuda lista o alias verify'
  assert_contem 'completion' "$esperados" 'e o alias completion'
  assert_igual "$esperados" "$(_completar '')" 'comandos do script = comandos da ajuda'
  assert_igual $'verificar\nverify' "$(_completar ver)" 'prefixo filtra'
}

teste_cpl01_completa_as_opcoes_globais_conforme_a_ajuda() {
  assert_igual "$(_opcoes_globais_da_ajuda)" "$(_completar -)" 'globais do script = da ajuda'
  assert_contem 'verificar' "$(_completar --json '')" 'depois de opcao global vem o comando'
}

# ---------------------------------------------------------------------------
# TC-CPL-02 — opcoes de cada comando, nos dois sentidos
# ---------------------------------------------------------------------------

teste_cpl02_opcoes_de_cada_comando_coincidem_com_a_ajuda() {
  local comando
  for comando in $COMANDOS; do
    assert_igual "$(_opcoes_da_ajuda "$comando")" "$(_completar "$comando" -)" \
      "opcoes de $comando: script e ajuda divergem"
  done
  assert_contem '--source' "$(_completar verificar --s)" 'ingles completado'
  assert_contem '--origem' "$(_completar verify --o)" 'portugues completado, tambem pelo alias'
}

teste_cpl02_toda_opcao_da_ajuda_existe_no_codigo_do_comando() {
  local comando opcao faltando=''
  for comando in $COMANDOS; do
    while IFS= read -r opcao; do
      [[ -n $opcao ]] || continue
      _opcoes_do_codigo "$DBX_HARNESS_RAIZ/commands/$comando.sh" | grep -qxF -- "$opcao" ||
        faltando+=" $comando:$opcao"
    done < <(_opcoes_da_ajuda "$comando")
  done
  assert_igual '' "$faltando" "opcao documentada que o comando nao reconhece:$faltando"
}

# ---------------------------------------------------------------------------
# TC-CPL-08 (RF-78) — os tres comandos da fase 3 e os aliases
# ---------------------------------------------------------------------------

teste_cpl08_revisoes_restaurar_lixeira_coincidem_com_a_ajuda() {
  local comando opcao faltando=''
  for comando in revisoes restaurar lixeira; do
    [[ -n $(_opcoes_da_ajuda "$comando") ]] || _harness_falhar "ajuda de $comando sem secao Opcoes"
    assert_igual "$(_opcoes_da_ajuda "$comando")" "$(_completar "$comando" -)" \
      "opcoes de $comando: script e ajuda divergem"
    while IFS= read -r opcao; do
      _opcoes_do_codigo "$DBX_HARNESS_RAIZ/commands/$comando.sh" | grep -qxF -- "$opcao" ||
        faltando+=" $comando:$opcao"
    done < <(_opcoes_da_ajuda "$comando")
  done
  assert_igual '' "$faltando" "opcao documentada que o comando nao reconhece:$faltando"
  assert_igual $'restaurar\nrestore' "$(_completar res)" 'comandos e aliases'
  assert_igual $'revisions\nrevisoes' "$(_completar rev)" 'comandos e aliases'
  assert_igual $'retain\nreter' "$(_completar ret)" 'reter e alias'
  assert_contem 'trash' "$(_completar t)" 'alias trash'
  assert_contem '--purge' "$(_completar trash --p)" 'opcoes pelo alias'
  assert_contem '--before' "$(_completar restore --b)" 'ingles completado'
  assert_contem '--by-id' "$(_completar revisions --b)" 'ingles completado'
  assert_nao_contem '--yes' "$(_completar lixeira --)" 'lixeira nao tem --yes (DIV-55)'
  assert_igual '' "$(_completar restaurar --rev '')" 'valor de --rev nao e completado'
}

teste_cpl02_a_conferencia_reprova_opcao_de_um_lado_so() {
  # Prova de discriminacao: um script mutante com uma opcao a mais e outro com
  # uma a menos precisam divergir da ajuda.
  local mutante
  mutante=$(mktemp "$DBX_TESTES_TMP/mutante.XXXXXX")
  assert_igual "$(_opcoes_da_ajuda space)" "$(_completar_com "$SCRIPT" space -)" 'o original confere'
  sed 's/--humano --human -H/--humano --human -H --extra/' "$SCRIPT" >"$mutante"
  assert_diferente "$(_opcoes_da_ajuda space)" "$(_completar_com "$mutante" space -)" 'opcao a mais'
  sed 's/--humano --human -H/--humano --human/' "$SCRIPT" >"$mutante"
  assert_diferente "$(_opcoes_da_ajuda space)" "$(_completar_com "$mutante" space -)" 'opcao a menos'
}

_completar_com() { # <script> <palavra...>
  local script=$1
  shift
  env -i PATH="$PATH" bash -c '
    . "$1"; shift
    COMP_WORDS=(dbx "$@"); COMP_CWORD=$#; COMPREPLY=()
    _dbx_completar dbx "${COMP_WORDS[COMP_CWORD]}" "${COMP_WORDS[COMP_CWORD-1]}"
    for item in ${COMPREPLY[@]+"${COMPREPLY[@]}"}; do printf "%s\n" "$item"; done
  ' _ "$script" "$@" 2>&1 | LC_ALL=C sort -u
}

# ---------------------------------------------------------------------------
# TC-CPL-03 — caminhos locais (e so os locais)
# ---------------------------------------------------------------------------

teste_cpl03_caminho_local_com_espaco_e_acento() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/caminhos.XXXXXX")
  mkdir -p "$area/minha pasta"
  printf 'x' >"$area/minha pasta/relatório ção.txt"
  assert_igual "$area/minha pasta" "$(_completar upload "$area/minha")" 'diretorio com espaco'
  assert_igual "$area/minha pasta/relatório ção.txt" "$(_completar upload "$area/minha pasta/rel")" \
    'arquivo com acento'
  assert_igual "$area/minha pasta/relatório ção.txt" "$(_completar upload "$area/minha\\ pasta/rel")" \
    'palavra digitada com barra invertida'
  assert_igual "$area/minha pasta" "$(_completar download /remoto/a "$area/minha")" \
    'destino local do download'
  assert_igual "$area/minha pasta" "$(_completar sync --enviar --origem "$area/minha")" \
    'origem local do sync --enviar'
  assert_igual "$area/minha pasta" "$(_completar verificar --receber --destino "$area/minha")" \
    'destino local do verificar --receber'
}

teste_cpl03_caminho_remoto_nao_e_completado() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/caminhos.XXXXXX")
  mkdir -p "$area/pasta"
  assert_igual '' "$(_completar download "$area/pas")" 'origem do download e remota'
  assert_igual '' "$(_completar upload /local "$area/pas")" 'destino do upload e remoto'
  assert_igual '' "$(_completar sync --receber --origem "$area/pas")" 'origem do --receber e remota'
  assert_igual '' "$(_completar info "$area/pas")" 'info e remoto'
}

# ---------------------------------------------------------------------------
# TC-CPL-04 — sem rede, sem segredo e sem efeito ao carregar
# ---------------------------------------------------------------------------

teste_cpl04_nenhuma_invocacao_de_curl_nem_leitura_de_credencial() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/rede.XXXXXX")
  mkdir -p "$area/bin"
  printf '#!/usr/bin/env bash\nprintf x >>%q\nexit 0\n' "$area/curl_chamado" >"$area/bin/curl"
  chmod +x "$area/bin/curl"
  DBX_PATH_EXTRA="$area/bin" _completar '' >/dev/null
  DBX_PATH_EXTRA="$area/bin" _completar sync - >/dev/null
  DBX_PATH_EXTRA="$area/bin" _completar upload "$area/" >/dev/null
  assert_arquivo_ausente "$area/curl_chamado" 'zero invocacoes do cliente de rede'
  local texto
  texto=$(grep -vE '^[[:space:]]*#' "$SCRIPT")
  local proibido
  for proibido in curl credencial XDG_ HOME state dropboxapi; do
    assert_nao_contem "$proibido" "$texto" "o script nao toca $proibido"
  done
}

teste_cpl04_carregar_nao_imprime_nem_muda_opcoes_do_shell() {
  local resultado
  resultado=$(env -i PATH="$PATH" bash -c '
    antes_o=$(set -o); antes_s=$(shopt); antes_f=$(compgen -A function)
    antes_v=$(compgen -v | grep -vxE "_|antes_.*|BASH_.*|FUNCNAME")
    saida=$(. "$1" 2>&1)
    . "$1"
    depois_v=$(compgen -v | grep -vxE "_|antes_.*|BASH_.*|FUNCNAME|saida")
    [[ -z $saida ]] || echo "imprimiu: $saida"
    [[ $antes_o == "$(set -o)" ]] || echo "set -o mudou"
    [[ $antes_s == "$(shopt)" ]] || echo "shopt mudou"
    [[ $antes_v == "$depois_v" ]] || echo "variaveis mudaram"
    novas=$(comm -13 <(printf "%s\n" "$antes_f") <(compgen -A function))
    [[ $novas == _dbx_completar ]] || echo "funcoes novas: $novas"
    complete -p dbx >/dev/null 2>&1 || echo "sem registro complete"
  ' _ "$SCRIPT" 2>&1)
  assert_igual '' "$resultado" 'source so define a funcao e o registro'
}

# ---------------------------------------------------------------------------
# TC-CPL-05 — dbx completar bash
# ---------------------------------------------------------------------------

teste_cpl05_completar_bash_imprime_o_script_identico() {
  local area
  area=$(mktemp -d "$DBX_TESTES_TMP/completar.XXXXXX")
  env -i PATH="$PATH" HOME="$area" bash "$DBX_EXEC" completar bash >"$area/out" 2>"$area/err"
  assert_igual 0 $? 'sai com 0'
  cmp -s "$SCRIPT" "$area/out" || _harness_falhar 'o conteudo difere de completions/dbx.bash'
  env -i PATH="$PATH" HOME="$area" bash "$DBX_EXEC" completion bash >"$area/out2" 2>&1
  cmp -s "$SCRIPT" "$area/out2" || _harness_falhar 'o alias completion difere'
}

teste_cpl05_sem_argumento_ou_outro_shell_e_uso_invalido() {
  local area estado
  area=$(mktemp -d "$DBX_TESTES_TMP/completar.XXXXXX")
  env -i PATH="$PATH" HOME="$area" bash "$DBX_EXEC" completar >/dev/null 2>&1
  estado=$?
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$estado" 'sem argumento: 2'
  env -i PATH="$PATH" HOME="$area" bash "$DBX_EXEC" completar zsh >/dev/null 2>&1
  estado=$?
  assert_igual "$(dbx_errors_codigo_saida uso_invalido)" "$estado" 'zsh: 2'
}

teste_cpl05_roda_onde_o_preflight_recusaria() {
  local area alvo origem bash_absoluto estado
  area=$(mktemp -d "$DBX_TESTES_TMP/completar.XXXXXX")
  mkdir -p "$area/bin"
  for alvo in dirname cat; do
    origem=$(command -v "$alvo") && ln -s "$origem" "$area/bin/$alvo"
  done
  bash_absoluto=$(command -v bash)
  env -i PATH="$area/bin" HOME="$area" "$bash_absoluto" "$DBX_EXEC" completar bash >"$area/out" 2>"$area/err"
  estado=$?
  assert_igual 0 "$estado" "sem curl, stat e cia., ainda imprime; erro: $(cat "$area/err")"
  cmp -s "$SCRIPT" "$area/out" || _harness_falhar 'o conteudo difere sem os utilitarios'
}

# ---------------------------------------------------------------------------
# TC-CPL-06 — install.sh, sem sudo e idempotente
# ---------------------------------------------------------------------------

_instalar() { # <home> <argumentos...>
  local casa=$1
  shift
  env -i PATH="$casa/bin-sentinela:$PATH" HOME="$casa" bash "$DBX_HARNESS_RAIZ/install.sh" "$@" \
    >"$casa/instalacao.log" 2>&1
}

_casa() {
  local casa
  casa=$(mktemp -d "$DBX_TESTES_TMP/casa.XXXXXX")
  mkdir -p "$casa/bin-sentinela"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>%q\nexit 1\n' "$casa/sudo_chamado" \
    >"$casa/bin-sentinela/sudo"
  chmod +x "$casa/bin-sentinela/sudo"
  printf 'linha do operador\n' >"$casa/.bashrc"
  printf '%s' "$casa"
}

teste_cpl06_install_poe_o_script_no_diretorio_do_usuario_sem_sudo() {
  local casa alvo antes
  casa=$(_casa)
  alvo="$casa/.local/share/bash-completion/completions/dbx"
  _instalar "$casa" --user
  assert_igual 0 $? "instalacao conclui: $(cat "$casa/instalacao.log")"
  assert_arquivo_existe "$alvo" 'script instalado'
  cmp -s "$SCRIPT" "$alvo" || _harness_falhar 'o instalado difere do versionado'
  assert_igual 644 "$(stat -c %a "$alvo")" 'modo 0644'
  assert_arquivo_ausente "$casa/sudo_chamado" 'nenhum sudo'
  assert_igual 'linha do operador' "$(cat "$casa/.bashrc")" '.bashrc intacto'
  antes=$(find "$casa/.local" -printf '%P %m %s\n' | sort)
  _instalar "$casa" --user
  assert_igual "$antes" "$(find "$casa/.local" -printf '%P %m %s\n' | sort)" 'idempotente'
  env -i PATH="$PATH" HOME="$casa" "$casa/.local/bin/dbx" completar bash >"$casa/impresso" 2>&1
  cmp -s "$SCRIPT" "$casa/impresso" || _harness_falhar 'o dbx instalado nao imprime o script'
}

teste_cpl06_prefix_e_uninstall() {
  local casa prefixo
  casa=$(_casa)
  prefixo="$casa/opt"
  _instalar "$casa" --prefix "$prefixo"
  assert_arquivo_existe "$prefixo/share/bash-completion/completions/dbx" 'instalado sob o prefixo'
  printf 'de outro programa' >"$prefixo/share/bash-completion/completions/outro"
  _instalar "$casa" --prefix "$prefixo" --uninstall
  assert_arquivo_ausente "$prefixo/share/bash-completion/completions/dbx" 'removido'
  assert_arquivo_existe "$prefixo/share/bash-completion/completions/outro" 'so ele e removido'
}

teste_cpl06_uninstall_sh_remove_so_o_autocompletar_do_dbx() {
  local casa alvo
  casa=$(_casa)
  alvo="$casa/.local/share/bash-completion/completions"
  _instalar "$casa" --user
  printf 'de outro programa' >"$alvo/outro"
  env -i PATH="$PATH" HOME="$casa" bash "$DBX_HARNESS_RAIZ/uninstall.sh" --user >"$casa/log" 2>&1
  assert_igual 0 $? "desinstalacao conclui: $(cat "$casa/log")"
  assert_arquivo_ausente "$alvo/dbx" 'o autocompletar do dbx sai'
  assert_arquivo_existe "$alvo/outro" 'o de outro programa fica'
}

# ---------------------------------------------------------------------------
# TC-CPL-07 — pacote
# ---------------------------------------------------------------------------

teste_cpl07_pacote_contem_o_script() {
  local copia item pacote
  copia=$(mktemp -d "$DBX_TESTES_TMP/pacote.XXXXXX")
  for item in bin lib commands completions scripts install.sh uninstall.sh README.md LICENSE; do
    cp -R "$DBX_HARNESS_RAIZ/$item" "$copia/"
  done
  env -i PATH="$PATH" HOME="$copia" TMPDIR="$copia" bash "$copia/scripts/empacotar.sh" \
    >"$copia/log" 2>&1
  assert_igual 0 $? "empacotamento conclui: $(cat "$copia/log")"
  pacote=$(find "$copia/dist" -name '*.tar.gz' | head -n 1)
  assert_contem './completions/dbx.bash' "$(tar -tzf "$pacote")" 'o pacote traz o script'
}

harness_executar "$@"
