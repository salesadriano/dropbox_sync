#!/usr/bin/env bash
# Suite independente do QA, fase 5 do backlog: link temporario (F-15, RF-84) e
# link compartilhado (F-16, RF-85..RF-92; DIV-104..DIV-127; RSK-57..RSK-61).
#
# Escrita como ADVERSARIO, pelo executavel real `bin/dbx`, com duplo de `curl`
# proprio (independente do da suite do developer). Os focos sao os P0:
#
#   - a SENHA do link (RF-86, RSK-58) nunca sai do arquivo de corpo: nem argv
#     nem ambiente de NENHUM processo durante a chamada (varredura de /proc
#     feita pelo proprio duplo, com o sentinela lido de arquivo), nem a
#     configuracao de `-K -`, nem stdout/stderr em qualquer modo, nem resto em
#     `TMPDIR` depois de sinal;
#   - o `--revogar` (RF-89, RSK-59) nunca revoga link de item fora da raiz: a
#     prova e o REGISTRO DE CHAMADAS do duplo, zero `revoke_shared_link`;
#   - visibilidade sempre explicita (RF-85, RSK-57): combinacao invalida sai 2
#     sem NENHUMA chamada, nem a renovacao do token;
#   - reuso e modificacao (RF-87) e confinamento da listagem (RF-88) e do link
#     temporario (RF-84).
#
# Duplo de `curl`: regras em `$B/regras`, uma por linha,
# `endpoint<TAB>filtro_do_corpo<TAB>codigo<TAB>resposta[<TAB>uma]` (padroes do
# shell); a primeira que casa responde. `@N@` na resposta vira um contador
# (cursores sempre novos). Codigo `DORME` responde 200 depois de criar
# `$B/em_voo` e dormir 3 s (janela para sinal). Toda chamada vai para
# `$B/chamadas` como `endpoint<TAB>corpo`; o `argv` vai para `$B/argv` e a
# configuracao lida por `-K -` para `$B/conf`. Chamada sem regra responde 400 e
# fica marcada `SEM_REGRA`. Com `$B/sentinela` presente, cada chamada de
# escrita varre `/proc/*/cmdline` e `/proc/*/environ` e anota em `$B/varredura`
# o pid e o arquivo onde o sentinela aparece (nunca o conteudo).
#
# Auditoria RNF-24: nenhum `$(...)` captura bytes externos (saida do programa,
# arquivo, registro); tudo e lido com `read`. Nenhum `grep -c` sobre arquivo.
#
# shellcheck disable=SC2016
# Justificativa: o duplo e os roteiros sao escritos sem expansao.
#
# shellcheck source=tests/support/harness.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../support/harness.sh"
. "$DBX_HARNESS_RAIZ/lib/errors.sh"

readonly QA_DBX="$DBX_HARNESS_RAIZ/bin/dbx"
QA_USO=$(dbx_errors_codigo_saida uso_invalido)
QA_AUT=$(dbx_errors_codigo_saida autenticacao)
QA_PERM=$(dbx_errors_codigo_saida permissao)
QA_NAO_ENC=$(dbx_errors_codigo_saida nao_encontrado)
QA_CONFLITO=$(dbx_errors_codigo_saida conflito)
QA_REMOTO=$(dbx_errors_codigo_saida erro_remoto)
QA_RECUSADO=$(dbx_errors_codigo_saida caminho_recusado)
QA_NAO_CONCLUIDA=$(dbx_errors_codigo_saida nao_concluida)
readonly QA_USO QA_AUT QA_PERM QA_NAO_ENC QA_CONFLITO QA_REMOTO QA_RECUSADO QA_NAO_CONCLUIDA
QA_BASH=$(command -v bash)
readonly QA_BASH
readonly QA_URL='https://www.dropbox.com/scl/fi/qa5abc/x.txt?rlkey=k1'
readonly QA_EXISTE='{"error_summary":"shared_link_already_exists/..","error":{".tag":"shared_link_already_exists"}}'

B=''
QA_ESTADO=''
QA_SAIDA=''
QA_ERRO=''
QA_N=0
QA_CONTAGEM=0
# Sentinela da senha, novo a cada execucao da suite (nunca exportado).
QA_SENHA="QA5senha${RANDOM}x${RANDOM}y$$z"
QA_TEXTO=''
QA_LINK=''
QA_TETO=40
declare -a QA_AMBIENTE=()

# _qa_cenario [raiz_remota] — credencial, duplo de `curl`, TMPDIR e estado privados.
_qa_cenario() {
  B=$(mktemp -d "$DBX_TESTES_TMP/qa-b5.XXXXXX")
  mkdir -p "$B/cfg/dbx" "$B/bin" "$B/resp" "$B/tmp" "$B/estado"
  chmod 700 "$B/cfg/dbx"
  printf '{"versao":1,"app_key":"ak","app_secret":"as","refresh_token":"rt","raiz_remota":"%s"}' \
    "${1:-/}" >"$B/cfg/dbx/credencial.json"
  chmod 600 "$B/cfg/dbx/credencial.json"
  : >"$B/regras"
  QA_N=0
  QA_AMBIENTE=()
  {
    printf '#!%s\nQA=%q\n' "$QA_BASH" "$B"
    cat <<'FIM'
conf=''
IFS= read -r -d '' conf
o=''; w=''; ant=''; url=''; dados=''
for a in "$@"; do
  case $ant in -o) o=$a ;; -w) w=$a ;; --data-binary) dados=${a#@} ;; esac
  case $a in http*) url=$a ;; esac
  ant=$a
done
printf '%s\n' "$*" >>"$QA/argv"
umask >>"$QA/umask"
[[ -n $dados && -e ${dados#@} ]] && stat -c '%a' -- "${dados#@}" >>"$QA/modo_corpo" 2>/dev/null
printf '%s\n--\n' "$conf" >>"$QA/conf"
pedido=''
[[ -n $dados && -r $dados ]] && IFS= read -r -d '' pedido <"$dados"
ep=${url#https://api.dropboxapi.com/2/}
cod=400 corpo='{"error_summary":"sem_regra/"}'
if [[ $url == *oauth2/token* ]]; then
  printf 'oauth2/token\t\n' >>"$QA/chamadas"
  cod=200 corpo='{"access_token":"sl.t","token_type":"bearer","expires_in":14400}'
  [[ -r $QA/token ]] && IFS= read -r -d '' corpo <"$QA/token"
else
  printf '%s\t%s\n' "$ep" "$pedido" >>"$QA/chamadas"
  if [[ -r $QA/sentinela && $ep == sharing/* ]]; then
    IFS= read -r alvo <"$QA/sentinela"
    for d in /proc/[0-9]*; do
      for f in cmdline environ; do
        [[ -r $d/$f ]] || continue
        partes=()
        mapfile -d '' partes <"$d/$f" 2>/dev/null || continue
        for p in ${partes[@]+"${partes[@]}"}; do
          [[ $p == *"$alvo"* ]] && { printf '%s %s\n' "$d" "$f" >>"$QA/varredura"; break; }
        done
      done
    done
    printf 'varrido %s\n' "$ep" >>"$QA/varrido"
  fi
  achou=nao n=0
  while IFS=$'\t' read -r rep rfi rco rar rvz; do
    n=$((n + 1))
    [[ -n $rep ]] || continue
    # shellcheck disable=SC2053
    [[ $ep == $rep && $pedido == $rfi ]] || continue
    if [[ $rvz == uma ]]; then
      [[ -e $QA/usada.$n ]] && continue
      : >"$QA/usada.$n"
    fi
    achou=sim cod=$rco corpo=''
    [[ -r $QA/resp/$rar ]] && IFS= read -r -d '' corpo <"$QA/resp/$rar"
    break
  done <"$QA/regras"
  [[ $achou == sim ]] || printf 'SEM_REGRA %s\n' "$ep" >>"$QA/chamadas"
fi
if [[ $cod == DORME ]]; then
  : >"$QA/em_voo"
  sleep 3
  cod=200
fi
if [[ $corpo == *@N@* ]]; then
  k=0
  [[ -r $QA/contador ]] && read -r k <"$QA/contador"
  k=$((k + 1))
  printf '%s\n' "$k" >"$QA/contador"
  corpo=${corpo//@N@/$k}
  fim=0
  [[ -r $QA/fim ]] && read -r fim <"$QA/fim"
  if ((fim > 0 && k >= fim)); then corpo=${corpo//@HM@/false}; else corpo=${corpo//@HM@/true}; fi
fi
[[ -n $o ]] && printf '%s' "$corpo" >"$o"
[[ -n $w ]] && printf '%s' "$cod"
exit 0
FIM
  } >"$B/bin/curl"
  chmod +x "$B/bin/curl"
}

# _qa_regra <endpoint> <filtro> <codigo> <corpo> [uma]
_qa_regra() {
  QA_N=$((QA_N + 1))
  printf '%s' "$4" >"$B/resp/r$QA_N"
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "r$QA_N" "${5:-}" >>"$B/regras"
}

# _qa_entrada <texto> — entrada padrao com os bytes exatos (printf %b).
_qa_entrada() { printf '%b' "$1" >"$B/entrada"; }

# _qa_rodar <argumentos...> — sem terminal, com teto de tempo; o codigo de
# saida e SEMPRE um de 0..15 (124 do teto = pendura, reprova).
_qa_rodar() {
  [[ -e $B/entrada ]] || : >"$B/entrada"
  env -i PATH="$B/bin:$PATH" HOME="$B" XDG_CONFIG_HOME="$B/cfg" XDG_STATE_HOME="$B/estado" \
    TMPDIR="$B/tmp" DBX_HTTP_TENTATIVAS_MAXIMAS=2 DBX_HTTP_ESPERA_BASE_MS=1 DBX_HTTP_ESPERA_TETO_MS=1 \
    ${QA_AMBIENTE[@]+"${QA_AMBIENTE[@]}"} \
    timeout -k 2 "${QA_TETO:-40}" "$QA_BASH" "$QA_DBX" "$@" <"$B/entrada" >"$B/out" 2>"$B/err"
  QA_ESTADO=$?
  _qa_ler_saidas
  if ((QA_ESTADO < 0 || QA_ESTADO > 15)); then
    _harness_falhar 'codigo de saida fora de 0..15 (124: pendurou)' "obtido: [$QA_ESTADO]" "argv: [$*]"
  fi
  return 0
}

# _qa_ler_saidas — stdout e stderr inteiros; NUL (modo --null) vira quebra
# de linha, para nenhum byte depois do primeiro NUL escapar das assercoes.
_qa_ler_saidas() {
  local pedaco
  local -a pedacos=()
  QA_SAIDA='' QA_ERRO=''
  mapfile -d '' pedacos <"$B/out"
  for pedaco in ${pedacos[@]+"${pedacos[@]}"}; do QA_SAIDA+="${pedaco%$'\0'}"$'\n'; done
  mapfile -d '' pedacos <"$B/err"
  for pedaco in ${pedacos[@]+"${pedacos[@]}"}; do QA_ERRO+="${pedaco%$'\0'}"$'\n'; done
  return 0
}

_qa_estado() { # <esperado> <descricao>
  assert_igual "$1" "$QA_ESTADO" "$2 (stderr: ${QA_ERRO:0:300})"
}

# _qa_contar <trecho> — linhas de `chamadas` que contem o trecho, em QA_CONTAGEM.
_qa_contar() {
  local linha total=0
  if [[ -f $B/chamadas ]]; then
    while IFS= read -r linha || [[ -n $linha ]]; do
      [[ $linha == *"$1"* ]] && total=$((total + 1))
    done <"$B/chamadas"
  fi
  QA_CONTAGEM=$total
}

_qa_sem_chamada() { assert_arquivo_ausente "$B/chamadas" "nenhuma chamada, nem renovacao: $1"; }

_qa_zero_revogacao() {
  _qa_contar sharing/revoke_shared_link
  assert_igual 0 "$QA_CONTAGEM" "zero revoke_shared_link: $1"
}

# _qa_ler <arquivo> — conteudo inteiro em QA_TEXTO (vazio se ausente).
_qa_ler() {
  QA_TEXTO=''
  [[ -r $1 ]] && IFS= read -r -d '' QA_TEXTO <"$1"
  return 0
}

# _qa_tmp_vazio <descricao> — nada sobrou no TMPDIR privado.
_qa_tmp_vazio() {
  local entrada lista=''
  for entrada in "$B"/tmp/* "$B"/tmp/.[!.]*; do
    [[ -e $entrada ]] && lista+=" ${entrada##*/}"
  done
  assert_igual '' "$lista" "TMPDIR vazio: $1"
}

# _qa_senha_em_disco <diretorio> — 0 quando algum arquivo sob o diretorio
# contem o sentinela da senha; o caminho fica em QA_TEXTO.
_qa_senha_em_disco() {
  local arquivo conteudo
  QA_TEXTO=''
  while IFS= read -r -d '' arquivo; do
    conteudo=''
    IFS= read -r -d '' conteudo <"$arquivo"
    if [[ $conteudo == *"$QA_SENHA"* ]]; then
      QA_TEXTO=$arquivo
      return 0
    fi
  done < <(find "$1" -type f -print0 2>/dev/null)
  return 1
}

# _qa_senha_ausente_de_tudo <descricao> — stdout, stderr, argv, `-K -`,
# varredura de /proc, TMPDIR, estado e configuracao.
_qa_senha_ausente_de_tudo() {
  assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA" "stdout sem a senha: $1"
  assert_segredo_ausente "$QA_SENHA" "$QA_ERRO" "stderr sem a senha: $1"
  _qa_ler "$B/argv"
  assert_segredo_ausente "$QA_SENHA" "$QA_TEXTO" "argv do curl sem a senha: $1"
  _qa_ler "$B/conf"
  assert_segredo_ausente "$QA_SENHA" "$QA_TEXTO" "configuracao -K - sem a senha: $1"
  assert_arquivo_ausente "$B/varredura" "nenhum cmdline/environ de /proc com a senha: $1"
  local d
  for d in tmp estado cfg; do
    if _qa_senha_em_disco "$B/$d"; then
      _harness_falhar "senha em disco depois da execucao: $1" "arquivo: [$QA_TEXTO]"
    fi
  done
  return 0
}

# _qa_link <id> <path_lower> <visibilidade> <require_password> [expires]
_qa_link() {
  local extra=''
  [[ -n ${5:-} ]] && extra=",\"expires\":\"$5\""
  printf -v QA_LINK '{".tag":"file","url":"https://www.dropbox.com/scl/fi/%s/a?rlkey=k","name":"a","path_lower":"%s","link_permissions":{"resolved_visibility":{".tag":"%s"},"require_password":%s}%s}' \
    "$1" "$2" "$3" "$4" "$extra"
}

# _qa_sinal <SINAL> <argumentos...> — roda o dbx em sessao propria (python,
# sinais com a disposicao padrao), espera `$B/em_voo` e manda o sinal ao grupo.
_qa_sinal() {
  local sinal=$1
  shift
  command -v python3 >/dev/null 2>&1 || pular 'python3 ausente: sem como sinalizar o grupo'
  python3 -I - "$B" "$QA_DBX" "$sinal" "$@" <<'PY' >"$B/sinal_rc" 2>&1
import os, signal, subprocess, sys, time
b, dbx, sinal = sys.argv[1:4]
env = {"PATH": b + "/bin:" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME": b,
       "XDG_CONFIG_HOME": b + "/cfg", "XDG_STATE_HOME": b + "/estado", "TMPDIR": b + "/tmp",
       "DBX_HTTP_TENTATIVAS_MAXIMAS": "1"}
p = subprocess.Popen(["bash", dbx] + sys.argv[4:], stdin=open(b + "/entrada", "rb"),
                     stdout=open(b + "/out", "wb"), stderr=open(b + "/err", "wb"),
                     env=env, start_new_session=True)
for _ in range(200):
    if os.path.exists(b + "/em_voo"):
        break
    time.sleep(0.05)
time.sleep(0.3)
os.killpg(p.pid, getattr(signal, "SIG" + sinal))
rc = p.wait()
time.sleep(0.2)
print(rc if rc >= 0 else 128 - rc)
PY
  QA_ESTADO=''
  IFS= read -r QA_ESTADO <"$B/sinal_rc"
  _qa_ler_saidas
}

# _qa_tty <argumentos...> — terminal real (pty por python). As respostas vem
# de `$B/tty_respostas` (uma por linha; nunca por argv), escritas so depois da
# pergunta e com o eco ja medido. Ao fim do dbx, `stty -a` mostra o eco.
# Transcricao em QA_SAIDA, codigo em QA_ESTADO; `$B/tty_eco` recebe `eco=0|1`
# medido no instante de cada resposta.
_qa_tty() {
  command -v python3 >/dev/null 2>&1 || pular 'python3 ausente: sem pseudo-terminal'
  python3 -I - "$B" "$QA_DBX" "$@" <<'PY' >"$B/tty_rc" 2>&1
import os, pty, select, sys, termios, time
b, dbx = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
respostas = open(b + "/tty_respostas", "rb").read().split(b"\n")[:-1]
env = {"PATH": b + "/bin:" + os.environ.get("PATH", "/usr/bin:/bin"), "HOME": b,
       "XDG_CONFIG_HOME": b + "/cfg", "XDG_STATE_HOME": b + "/estado", "TMPDIR": b + "/tmp",
       "DBX_HTTP_TENTATIVAS_MAXIMAS": "1", "TERM": "dumb"}
pid, fd = pty.fork()
if pid == 0:
    os.execve("/bin/sh", ["sh", "-c", 'bash "$0" "$@"; e=$?; printf "\\nESTADO=%s\\n" "$e"; stty -a; exit $e', dbx] + args, env)
texto = b""
i = 0
fim = time.time() + 30
ecos = []
perguntas = (b"senha do link: ", b"confirme a senha: ")
while time.time() < fim:
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try:
            dado = os.read(fd, 4096)
        except OSError:
            break
        if not dado:
            break
        texto += dado
    vistas = sum(texto.count(p) for p in perguntas)
    if vistas > i and i < len(respostas):
        time.sleep(0.3)
        ecos.append("eco=%d" % (1 if termios.tcgetattr(fd)[3] & termios.ECHO else 0))
        os.write(fd, respostas[i] + b"\n")
        i += 1
try:
    if os.waitpid(pid, os.WNOHANG) == (0, 0):
        os.kill(pid, 9)
        os.waitpid(pid, 0)
except ChildProcessError:
    pass
open(b + "/tty_out", "wb").write(texto)
open(b + "/tty_eco", "w").write(" ".join(ecos))
PY
  QA_SAIDA=''
  IFS= read -r -d '' QA_SAIDA <"$B/tty_out"
  QA_ESTADO=''
  [[ $QA_SAIDA =~ ESTADO=([0-9]+) ]] && QA_ESTADO=${BASH_REMATCH[1]}
  return 0
}

# ===========================================================================
# P0-1: a senha (RF-86, RSK-58)
# ===========================================================================

# QA-B5-S01 — --senha-stdin com sentinela, em texto, --null, --json e --debug:
# a senha chega SO ao corpo da chamada; nenhum processo a tem em argv ou
# ambiente durante a chamada (varredura de /proc pelo duplo); `-K -`, saidas,
# TMPDIR, estado e configuracao limpos. DBX_SENHA/DBX_PASSWORD no ambiente
# nao viram senha.
teste_qa_s01_senha_so_no_corpo_em_todo_modo() {
  local modo
  for modo in '' --null --json --debug; do
    _qa_cenario /r
    printf '%s\n' "$QA_SENHA" >"$B/sentinela"
    _qa_link 1 /r/a.txt password true
    _qa_regra sharing/create_shared_link_with_settings '*' 200 "$QA_LINK"
    _qa_entrada "$QA_SENHA\n"
    QA_AMBIENTE=(DBX_SENHA=ambiente_nao DBX_PASSWORD=ambiente_nao2)
    _qa_rodar ${modo:+"$modo"} compartilhar --senha-stdin /r/a.txt
    _qa_estado 0 "criado [$modo]"
    assert_arquivo_existe "$B/varrido" "a varredura de /proc rodou durante a chamada [$modo]"
    _qa_contar "\"link_password\":\"$QA_SENHA\""
    assert_igual 1 "$QA_CONTAGEM" "a senha da entrada, e so ela, vai no corpo [$modo]"
    _qa_contar 'ambiente_nao'
    assert_igual 0 "$QA_CONTAGEM" "variavel de ambiente nunca vira senha [$modo]"
    _qa_senha_ausente_de_tudo "modo [$modo]"
    _qa_tmp_vazio "modo [$modo]"
    assert_contem 'senha=sim' "$QA_SAIDA" "saida diz senha sim, sem o valor [$modo]"
  done
}

# QA-B5-S02 — o mesmo na MODIFICACAO de link existente (DIV-108: senha pedida
# sempre modifica) e no --dry-run (que nao le a senha: zero escrita).
teste_qa_s02_senha_na_modificacao_e_dry_run() {
  _qa_cenario /r
  printf '%s\n' "$QA_SENHA" >"$B/sentinela"
  _qa_link 1 /r/a.txt public false
  _qa_regra sharing/create_shared_link_with_settings '*' 409 "$QA_EXISTE"
  _qa_regra sharing/list_shared_links '*' 200 "{\"links\":[$QA_LINK],\"has_more\":false}"
  _qa_link 1 /r/a.txt password true
  _qa_regra sharing/modify_shared_link_settings '*' 200 "$QA_LINK"
  _qa_entrada "$QA_SENHA\n"
  _qa_rodar compartilhar --senha-stdin /r/a.txt
  _qa_estado 0 'modificado'
  _qa_contar "sharing/modify_shared_link_settings	{\"url\":\"https://www.dropbox.com/scl/fi/1/a?rlkey=k\",\"settings\":{\"audience\":\"public\",\"require_password\":true,\"link_password\":\"$QA_SENHA\"}}"
  assert_igual 1 "$QA_CONTAGEM" 'modify com a senha, no link listado'
  _qa_senha_ausente_de_tudo 'modificacao'
  _qa_tmp_vazio 'modificacao'

  _qa_cenario /r
  _qa_link 1 /r/a.txt public false
  _qa_regra sharing/list_shared_links '*' 200 "{\"links\":[$QA_LINK],\"has_more\":false}"
  _qa_entrada "$QA_SENHA\n"
  _qa_rodar --dry-run compartilhar --senha-stdin /r/a.txt
  _qa_estado 0 'dry-run'
  _qa_contar "$QA_SENHA"
  assert_igual 0 "$QA_CONTAGEM" 'dry-run nao le nem envia a senha'
  _qa_contar _settings
  assert_igual 0 "$QA_CONTAGEM" 'dry-run: nenhuma escrita (create/modify)'
  assert_contem 'situacao=modificaria' "$QA_SAIDA" 'plano'
  assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA$QA_ERRO" 'dry-run sem a senha'
}

# QA-B5-S03 — erro do servico que ECOA a senha sob a chave `link_password`
# (DIV-111): corpo JSON e corpo texto de 400 passam pela redacao.
teste_qa_s03_eco_de_link_password_no_erro_e_redigido() {
  local corpo
  for corpo in \
    "Error in call to API function \"sharing/create_shared_link_with_settings\": request body: settings.link_password: '@S@' is invalid" \
    "link_password=@S@" \
    "{\"error\":{\"link_password\":\"@S@\"},\"detalhe\":\"x\"}"; do
    _qa_cenario /r
    _qa_regra sharing/create_shared_link_with_settings '*' 400 "${corpo//@S@/$QA_SENHA}"
    _qa_entrada "$QA_SENHA\n"
    _qa_rodar --debug compartilhar --senha-stdin /r/a.txt
    assert_diferente 0 "$QA_ESTADO" 'recusa'
    _qa_senha_ausente_de_tudo "eco com chave [${corpo:0:30}]"
    _qa_tmp_vazio 'eco'
  done
}

# QA-B5-S04 — ACHADO QA-B5-02: `error_summary` (JSON) que contem a senha crua
# vai para stderr sem redacao (`_dbx_http_interpretar_erro` so redige o corpo
# NAO JSON). RF-86(f): "mensagens de erro nunca trazem a senha".
teste_qa_s04_error_summary_com_a_senha_nao_vaza() {
  _qa_cenario /r
  _qa_regra sharing/create_shared_link_with_settings '*' 409 \
    "{\"error_summary\":\"settings_error/other/$QA_SENHA/..\",\"error\":{\".tag\":\"settings_error\"}}"
  _qa_entrada "$QA_SENHA\n"
  _qa_rodar compartilhar --senha-stdin /r/a.txt
  assert_diferente 0 "$QA_ESTADO" 'recusa'
  assert_segredo_ausente "$QA_SENHA" "$QA_ERRO" 'error_summary com a senha nao chega ao stderr'
  assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA" 'nem ao stdout'
}

# QA-B5-S05 — TERM, INT e HUP durante a chamada: 14, TMPDIR vazio, senha em
# lugar nenhum do disco.
teste_qa_s05_sinal_durante_a_chamada_limpa_tudo() {
  local sinal
  for sinal in TERM INT HUP; do
    _qa_cenario /r
    _qa_regra sharing/create_shared_link_with_settings '*' DORME '{}'
    _qa_entrada "$QA_SENHA\n"
    _qa_sinal "$sinal" compartilhar --senha-stdin /r/a.txt
    assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" "$sinal durante a chamada sai 14"
    _qa_tmp_vazio "$sinal"
    if _qa_senha_em_disco "$B/tmp" || _qa_senha_em_disco "$B/estado"; then
      _harness_falhar "senha em disco depois de $sinal" "[$QA_TEXTO]"
    fi
    assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA$QA_ERRO" "$sinal: saidas sem a senha"
  done
}

# QA-B5-S06 — SIGKILL nao tem tratador: o que sobra com a senha so pode estar
# dentro de diretorio 0700 do proprio usuario, criado por lib/tmp (RF-86(e)).
teste_qa_s06_sigkill_deixa_a_senha_so_em_diretorio_privado() {
  local modo dono eu
  _qa_cenario /r
  _qa_regra sharing/create_shared_link_with_settings '*' DORME '{}'
  _qa_entrada "$QA_SENHA\n"
  _qa_sinal KILL compartilhar --senha-stdin /r/a.txt
  assert_igual 137 "$QA_ESTADO" 'morto por SIGKILL'
  _qa_senha_em_disco "$B/estado" && _harness_falhar 'senha no estado' "[$QA_TEXTO]"
  _qa_senha_em_disco "$B/cfg" && _harness_falhar 'senha na configuracao' "[$QA_TEXTO]"
  if _qa_senha_em_disco "$B/tmp"; then
    IFS=' ' read -r modo dono < <(stat -c '%a %u' -- "${QA_TEXTO%/*}")
    IFS= read -r eu < <(id -u)
    assert_igual 700 "$modo" 'diretorio do resto e 0700'
    assert_igual "$eu" "$dono" 'diretorio do resto e do usuario'
    assert_igual "$B/tmp" "${QA_TEXTO%/*/*}" 'resto so na area de lib/tmp, um nivel abaixo do TMPDIR'
  fi
  return 0
}

# QA-B5-S07 — --senha no terminal: pergunta duas vezes, eco DESLIGADO no
# instante de cada resposta, nada ecoado, eco religado ao fim; a senha chega
# ao corpo. Divergente: 14, zero chamada `sharing/*`.
teste_qa_s07_terminal_sem_eco_e_confirmacao() {
  _qa_cenario /r
  _qa_link 1 /r/a.txt password true
  _qa_regra sharing/create_shared_link_with_settings '*' 200 "$QA_LINK"
  printf '%s\n%s\n' "$QA_SENHA" "$QA_SENHA" >"$B/tty_respostas"
  _qa_tty compartilhar --senha /r/a.txt
  assert_igual 0 "$QA_ESTADO" "criado pelo terminal (transcricao: ${QA_SAIDA:0:200})"
  _qa_ler "$B/tty_eco"
  assert_igual 'eco=0 eco=0' "$QA_TEXTO" 'eco desligado nas duas leituras'
  assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA" 'nada ecoado no terminal'
  assert_contem 'confirme a senha:' "$QA_SAIDA" 'confirmacao pedida'
  [[ $QA_SAIDA =~ [[:space:]]echo[[:space:]] ]] || _harness_falhar 'eco religado ao fim' "${QA_SAIDA: -400}"
  _qa_contar "\"link_password\":\"$QA_SENHA\""
  assert_igual 1 "$QA_CONTAGEM" 'a senha digitada vai no corpo'
  _qa_tmp_vazio 'terminal'

  _qa_cenario /r
  _qa_regra sharing/create_shared_link_with_settings '*' 200 '{}'
  printf '%s\n%sx\n' "$QA_SENHA" "$QA_SENHA" >"$B/tty_respostas"
  _qa_tty compartilhar --senha /r/a.txt
  assert_igual "$QA_NAO_CONCLUIDA" "$QA_ESTADO" 'confirmacao divergente sai 14'
  _qa_contar sharing/
  assert_igual 0 "$QA_CONTAGEM" 'divergente: zero chamada sharing'
  assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA" 'divergente: nada ecoado'
  [[ $QA_SAIDA =~ [[:space:]]echo[[:space:]] ]] || _harness_falhar 'eco religado depois da recusa' "${QA_SAIDA: -400}"
}

# QA-B5-S08 — --senha-stdin com a entrada em terminal: le SEM eco, UMA vez.
teste_qa_s08_senha_stdin_em_terminal_sem_eco_sem_confirmacao() {
  _qa_cenario /r
  _qa_link 1 /r/a.txt password true
  _qa_regra sharing/create_shared_link_with_settings '*' 200 "$QA_LINK"
  printf '%s\n' "$QA_SENHA" >"$B/tty_respostas"
  _qa_tty compartilhar --senha-stdin /r/a.txt
  assert_igual 0 "$QA_ESTADO" "criado (transcricao: ${QA_SAIDA:0:200})"
  _qa_ler "$B/tty_eco"
  assert_igual 'eco=0' "$QA_TEXTO" 'uma leitura, sem eco'
  assert_nao_contem 'confirme a senha:' "$QA_SAIDA" 'sem confirmacao'
  assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA" 'nada ecoado'
}

# QA-B5-S09 — validacao da senha ANTES da rede pela --senha-stdin: recusa 2
# sem NENHUMA chamada (nem renovacao) e sem citar a senha; os limites aceitos
# chegam intactos ao corpo.
teste_qa_s09_validacao_da_senha_antes_da_rede() {
  local entrada longa=''
  printf -v longa '%*s' 1025 ''
  longa=${longa// /k}
  for entrada in '' '\n' '\n\n' 'abc\r\n' 'a\001b\n' 'a\tb\n' 'a\177b\n' \
    "${longa}\n" 'a\377b\n' 'a\300\257b\n' 'a\355\240\200b\n' 'a\303\n'; do
    _qa_cenario /r
    _qa_regra sharing/create_shared_link_with_settings '*' 200 '{}'
    _qa_entrada "$entrada"
    _qa_rodar compartilhar --senha-stdin /r/a.txt
    _qa_estado "$QA_USO" "senha recusada [${entrada:0:24}]"
    _qa_sem_chamada "senha recusada [${entrada:0:24}]"
    [[ ${#entrada} -gt 4 ]] && assert_nao_contem "${entrada:0:4}" "$QA_ERRO" 'o motivo nao cita a senha'
  done
  # Aceitas: sem quebra final, varias linhas (so a primeira), 1024 bytes, UTF-8.
  local -a aceitas=("${QA_SENHA}" "${QA_SENHA}\nSEGUNDA_LINHA_QA\n" "${longa:1}\n" 'ção€😀\n')
  local -a esperadas=("$QA_SENHA" "$QA_SENHA" "${longa:1}" 'ção€😀')
  local i
  for i in 0 1 2 3; do
    _qa_cenario /r
    _qa_link 1 /r/a.txt password true
    _qa_regra sharing/create_shared_link_with_settings '*' 200 "$QA_LINK"
    _qa_entrada "${aceitas[i]}"
    _qa_rodar compartilhar --senha-stdin /r/a.txt
    _qa_estado 0 "senha aceita [$i]"
    _qa_contar "\"link_password\":\"${esperadas[i]}\"}"
    assert_igual 1 "$QA_CONTAGEM" "corpo com a senha exata [$i]"
    _qa_contar SEGUNDA_LINHA_QA
    assert_igual 0 "$QA_CONTAGEM" "a segunda linha nunca e lida [$i]"
  done
}

# QA-B5-S10 — formas com valor e posicional excedente: 2, sem citar o valor,
# sem chamada.
teste_qa_s10_senha_na_linha_de_comando_recusada_sem_citar() {
  local -a args
  local forma
  for forma in "--senha=$QA_SENHA" "--senha-stdin=$QA_SENHA" "--password=$QA_SENHA" \
    "--password-stdin=$QA_SENHA" "--publico=$QA_SENHA" "--qualquer=$QA_SENHA"; do
    _qa_cenario /r
    _qa_rodar compartilhar "$forma" /r/a.txt
    _qa_estado "$QA_USO" "forma com valor [${forma%%=*}]"
    _qa_sem_chamada "forma com valor [${forma%%=*}]"
    assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA$QA_ERRO" "valor nao citado [${forma%%=*}]"
  done
  for args in "/r/a.txt --senha-stdin $QA_SENHA" "--publico /r/a.txt $QA_SENHA" "--listar /r $QA_SENHA"; do
    _qa_cenario /r
    # shellcheck disable=SC2086
    _qa_rodar compartilhar $args
    _qa_estado "$QA_USO" 'posicional excedente'
    _qa_sem_chamada 'posicional excedente'
    assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA$QA_ERRO" 'excedente nao citado'
  done
}

# ===========================================================================
# P0-2: --revogar confinado (RF-89, RSK-59)
# ===========================================================================

# QA-B5-R01 — metadados hostis de `get_shared_link_metadata` com raiz /r:
# nenhum revoga. Ausente, nulo, chave repetida nas duas ordens, `..`, prefixo
# enganoso, relativo, vazio, nao texto, quebra de linha, \u0000, documento
# lixo, raiz do documento em arranjo, path_lower aninhado.
teste_qa_r01_metadados_hostis_nunca_revogam() {
  local esperado corpo
  while IFS=$'\t' read -r esperado corpo; do
    [[ -n $esperado ]] || continue
    _qa_cenario /r
    _qa_regra sharing/get_shared_link_metadata '*' 200 "$corpo"
    _qa_regra sharing/revoke_shared_link '*' 200 '{}'
    _qa_rodar compartilhar --revogar "$QA_URL"
    _qa_estado "$esperado" "metadados [$corpo]"
    _qa_zero_revogacao "metadados [$corpo]"
    _qa_contar sharing/get_shared_link_metadata
    assert_igual 1 "$QA_CONTAGEM" "a guarda consultou o link [$corpo]"
  done <<FIM
$QA_RECUSADO	{".tag":"file","url":"$QA_URL","name":"x"}
$QA_RECUSADO	{".tag":"file","url":"$QA_URL","path_lower":null}
$QA_REMOTO	{".tag":"file","path_lower":"/r/x","path_lower":"/fora/x"}
$QA_REMOTO	{".tag":"file","path_lower":"/fora/x","path_lower":"/r/x"}
$QA_RECUSADO	{".tag":"file","path_lower":"/r/../fora/x"}
$QA_RECUSADO	{".tag":"file","path_lower":"/r/.."}
$QA_RECUSADO	{".tag":"file","path_lower":"/r-x/y"}
$QA_RECUSADO	{".tag":"file","path_lower":"/rx"}
$QA_RECUSADO	{".tag":"file","path_lower":"/r\\nx/../../fora"}
$QA_RECUSADO	{".tag":"file","path_lower":"r/x"}
$QA_RECUSADO	{".tag":"file","path_lower":"/"}
$QA_RECUSADO	{".tag":"file","path_lower":"/fora/r/x"}
$QA_REMOTO	{".tag":"file","path_lower":"/r\\u0000/../fora"}
$QA_REMOTO	{".tag":"file","path_lower":""}
$QA_REMOTO	{".tag":"file","path_lower":123}
$QA_REMOTO	{".tag":"file","path_lower":["/r/x"]}
$QA_REMOTO	{".tag":"file","path_lower":{"p":"/r/x"}}
$QA_REMOTO	{".tag":"file","path_lower":"/r/x"} lixo
$QA_RECUSADO	[{"path_lower":"/r/x"}]
$QA_RECUSADO	{"metadata":{"path_lower":"/r/x"}}
FIM
  # Controle positivo: dentro da raiz revoga UMA vez, com a URL do operador.
  _qa_cenario /r
  _qa_regra sharing/get_shared_link_metadata '*' 200 \
    '{".tag":"file","url":"https://www.dropbox.com/s/OUTRO/y","path_lower":"/r/x"}'
  _qa_regra sharing/revoke_shared_link '*' 200 '{}'
  _qa_rodar compartilhar --revogar "$QA_URL"
  _qa_estado 0 'dentro da raiz revoga'
  _qa_contar "sharing/revoke_shared_link	{\"url\":\"$QA_URL\"}"
  assert_igual 1 "$QA_CONTAGEM" 'revoga a URL do operador, nunca a da resposta'
  _qa_contar OUTRO
  assert_igual 0 "$QA_CONTAGEM" 'a url da resposta nunca e usada'
}

# QA-B5-R02 — raiz `/`: path_lower ausente ou nulo continua 13 (DIV-114).
# Raiz com Unicode: caixa fora do ASCII diferente falha fechada (DIV-118);
# caixa ASCII diferente e a propria raiz sao dentro.
teste_qa_r02_raiz_barra_e_unicode() {
  local corpo
  for corpo in '{".tag":"file"}' '{".tag":"file","path_lower":null}'; do
    _qa_cenario /
    _qa_regra sharing/get_shared_link_metadata '*' 200 "$corpo"
    _qa_regra sharing/revoke_shared_link '*' 200 '{}'
    _qa_rodar compartilhar --revogar "$QA_URL"
    _qa_estado "$QA_RECUSADO" "raiz / com [$corpo]"
    _qa_zero_revogacao "raiz / com [$corpo]"
  done
  _qa_cenario '/Ção'
  _qa_regra sharing/get_shared_link_metadata '*' 200 '{"path_lower":"/ção/x"}'
  _qa_regra sharing/revoke_shared_link '*' 200 '{}'
  _qa_rodar compartilhar --revogar "$QA_URL"
  _qa_estado "$QA_RECUSADO" 'caixa fora do ASCII: falha fechada'
  _qa_zero_revogacao 'caixa fora do ASCII'
  local raiz pl
  while IFS=$'\t' read -r raiz pl; do
    _qa_cenario "$raiz"
    _qa_regra sharing/get_shared_link_metadata '*' 200 "{\"path_lower\":\"$pl\"}"
    _qa_regra sharing/revoke_shared_link '*' 200 '{}'
    _qa_rodar compartilhar --revogar "$QA_URL"
    _qa_estado 0 "dentro [$raiz] [$pl]"
    _qa_contar sharing/revoke_shared_link
    assert_igual 1 "$QA_CONTAGEM" "revoga [$raiz] [$pl]"
  done <<'FIM'
/Ção	/Ção/x
/R	/r/x
/	/qualquer/x
FIM
}

# QA-B5-R03 — URLs hostis: 2 antes de qualquer rede (nem renovacao).
teste_qa_r03_urls_hostis_recusadas_antes_da_rede() {
  local url gigante
  printf -v gigante '%*s' 2100 ''
  gigante="https://www.dropbox.com/s/${gigante// /a}"
  while IFS= read -r url; do
    [[ $url == '#'* ]] && continue
    url=${url//@NL@/$'\n'}
    url=${url//@CR@/$'\r'}
    url=${url//@TAB@/$'\t'}
    _qa_cenario /r
    _qa_rodar compartilhar --revogar "$url"
    _qa_estado "$QA_USO" "url hostil [$url]"
    _qa_sem_chamada "url hostil [$url]"
  done <<FIM
http://www.dropbox.com/s/abc/x
https://evil.example/s/abc/x
https://www.dropbox.com.evil.example/s/abc/x
https://evil.example#@www.dropbox.com/s/abc
https://user:pw@www.dropbox.com/s/abc/x
https://www.dropbox.com@evil.example/s/abc/x
https://www.dropbox.com:8443/s/abc/x
https://www.dropbox.com/s/abc/x@NL@https://evil.example/s/y
https://www.dropbox.com/s/abc/x@CR@
https://www.dropbox.com/s/abc@TAB@x
https://www.dropbox.com/s/abc x
https://www.dropbox.com/home/abc
https://www.dropbox.com/s/
https://dl.dropboxusercontent.com/apitl/1/abc
ftp://www.dropbox.com/s/abc
//www.dropbox.com/s/abc
/s/abc
$gigante
FIM
  _qa_cenario /r
  _qa_rodar compartilhar --revogar ''
  _qa_estado "$QA_USO" 'url vazia'
  _qa_sem_chamada 'url vazia'
}

# QA-B5-R04 — retentativa (DIV-119/127): a guarda repetida por 5xx continua
# decidindo; 5xx seguido de fora da raiz nao revoga; a revogacao repetida que
# recebe `shared_link_not_found` sai 4; `--dry-run` executa a guarda e nao
# revoga; consulta recusada pelo servico nao revoga.
teste_qa_r04_retentativa_e_dry_run_da_revogacao() {
  _qa_cenario /r
  _qa_regra sharing/get_shared_link_metadata '*' 500 '{"error_summary":"internal/"}' uma
  _qa_regra sharing/get_shared_link_metadata '*' 200 '{"path_lower":"/fora/x"}'
  _qa_regra sharing/revoke_shared_link '*' 200 '{}'
  _qa_rodar compartilhar --revogar "$QA_URL"
  _qa_estado "$QA_RECUSADO" '5xx e depois fora da raiz'
  _qa_zero_revogacao '5xx e depois fora'

  _qa_cenario /r
  _qa_regra sharing/get_shared_link_metadata '*' 200 '{"path_lower":"/r/x"}'
  _qa_regra sharing/revoke_shared_link '*' 500 '{"error_summary":"internal/"}' uma
  _qa_regra sharing/revoke_shared_link '*' 409 \
    '{"error_summary":"shared_link_not_found/","error":{".tag":"shared_link_not_found"}}'
  _qa_rodar compartilhar --revogar "$QA_URL"
  _qa_estado "$QA_NAO_ENC" 'resposta perdida: a repeticao acha o link ja revogado'
  _qa_contar sharing/revoke_shared_link
  assert_igual 2 "$QA_CONTAGEM" 'uma repeticao da revogacao'
  _qa_contar sharing/get_shared_link_metadata
  assert_igual 1 "$QA_CONTAGEM" 'a guarda nao precisa repetir'

  _qa_cenario /r
  _qa_regra sharing/get_shared_link_metadata '*' 200 '{"path_lower":"/r/x"}'
  _qa_regra sharing/revoke_shared_link '*' 200 '{}'
  _qa_rodar --dry-run compartilhar --revogar "$QA_URL"
  _qa_estado 0 'dry-run dentro'
  _qa_zero_revogacao 'dry-run'
  assert_contem 'resultado=revogaria' "$QA_SAIDA" 'plano'

  _qa_cenario /r
  _qa_regra sharing/get_shared_link_metadata '*' 200 '{"path_lower":"/fora/x"}'
  _qa_rodar --dry-run compartilhar --revogar "$QA_URL"
  _qa_estado "$QA_RECUSADO" 'dry-run fora: a guarda tambem recusa'

  local resumo esperado
  while IFS=$'\t' read -r esperado resumo; do
    _qa_cenario /r
    _qa_regra sharing/get_shared_link_metadata '*' 409 "{\"error_summary\":\"$resumo\",\"error\":{\".tag\":\"x\"}}"
    _qa_regra sharing/revoke_shared_link '*' 200 '{}'
    _qa_rodar compartilhar --revogar "$QA_URL"
    _qa_estado "$esperado" "consulta recusada [$resumo]"
    _qa_zero_revogacao "consulta recusada [$resumo]"
  done <<FIM
$QA_NAO_ENC	shared_link_not_found/
$QA_PERM	shared_link_access_denied/
$QA_USO	unsupported_link_type/
FIM
}

# QA-B5-R05 — guarda SEM estado: listar antes (que viu o link dentro) nao
# autoriza a revogacao quando a guarda desta execucao diz fora; e arquivos
# plantados em XDG_STATE_HOME/XDG_CONFIG_HOME nao mudam nada.
teste_qa_r05_guarda_sem_estado() {
  _qa_cenario /r
  _qa_regra sharing/list_shared_links '*' 200 \
    "{\"links\":[{\".tag\":\"file\",\"url\":\"$QA_URL\",\"path_lower\":\"/r/x\"}],\"has_more\":false}"
  _qa_rodar compartilhar --listar
  _qa_estado 0 'listagem viu o link dentro'
  mkdir -p "$B/estado/dropbox_sync" "$B/estado/dbx"
  printf '%s\t/r/x\n' "$QA_URL" >"$B/estado/dropbox_sync/links"
  printf '%s\t/r/x\n' "$QA_URL" >"$B/estado/dbx/links"
  printf '%s\t/r/x\n' "$QA_URL" >"$B/cfg/dbx/links"
  _qa_regra sharing/get_shared_link_metadata '*' 200 '{".tag":"file"}'
  _qa_regra sharing/revoke_shared_link '*' 200 '{}'
  _qa_rodar compartilhar --revogar "$QA_URL"
  _qa_estado "$QA_RECUSADO" 'a guarda desta execucao decide'
  _qa_zero_revogacao 'estado anterior nao autoriza'
}

# ===========================================================================
# P0-3: visibilidade explicita (RF-85, RSK-57)
# ===========================================================================

# QA-B5-V01 — combinacoes invalidas: 2 sem NENHUMA chamada e sem ler a
# entrada (que traz a senha: nunca chega a lugar nenhum).
teste_qa_v01_combinacoes_invalidas_saem_2_sem_rede() {
  local linha
  local -a args
  while IFS= read -r linha; do
    [[ -n $linha ]] || continue
    read -r -a args <<<"$linha"
    _qa_cenario /r
    _qa_entrada "$QA_SENHA\n"
    _qa_rodar compartilhar "${args[@]}"
    _qa_estado "$QA_USO" "combinacao [$linha]"
    _qa_sem_chamada "combinacao [$linha]"
    assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA$QA_ERRO" "combinacao [$linha]"
  done <<'FIM'
/r/a.txt
--expira 7d /r/a.txt
--publico --equipe /r/a.txt
--public --team /r/a.txt
--equipe --senha-stdin /r/a.txt
--team --password-stdin /r/a.txt
--equipe --senha /r/a.txt
--senha --senha-stdin /r/a.txt
--listar --publico
--listar --equipe /r
--listar --senha-stdin
--listar --expira 1d
--revogar https://www.dropbox.com/s/abc --publico
--revogar https://www.dropbox.com/s/abc --senha-stdin
--revogar https://www.dropbox.com/s/abc --expira 1d
--listar --revogar https://www.dropbox.com/s/abc
--revogar https://www.dropbox.com/s/abc --revogar https://www.dropbox.com/s/def
--revogar https://www.dropbox.com/s/abc /r/a.txt
--publico
--publico /r/a.txt /r/b.txt
--publico r/a.txt
--publico --expira
--publico --expira ontem /r/a.txt
--publico --expira 0d /r/a.txt
--publico --expira 8761h /r/a.txt
--publico --expira 3651d /r/a.txt
--publico --expira 07d /r/a.txt
--publico --expira 2000-01-01 /r/a.txt
--publico --expira 2099-02-30 /r/a.txt
--publico --expira 2099-01-01T25:00:00Z /r/a.txt
--publico --expira 2099-01-01T00:00:00+03:00 /r/a.txt
--publico -- /r/a.txt
--publico -x /r/a.txt
FIM
}

# QA-B5-V02 — variaveis de ambiente nunca escolhem a visibilidade.
teste_qa_v02_ambiente_nao_escolhe_visibilidade() {
  _qa_cenario /r
  QA_AMBIENTE=(DBX_VISIBILIDADE=publico DBX_PUBLICO=1 DBX_COMPARTILHAR=--publico DBX_AUDIENCE=public)
  _qa_rodar compartilhar /r/a.txt
  _qa_estado "$QA_USO" 'sem flag, ambiente nao vale'
  _qa_sem_chamada 'sem flag'
}

# QA-B5-V03 — o corpo enviado corresponde exatamente ao pedido: --equipe nunca
# leva `audience public`; nenhum corpo leva `requested_visibility`; `expires`
# so com --expira; --publico com --senha vale --senha.
teste_qa_v03_corpo_corresponde_ao_pedido() {
  local -a args
  local esperado linha
  while IFS=$'\t' read -r linha esperado; do
    read -r -a args <<<"$linha"
    _qa_cenario /r
    _qa_link 1 /r/a.txt public false
    _qa_regra sharing/create_shared_link_with_settings '*' 200 "$QA_LINK"
    _qa_entrada "$QA_SENHA\n"
    _qa_rodar compartilhar "${args[@]}" /r/a.txt
    _qa_estado 0 "criar [$linha]"
    _qa_contar "sharing/create_shared_link_with_settings	{\"path\":\"/r/a.txt\",\"settings\":{$esperado}}"
    assert_igual 1 "$QA_CONTAGEM" "corpo exato [$linha]"
    _qa_contar requested_visibility
    assert_igual 0 "$QA_CONTAGEM" "sem campo depreciado [$linha]"
  done <<FIM
--equipe	"audience":"team","require_password":false
--team	"audience":"team","require_password":false
--publico	"audience":"public","require_password":false
--publico --senha-stdin	"audience":"public","require_password":true,"link_password":"$QA_SENHA"
--senha-stdin	"audience":"public","require_password":true,"link_password":"$QA_SENHA"
--equipe --expira 2099-01-01	"audience":"team","require_password":false,"expires":"2099-01-01T23:59:59Z"
--publico --expira 2099-06-30T12:00:00Z	"audience":"public","require_password":false,"expires":"2099-06-30T12:00:00Z"
FIM
}

# ===========================================================================
# P0-4: reuso e modificacao (RF-87)
# ===========================================================================

# _qa_existente <link_listado...> — create diz que existe, list devolve os links.
_qa_existente() {
  local itens='' item
  for item in "$@"; do itens+="${itens:+,}$item"; done
  _qa_regra sharing/create_shared_link_with_settings '*' 409 "$QA_EXISTE"
  _qa_regra sharing/list_shared_links '*' 200 "{\"links\":[$itens],\"has_more\":false}"
}

# QA-B5-X01 — sem diferenca, nenhuma escrita; publico existente NUNCA atende
# --equipe nem --senha (sempre modify com o pedido).
teste_qa_x01_reuso_so_quando_igual() {
  local antes pedido situacao
  while IFS=$'\t' read -r antes pedido situacao; do
    _qa_cenario /r
    read -r -a partes <<<"$antes"
    _qa_link 1 /r/a.txt "${partes[0]}" "${partes[1]}" "${partes[2]:-}"
    _qa_existente "$QA_LINK"
    _qa_link 1 /r/a.txt team_only false
    _qa_regra sharing/modify_shared_link_settings '*' 200 "$QA_LINK"
    _qa_entrada "$QA_SENHA\n"
    read -r -a partes <<<"$pedido"
    _qa_rodar compartilhar "${partes[@]}" /r/a.txt
    _qa_estado 0 "[$antes] pedido [$pedido]"
    _qa_contar sharing/modify_shared_link_settings
    if [[ $situacao == existente ]]; then
      assert_igual 0 "$QA_CONTAGEM" "igual: zero escrita [$antes] [$pedido]"
      assert_contem 'situacao=existente' "$QA_SAIDA" 'devolve o existente'
    else
      assert_igual 1 "$QA_CONTAGEM" "diferente: modify [$antes] [$pedido]"
      assert_contem 'situacao=modificado' "$QA_SAIDA" 'modificado'
      assert_contem 'antes_visibilidade=' "$QA_SAIDA" 'mostra o antes'
      assert_contem 'depois_visibilidade=' "$QA_SAIDA" 'mostra o depois'
    fi
    _qa_contar 'create_shared_link_with_settings'
    assert_igual 1 "$QA_CONTAGEM" "uma criacao so [$antes] [$pedido]"
  done <<'FIM'
public false	--publico	existente
team_only false	--equipe	existente
team_only false 2099-01-01T23:59:59Z	--equipe --expira 2099-01-01	existente
team_only false 2099-01-01T23:59:59Z	--equipe	existente
public false	--equipe	modificado
public false	--senha-stdin	modificado
public false	--publico --senha-stdin	modificado
password true	--senha-stdin	modificado
password true	--publico	modificado
public true	--publico	modificado
team_only true	--equipe	modificado
team_and_password true	--equipe	modificado
team_only false 2099-01-01T23:59:59Z	--equipe --expira 2099-01-02	modificado
public false	--publico --expira 2099-01-01	modificado
FIM
}

# QA-B5-X02 — ACHADO QA-B5-01: o `modify` responde 200 mas o link continua
# PUBLICO (politica que restringe, ou servico que ignora o pedido). Para
# --senha e --equipe o comando nao pode sair como se o pedido estivesse
# atendido: tem de trazer `visibilidade_pedida` e o aviso "o servico aplicou
# <resolvida> no lugar de <pedida>" (RF-85(i)), e nunca `senha_redefinida sim`
# com `senha nao`.
teste_qa_x02_publico_que_continua_publico_nao_atende_senha_nem_equipe() {
  local pedido esperada
  while IFS=$'\t' read -r pedido esperada; do
    _qa_cenario /r
    _qa_link 1 /r/a.txt public false
    _qa_existente "$QA_LINK"
    _qa_regra sharing/modify_shared_link_settings '*' 200 "$QA_LINK"
    _qa_entrada "$QA_SENHA\n"
    _qa_rodar compartilhar "$pedido" /r/a.txt
    assert_contem "visibilidade_pedida=$esperada" "$QA_SAIDA" "pedido [$pedido] nao atendido aparece na saida"
    assert_contem "no lugar de $esperada" "$QA_ERRO" "aviso em stderr [$pedido]"
    if [[ $QA_SAIDA == *'senha_redefinida=sim'* ]]; then
      assert_nao_contem $'\nsenha=nao' $'\n'"$QA_SAIDA" 'senha_redefinida sim com senha nao'
    fi
  done <<'FIM'
--senha-stdin	password
--equipe	team_only
FIM
}

# QA-B5-X03 — mais de um link (inclusive por caixa ASCII): 7, nada modificado;
# so link de ancestral ou de outro item: 10, nada modificado.
teste_qa_x03_varios_links_ou_nenhum_candidato() {
  local l1 l2
  _qa_cenario /r
  _qa_link 1 /r/a.txt public false
  l1=$QA_LINK
  _qa_link 2 /R/A.TXT team_only false
  l2=$QA_LINK
  _qa_existente "$l1" "$l2"
  _qa_regra sharing/modify_shared_link_settings '*' 200 "$l1"
  _qa_rodar compartilhar --equipe /r/a.txt
  _qa_estado "$QA_CONFLITO" 'dois links'
  _qa_contar sharing/modify_shared_link_settings
  assert_igual 0 "$QA_CONTAGEM" 'nada modificado com dois links'
  assert_contem 'scl/fi/1/' "$QA_ERRO" 'cita as urls'
  assert_contem 'scl/fi/2/' "$QA_ERRO" 'cita as urls'

  local outro
  for outro in /r /r/a.txt.bak /r/a /fora/a.txt; do
    _qa_cenario /r
    _qa_link 1 "$outro" public false
    _qa_existente "$QA_LINK"
    _qa_regra sharing/modify_shared_link_settings '*' 200 "$QA_LINK"
    _qa_rodar compartilhar --equipe /r/a.txt
    _qa_estado "$QA_REMOTO" "so link de [$outro]"
    _qa_contar sharing/modify_shared_link_settings
    assert_igual 0 "$QA_CONTAGEM" "nada modificado [$outro]"
  done
}

# QA-B5-X04 — dry-run sobre existente diferente: zero create e modify; e a
# retentativa da criacao que acha o link ja criado cai no reuso sem escrita.
teste_qa_x04_dry_run_e_retentativa_da_criacao() {
  _qa_cenario /r
  _qa_link 1 /r/a.txt public false
  _qa_regra sharing/list_shared_links '*' 200 "{\"links\":[$QA_LINK],\"has_more\":false}"
  _qa_rodar --dry-run compartilhar --equipe /r/a.txt
  _qa_estado 0 'dry-run'
  _qa_contar _settings
  assert_igual 0 "$QA_CONTAGEM" 'dry-run sem create/modify'
  assert_contem 'situacao=modificaria' "$QA_SAIDA" 'plano'

  _qa_cenario /r
  _qa_link 1 /r/a.txt team_only false
  _qa_regra sharing/create_shared_link_with_settings '*' 500 '{"error_summary":"internal/"}' uma
  _qa_existente "$QA_LINK"
  _qa_rodar compartilhar --equipe /r/a.txt
  _qa_estado 0 'resposta perdida e repeticao'
  assert_contem 'situacao=existente' "$QA_SAIDA" 'reusa o link que a primeira tentativa criou'
  _qa_contar sharing/modify_shared_link_settings
  assert_igual 0 "$QA_CONTAGEM" 'sem escrita extra'
}

# ===========================================================================
# P0-5: confinamento e paginacao hostil (RF-84, RF-85(f), RF-88)
# ===========================================================================

# QA-B5-L01 — listagem filtra fora da raiz, sem path_lower, prefixo enganoso e
# nao texto; a URL dos omitidos nunca sai; caixa ASCII diferente entra.
teste_qa_l01_listagem_filtra_fora_da_raiz() {
  local item pagina='' omitido
  _qa_cenario /r
  for item in \
    'dentro1	/r/a' 'dentro2	/R/B' 'dentro3	/r/sub/c' \
    'FORA1	/fora/a' 'FORA2	/r-x/a' 'FORA3	/rx' 'FORA4	/r/../fora' 'FORA5	r/a'; do
    pagina+="${pagina:+,}{\".tag\":\"file\",\"url\":\"https://www.dropbox.com/s/${item%%$'\t'*}/z\",\"path_lower\":\"${item#*$'\t'}\"}"
  done
  pagina+=',{".tag":"file","url":"https://www.dropbox.com/s/FORA6/z"}'
  pagina+=',{".tag":"file","url":"https://www.dropbox.com/s/FORA7/z","path_lower":null}'
  pagina+=',{".tag":"file","url":"https://www.dropbox.com/s/FORA8/z","path_lower":7}'
  _qa_regra sharing/list_shared_links '*' 200 "{\"links\":[$pagina],\"has_more\":false}"
  _qa_rodar compartilhar --listar
  _qa_estado 0 'listagem'
  for omitido in FORA1 FORA2 FORA3 FORA4 FORA5 FORA6 FORA7 FORA8; do
    assert_nao_contem "$omitido" "$QA_SAIDA$QA_ERRO" "url omitida nunca sai [$omitido]"
  done
  assert_contem 's/dentro1/' "$QA_SAIDA" 'dentro'
  assert_contem 's/dentro2/' "$QA_SAIDA" 'caixa ASCII'
  assert_contem 's/dentro3/' "$QA_SAIDA" 'descendente'
  assert_contem 'total=3' "$QA_SAIDA" 'total'
  assert_contem 'omitidos=8' "$QA_SAIDA" 'omitidos'
  _qa_contar 'sharing/list_shared_links	{}'
  assert_igual 1 "$QA_CONTAGEM" 'sem path no corpo'

  # Pasta pedida: so ela e descendentes por componente.
  _qa_rodar compartilhar --listar /r/sub
  _qa_estado 0 'listagem da pasta'
  assert_contem 's/dentro3/' "$QA_SAIDA" 'descendente da pasta'
  assert_nao_contem 's/dentro1/' "$QA_SAIDA" 'irmao fora da pasta'
  assert_contem 'total=1' "$QA_SAIDA" 'total da pasta'
}

# QA-B5-L02 — paginacao hostil: cursor repetido e has_more sem cursor saem 10
# sem laco, sem listar nada.
teste_qa_l02_paginacao_que_nao_avanca() {
  _qa_cenario /r
  _qa_regra sharing/list_shared_links '*' 200 \
    '{"links":[{".tag":"file","url":"https://www.dropbox.com/s/p1/z","path_lower":"/r/a"}],"has_more":true,"cursor":"MESMO"}'
  _qa_rodar compartilhar --listar
  _qa_estado "$QA_REMOTO" 'cursor repetido'
  _qa_contar sharing/list_shared_links
  assert_igual 2 "$QA_CONTAGEM" 'para na primeira repeticao'
  assert_nao_contem 's/p1/' "$QA_SAIDA" 'nada listado'

  _qa_cenario /r
  _qa_regra sharing/list_shared_links '*' 200 '{"links":[],"has_more":true}'
  _qa_rodar compartilhar --listar
  _qa_estado "$QA_REMOTO" 'has_more sem cursor'
  _qa_contar sharing/list_shared_links
  assert_igual 1 "$QA_CONTAGEM" 'uma pagina so'

  # Ciclo de dois cursores: A -> B -> A.
  _qa_cenario /r
  _qa_regra sharing/list_shared_links '{}' 200 '{"links":[],"has_more":true,"cursor":"A"}'
  _qa_regra sharing/list_shared_links '{"cursor":"A"}' 200 '{"links":[],"has_more":true,"cursor":"B"}'
  _qa_regra sharing/list_shared_links '{"cursor":"B"}' 200 '{"links":[],"has_more":true,"cursor":"A"}'
  _qa_rodar compartilhar --listar
  _qa_estado "$QA_REMOTO" 'ciclo de cursores'
}

# QA-B5-L03 — ACHADO QA-B5-03: `has_more` infinito com cursor sempre novo e
# pagina VAZIA (nao avanca: nenhum link). RF-88(b): "pagina que nao avanca:
# 10, sem laco". Hoje o laco nao termina (o teto de tempo do caso reprova).
teste_qa_l03_has_more_infinito_com_pagina_vazia_termina() {
  _qa_cenario /r
  _qa_regra sharing/list_shared_links '*' 200 '{"links":[],"has_more":true,"cursor":"c@N@"}'
  QA_TETO=20
  _qa_rodar compartilhar --listar
  _qa_estado "$QA_REMOTO" 'pagina vazia com has_more nao avanca'
}

# QA-B5-L04 — confinamento antes de qualquer rede nos tres modos e no
# link-temporario: fora da raiz, `..` acima dela, controle: 13 sem chamada;
# a raiz da conta (/) como alvo de criar e de link temporario e recusada.
teste_qa_l04_confinamento_antes_da_rede() {
  local alvo
  local caso
  for alvo in /fora/a.txt /r/../fora/a.txt /r-x/a.txt $'/r/a\n.txt' $'/r/a\r'; do
    for caso in 'compartilhar --publico' 'compartilhar --listar' 'link-temporario' 'temp-link' 'share --team'; do
      _qa_cenario /r
      _qa_entrada "$QA_SENHA\n"
      read -r -a args <<<"$caso"
      _qa_rodar "${args[@]}" "$alvo"
      _qa_estado "$QA_RECUSADO" "[$caso] [$alvo]"
      _qa_sem_chamada "[$caso] [$alvo]"
    done
    _qa_cenario /r
    _qa_entrada "$QA_SENHA\n"
    _qa_rodar compartilhar --senha-stdin "$alvo"
    _qa_estado "$QA_RECUSADO" "senha: confinamento antes da leitura [$alvo]"
    _qa_sem_chamada "senha [$alvo]"
  done
  for caso in 'compartilhar --publico' 'link-temporario'; do
    _qa_cenario /
    read -r -a args <<<"$caso"
    _qa_rodar "${args[@]}" /
    _qa_estado "$QA_USO" "[$caso] raiz da conta"
    _qa_sem_chamada "[$caso] raiz da conta"
  done
}

# QA-B5-L05 — link temporario: resposta fora da raiz, sem path_lower, com
# chave repetida ou documento lixo: 10 e o link NUNCA sai (stdout, stderr,
# --debug, --null); dentro, o link sai so no stdout. --dry-run nao gera link.
teste_qa_l05_link_temporario_confere_a_resposta() {
  local corpo modo
  local link='https://dl.dropboxusercontent.com/apitl/1/QA5LINKTEMP'
  for corpo in \
    "{\"metadata\":{\".tag\":\"file\",\"path_lower\":\"/fora/a\"},\"link\":\"$link\"}" \
    "{\"metadata\":{\".tag\":\"file\",\"path_lower\":\"/rx/a\"},\"link\":\"$link\"}" \
    "{\"metadata\":{\".tag\":\"file\"},\"link\":\"$link\"}" \
    "{\"metadata\":{\".tag\":\"file\",\"path_lower\":null},\"link\":\"$link\"}" \
    "{\"metadata\":{\".tag\":\"file\",\"path_lower\":\"/r/a\",\"path_lower\":\"/fora\"},\"link\":\"$link\"}" \
    "{\"metadata\":{\".tag\":\"file\",\"path_lower\":\"/r/a\"},\"link\":\"$link\",\"link\":\"x\"}" \
    "{\"path_lower\":\"/r/a\",\"link\":\"$link\"}" \
    "{\"metadata\":{\".tag\":\"file\",\"path_lower\":\"/r/a\"},\"link\":\"$link\"} lixo"; do
    for modo in '' --debug --null; do
      _qa_cenario /r
      _qa_regra files/get_temporary_link '*' 200 "$corpo"
      _qa_rodar ${modo:+"$modo"} link-temporario /r/a
      _qa_estado "$QA_REMOTO" "resposta hostil [$modo] [$corpo]"
      assert_nao_contem QA5LINKTEMP "$QA_SAIDA$QA_ERRO" "link nao sai [$modo] [$corpo]"
    done
  done
  _qa_cenario /r
  _qa_regra files/get_temporary_link '*' 200 \
    "{\"metadata\":{\".tag\":\"file\",\"name\":\"a\",\"path_lower\":\"/r/a\",\"path_display\":\"/r/a\"},\"link\":\"$link\"}"
  _qa_rodar --debug link-temporario /r/a
  _qa_estado 0 'dentro'
  assert_contem "link=$link" "$QA_SAIDA" 'link no stdout'
  assert_nao_contem QA5LINKTEMP "$QA_ERRO" 'nunca no stderr, nem com --debug'

  _qa_cenario /r
  _qa_regra files/get_metadata '*' 200 '{".tag":"file","name":"a","path_lower":"/r/a"}'
  _qa_regra files/get_temporary_link '*' 200 "{\"link\":\"$link\"}"
  _qa_rodar --dry-run link-temporario /r/a
  _qa_estado 0 'dry-run'
  _qa_contar files/get_temporary_link
  assert_igual 0 "$QA_CONTAGEM" 'dry-run nao gera o link'
}

# ===========================================================================
# P0-6: erros (RF-90)
# ===========================================================================

# QA-B5-E01 — mapeamento das recusas para 0..15 na criacao, na modificacao e
# no link temporario; restricao de plano sai 6 com a frase do DIV-122 intacta
# (sem [REDIGIDO]), inclusive com --debug.
teste_qa_e01_mapeamento_de_erros() {
  local esperado resumo rota args
  while IFS=$'\t' read -r rota esperado resumo args; do
    [[ -n $rota ]] || continue
    _qa_cenario /r
    _qa_regra "$rota" '*' 409 "{\"error_summary\":\"$resumo\",\"error\":{\".tag\":\"x\"}}"
    read -r -a partes <<<"$args"
    _qa_rodar --debug "${partes[@]}"
    _qa_estado "$esperado" "[$rota] [$resumo]"
  done <<FIM
sharing/create_shared_link_with_settings	$QA_PERM	settings_error/not_authorized/..	compartilhar --equipe /r/a
sharing/create_shared_link_with_settings	$QA_USO	settings_error/invalid_settings/..	compartilhar --equipe /r/a
sharing/create_shared_link_with_settings	$QA_AUT	missing_scope/..	compartilhar --equipe /r/a
sharing/create_shared_link_with_settings	$QA_PERM	email_not_verified/	compartilhar --equipe /r/a
sharing/create_shared_link_with_settings	$QA_PERM	access_denied/	compartilhar --equipe /r/a
sharing/create_shared_link_with_settings	$QA_NAO_ENC	path/not_found/..	compartilhar --equipe /r/a
sharing/create_shared_link_with_settings	$QA_PERM	banned_member/	compartilhar --equipe /r/a
sharing/create_shared_link_with_settings	$QA_USO	unsupported_parameter_field/	compartilhar --equipe /r/a
files/get_temporary_link	$QA_USO	path/not_file/..	link-temporario /r/a
files/get_temporary_link	$QA_USO	unsupported_file/	link-temporario /r/a
files/get_temporary_link	$QA_PERM	email_not_verified/	link-temporario /r/a
files/get_temporary_link	$QA_PERM	not_allowed/	link-temporario /r/a
files/get_temporary_link	$QA_NAO_ENC	path/not_found/	link-temporario /r/a
sharing/list_shared_links	$QA_AUT	missing_scope/	compartilhar --listar
FIM
  _qa_cenario /r
  _qa_regra sharing/create_shared_link_with_settings '*' 409 \
    '{"error_summary":"settings_error/not_authorized/","error":{".tag":"settings_error"}}'
  _qa_entrada "$QA_SENHA\n"
  _qa_rodar --debug compartilhar --senha-stdin --expira 7d /r/a
  _qa_estado "$QA_PERM" 'plano Basic sai 6'
  assert_contem 'no plano Basic, so link publico, sem senha e sem expiracao' "$QA_ERRO" 'frase intacta (DIV-122)'
  assert_nao_contem 'REDIGIDO' "$QA_ERRO" 'a redacao nao come a frase'
  assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA$QA_ERRO" 'plano: sem a senha'

  # Modificacao recusada por plano e corrida (link sumiu): 6 e 4, sem criar.
  _qa_cenario /r
  _qa_link 1 /r/a public false
  _qa_existente "$QA_LINK"
  _qa_regra sharing/modify_shared_link_settings '*' 409 \
    '{"error_summary":"settings_error/not_authorized/","error":{".tag":"settings_error"}}'
  _qa_rodar compartilhar --equipe /r/a
  _qa_estado "$QA_PERM" 'modify recusado por plano'
  _qa_cenario /r
  _qa_link 1 /r/a public false
  _qa_existente "$QA_LINK"
  _qa_regra sharing/modify_shared_link_settings '*' 409 \
    '{"error_summary":"shared_link_not_found/","error":{".tag":"shared_link_not_found"}}'
  _qa_rodar compartilhar --equipe /r/a
  _qa_estado "$QA_NAO_ENC" 'corrida: link sumiu'
  _qa_contar create_shared_link_with_settings
  assert_igual 1 "$QA_CONTAGEM" 'nenhum link novo na corrida'
}

# QA-B5-E02 — `link_password` e chave sensivel da redacao (DIV-111), em todas
# as formas; `password` sozinho continua.
teste_qa_e02_link_password_na_redacao() {
  local forma
  for forma in '{"link_password":"@S@"}' 'link_password=@S@' 'link_password: @S@' \
    '"link_password" : "@S@"' "settings.link_password: '@S@'" 'LINK_PASSWORD=@S@'; do
    dbx_errors_redigir "${forma//@S@/$QA_SENHA}" >/dev/null
    assert_segredo_ausente "$QA_SENHA" "$DBX_ERRORS_REDIGIDO" "redacao de [$forma]"
  done
}

# ===========================================================================
# Escopo (RF-91, RF-92, DIV-121)
# ===========================================================================

# QA-B5-D01 — a grafia `link_temporario` (nome do arquivo) nao aparece na
# ajuda, no autocompletar nem no README; os nomes documentados aparecem.
teste_qa_d01_grafia_do_arquivo_nao_documentada() {
  _qa_cenario /r
  _qa_rodar help
  assert_nao_contem link_temporario "$QA_SAIDA$QA_ERRO" 'ajuda geral'
  assert_contem link-temporario "$QA_SAIDA" 'ajuda geral cita link-temporario'
  assert_contem temp-link "$QA_SAIDA" 'ajuda geral cita temp-link'
  assert_contem compartilhar "$QA_SAIDA" 'ajuda geral cita compartilhar'
  local nome
  for nome in link-temporario temp-link compartilhar share; do
    _qa_rodar help "$nome"
    _qa_estado 0 "ajuda de $nome"
    assert_nao_contem link_temporario "$QA_SAIDA$QA_ERRO" "ajuda de $nome"
  done
  _qa_ler "$DBX_HARNESS_RAIZ/README.md"
  assert_nao_contem link_temporario "$QA_TEXTO" 'README'
  assert_contem 'link-temporario' "$QA_TEXTO" 'README cita o comando'
  # Autocompletar: o que o operador ve em <TAB>.
  local prefixo
  for prefixo in '' l link link_ t te s sh c; do
    env -i PATH="$PATH" "$QA_BASH" --norc -c '
      . "$1"
      COMP_WORDS=(dbx "$2"); COMP_CWORD=1
      _dbx_completar dbx "$2" dbx
      printf "%s\n" "${COMPREPLY[@]}"' _ "$DBX_HARNESS_RAIZ/completions/dbx.bash" "$prefixo" \
      >"$B/comp" 2>&1
    _qa_ler "$B/comp"
    assert_nao_contem link_temporario "$QA_TEXTO" "autocompletar [$prefixo]"
  done
  env -i PATH="$PATH" "$QA_BASH" --norc -c '
    . "$1"
    COMP_WORDS=(dbx l); COMP_CWORD=1
    _dbx_completar dbx l dbx
    printf "%s\n" "${COMPREPLY[@]}"' _ "$DBX_HARNESS_RAIZ/completions/dbx.bash" >"$B/comp" 2>&1
  _qa_ler "$B/comp"
  assert_contem link-temporario "$QA_TEXTO" 'autocompletar oferece link-temporario'
}

# QA-B5-D02 — diagnostico: escopos de compartilhamento na linha `escopos`,
# sem reprovar quando ausentes.
teste_qa_d02_diagnostico_escopos_de_compartilhamento() {
  local base='account_info.read files.metadata.read files.content.read files.content.write'
  _qa_cenario /r
  printf '{"access_token":"sl.t","token_type":"bearer","expires_in":14400,"scope":"%s"}' "$base" >"$B/token"
  _qa_regra '*' '*' 200 '{"used":1,"allocation":{".tag":"individual","allocated":1000},"result":"dbx"}'
  _qa_rodar diagnostico
  assert_contem 'opcional sharing.write ausente' "$QA_SAIDA" 'cita sharing.write ausente'
  assert_contem 'opcional sharing.read ausente' "$QA_SAIDA" 'cita sharing.read ausente'
  assert_nao_contem 'concedidos (dbx compartilhar' "$QA_SAIDA" 'nao diz concedidos sem os escopos'
  assert_nao_contem 'escopos=falha' "$QA_SAIDA" 'ausente nao reprova'
  local estado_sem=$QA_ESTADO
  printf '{"access_token":"sl.t","token_type":"bearer","expires_in":14400,"scope":"%s sharing.write sharing.read"}' \
    "$base" >"$B/token"
  _qa_rodar diagnostico
  assert_contem 'sharing.write e sharing.read concedidos' "$QA_SAIDA" 'concedidos'
  assert_igual "$estado_sem" "$QA_ESTADO" 'mesmo codigo com e sem'
}

# ===========================================================================
# Ciclo 2: ataque as correcoes de QA-B5-01..07
# ===========================================================================

# QA-B5-C01 — ACHADO QA-B5-08: a mascaracao pelo valor (QA-B5-02) roda ANTES
# da classificacao da recusa. Senha que e trecho do resumo do servico
# (`link`, `exists`, `not`, `_`) quebra o reuso (RF-87: vira 7 em vez de
# modificar), a mensagem do plano (DIV-122) e a corrida (RF-87(g)); e o
# `[REDIGIDO]` no meio de uma tag conhecida revela a senha pelo contexto.
teste_qa_c01_senha_trecho_da_tag_nao_muda_a_classificacao() {
  local s
  for s in link exists shared_link_already_exists _; do
    _qa_cenario /r
    _qa_link 1 /r/a.txt public false
    _qa_existente "$QA_LINK"
    _qa_link 1 /r/a.txt password true
    _qa_regra sharing/modify_shared_link_settings '*' 200 "$QA_LINK"
    _qa_entrada "$s\n"
    _qa_rodar compartilhar --senha-stdin /r/a.txt
    _qa_estado 0 "senha [$s] ainda reusa/modifica o link existente"
    _qa_contar sharing/modify_shared_link_settings
    assert_igual 1 "$QA_CONTAGEM" "senha [$s]: modify feito"
  done
  for s in not authorized; do
    _qa_cenario /r
    _qa_regra sharing/create_shared_link_with_settings '*' 409 \
      '{"error_summary":"settings_error/not_authorized/..","error":{".tag":"settings_error"}}'
    _qa_entrada "$s\n"
    _qa_rodar compartilhar --senha-stdin /r/a.txt
    _qa_estado "$QA_PERM" "plano com senha [$s]"
    assert_contem 'no plano Basic' "$QA_ERRO" "remedio do plano com senha [$s]"
    assert_nao_contem 'not_[REDIGIDO]' "$QA_ERRO" "o [REDIGIDO] na tag revela a senha [$s]"
    assert_nao_contem '[REDIGIDO]_authorized' "$QA_ERRO" "o [REDIGIDO] na tag revela a senha [$s]"
  done
  _qa_cenario /r
  _qa_link 1 /r/a.txt public false
  _qa_existente "$QA_LINK"
  _qa_regra sharing/modify_shared_link_settings '*' 409 \
    '{"error_summary":"shared_link_not_found/","error":{".tag":"shared_link_not_found"}}'
  _qa_entrada 'found\n'
  _qa_rodar compartilhar --senha-stdin /r/a.txt
  _qa_estado "$QA_NAO_ENC" 'corrida com senha [found]'
  assert_contem 'o link mudou durante a operacao' "$QA_ERRO" 'mensagem da corrida com senha [found]'
}

# QA-B5-C02 — a mascara pelo valor com metacaracteres do shell e do sed, nos
# corpos JSON e texto, com --debug: nada vaza e, com a senha no pedido, nenhum
# texto bruto do servico aparece (DIV-128): so o codigo HTTP e a mensagem do dbx.
teste_qa_c02_mascara_com_metacaracteres() {
  local s esc corpo
  for s in 'a*b?c[d]e\f&g/h' '*' '[x]' "x\\\\y" '&' 'p/q' 'ab"cd' 'x%sy' '$(id)' 'ç€😀z'; do
    esc=${s//\\/\\\\}
    esc=${esc//\"/\\\"}
    for corpo in "{\"error_summary\":\"other/x${esc}y/..\",\"error\":{\".tag\":\"other\"}}" "bad x${s}y here"; do
      _qa_cenario /r
      _qa_regra sharing/create_shared_link_with_settings '*' 409 "$corpo"
      printf '%s\n' "$s" >"$B/entrada"
      _qa_rodar --debug compartilhar --senha-stdin /r/a.txt
      assert_diferente 0 "$QA_ESTADO" "recusa [$s]"
      assert_segredo_ausente "$s" "$QA_SAIDA$QA_ERRO" "metacaractere [$s] mascarado"
      # DIV-128: com a senha no pedido, nenhum texto bruto do servico aparece;
      # so a mensagem do dbx, o codigo HTTP e a tag reconhecida.
      assert_nao_contem 'other/x' "$QA_SAIDA$QA_ERRO" "nenhum trecho do error_summary [$s]"
      assert_nao_contem 'bad x' "$QA_SAIDA$QA_ERRO" "nenhum trecho do corpo texto [$s]"
      assert_nao_contem ' here' "$QA_SAIDA$QA_ERRO" "nenhum trecho do corpo texto [$s]"
      assert_nao_contem 'y/..' "$QA_SAIDA$QA_ERRO" "nenhum trecho do error_summary [$s]"
      assert_contem 'codigo HTTP 409' "$QA_ERRO" "codigo HTTP citado [$s]"
      assert_contem 'criacao do link recusada' "$QA_ERRO" "mensagem propria do dbx [$s]"
    done
  done
}

# QA-B5-C03 — ACHADO QA-B5-09: a senha em PEDACOS. O corpo nao JSON e cortado
# em 120 bytes antes da mascara: o prefixo da senha sobra. E a senha na forma
# escapada do JSON (`\"`, `\\`) num corpo texto nao e reconhecida.
teste_qa_c03_senha_em_pedacos_nao_vaza() {
  local pre
  printf -v pre '%*s' 100 ''
  pre=${pre// /p}
  _qa_cenario /r
  _qa_regra sharing/create_shared_link_with_settings '*' 400 "$pre $QA_SENHA fim"
  _qa_entrada "$QA_SENHA\n"
  _qa_rodar compartilhar --senha-stdin /r/a.txt
  assert_segredo_ausente "${QA_SENHA:0:12}" "$QA_ERRO" 'prefixo da senha cortado em 120 bytes'
  _qa_cenario /r
  _qa_regra sharing/create_shared_link_with_settings '*' 400 'value "QA5\"Pe\\daco" invalid'
  printf '%s\n' 'QA5"Pe\daco' >"$B/entrada"
  _qa_rodar compartilhar --senha-stdin /r/a.txt
  assert_segredo_ausente 'Pe\\daco' "$QA_ERRO" 'senha na forma escapada do JSON'
}

# QA-B5-C04 — QA-B5-04: credencial embutida nunca e citada: `%40`, `@` dentro
# da senha, so usuario, `/` dentro da senha (ACHADO QA-B5-11: o host e
# cortado no primeiro `/` e `usuario:pedaco` sai como host).
teste_qa_c04_credencial_embutida_nunca_citada() {
  local u
  while IFS= read -r u; do
    _qa_cenario /r
    _qa_rodar compartilhar --revogar "$u"
    _qa_estado "$QA_USO" "url com credencial [${u:0:8}]"
    _qa_sem_chamada 'url com credencial'
    assert_segredo_ausente 'QAcred' "$QA_SAIDA$QA_ERRO" 'credencial omitida'
    assert_segredo_ausente 'Seg1' "$QA_SAIDA$QA_ERRO" 'senha da credencial omitida'
  done <<'FIM'
https://QAcred:Pw%40Seg1@www.dropbox.com/s/a/x
https://QAcred:P@Seg1@www.dropbox.com/s/a/x
https://QAcred@www.dropbox.com/s/a/x
https://QAcred:Seg1@evil.example/s/a
https://QAcred:Seg1@www.dropbox.com:443/s/a
https://QAcred:Se g1@www.dropbox.com/s/a
https://QAcred:Se/g1@www.dropbox.com/s/a/x
FIM
}

# QA-B5-C05 — QA-B5-05: o arquivo de corpo nasce 0600 qualquer que seja a
# mascara; a mascara do processo (herdada pelo curl) fica a do operador.
teste_qa_c05_corpo_0600_e_mascara_intacta() {
  local m modo masc
  for m in 022 027 002; do
    _qa_cenario /r
    _qa_link 1 /r/a.txt password true
    _qa_regra sharing/create_shared_link_with_settings '*' 200 "$QA_LINK"
    _qa_entrada "$QA_SENHA\n"
    (umask "$m" && _qa_rodar compartilhar --senha-stdin /r/a.txt)
    IFS= read -r modo <"$B/modo_corpo"
    assert_igual 600 "$modo" "corpo 0600 com umask $m"
    while IFS= read -r masc; do
      assert_igual "0$m" "$masc" "mascara do processo intacta com umask $m"
    done <"$B/umask"
  done
}

# QA-B5-C06 — QA-B5-03: pagina vazia com has_more na 1a, 2a e 5a posicao: 10,
# finito, nada listado. Pagina so de omitidos com has_more falso: 0.
teste_qa_c06_pagina_vazia_em_qualquer_posicao() {
  local n i c
  for n in 1 2 5; do
    _qa_cenario /r
    for ((i = 1; i < n; i++)); do
      c='{}'
      ((i > 1)) && c="{\"cursor\":\"c$((i - 1))\"}"
      _qa_regra sharing/list_shared_links "$c" 200 \
        "{\"links\":[{\".tag\":\"file\",\"url\":\"https://www.dropbox.com/s/p$i/z\",\"path_lower\":\"/r/a$i\"}],\"has_more\":true,\"cursor\":\"c$i\"}"
    done
    c='{}'
    ((n > 1)) && c="{\"cursor\":\"c$((n - 1))\"}"
    _qa_regra sharing/list_shared_links "$c" 200 "{\"links\":[],\"has_more\":true,\"cursor\":\"c$n\"}"
    _qa_regra sharing/list_shared_links '*' 200 '{"links":[],"has_more":false}'
    _qa_rodar compartilhar --listar
    _qa_estado "$QA_REMOTO" "pagina vazia na posicao $n"
    _qa_contar sharing/list_shared_links
    assert_igual "$n" "$QA_CONTAGEM" "para na pagina $n"
    assert_nao_contem 'url=' "$QA_SAIDA" "nada listado [$n]"
  done
  _qa_cenario /r
  _qa_regra sharing/list_shared_links '{}' 200 \
    '{"links":[{".tag":"file","url":"https://www.dropbox.com/s/f/z","path_lower":"/fora"}],"has_more":true,"cursor":"c1"}'
  _qa_regra sharing/list_shared_links '*' 200 '{"links":[],"has_more":false}'
  _qa_rodar compartilhar --listar
  _qa_estado 0 'ultima pagina vazia sem has_more'
  assert_contem 'omitidos=1' "$QA_SAIDA" 'omitido contado'
}

# QA-B5-C07 — ACHADO QA-B5-12: escrita com 2xx e corpo malformado (lixo,
# \u0000) diz "recusada" mas sai 0, em create, modify e revoke. QA-B5-07 no
# reuso (ACHADO QA-B5-13): link existente listado sem `url` sai 0 com `url=`.
teste_qa_c07_resposta_malformada_nunca_sai_0() {
  local corpo
  for corpo in 'lixo' '{"url":"https://www.dropbox.com/s/x\u0000","path_lower":"/r/a.txt"}'; do
    _qa_cenario /r
    _qa_regra sharing/create_shared_link_with_settings '*' 200 "$corpo"
    _qa_rodar compartilhar --equipe /r/a.txt
    _qa_estado "$QA_REMOTO" "create 200 malformado [$corpo]"
    _qa_cenario /r
    _qa_link 1 /r/a.txt public false
    _qa_existente "$QA_LINK"
    _qa_regra sharing/modify_shared_link_settings '*' 200 "$corpo"
    _qa_rodar compartilhar --equipe /r/a.txt
    _qa_estado "$QA_REMOTO" "modify 200 malformado [$corpo]"
    _qa_cenario /r
    _qa_regra sharing/get_shared_link_metadata '*' 200 '{"path_lower":"/r/x"}'
    _qa_regra sharing/revoke_shared_link '*' 200 "$corpo"
    _qa_rodar compartilhar --revogar "$QA_URL"
    _qa_estado "$QA_REMOTO" "revoke 200 malformado [$corpo]"
  done
  _qa_cenario /r
  _qa_existente '{".tag":"file","path_lower":"/r/a.txt","link_permissions":{"resolved_visibility":{".tag":"team_only"},"require_password":false}}'
  _qa_rodar compartilhar --equipe /r/a.txt
  _qa_estado "$QA_REMOTO" 'link existente listado sem url'
}

# QA-B5-C08 — RF-85(i) igual na criacao e no modify: para cada visibilidade
# resolvida, `visibilidade_pedida` e o aviso aparecem nos dois caminhos ou em
# nenhum; `senha_redefinida sim` so com `senha sim`.
teste_qa_c08_paridade_criacao_e_modify() {
  local ped vis rp esperada cri mod
  for ped in --senha-stdin --publico; do
    for vis in public team_only password team_and_password shared_folder_only; do
      rp=false
      [[ $vis == password || $vis == team_and_password ]] && rp=true
      _qa_cenario /r
      _qa_link 1 /r/a.txt "$vis" "$rp"
      _qa_regra sharing/create_shared_link_with_settings '*' 200 "$QA_LINK"
      _qa_entrada "$QA_SENHA\n"
      _qa_rodar compartilhar "$ped" /r/a.txt
      cri=nao
      [[ $QA_SAIDA == *visibilidade_pedida=* && $QA_ERRO == *'no lugar de'* ]] && cri=sim
      _qa_cenario /r
      _qa_link 1 /r/a.txt team_only false
      _qa_existente "$QA_LINK"
      _qa_link 1 /r/a.txt "$vis" "$rp"
      _qa_regra sharing/modify_shared_link_settings '*' 200 "$QA_LINK"
      _qa_entrada "$QA_SENHA\n"
      _qa_rodar compartilhar "$ped" /r/a.txt
      mod=nao
      [[ $QA_SAIDA == *visibilidade_pedida=* && $QA_ERRO == *'no lugar de'* ]] && mod=sim
      esperada=sim
      [[ $ped == --senha-stdin && $vis == password ]] && esperada=nao
      [[ $ped == --publico && $vis == public ]] && esperada=nao
      assert_igual "$esperada" "$cri" "criacao [$ped] resolvida [$vis]"
      assert_igual "$esperada" "$mod" "modify [$ped] resolvida [$vis]"
      if [[ $QA_SAIDA == *senha_redefinida=sim* ]]; then
        assert_contem $'\nsenha=sim' $'\n'"$QA_SAIDA" "senha_redefinida so com senha sim [$vis]"
      fi
    done
  done
}

# ===========================================================================
# Ciclo 3: ataque as correcoes de QA-B5-08..16 (DIV-128)
# ===========================================================================

# QA-B5-C09 — com a senha no pedido (criar e modificar), NENHUM texto bruto do
# servico chega a stdout/stderr em texto, --debug e --null: 5xx em JSON e em
# texto (com retentativa), 429, 401 no meio (renovacao) e 401 persistente,
# 400 texto, tag desconhecida hostil, 2xx malformado; o escopo ausente cita o
# escopo fixo e nunca o `required_scope` do corpo.
teste_qa_c09_nenhum_texto_do_servico_com_a_senha_no_pedido() {
  local via modo cod1 corpo1 cod2 corpo2 ep
  for via in criar modificar; do
    for modo in '' --debug --null; do
      while IFS=$'\t' read -r cod1 corpo1 cod2 corpo2; do
        _qa_cenario /r
        ep=sharing/create_shared_link_with_settings
        if [[ $via == modificar ]]; then
          _qa_link 1 /r/a.txt public false
          _qa_existente "$QA_LINK"
          ep=sharing/modify_shared_link_settings
        fi
        _qa_regra "$ep" '*' "$cod1" "$corpo1" uma
        _qa_regra "$ep" '*' "$cod2" "$corpo2"
        _qa_entrada "$QA_SENHA\n"
        _qa_rodar ${modo:+"$modo"} compartilhar --senha-stdin /r/a.txt
        assert_diferente 0 "$QA_ESTADO" "recusa [$via] [$modo] [$cod1/$cod2]"
        assert_nao_contem 'QA5SVC' "$QA_SAIDA$QA_ERRO" "texto do servico ausente [$via] [$modo] [$cod1 $corpo1 / $cod2]"
        assert_segredo_ausente "$QA_SENHA" "$QA_SAIDA$QA_ERRO" "senha ausente [$via] [$modo]"
      done <<'FIM'
500	{"error_summary":"internal_QA5SVC/"}	500	{"error_summary":"internal_QA5SVC2/"}
503	QA5SVC texto de 503	503	QA5SVC texto de 503
429	{"error_summary":"too_many_requests/QA5SVC"}	429	{"error_summary":"too_many_requests/QA5SVC"}
401	{"error_summary":"expired_access_token/QA5SVC"}	409	{"error_summary":"other/QA5SVC"}
401	{"error_summary":"expired_access_token/QA5SVC"}	401	{"error_summary":"expired_access_token/QA5SVC"}
400	Error in call to API function QA5SVC	400	Error in call to API function QA5SVC
409	{"error_summary":"QA5SVC_hostil/other/"}	409	{"error_summary":"QA5SVC_hostil/other/"}
409	{"error_summary":"missing_scope/QA5SVC","error":{".tag":"missing_scope","required_scope":"QA5SVC.scope"}}	409	{"error_summary":"missing_scope/QA5SVC","error":{".tag":"missing_scope","required_scope":"QA5SVC.scope"}}
200	QA5SVC lixo	200	QA5SVC lixo
200	{"url":"https://www.dropbox.com/s/QA5SVC\nx","path_lower":"/r/a.txt"}	200	{"url":"https://www.dropbox.com/s/QA5SVC\nx","path_lower":"/r/a.txt"}
FIM
    done
  done
}

# QA-B5-C10 — QA-B5-11: host so citado na forma `^[A-Za-z0-9.-]+(:[0-9]+)?$`;
# IDN, IPv6 entre colchetes (com e sem porta, com credencial), porta vazia,
# porcento, barra invertida e credencial no esquema: credencial nunca sai.
teste_qa_c10_host_hostil_na_recusa_de_url() {
  local u
  while IFS= read -r u; do
    _qa_cenario /r
    _qa_rodar compartilhar --revogar "$u"
    _qa_estado "$QA_USO" "url hostil [$u]"
    _qa_sem_chamada "url hostil [$u]"
    assert_nao_contem 'Seg1' "$QA_SAIDA$QA_ERRO" "credencial omitida [$u]"
    assert_nao_contem 'dröpbox' "$QA_ERRO" "IDN nao citado [$u]"
    assert_nao_contem '::1' "$QA_ERRO" "IPv6 nao citado [$u]"
  done <<'FIM'
https://dröpbox.com/s/a
https://[::1]/s/a
https://[2001:db8::1]:8443/s/a
https://u:Seg1@[::1]:443/s/a
https://[u:Seg1@::1]/s/a
https://www.dropbox.com:/s/a
https://ev%69l.com/s/a
https://evil.com\@www.dropbox.com/s/a
https://www.dropbox.com%2F@evil/s
https://evil.com:Seg1/s/a
HTTPS://u:Seg1@evil/s
u:Seg1@x://www.dropbox.com/s/a
FIM
}

# QA-B5-C11 — QA-B5-14: teto de 1000 paginas no --listar. 1000 paginas que
# terminam: 0 com as 1000; paginas sem fim (cada uma com link, so omitidos):
# 10 "listagem nao terminou em 1000 paginas", exatamente 1000 chamadas.
teste_qa_c11_teto_de_1000_paginas() {
  QA_TETO=180
  _qa_cenario /r
  printf '1000\n' >"$B/fim"
  _qa_regra sharing/list_shared_links '*' 200 \
    '{"links":[{".tag":"file","url":"https://www.dropbox.com/s/p@N@/z","path_lower":"/r/x@N@"}],"has_more":@HM@,"cursor":"c@N@"}'
  _qa_rodar compartilhar --listar
  _qa_estado 0 '1000 paginas que terminam'
  assert_contem 'total=1000' "$QA_SAIDA" 'as 1000 listadas'
  _qa_cenario /r
  _qa_regra sharing/list_shared_links '*' 200 \
    '{"links":[{".tag":"file","url":"https://www.dropbox.com/s/f@N@/z","path_lower":"/fora/x@N@"}],"has_more":true,"cursor":"c@N@"}'
  _qa_rodar compartilhar --listar
  _qa_estado "$QA_REMOTO" 'paginas sem fim'
  assert_contem 'listagem nao terminou em 1000 paginas' "$QA_ERRO" 'mensagem do teto'
  _qa_contar sharing/list_shared_links
  assert_igual 1000 "$QA_CONTAGEM" 'exatamente 1000 paginas'
  assert_nao_contem 's/f' "$QA_SAIDA" 'nada listado'
}

# ===========================================================================
# Auditoria RNF-24 desta suite
# ===========================================================================

# QA-B5-A01 — esta suite nao captura bytes externos com substituicao de
# comando, nem usa `grep -c` sobre arquivo.
teste_qa_a01_suite_sem_captura_de_bytes_externos() {
  local linha g='grep' abre='$('
  while IFS= read -r linha || [[ -n $linha ]]; do
    [[ $linha =~ ^[[:space:]]*# ]] && continue
    [[ $linha == *"$g -c"* ]] && _harness_falhar 'contagem por grep na suite' "[$linha]"
    [[ $linha == *"${abre}cat "* || $linha == *"${abre}<"* || $linha == *"${abre}_qa_"* ]] &&
      _harness_falhar 'captura de bytes externos' "[$linha]"
  done <"$DBX_HARNESS_RAIZ/tests/integracao/qa_compartilhamento_b5_test.sh"
  return 0
}

harness_executar "$@"
