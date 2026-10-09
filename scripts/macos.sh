#!/usr/bin/env bash
# Loaded by local.sh; definitions only, so the installation flow can be tested.

mac_run() {
  local description="$1"
  shift
  printf '\n[%s] %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')" "$description" >> "$INSIGHTS_MAC_LOG"
  if "$@" >> "$INSIGHTS_MAC_LOG" 2>&1; then return 0; fi
  printf '%s\n' "$description nao foi concluido. O Codex pode consultar $INSIGHTS_MAC_LOG e retomar esta etapa." >&2
  return 1
}

mac_wait() {
  local description="$1" attempts=0
  shift
  until "$@" >/dev/null 2>&1; do
    if [ "$attempts" -ge "$INSIGHTS_MAC_WAIT_ATTEMPTS" ]; then
      printf '%s\n' "$description ainda nao terminou. Conclua a janela aberta e diga continuar ao Codex." >&2
      return 1
    fi
    sleep 5
    attempts=$((attempts + 1))
  done
}

mac_git_ready() { xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; }

mac_prepare_git() {
  if git --version >/dev/null 2>&1; then return 0; fi
  if [ "$INSIGHTS_NONINTERACTIVE" = true ]; then
    printf '%s\n' "Falta confirmar a instalacao das ferramentas Apple. Retome com o Codex em modo interativo." >&2
    return 1
  fi
  printf '%s\n' "Na janela das ferramentas Apple, escolha Instalar e aceite os termos. Vou aguardar e continuar."
  mac_run "Iniciando ferramentas Apple" xcode-select --install || true
  mac_wait "A instalacao das ferramentas Apple" mac_git_ready
}

mac_find_brew() {
  if command -v brew >/dev/null 2>&1; then INSIGHTS_BREW="$(command -v brew)"
  elif [ -x /opt/homebrew/bin/brew ]; then INSIGHTS_BREW=/opt/homebrew/bin/brew
  elif [ -x /usr/local/bin/brew ]; then INSIGHTS_BREW=/usr/local/bin/brew
  else return 1
  fi
  if [ "$INSIGHTS_BREW" != brew ]; then
    INSIGHTS_BREW_DIR="$(dirname "$INSIGHTS_BREW")"
    export PATH="$INSIGHTS_BREW_DIR:$PATH"
  fi
}

mac_admin() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif sudo -n true >/dev/null 2>&1; then sudo -n "$@"
  elif [ "$INSIGHTS_NONINTERACTIVE" = true ]; then
    printf '%s\n' "A instalacao precisa de autorizacao de administrador pelo usuario." >&2
    return 1
  else
    local privileged_command
    printf -v privileged_command '%q ' "$@"
    osascript -e 'on run argv' -e 'do shell script (item 1 of argv) with administrator privileges' -e 'end run' "$privileged_command"
  fi
}

mac_prepare_askpass() {
  INSIGHTS_ASKPASS="$INSIGHTS_ROOT/.local/macos-sudo-askpass.sh"
  cp "$INSIGHTS_ROOT/scripts/macos-askpass.sh" "$INSIGHTS_ASKPASS"
  chmod 700 "$INSIGHTS_ASKPASS"
}

mac_brew_run() (
  export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1
  if [ "$INSIGHTS_NONINTERACTIVE" = true ]; then unset SUDO_ASKPASS; export HOMEBREW_NO_SUDO=1
  else unset HOMEBREW_NO_SUDO; export SUDO_ASKPASS="$INSIGHTS_ASKPASS"
  fi
  "$INSIGHTS_BREW" "$@"
)

mac_download_verified() {
  local url="$1" destination="$2" expected="$3" actual
  if [ -f "$destination" ]; then
    actual="$(shasum -a 256 "$destination" | awk '{print $1}')"
    if [ "$actual" = "$expected" ]; then return 0; fi
  fi
  mac_run "Baixando pacote oficial" curl --fail --silent --show-error --location \
    --retry 3 --connect-timeout 20 --max-time 900 "$url" -o "$destination" || return 1
  actual="$(shasum -a 256 "$destination" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    printf '%s\n' "O download nao passou na verificacao. O Codex deve repetir o download antes de instalar." >&2
    return 1
  fi
}

mac_prepare_brew() {
  if mac_find_brew; then return 0; fi
  local downloads="$INSIGHTS_ROOT/.local/downloads" architecture
  mkdir -p "$downloads"
  architecture="$(uname -m)"
  printf '%s\n' "Preparando o Homebrew. Se aparecer uma janela de autorizacao, confirme nela para continuar."
  if [ "$architecture" = arm64 ]; then
    mac_download_verified \
      https://github.com/Homebrew/brew/releases/download/7.0.9/Homebrew.pkg \
      "$downloads/Homebrew-7.0.9.pkg" e021295947a4a9b7ca1a8eff310c9ea1db14d923c5acf7d79e325b60a81f1a15 || return 1
    mac_run "Instalando Homebrew" mac_admin /usr/sbin/installer -pkg "$downloads/Homebrew-7.0.9.pkg" -target / || return 1
  elif [ "$architecture" = x86_64 ]; then
    mac_download_verified \
      https://raw.githubusercontent.com/Homebrew/install/8ab1549dfa1189fd4d818a2116592d8f0ee06d8c/install.sh \
      "$downloads/homebrew-install.sh" 5f333bbe53bc490e51e7ccb1df8779b3dd6ee73a1a7379efda216edb08ccb148 || return 1
    # Official shell installer for Intel; only sudo receives the local askpass result.
    if [ "$INSIGHTS_NONINTERACTIVE" = true ]; then
      mac_run "Instalando Homebrew" env NONINTERACTIVE=1 HOMEBREW_NO_SUDO=1 /bin/bash "$downloads/homebrew-install.sh" || return 1
    else
      mac_run "Instalando Homebrew" env NONINTERACTIVE=1 SUDO_ASKPASS="$INSIGHTS_ASKPASS" \
        /bin/bash "$downloads/homebrew-install.sh" || return 1
    fi
  else
    printf '%s\n' "Este Mac usa uma arquitetura nao suportada pelo instalador." >&2
    return 1
  fi
  mac_find_brew || { printf '%s\n' "O Homebrew ainda nao esta disponivel. O Codex deve consultar o diagnostico da instalacao." >&2; return 1; }
}

mac_docker_ready() {
  if ! command -v docker >/dev/null 2>&1; then return 1; fi
  if [ -n "${INSIGHTS_DOCKER_CONTEXT:-}" ]; then docker --context "$INSIGHTS_DOCKER_CONTEXT" info >/dev/null 2>&1
  else docker info >/dev/null 2>&1 || docker --context default info >/dev/null 2>&1
  fi
}

mac_docker_app() {
  if [ -d /Applications/Docker.app ]; then printf '%s\n' /Applications/Docker.app
  elif [ -d "$HOME/Applications/Docker.app" ]; then printf '%s\n' "$HOME/Applications/Docker.app"
  else return 1
  fi
}

install_macos() {
  INSIGHTS_MAC_LOG="$INSIGHTS_ROOT/.local/install-macos.log"
  INSIGHTS_MAC_WAIT_ATTEMPTS="${INSIGHTS_INSTALL_WAIT_ATTEMPTS:-360}"
  [[ "$INSIGHTS_MAC_WAIT_ATTEMPTS" =~ ^[0-9]{1,4}$ ]] || fail "Tempo de espera da instalacao invalido."
  if [ "$INSIGHTS_MAC_WAIT_ATTEMPTS" -le 0 ] || [ "$INSIGHTS_MAC_WAIT_ATTEMPTS" -gt 1440 ]; then
    fail "Tempo de espera da instalacao invalido."
  fi
  mac_prepare_git || fail "Falta concluir a instalacao das ferramentas Apple. Diga continuar ao Codex depois de confirmar a janela."
  local app="" needs_brew=false
  if ! command -v gh >/dev/null 2>&1; then needs_brew=true; fi
  if ! mac_docker_ready || ! docker compose version >/dev/null 2>&1; then
    if ! app="$(mac_docker_app)"; then needs_brew=true; fi
  fi
  if [ "$needs_brew" = true ]; then
    mac_prepare_askpass
    mac_prepare_brew || fail "A preparacao do Homebrew parou. O Codex deve consultar $INSIGHTS_MAC_LOG antes de pedir uma acao."
    if ! command -v gh >/dev/null 2>&1; then
      printf '%s\n' "Instalando o acesso ao GitHub. Isso acontece automaticamente."
      mac_run "Instalando GitHub CLI" mac_brew_run install gh || fail "O acesso ao GitHub ainda nao foi instalado. O Codex deve consultar $INSIGHTS_MAC_LOG."
    fi
    if ! mac_docker_ready || ! docker compose version >/dev/null 2>&1; then
      if ! app="$(mac_docker_app)"; then
        printf '%s\n' "Instalando o Docker pelo Homebrew. Vou baixar e preparar os arquivos automaticamente."
        mac_run "Instalando Docker Desktop" mac_brew_run install --cask --require-sha docker-desktop \
          || fail "A instalacao do Docker parou. O Codex deve consultar $INSIGHTS_MAC_LOG para identificar o motivo."
        app="$(mac_docker_app)" || fail "O Homebrew terminou, mas o Docker nao foi localizado. O Codex deve conferir $INSIGHTS_MAC_LOG."
      fi
    fi
  fi
  if [ -n "$app" ]; then export PATH="$app/Contents/Resources/bin:$PATH"; fi
  if ! mac_docker_ready; then
    if [ "$INSIGHTS_NONINTERACTIVE" = true ]; then fail "Falta concluir a primeira abertura do Docker. Retome com o Codex em modo interativo."; fi
    app="${app:-$(mac_docker_app)}"
    mac_run "Abrindo Docker Desktop" open "$app" || fail "O Docker nao abriu. O Codex deve consultar o diagnostico em $INSIGHTS_MAC_LOG."
    printf '%s\n' "Na janela do Docker, aceite os termos se concordar. Vou aguardar a inicializacao e continuar."
    mac_wait "A configuracao inicial do Docker" mac_docker_ready || fail "Conclua a janela do Docker e diga continuar ao Codex."
  fi
  printf '%s\n' "Ferramentas prontas. Vou preparar os projetos e abrir o Avanti Insights."
}
