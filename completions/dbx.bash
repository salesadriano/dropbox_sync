# completions/dbx.bash — autocompletar de bash do dbx (RF-68, F-19).
#
# Ativacao na sessao corrente:   source <(dbx completar bash)
# O install.sh o instala em ~/.local/share/bash-completion/completions/dbx,
# onde o pacote bash-completion o carrega sob demanda. Este arquivo NAO exige
# esse pacote: usa so `compgen`, `compopt` e `complete`, que sao do bash.
#
# Completa comandos e aliases, opcoes globais, opcoes de cada comando (nome em
# portugues e alias em ingles) e caminhos LOCAIS onde o argumento e local. Nunca
# completa caminho remoto, nunca chama a rede e nunca le arquivo do dbx: so a
# linha de comando e, para caminho local, o sistema de arquivos. Carregar este
# arquivo so define a funcao abaixo e o registro `complete`. O VALOR de `--perfil`
# nao e completado: so a opcao (DIV-255 C; completar o valor fica no backlog F-45).
#
# As listas tem fonte unica na ajuda (`dbx help` e `dbx help <comando>`): a
# suite reprova quando uma opcao existe so de um lado.

_dbx_completar() {
  local atual=${COMP_WORDS[COMP_CWORD]} anterior=${COMP_WORDS[COMP_CWORD - 1]}
  local comando='' sentido='' palavra lista='' local_='nao' indice posicionais=0 valor='nao'
  COMPREPLY=()

  # Comando e a primeira palavra que nao e opcao; o sentido do sync e do
  # verificar decide qual lado e local.
  for ((indice = 1; indice < COMP_CWORD; indice++)); do
    palavra=${COMP_WORDS[indice]}
    if [[ -z $comando ]]; then
      [[ $palavra == -* ]] || comando=$palavra
      continue
    fi
    case $palavra in
      --enviar | --push) sentido='enviar' ;;
      --receber | --pull) sentido='receber' ;;
    esac
    # Posicionais antes da palavra corrente, sem contar opcao nem valor dela.
    if [[ $valor == 'sim' ]]; then
      valor='nao'
    else
      case $palavra in
        --modo | --mode | --rev | --limite | --limit | --raiz | --root | \
          --origem | --source | --destino | --dest | --esperar | --wait | \
          --antes-de | --before | --excluir | --purge | --confirmar-caminho | \
          --exclude | --incluir | --include | --modificado-desde | --modified-since | \
          --modificado-ate | --modified-until | --tamanho-min | --min-size | --tamanho-max | \
          --max-size | --limite-banda | --bwlimit | --expira | --expires | --revogar | \
          --revoke | --padrao | --pattern | --manter | --keep | --dias | --days | \
          --perfil | --profile) valor='sim' ;;
        -?*) ;;
        *) posicionais=$((posicionais + 1)) ;;
      esac
    fi
  done
  case $comando in
    verify) comando='verificar' ;;
    doctor) comando='diagnostico' ;;
    check) comando='testar' ;;
    completion) comando='completar' ;;
    revisions) comando='revisoes' ;;
    restore) comando='restaurar' ;;
    trash) comando='lixeira' ;;
    link-temporario | temp-link) comando='link_temporario' ;;
    share) comando='compartilhar' ;;
    retain) comando='reter' ;;
    profiles) comando='perfis' ;;
  esac

  if [[ -z $comando || $comando == 'help' ]]; then
    if [[ -z $comando && $atual == -* ]]; then
      lista='--help -h --version -V --json --null --dry-run --progresso --progress -p --sem-progresso --no-progress --debug --perfil --profile'
    elif [[ -z $comando || $posicionais -eq 0 ]]; then
      lista='upload download list delete info space config unlink sync verificar verify diagnostico doctor testar check completar completion revisoes revisions restaurar restore lixeira trash link-temporario temp-link compartilhar share reter retain perfis profiles help'
    fi
    mapfile -t COMPREPLY < <(compgen -W "$lista" -- "$atual")
    return 0
  fi

  case $comando in
    upload) lista='--modo --mode --rev --forcar --force --limite-banda --bwlimit --paralelo --parallel --sem-retomada --no-resume --progresso --progress -p --sem-progresso --no-progress' ;;
    download) lista='--excluir --exclude --incluir --include --modificado-desde --modified-since --modificado-ate --modified-until --tamanho-min --min-size --tamanho-max --max-size --limite-banda --bwlimit --paralelo --parallel --progresso --progress -p --sem-progresso --no-progress --forcar --force --sem-retomada --no-resume' ;;
    list) lista='--limite --limit --recursivo --recursive -R' ;;
    delete) lista='--confirmar --yes -y --rev' ;;
    space) lista='--humano --human -H' ;;
    config) lista='--perfil --profile --substituir --replace --raiz --root --debug' ;;
    unlink) lista='--perfil --profile --confirmar --yes --manter-aplicativo --keep-app' ;;
    perfis) lista='' ;;
    sync) lista='--enviar --push --receber --pull --origem --source --destino --dest --espelhar --mirror --confirmar --yes --permitir-origem-vazia --allow-empty-source --forcar --force --esperar --wait --excluir --exclude --incluir --include --modificado-desde --modified-since --modificado-ate --modified-until --tamanho-min --min-size --tamanho-max --max-size --limite-banda --bwlimit --paralelo --parallel --sem-cursor --no-cursor --varredura-completa --full-scan --progresso --progress -p --sem-progresso --no-progress' ;;
    verificar) lista='--enviar --push --receber --pull --origem --source --destino --dest --esperar --wait --excluir --exclude --incluir --include --progresso --progress -p --sem-progresso --no-progress' ;;
    revisoes) lista='--limite --limit --por-id --by-id' ;;
    restaurar) lista='--rev --antes-de --before' ;;
    lixeira) lista='--recursivo --recursive -R --limite --limit --excluir --purge --confirmar-caminho' ;;
    link_temporario) lista='' ;;
    compartilhar) lista='--publico --public --equipe --team --senha --password --senha-stdin --password-stdin --expira --expires --listar --list --revogar --revoke' ;;
    reter) lista='--padrao --pattern --manter --keep --dias --days --confirmar --yes -y' ;;
  esac

  if [[ $atual == -* ]]; then
    mapfile -t COMPREPLY < <(compgen -W "$lista" -- "$atual")
    return 0
  fi

  case $anterior in
    --modo | --mode)
      mapfile -t COMPREPLY < <(compgen -W 'add overwrite' -- "$atual")
      return 0
      ;;
    # `--raiz` do `config` e a raiz REMOTA gravada na credencial.
    --rev | --limite | --limit | --raiz | --root | --esperar | --wait | --antes-de | --before | \
      --excluir | --purge | --confirmar-caminho | --exclude | --incluir | --include | \
      --modificado-desde | --modified-since | --modificado-ate | --modified-until | \
      --tamanho-min | --min-size | --tamanho-max | --max-size | --limite-banda | --bwlimit | --paralelo | --parallel | \
      --expira | --expires | --revogar | --revoke | --padrao | --pattern | --manter | --keep | \
      --dias | --days | --perfil | --profile) return 0 ;;
    --origem | --source) [[ $sentido == 'enviar' ]] && local_='sim' ;;
    --destino | --dest) [[ $sentido == 'receber' ]] && local_='sim' ;;
    *)
      case $comando in
        upload) [[ $posicionais -eq 0 ]] && local_='sim' ;;
        download) [[ $posicionais -eq 1 ]] && local_='sim' ;;
        completar)
          [[ $posicionais -eq 0 ]] && mapfile -t COMPREPLY < <(compgen -W 'bash' -- "$atual")
          return 0
          ;;
      esac
      ;;
  esac
  [[ $local_ == 'sim' ]] || return 0

  # Caminho local: desfaz a citacao mais comum da palavra digitada (aspa de
  # abertura e barra invertida) e deixa o bash escapar o resultado.
  palavra=$atual
  case $palavra in
    \'* | \"*) palavra=${palavra:1} ;;
  esac
  palavra=${palavra//\\/}
  compopt -o filenames 2>/dev/null
  mapfile -t COMPREPLY < <(compgen -f -- "$palavra")
  return 0
}

complete -F _dbx_completar dbx
