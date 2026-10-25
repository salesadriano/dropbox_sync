# Roteiro de validacao no FreeBSD real (TC-FBSD-24)

Validacao manual do solicitante antes do merge da demanda `suporte-freebsd` (secao 5.22 do escopo, `DIV-355`). A suite roda em Linux com dubles dos utilitarios do FreeBSD; este roteiro cobre o que o duble nao reproduz: o comportamento sem `fdescfs`, ausencia de `/proc`, `getopt` real dos utilitarios e as mensagens exatas.

Rode como o usuario que vai usar o `dbx` (root, no caso do solicitante). Use uma pasta remota de teste vazia, por exemplo `/teste-freebsd`.

## 1. Preparo

```sh
pkg install -y bash curl git
git clone -b feature/chmod-portavel-bsd https://github.com/salesadriano/dropbox_sync.git /tmp/dbx-freebsd
cd /tmp/dbx-freebsd
freebsd-version; bash --version | head -1
```

## 2. Sem fdescfs

O `dbx` nao depende mais do `fdescfs` (a validacao anterior mostrou que, no FreeBSD 15, nenhum modo dele serve). Rode com ele desmontado:

```sh
umount /dev/fd 2>/dev/null; mount | grep fdescfs || echo "fdescfs NAO montado"
bash bin/dbx space; echo "saida=$?"
bash bin/dbx diagnostico; echo "saida=$?"
```

Esperado: nenhuma mensagem cita o `fdescfs`. Sem credencial valida, `space` pode oferecer o `dbx config` ou sair com `3` por credencial. No `diagnostico`, a linha `dependencias` diz de qual utilitario vem o resumo SHA-256.

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

Download (o caminho de escrita do `curl` mudou nesta versao; e o ponto mais importante a conferir):

```sh
dbx --debug download /teste-freebsd/grande.bin /tmp/dbx-grande.bin   # Ctrl-C no meio
dbx --debug download /teste-freebsd/grande.bin /tmp/dbx-grande.bin   # retoma
cmp /tmp/dbx-local/grande.bin /tmp/dbx-grande.bin && echo IGUAL
dbx download /teste-freebsd/a.txt - | cat                             # saida padrao
```

Esperado: a segunda execucao mostra `retomada=encontrada` e uma faixa no `debug: http`; o `cmp` diz `IGUAL`; a saida padrao imprime `ola freebsd`.

## 7. Duas conferencias do sistema (para o Tech Lead)

```sh
stat -f '%.9Fm|%.9Fc' /tmp/dbx-local/a.txt     # nanossegundos disponiveis? (achado 5 da conformidade)
chmod 4044 /tmp/dbx-local/a.txt; stat -f '%Mp|%Lp|%03Lp' /tmp/dbx-local/a.txt; chmod 644 /tmp/dbx-local/a.txt   # esperado: 4|44|044 (achado N1)
bash -c 'exec 3</etc/passwd; stat -f "%d|%i|%HT" <&3; stat -f "%d|%i" /etc/passwd'   # o stat pelo descritor devolve o mesmo dev|ino do arquivo?
```

## 8. Resultado

Copie para o Tech Lead a saida dos passos 2 a 5, **sem** a URL de autorizacao nem o codigo do `dbx config`. O resultado vai para o registro de entrega da demanda.
