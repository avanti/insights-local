#!/usr/bin/env bash
# Bash 3.2 compatible (including the Bash shipped with macOS).
set -euo pipefail
umask 077

INSIGHTS_COMMAND="${1:-help}"
if [ "$#" -gt 0 ]; then shift; fi
INSIGHTS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$INSIGHTS_SCRIPT_DIR")" = scripts ]; then
  INSIGHTS_ROOT="$(cd "$INSIGHTS_SCRIPT_DIR/.." && pwd)"
else
  INSIGHTS_ROOT="$PWD/insights-local"
fi
INSIGHTS_PORT=""
INSIGHTS_API_PORT=""
INSIGHTS_NO_BROWSER=false
INSIGHTS_NONINTERACTIVE=false
INSIGHTS_PROJECT="all"
INSIGHTS_DOCKER=(docker)

usage() {
  cat <<'USAGE'
Avanti Insights local
Uso: bash scripts/local.sh <setup|start|stop|status|doctor|codex|help> [opcoes]
  --root DIRETORIO       Pasta do repositorio clonado.
  --port NUMERO          Porta da interface (padrao 3000).
  --api-port NUMERO      Porta da API (padrao 8000).
  --no-browser          Nao abrir o navegador.
  --non-interactive     Nao iniciar logins ou confirmacoes interativas.
  --project frontend|backend|all  Pasta a abrir com codex (padrao all).
setup instala dependencias ausentes, clona, configura e inicia.
start/stop/status/doctor/codex nao instalam software.
codex abre conversas nas pastas dos aplicativos; confira o cadastro de projetos no app.
USAGE
}

fail() { printf '%s\n' "$*" >&2; exit 2; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root|--port|--api-port|--project)
      [ "$#" -ge 2 ] || fail "Falta o valor de $1."
      case "$1" in
        --root) INSIGHTS_ROOT="$2";;
        --port) INSIGHTS_PORT="$2";;
        --api-port) INSIGHTS_API_PORT="$2";;
        --project) INSIGHTS_PROJECT="$2";;
      esac
      shift 2;;
    --no-browser) INSIGHTS_NO_BROWSER=true; shift;;
    --non-interactive) INSIGHTS_NONINTERACTIVE=true; shift;;
    *) fail "Opcao desconhecida: $1";;
  esac
done
case "$INSIGHTS_COMMAND" in setup|start|stop|status|doctor|codex|help|--help|-h) ;; *) fail "Comando desconhecido: $INSIGHTS_COMMAND";; esac
case "$INSIGHTS_PROJECT" in all|frontend|backend) ;; *) fail "Projeto deve ser frontend, backend ou all.";; esac
if [ "$INSIGHTS_COMMAND" != codex ] && [ "$INSIGHTS_PROJECT" != all ]; then
  fail "Use codex para selecionar um projeto."
fi
for INSIGHTS_PORT_VALUE in "$INSIGHTS_PORT" "$INSIGHTS_API_PORT"; do
  if [ -n "$INSIGHTS_PORT_VALUE" ]; then
    [[ "$INSIGHTS_PORT_VALUE" =~ ^[0-9]{1,5}$ ]] || fail "Porta invalida."
    INSIGHTS_PORT_NUMBER=$((10#$INSIGHTS_PORT_VALUE))
    if [ "$INSIGHTS_PORT_NUMBER" -lt 1024 ] || [ "$INSIGHTS_PORT_NUMBER" -gt 65535 ]; then
      fail "Portas devem estar entre 1024 e 65535."
    fi
  fi
done
if [ "$INSIGHTS_COMMAND" = help ] || [ "$INSIGHTS_COMMAND" = --help ] || [ "$INSIGHTS_COMMAND" = -h ]; then usage; exit 0; fi
if [ "$INSIGHTS_COMMAND" != setup ] && { [ -n "$INSIGHTS_PORT" ] || [ -n "$INSIGHTS_API_PORT" ]; }; then
  fail "Use setup para alterar portas."
fi
export PATH="$HOME/.local/bin:$HOME/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

progress() {
  INSIGHTS_STAGE="$1"
  mkdir -p "$INSIGHTS_ROOT/.local"
  printf 'Etapa: %s\nPasta: %s\n' "$INSIGHTS_STAGE" "$INSIGHTS_ROOT" > "$INSIGHTS_ROOT/.local/setup-progress.txt"
  printf '%s\n' "$INSIGHTS_STAGE"
}

setup_exit() {
  local code="$?"
  if [ "$code" -ne 0 ]; then
    printf 'Etapa: %s\nPasta: %s\nResultado: interrompido (codigo %s)\n' \
      "$INSIGHTS_STAGE" "$INSIGHTS_ROOT" "$code" > "$INSIGHTS_ROOT/.local/setup-progress.txt" || true
    printf '%s\n' "O Codex pode retomar na mesma pasta. A etapa foi registrada em .local/setup-progress.txt." >&2
  fi
}

open_codex() {
  INSIGHTS_CODEX_LINKS=()
  for INSIGHTS_NAME in frontend backend; do
    if [ "$INSIGHTS_PROJECT" != all ] && [ "$INSIGHTS_PROJECT" != "$INSIGHTS_NAME" ]; then continue; fi
    INSIGHTS_LINK="$INSIGHTS_ROOT/.local/codex/$INSIGHTS_NAME.link"
    [ -f "$INSIGHTS_LINK" ] || fail "Atalhos Codex ausentes. Execute setup novamente na mesma pasta."
    [ -d "$INSIGHTS_ROOT/sources/$INSIGHTS_NAME/.git" ] || fail "Pasta do aplicativo $INSIGHTS_NAME ausente. Execute setup."
    INSIGHTS_URL="$(cat "$INSIGHTS_LINK")"
    [[ "$INSIGHTS_URL" =~ ^codex://new\?path=[a-zA-Z0-9%._~-]+$ ]] || fail "Atalho Codex invalido. Execute setup novamente."
    INSIGHTS_CODEX_LINKS+=("$INSIGHTS_URL")
  done
  case "$(uname -s)" in
    Darwin) INSIGHTS_OPENER=open;;
    Linux) INSIGHTS_OPENER=xdg-open;;
    *) fail "Use local.ps1 no Windows.";;
  esac
  command -v "$INSIGHTS_OPENER" >/dev/null || fail "Abra .local/codex-projects.html no navegador para usar os atalhos Codex."
  for INSIGHTS_URL in "${INSIGHTS_CODEX_LINKS[@]}"; do "$INSIGHTS_OPENER" "$INSIGHTS_URL"; done
  printf '%s\n' "Solicitada a abertura das pastas no Codex. Confira se aparecem como projetos na barra lateral."
}

admin() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  else command -v sudo >/dev/null || fail "Instalacao requer sudo. Peça ajuda ao administrador."; sudo "$@"
  fi
}

install_linux() {
  [ -r /etc/os-release ] || fail "Distribuicao desconhecida. Instale Docker e Compose seguindo https://docs.docker.com/engine/install/."
  # System-owned OS identification; no project environment file is sourced.
  # shellcheck source=/dev/null
  . /etc/os-release
  case "$ID" in
    ubuntu|debian)
      if ! command -v git >/dev/null || ! command -v gh >/dev/null || ! command -v curl >/dev/null || ! command -v unzip >/dev/null; then
        admin apt-get update
        admin apt-get install -y git gh curl ca-certificates unzip
      fi
      if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
        admin apt-get update
        admin apt-get install -y ca-certificates curl
        admin install -m 0755 -d /etc/apt/keyrings
        admin curl --fail --silent --show-error --location "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
        admin chmod a+r /etc/apt/keyrings/docker.asc
        INSIGHTS_ARCH="$(dpkg --print-architecture)"
        INSIGHTS_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
        [ -n "$INSIGHTS_CODENAME" ] || fail "Nao foi possivel identificar a versao da distribuicao."
        printf 'Types: deb\nURIs: https://download.docker.com/linux/%s\nSuites: %s\nComponents: stable\nArchitectures: %s\nSigned-By: /etc/apt/keyrings/docker.asc\n' \
          "$ID" "$INSIGHTS_CODENAME" "$INSIGHTS_ARCH" | admin tee /etc/apt/sources.list.d/docker.sources >/dev/null
        admin apt-get update
        admin apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      fi;;
    fedora)
      if ! command -v git >/dev/null || ! command -v gh >/dev/null || ! command -v curl >/dev/null || ! command -v unzip >/dev/null; then
        admin dnf install -y git gh curl unzip
      fi
      if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
        admin dnf install -y dnf-plugins-core
        admin curl --fail --silent --show-error --location https://download.docker.com/linux/fedora/docker-ce.repo -o /etc/yum.repos.d/docker-ce.repo
        admin dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      fi;;
    *)
      for INSIGHTS_TOOL in git gh docker curl unzip; do
        if ! command -v "$INSIGHTS_TOOL" >/dev/null; then
          fail "Instalacao automatica Linux: Ubuntu, Debian e Fedora. Nesta distribuicao instale Git, gh, curl, unzip, Docker e Compose conforme README."
        fi
      done
      ;;
  esac
  if ! docker info >/dev/null 2>&1 && ! docker --context default info >/dev/null 2>&1; then
    if command -v systemctl >/dev/null; then admin systemctl start docker; fi
  fi
}

select_docker() {
  command -v docker >/dev/null || fail "Docker ausente. Execute setup."
  INSIGHTS_DOCKER=(docker)
  if [ -n "${INSIGHTS_DOCKER_CONTEXT:-}" ]; then
    INSIGHTS_DOCKER=(docker --context "$INSIGHTS_DOCKER_CONTEXT")
  elif ! docker info >/dev/null 2>&1; then
    if docker --context default info >/dev/null 2>&1; then
      INSIGHTS_DOCKER=(docker --context default)
    elif [ "$(uname -s)" = Linux ] && command -v sudo >/dev/null && sudo -n docker --context default info >/dev/null 2>&1; then
      INSIGHTS_DOCKER=(sudo docker --context default)
    else
      fail "Docker nao esta acessivel. Inicie o Docker ou autorize o acesso ao daemon e execute novamente."
    fi
  fi
  "${INSIGHTS_DOCKER[@]}" info >/dev/null 2>&1 || fail "Docker nao esta pronto."
  "${INSIGHTS_DOCKER[@]}" compose version >/dev/null 2>&1 || fail "Docker Compose ausente. Execute setup."
}

ensure_checkout() {
  local file
  for file in scripts/bootstrap_local.py scripts/macos.sh scripts/macos-askpass.sh scripts/aws.sh scripts/aws-cli-public-key.asc compose.local.yml templates/nginx.conf sources.lock; do
    [ -f "$INSIGHTS_ROOT/$file" ] || fail "Repositorio incompleto: falta $file. O Codex deve usar o clone completo do insights-local, preservando esta pasta."
  done
}

value() { sed -n "s/^$1=//p" "$2" | sed "s/^'//;s/'$//"; }
private_git() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }

checkout_source() {
  INSIGHTS_NAME="$1"
  INSIGHTS_REPOSITORY="$(value "$2_REPOSITORY" "$INSIGHTS_ROOT/sources.lock")"
  INSIGHTS_REF="$(value "$2_REF" "$INSIGHTS_ROOT/sources.lock")"
  [[ "$INSIGHTS_REPOSITORY" =~ ^avanti/[a-zA-Z0-9._-]+$ ]] || fail "Repositorio invalido em sources.lock."
  [[ "$INSIGHTS_REF" =~ ^[0-9a-f]{40}$ ]] || fail "Revisao invalida em sources.lock."
  INSIGHTS_DEST="$INSIGHTS_ROOT/sources/$INSIGHTS_NAME"
  if [ ! -d "$INSIGHTS_DEST/.git" ]; then
    [ ! -e "$INSIGHTS_DEST" ] || fail "A pasta $INSIGHTS_DEST ja existe e nao e um checkout gerenciado."
    mkdir -p "$INSIGHTS_DEST"
    git init -q "$INSIGHTS_DEST"
    git -C "$INSIGHTS_DEST" remote add origin "https://github.com/$INSIGHTS_REPOSITORY.git"
  fi
  if ! git -C "$INSIGHTS_DEST" rev-parse --verify HEAD >/dev/null 2>&1; then
    [ "$(git -C "$INSIGHTS_DEST" remote get-url origin)" = "https://github.com/$INSIGHTS_REPOSITORY.git" ] \
      || fail "A origem do checkout incompleto difere de sources.lock."
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
      if [ "$INSIGHTS_NONINTERACTIVE" = true ] || [ -n "${CI:-}" ]; then
        fail "Falta conectar sua conta GitHub. O Codex deve iniciar o login permitido e orientar a confirmacao no navegador."
      fi
      printf '%s\n' "Conecte sua conta GitHub no navegador e autorize o acesso aos projetos Avanti. Vou continuar depois da confirmacao."
      gh auth login --hostname github.com --git-protocol https --web \
        || fail "A conexao com o GitHub nao terminou. O Codex deve identificar qual confirmacao falta antes de continuar."
    fi
    private_git -C "$INSIGHTS_DEST" fetch --depth 1 origin "$INSIGHTS_REF"
    private_git -C "$INSIGHTS_DEST" checkout --detach -q "$INSIGHTS_REF"
  fi
  [ "$(git -C "$INSIGHTS_DEST" remote get-url origin)" = "https://github.com/$INSIGHTS_REPOSITORY.git" ] \
    || fail "O checkout existente de $INSIGHTS_NAME aponta para outro repositorio. Nenhum arquivo foi sobrescrito."
  printf '%s\n' "Projeto $INSIGHTS_NAME pronto. Codigo e alteracoes locais preservados."
}

compose() {
  [ -f "$INSIGHTS_ROOT/.local/compose.env" ] || fail "Configuracao ausente. Execute setup."
  COMPOSE_PROFILES="" "${INSIGHTS_DOCKER[@]}" compose \
    --project-name "${INSIGHTS_PROJECT_NAME:-insights-local}" \
    --project-directory "$INSIGHTS_ROOT" --env-file "$INSIGHTS_ROOT/.local/compose.env" \
    -f "$INSIGHTS_ROOT/compose.local.yml" "$@"
}

start_stack() {
  [ "$(value LOCAL_MODE "$INSIGHTS_ROOT/.local/compose.env")" = connected ] \
    || fail "Instalacao anterior ainda usa demonstracao. Execute setup para preparar as integracoes reais."
  compose config --quiet
  compose up -d --build --wait --wait-timeout 600 --remove-orphans
  compose exec -T api python /opt/insights-local/scripts/bootstrap_local.py smoke
  INSIGHTS_WEB_PORT="$(value LOCAL_WEB_PORT "$INSIGHTS_ROOT/.local/compose.env")"
  curl --fail --silent --show-error --max-time 30 "http://127.0.0.1:$INSIGHTS_WEB_PORT/login" -o /dev/null
  printf '%s\n' "Interface: http://localhost:$INSIGHTS_WEB_PORT" "Usuario e senha: $INSIGHTS_ROOT/.local/access.txt"
  printf '%s\n' "Atalhos para o Codex: $INSIGHTS_ROOT/.local/codex-projects.html"
  if [ "$INSIGHTS_NO_BROWSER" = false ]; then
    case "$(uname -s)" in
      Darwin) open "http://localhost:$INSIGHTS_WEB_PORT" || printf '%s\n' "A interface esta pronta; abra o endereco acima no navegador.";;
      Linux) if command -v xdg-open >/dev/null; then xdg-open "http://localhost:$INSIGHTS_WEB_PORT" >/dev/null 2>&1 || true; fi;;
    esac
  fi
}

case "$INSIGHTS_COMMAND" in
  setup)
    mkdir -p "$INSIGHTS_ROOT"
    INSIGHTS_ROOT="$(cd "$INSIGHTS_ROOT" && pwd)"
    progress "Preparando as ferramentas do computador."
    trap setup_exit EXIT
    ensure_checkout
    case "$(uname -s)" in
      Darwin)
        # shellcheck source=scripts/macos.sh
        . "$INSIGHTS_ROOT/scripts/macos.sh"
        install_macos;;
      Linux) install_linux;;
      *) fail "Use local.ps1 no Windows.";;
    esac
    select_docker
    # shellcheck source=scripts/aws.sh
    . "$INSIGHTS_ROOT/scripts/aws.sh"
    install_aws
    progress "Conectando o GitHub e preparando os projetos."
    checkout_source backend BACKEND
    checkout_source frontend FRONTEND
    progress "Conectando a AWS e preparando as integracoes."
    ensure_aws_session
    fetch_integrations
    progress "Configurando o ambiente local."
    INSIGHTS_HOST_PLATFORM=linux
    if [ "$(uname -s)" = Darwin ]; then INSIGHTS_HOST_PLATFORM=macos; fi
    INSIGHTS_CONFIG_ARGS=(configure --host-root "$INSIGHTS_ROOT" --host-platform "$INSIGHTS_HOST_PLATFORM")
    if [ -n "$INSIGHTS_PORT" ]; then INSIGHTS_CONFIG_ARGS+=(--port "$INSIGHTS_PORT"); fi
    if [ -n "$INSIGHTS_API_PORT" ]; then INSIGHTS_CONFIG_ARGS+=(--api-port "$INSIGHTS_API_PORT"); fi
    "${INSIGHTS_DOCKER[@]}" run --rm --network none --user "$(id -u):$(id -g)" \
      --mount "type=bind,source=$INSIGHTS_ROOT,target=/bootstrap" \
      python:3.11-slim python /bootstrap/scripts/bootstrap_local.py "${INSIGHTS_CONFIG_ARGS[@]}"
    if [ -f "$INSIGHTS_ROOT/.local/compose.env" ]; then compose down --remove-orphans; fi
    progress "Iniciando o Avanti Insights. O primeiro inicio pode levar varios minutos."
    start_stack
    progress "Avanti Insights pronto. Interface, login, workers e Hub verificados.";;
  start) select_docker; start_stack;;
  stop) select_docker; compose down --remove-orphans;;
  codex) open_codex;;
  status)
    select_docker
    compose ps
    printf '%s\n' "Modo: $(value LOCAL_MODE "$INSIGHTS_ROOT/.local/compose.env")" \
      "Interface: http://localhost:$(value LOCAL_WEB_PORT "$INSIGHTS_ROOT/.local/compose.env")";;
  doctor)
    printf '%s\n' "Sistema: $(uname -s) $(uname -m)" "Pasta: $INSIGHTS_ROOT"
    for INSIGHTS_TOOL in git gh docker aws; do command -v "$INSIGHTS_TOOL" >/dev/null || fail "Dependencia ausente: $INSIGHTS_TOOL. Execute setup."; done
    select_docker
    "${INSIGHTS_DOCKER[@]}" compose version
    if [ -f "$INSIGHTS_ROOT/.local/compose.env" ]; then
      compose config --quiet
      compose ps
      compose exec -T api python /opt/insights-local/scripts/bootstrap_local.py smoke
      for INSIGHTS_SERVICE in worker playwright_worker; do
        # HOSTNAME is expanded by the shell inside the worker container.
        # shellcheck disable=SC2016
        compose exec -T "$INSIGHTS_SERVICE" sh -c 'celery -A app.core.celery inspect ping -d "celery@$HOSTNAME" --timeout=10'
      done
      compose exec -T scheduler python -c 'print("Scheduler local em execucao.")'
    else
      fail "Dependencias prontas, mas falta configurar os projetos. Execute setup."
    fi;;
esac
