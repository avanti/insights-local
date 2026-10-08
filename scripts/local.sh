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
INSIGHTS_MODE=""
INSIGHTS_PORT=""
INSIGHTS_API_PORT=""
INSIGHTS_NO_BROWSER=false
INSIGHTS_NONINTERACTIVE=false
INSIGHTS_DOCKER=(docker)

usage() {
  cat <<'USAGE'
Avanti Insights local
Uso: bash scripts/local.sh <setup|start|stop|status|doctor|help> [opcoes]
  --root DIRETORIO       Pasta do instalador (util para o script avulso).
  --mode demo|connected  Modo inicial demo; execucoes seguintes preservam o modo.
  --port NUMERO          Porta da interface (padrao 3000).
  --api-port NUMERO      Porta da API (padrao 8000).
  --no-browser          Nao abrir o navegador.
  --non-interactive     Nao iniciar login interativo no GitHub.
setup instala dependencias ausentes, clona, configura e inicia.
start/stop/status/doctor nao instalam software.
USAGE
}

fail() { printf '%s\n' "$*" >&2; exit 2; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root|--mode|--port|--api-port)
      [ "$#" -ge 2 ] || fail "Falta o valor de $1."
      case "$1" in
        --root) INSIGHTS_ROOT="$2";;
        --mode) INSIGHTS_MODE="$2";;
        --port) INSIGHTS_PORT="$2";;
        --api-port) INSIGHTS_API_PORT="$2";;
      esac
      shift 2;;
    --no-browser) INSIGHTS_NO_BROWSER=true; shift;;
    --non-interactive) INSIGHTS_NONINTERACTIVE=true; shift;;
    *) fail "Opcao desconhecida: $1";;
  esac
done
case "$INSIGHTS_COMMAND" in setup|start|stop|status|doctor|help|--help|-h) ;; *) fail "Comando desconhecido: $INSIGHTS_COMMAND";; esac
case "$INSIGHTS_MODE" in ""|demo|connected) ;; *) fail "Modo deve ser demo ou connected.";; esac
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
if [ "$INSIGHTS_COMMAND" != setup ] && { [ -n "$INSIGHTS_MODE" ] || [ -n "$INSIGHTS_PORT" ] || [ -n "$INSIGHTS_API_PORT" ]; }; then
  fail "Use setup para alterar modo ou portas."
fi
export PATH="$HOME/.local/bin:$HOME/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

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

install_macos() {
  if ! git --version >/dev/null 2>&1; then
    xcode-select --install || true
    fail "Conclua a instalacao das ferramentas Apple na janela aberta e execute setup novamente."
  fi
  if ! command -v gh >/dev/null; then
    INSIGHTS_TMP="$(mktemp -d)"
    INSIGHTS_ARCH="$(uname -m)"
    case "$INSIGHTS_ARCH" in arm64) ;; x86_64) INSIGHTS_ARCH=amd64;; *) fail "Arquitetura macOS nao suportada.";; esac
    INSIGHTS_ASSET="gh_2.102.0_macOS_$INSIGHTS_ARCH.zip"
    curl --fail --silent --show-error --location "https://github.com/cli/cli/releases/download/v2.102.0/$INSIGHTS_ASSET" -o "$INSIGHTS_TMP/$INSIGHTS_ASSET"
    curl --fail --silent --show-error --location https://github.com/cli/cli/releases/download/v2.102.0/gh_2.102.0_checksums.txt -o "$INSIGHTS_TMP/checksums.txt"
    INSIGHTS_EXPECTED="$(awk -v asset="$INSIGHTS_ASSET" '$2 == asset {print $1}' "$INSIGHTS_TMP/checksums.txt")"
    [ -n "$INSIGHTS_EXPECTED" ] || fail "Checksum do GitHub CLI nao encontrado."
    INSIGHTS_ACTUAL="$(shasum -a 256 "$INSIGHTS_TMP/$INSIGHTS_ASSET" | awk '{print $1}')"
    [ "$INSIGHTS_EXPECTED" = "$INSIGHTS_ACTUAL" ] || fail "Download do GitHub CLI nao passou na verificacao."
    unzip -q "$INSIGHTS_TMP/$INSIGHTS_ASSET" -d "$INSIGHTS_TMP/unpacked"
    mkdir -p "$HOME/.local/bin"
    cp "$INSIGHTS_TMP/unpacked/gh_2.102.0_macOS_$INSIGHTS_ARCH/bin/gh" "$HOME/.local/bin/gh"
    chmod 755 "$HOME/.local/bin/gh"
    rm -rf "$INSIGHTS_TMP"
  fi
  if [ ! -d /Applications/Docker.app ]; then
    INSIGHTS_TMP="$(mktemp -d)"
    INSIGHTS_ARCH="$(uname -m)"
    case "$INSIGHTS_ARCH" in arm64) ;; x86_64) INSIGHTS_ARCH=amd64;; *) fail "Arquitetura macOS nao suportada.";; esac
    curl --fail --silent --show-error --location "https://desktop.docker.com/mac/main/$INSIGHTS_ARCH/Docker.dmg" -o "$INSIGHTS_TMP/Docker.dmg"
    INSIGHTS_MOUNT="$INSIGHTS_TMP/mounted"
    hdiutil attach "$INSIGHTS_TMP/Docker.dmg" -nobrowse -mountpoint "$INSIGHTS_MOUNT"
    if ! admin "$INSIGHTS_MOUNT/Docker.app/Contents/MacOS/install"; then
      hdiutil detach "$INSIGHTS_MOUNT" || true
      fail "Instalacao do Docker interrompida; execute setup novamente."
    fi
    hdiutil detach "$INSIGHTS_MOUNT"
    rm -rf "$INSIGHTS_TMP"
  fi
  if ! docker info >/dev/null 2>&1; then
    open -a Docker
    printf '%s\n' "Conclua os termos e a configuracao inicial na janela do Docker."
    INSIGHTS_ATTEMPT=0
    until docker info >/dev/null 2>&1; do
      INSIGHTS_ATTEMPT=$((INSIGHTS_ATTEMPT + 1))
      [ "$INSIGHTS_ATTEMPT" -lt 60 ] || fail "Docker ainda nao esta pronto. Conclua a janela e execute setup novamente."
      sleep 5
    done
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

ensure_bundle() {
  mkdir -p "$INSIGHTS_ROOT"
  INSIGHTS_ROOT="$(cd "$INSIGHTS_ROOT" && pwd)"
  if [ -f "$INSIGHTS_ROOT/scripts/bootstrap_local.py" ]; then return; fi
  INSIGHTS_TMP="$(mktemp -d)"
  curl --fail --silent --show-error --location https://github.com/avanti/insights-local/archive/refs/tags/v0.1.0.zip -o "$INSIGHTS_TMP/starter.zip"
  unzip -q "$INSIGHTS_TMP/starter.zip" -d "$INSIGHTS_TMP/unpacked"
  cp -R "$INSIGHTS_TMP/unpacked/insights-local-0.1.0/." "$INSIGHTS_ROOT/"
  rm -rf "$INSIGHTS_TMP"
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
  [ -z "$(git -C "$INSIGHTS_DEST" status --porcelain)" ] || fail "Existem alteracoes em $INSIGHTS_DEST; preserve-as antes de continuar."
  if ! git -C "$INSIGHTS_DEST" rev-parse --verify HEAD >/dev/null 2>&1; then
    [ "$(git -C "$INSIGHTS_DEST" remote get-url origin)" = "https://github.com/$INSIGHTS_REPOSITORY.git" ] \
      || fail "A origem do checkout incompleto difere de sources.lock."
    if ! gh auth status --hostname github.com >/dev/null 2>&1; then
      if [ "$INSIGHTS_NONINTERACTIVE" = true ] || [ -n "${CI:-}" ]; then
        fail "Autentique o GitHub CLI com gh auth login e autorize acesso aos repositorios Avanti."
      fi
      gh auth login --hostname github.com --git-protocol https --web
    fi
    private_git -C "$INSIGHTS_DEST" fetch --depth 1 origin "$INSIGHTS_REF"
    private_git -C "$INSIGHTS_DEST" checkout --detach -q "$INSIGHTS_REF"
  fi
  [ "$(git -C "$INSIGHTS_DEST" rev-parse HEAD)" = "$INSIGHTS_REF" ] || fail "Checkout $INSIGHTS_NAME difere de sources.lock. Nenhuma alteracao foi sobrescrita."
}

compose() {
  [ -f "$INSIGHTS_ROOT/.local/compose.env" ] || fail "Configuracao ausente. Execute setup."
  INSIGHTS_PROFILES=(--profile demo)
  if [ "$(value LOCAL_MODE "$INSIGHTS_ROOT/.local/compose.env")" = connected ]; then INSIGHTS_PROFILES=(--profile connected); fi
  COMPOSE_PROFILES="" "${INSIGHTS_DOCKER[@]}" compose \
    --project-name "${INSIGHTS_PROJECT_NAME:-insights-local}" \
    --project-directory "$INSIGHTS_ROOT" --env-file "$INSIGHTS_ROOT/.local/compose.env" \
    -f "$INSIGHTS_ROOT/compose.local.yml" "${INSIGHTS_PROFILES[@]}" "$@"
}

start_stack() {
  compose config --quiet
  compose up -d --build --wait --wait-timeout 600 --remove-orphans
  compose exec -T api python /opt/insights-local/scripts/bootstrap_local.py smoke
  INSIGHTS_WEB_PORT="$(value LOCAL_WEB_PORT "$INSIGHTS_ROOT/.local/compose.env")"
  curl --fail --silent --show-error --max-time 30 "http://127.0.0.1:$INSIGHTS_WEB_PORT/login" -o /dev/null
  printf '%s\n' "Interface: http://localhost:$INSIGHTS_WEB_PORT" "Usuario e senha: $INSIGHTS_ROOT/.local/access.txt"
  if [ "$INSIGHTS_NO_BROWSER" = false ]; then
    case "$(uname -s)" in
      Darwin) open "http://localhost:$INSIGHTS_WEB_PORT";;
      Linux) if command -v xdg-open >/dev/null; then xdg-open "http://localhost:$INSIGHTS_WEB_PORT" >/dev/null 2>&1 || true; fi;;
    esac
  fi
}

case "$INSIGHTS_COMMAND" in
  setup)
    case "$(uname -s)" in Darwin) install_macos;; Linux) install_linux;; *) fail "Use local.ps1 no Windows.";; esac
    select_docker
    ensure_bundle
    checkout_source backend BACKEND
    checkout_source frontend FRONTEND
    if [ -f "$INSIGHTS_ROOT/.local/compose.env" ]; then compose down --remove-orphans; fi
    INSIGHTS_CONFIG_ARGS=(configure)
    if [ -n "$INSIGHTS_MODE" ]; then INSIGHTS_CONFIG_ARGS+=(--mode "$INSIGHTS_MODE"); fi
    if [ -n "$INSIGHTS_PORT" ]; then INSIGHTS_CONFIG_ARGS+=(--port "$INSIGHTS_PORT"); fi
    if [ -n "$INSIGHTS_API_PORT" ]; then INSIGHTS_CONFIG_ARGS+=(--api-port "$INSIGHTS_API_PORT"); fi
    "${INSIGHTS_DOCKER[@]}" run --rm --network none --user "$(id -u):$(id -g)" \
      --mount "type=bind,source=$INSIGHTS_ROOT,target=/bootstrap" \
      python:3.11-slim python /bootstrap/scripts/bootstrap_local.py "${INSIGHTS_CONFIG_ARGS[@]}"
    start_stack;;
  start) select_docker; start_stack;;
  stop) select_docker; compose down --remove-orphans;;
  status)
    select_docker
    compose ps
    printf '%s\n' "Modo: $(value LOCAL_MODE "$INSIGHTS_ROOT/.local/compose.env")" \
      "Interface: http://localhost:$(value LOCAL_WEB_PORT "$INSIGHTS_ROOT/.local/compose.env")";;
  doctor)
    printf '%s\n' "Sistema: $(uname -s) $(uname -m)" "Pasta: $INSIGHTS_ROOT"
    for INSIGHTS_TOOL in git gh docker; do command -v "$INSIGHTS_TOOL" >/dev/null || fail "Dependencia ausente: $INSIGHTS_TOOL. Execute setup."; done
    select_docker
    "${INSIGHTS_DOCKER[@]}" compose version
    if [ -f "$INSIGHTS_ROOT/.local/compose.env" ]; then
      compose config --quiet
      compose ps
      compose exec -T api python /opt/insights-local/scripts/bootstrap_local.py smoke
    else
      fail "Dependencias prontas, mas falta configurar os projetos. Execute setup."
    fi;;
esac
