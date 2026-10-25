# Roteiro de validacao no FreeBSD real (TC-FBSD-24)

Validacao manual do solicitante antes do merge da demanda `suporte-freebsd` (secao 5.22 do escopo, `DIV-355`). A suite roda em Linux com dubles dos utilitarios do FreeBSD; este roteiro cobre o que o duble nao reproduz: `/dev/fd` com e sem `fdescfs`, ausencia de `/proc`, `getopt` real dos utilitarios e as mensagens exatas.

Rode como o usuario que vai usar o `dbx` (root, no caso do solicitante). Use uma pasta remota de teste vazia, por exemplo `/teste-freebsd`.

## 1. Preparo

```sh
pkg install -y bash curl git
git clone -b feature/chmod-portavel-bsd https://github.com/salesadriano/dropbox_sync.git /tmp/dbx-freebsd
cd /tmp/dbx-freebsd
freebsd-version; bash --version | head -1
```

## 2. Preflight e fdescfs

```sh
mount | grep fdescfs || echo "fdescfs NAO montado"
# Sem fdescfs: a verificacao previa deve recusar citando o fdescfs.
bash bin/dbx space; echo "saida=$?"
mount -t fdescfs fdesc /dev/fd
bash bin/dbx space; echo "saida=$?"
bash bin/dbx diagnostico; echo "saida=$?"
```

Esperado: sem `fdescfs`, a primeira execucao sai com `3` e a mensagem cita `mount -t fdescfs fdesc /dev/fd`. Montado, a segunda execucao nao cita mais o `fdescfs` (ainda sem credencial, ela pode oferecer o `dbx config` ou sair com `3` por credencial ausente). No `diagnostico`, a linha `dependencias` diz `resumo SHA-256 via sha256` (ou `openssl`) e a linha `trava` diz que o tipo do sistema de arquivos nao foi verificado.

## 3. Instalacao

```sh
bash install.sh --prefix /usr/local
dbx --version
```

Esperado: `dbx 2.0.0` (ou a versao da branch), sem nenhuma linha `chmod: --` nem `stat: illegal option`.

## 4. Credencial

```sh
dbx config
ls -l ~/.config/dbx/credencial.json
```

Esperado: conclui sem `chmod: --: No such file or directory`; o arquivo fica `-rw-------`.

## 5. Transferencias

```sh
mkdir -p /tmp/dbx-local && printf 'ola freebsd\n' > /tmp/dbx-local/a.txt
dd if=/dev/urandom of=/tmp/dbx-local/grande.bin bs=1m count=200
dbx --debug upload /tmp/dbx-local/a.txt /teste-freebsd/a.txt
dbx upload /tmp/dbx-local/grande.bin /teste-freebsd/grande.bin
dbx download /teste-freebsd/a.txt /tmp/dbx-baixado.txt && cmp /tmp/dbx-local/a.txt /tmp/dbx-baixado.txt && echo IGUAL
dbx sync --enviar --origem /tmp/dbx-local --destino /teste-freebsd
dbx sync --enviar --origem /tmp/dbx-local --destino /teste-freebsd   # segunda vez: nada a enviar
rm -rf /tmp/dbx-recebido && dbx sync --receber --origem /teste-freebsd --destino /tmp/dbx-recebido
dbx verificar --enviar --origem /tmp/dbx-local --destino /teste-freebsd
```

Esperado: todos saem com `0`; a segunda execucao do `sync --enviar` nao reenvia nada; `verificar` nao aponta divergencia.

## 6. Retomada (opcional)

Interrompa com Ctrl-C o upload de `grande.bin` no meio e rode de novo: com `--debug`, deve aparecer `debug: upload retomada=encontrada`.

## 7. Duas conferencias do sistema (para o Tech Lead)

```sh
stat -f '%.9Fm|%.9Fc' /tmp/dbx-local/a.txt     # nanossegundos disponiveis? (achado 5 da conformidade)
bash -c 'exec 3</etc/passwd; [[ -f /dev/fd/3 ]] && echo bash-ve-fd3; stat -L -f %i /dev/fd/3'   # com e sem fdescfs
```

## 8. Resultado

Copie para o Tech Lead a saida dos passos 2 a 5, **sem** a URL de autorizacao nem o codigo do `dbx config`. O resultado vai para o registro de entrega da demanda.
