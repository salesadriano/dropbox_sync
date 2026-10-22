#!/usr/bin/env bats
# Testes de scripts/bancada.sh (F-34) sem rede real: dbx e curl sao dubles no PATH/DBX_BIN.
# Rodar: npx --yes bats@1.13.0 --abort scripts/tests/bancada.bats

SCRIPT="$BATS_TEST_DIRNAME/../bancada.sh"

setup() {
  export BANCADA_PEQUENOS=6 BANCADA_MEDIOS=2 BANCADA_GRANDES=1 BANCADA_GRANDE_MB=1
  export CHAMADAS="$BATS_TEST_TMPDIR/chamadas"
  : >"$CHAMADAS"
  # dbx falso. `list` responde pelo estado em lista_status (padrao 4 = pasta inexistente) e lista_saida;
  # a etapa cujo nome esta em falha_etapa (sync --receber -> "receber"; reter -> "reter") sai 14 e escreve
  # no stdout e no stderr; `delete` falha se existir delete_falha.
  cat >"$BATS_TEST_TMPDIR/dbx" <<DUBLE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CHAMADAS"
T="$BATS_TEST_TMPDIR"
case "\$1" in
  list)
    [ -f "\$T/lista_saida" ] && cat "\$T/lista_saida"
    exit "\$(cat "\$T/lista_status" 2>/dev/null || echo 4)" ;;
  delete) [ -f "\$T/delete_falha" ] && exit 1; exit 0 ;;
  upload) exit 0 ;;
esac
curl -s -w '%{http_code}' http://invalido.test >/dev/null || true
etapa="\$1"; [ "\$1" = sync ] && etapa="\${2#--}"
if [ -f "\$T/falha_etapa" ] && [ "\$(cat "\$T/falha_etapa")" = "\$etapa" ]; then
  echo "item falhou: /x/a.bin token sl.SEGREDOSEGREDO123456 e Bearer abc123"
  echo "erro no stderr" >&2
  exit 14
fi
echo "saida de \$etapa"
exit 0
DUBLE
  chmod +x "$BATS_TEST_TMPDIR/dbx"
  export DBX_BIN="$BATS_TEST_TMPDIR/dbx"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # curl falso: devolve 429 na primeira chamada e 200 nas demais (o shim do script envolve este).
  cat >"$BATS_TEST_TMPDIR/bin/curl" <<DUBLE
#!/usr/bin/env bash
n=\$(wc -l <"$BATS_TEST_TMPDIR/n" 2>/dev/null || echo 0); echo x >>"$BATS_TEST_TMPDIR/n"
if [ "\$n" -eq 0 ]; then printf 429; else printf 200; fi
DUBLE
  chmod +x "$BATS_TEST_TMPDIR/bin/curl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

hash_conjunto() { (cd "$1" && find . -type f | LC_ALL=C sort | xargs sha256sum | sha256sum | cut -c1-64); }

@test "gerar e deterministico: mesma semente, mesmo conjunto; outra semente difere" {
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/a" --semente 7
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/b" --semente 7
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/c" --semente 8
  [ "$(hash_conjunto "$BATS_TEST_TMPDIR/a")" = "$(hash_conjunto "$BATS_TEST_TMPDIR/b")" ]
  [ "$(hash_conjunto "$BATS_TEST_TMPDIR/a")" != "$(hash_conjunto "$BATS_TEST_TMPDIR/c")" ]
}

@test "gerar cria contagem, tamanhos e tres niveis de pasta" {
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/v"
  [ "$(find "$BATS_TEST_TMPDIR/v" -type f | wc -l)" -eq 9 ]
  [ -f "$BATS_TEST_TMPDIR/v.marcador" ]
  while read -r f; do
    t=$(stat -c %s "$f")
    [ "$t" -ge 1024 ] && [ "$t" -le 51200 ]
  done < <(find "$BATS_TEST_TMPDIR/v" -name 'pequeno-*')
  while read -r f; do
    t=$(stat -c %s "$f")
    [ "$t" -ge 1048576 ] && [ "$t" -le 5242880 ]
  done < <(find "$BATS_TEST_TMPDIR/v" -name 'medio-*')
  [ "$(stat -c %s "$BATS_TEST_TMPDIR/v/n1-0/n2-0/n3-0/grande-0.bin")" -eq 1048576 ]
  [ -f "$BATS_TEST_TMPDIR/v/n1-0/n2-0/n3-0/pequeno-0.bin" ]
}

@test "remoto fora do padrao e recusado com 2 e sem chamar o dbx" {
  for r in / /dbx-bancada '/dbx-bancada-../x' /dbx-bancada-ABC /outra /dbx-bancada-a/b; do
    run bash "$SCRIPT" limpar --remoto "$r"
    [ "$status" -eq 2 ]
    mkdir -p "$BATS_TEST_TMPDIR/v"
    run bash "$SCRIPT" medir "$BATS_TEST_TMPDIR/v" --remoto "$r" --saida "$BATS_TEST_TMPDIR/s" --confirmo-conta-real
    [ "$status" -eq 2 ]
  done
  [ ! -s "$CHAMADAS" ]
}

@test "medir sem --confirmo-conta-real sai 2 sem chamar o dbx" {
  mkdir -p "$BATS_TEST_TMPDIR/v"
  run bash "$SCRIPT" medir "$BATS_TEST_TMPDIR/v" --remoto /dbx-bancada-ok --saida "$BATS_TEST_TMPDIR/s"
  [ "$status" -eq 2 ]
  [ ! -s "$CHAMADAS" ]
}

pasta_com_marcador() { printf 'x\t.bancada-marcador\n' >"$BATS_TEST_TMPDIR/lista_saida"; echo 0 >"$BATS_TEST_TMPDIR/lista_status"; }
pasta_sem_marcador() { printf 'x\toutro.txt\n' >"$BATS_TEST_TMPDIR/lista_saida"; echo 0 >"$BATS_TEST_TMPDIR/lista_status"; }

@test "limpar so apaga com o marcador na pasta" {
  pasta_com_marcador
  run bash "$SCRIPT" limpar --remoto /dbx-bancada-ok-1
  [ "$status" -eq 0 ]
  grep -qx "delete /dbx-bancada-ok-1 --yes" "$CHAMADAS"
}

@test "limpar recusa pasta existente sem o marcador e nao apaga" {
  pasta_sem_marcador
  run bash "$SCRIPT" limpar --remoto /dbx-bancada-ok-1
  [ "$status" -eq 2 ]
  ! grep -q '^delete' "$CHAMADAS"
}

@test "medir recusa pasta existente sem o marcador: nada enviado nem apagado" {
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/v"
  pasta_sem_marcador
  run bash "$SCRIPT" medir "$BATS_TEST_TMPDIR/v" --remoto /dbx-bancada-ok --saida "$BATS_TEST_TMPDIR/s.tsv" --confirmo-conta-real
  [ "$status" -eq 2 ]
  ! grep -Eq '^(sync|upload|delete|reter)' "$CHAMADAS"
}

@test "medir cria a pasta com o marcador, mede quatro etapas, conta chamadas e 429 e repassa extras so ao sync" {
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/v"
  run bash "$SCRIPT" medir "$BATS_TEST_TMPDIR/v" --remoto /dbx-bancada-ok --saida "$BATS_TEST_TMPDIR/s.tsv" --confirmo-conta-real -- --paralelo 4
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$BATS_TEST_TMPDIR/s.tsv")" -eq 4 ]
  cut -f1 "$BATS_TEST_TMPDIR/s.tsv" | paste -sd, | grep -qx 'envio,reenvio_sem_mudancas,recebimento,reter'
  grep -Pq '^envio\t[0-9]+\.[0-9]{3}\t1\t1\t0\t/dbx-bancada-ok$' "$BATS_TEST_TMPDIR/s.tsv"
  grep -Pq '^recebimento\t[0-9]+\.[0-9]{3}\t1\t0\t0\t' "$BATS_TEST_TMPDIR/s.tsv"
  grep -Fq 'upload ' "$CHAMADAS"
  grep -Fq '.bancada-marcador' "$CHAMADAS"
  [ "$(grep -c -- '--paralelo 4' "$CHAMADAS")" -eq 3 ]
  grep -Fq "reter /dbx-bancada-ok/n1-0/n2-0/n3-0 --padrao pequeno-*.bin --manter 1 --confirmar" "$CHAMADAS"
  # trap: ao fim apaga a pasta remota e o volume local (com marcador)
  grep -qx "delete /dbx-bancada-ok --yes" "$CHAMADAS"
  [ ! -e "$BATS_TEST_TMPDIR/v" ]
}

@test "medir preserva a saida de cada etapa, sem segredo, e sai 1 apontando o log quando uma etapa falha" {
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/v"
  echo receber >"$BATS_TEST_TMPDIR/falha_etapa"
  run bash "$SCRIPT" medir "$BATS_TEST_TMPDIR/v" --remoto /dbx-bancada-ok --saida "$BATS_TEST_TMPDIR/s.tsv" --confirmo-conta-real
  [ "$status" -eq 1 ]
  [[ "$output" == *"etapa recebimento saiu com status 14; ver $BATS_TEST_TMPDIR/s.tsv.recebimento.log"* ]]
  log="$BATS_TEST_TMPDIR/s.tsv.recebimento.log"
  [ -f "$log" ]
  grep -q 'item falhou: /x/a.bin' "$log"
  grep -q 'erro no stderr' "$log"
  ! grep -q 'SEGREDOSEGREDO' "$log"
  ! grep -q 'abc123' "$log"
  [ -f "$BATS_TEST_TMPDIR/s.tsv.envio.log" ]
  grep -Pq '^recebimento\t[0-9.]+\t[0-9]+\t[0-9]+\t14\t' "$BATS_TEST_TMPDIR/s.tsv"
  # a limpeza ainda ocorreu
  grep -qx "delete /dbx-bancada-ok --yes" "$CHAMADAS"
}

@test "falha de limpeza sai nao zero e imprime o caminho remanescente" {
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/v"
  : >"$BATS_TEST_TMPDIR/delete_falha"
  run bash "$SCRIPT" medir "$BATS_TEST_TMPDIR/v" --remoto /dbx-bancada-ok --saida "$BATS_TEST_TMPDIR/s.tsv" --confirmo-conta-real
  [ "$status" -ne 0 ]
  [[ "$output" == *"remanescente remoto: /dbx-bancada-ok"* ]]
}

@test "o trap apaga a pasta remota e o volume local quando o medir e interrompido (TERM)" {
  bash "$SCRIPT" gerar "$BATS_TEST_TMPDIR/v"
  # etapa lenta: o dbx falso dorme no sync de envio
  cat >"$BATS_TEST_TMPDIR/dbx2" <<DUBLE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CHAMADAS"
case "\$1" in
  list) exit 4 ;;
  sync) sleep 30 ;;
esac
exit 0
DUBLE
  chmod +x "$BATS_TEST_TMPDIR/dbx2"
  DBX_BIN="$BATS_TEST_TMPDIR/dbx2" bash "$SCRIPT" medir "$BATS_TEST_TMPDIR/v" --remoto /dbx-bancada-ok --saida "$BATS_TEST_TMPDIR/s.tsv" --confirmo-conta-real &
  pid=$!
  for _ in $(seq 1 50); do grep -q '^sync' "$CHAMADAS" && break; sleep 0.1; done
  pkill -TERM -P "$pid" sleep || true
  kill -TERM "$pid"
  wait "$pid" || true
  grep -qx "delete /dbx-bancada-ok --yes" "$CHAMADAS"
  [ ! -e "$BATS_TEST_TMPDIR/v" ]
}
