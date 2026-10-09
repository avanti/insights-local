#!/usr/bin/env bash
# AWS dependency and browser authentication; sourced by local.sh (Bash 3.2).

aws_version_ready() {
  local version pattern='aws-cli/([0-9]+)\.([0-9]+)\.([0-9]+)'
  command -v aws >/dev/null 2>&1 || return 1
  version="$(aws --version 2>&1)"
  [[ "$version" =~ $pattern ]] || return 1
  [ "${BASH_REMATCH[1]}" -eq 2 ] && [ "${BASH_REMATCH[2]}" -ge 32 ]
}

install_aws_linux() {
  local architecture downloads keyring
  case "$(uname -m)" in
    x86_64) architecture=x86_64;;
    aarch64|arm64) architecture=aarch64;;
    *) fail "AWS CLI requer Linux x86_64 ou ARM64.";;
  esac
  if ! command -v gpg >/dev/null 2>&1; then
    # install_linux has already identified the system-owned os-release.
    case "$ID" in
      ubuntu|debian) admin apt-get install -y gnupg;;
      fedora) admin dnf install -y gnupg2;;
      *) fail "Instale GnuPG para verificar o instalador oficial da AWS.";;
    esac
  fi
  downloads="$INSIGHTS_ROOT/.local/downloads/aws-cli"
  keyring="$downloads/keyring"
  mkdir -p "$keyring" "$HOME/.local/bin"
  chmod 700 "$keyring"
  curl --fail --silent --show-error --location --retry 3 \
    "https://awscli.amazonaws.com/awscli-exe-linux-$architecture.zip" -o "$downloads/awscliv2.zip"
  curl --fail --silent --show-error --location --retry 3 \
    "https://awscli.amazonaws.com/awscli-exe-linux-$architecture.zip.sig" -o "$downloads/awscliv2.zip.sig"
  gpg --batch --homedir "$keyring" --import "$INSIGHTS_ROOT/scripts/aws-cli-public-key.asc" >/dev/null 2>&1
  gpg --batch --homedir "$keyring" --verify "$downloads/awscliv2.zip.sig" "$downloads/awscliv2.zip" \
    >/dev/null 2>&1 || fail "A assinatura do instalador AWS nao foi validada. Nenhum pacote foi instalado."
  unzip -oq "$downloads/awscliv2.zip" -d "$downloads"
  "$downloads/aws/install" --install-dir "$HOME/.local/share/avanti-aws-cli" \
    --bin-dir "$HOME/.local/bin" --update
  hash -r
}

install_aws() {
  if aws_version_ready; then return 0; fi
  printf '%s\n' "Preparando o acesso a AWS para entrar pelo navegador."
  case "$(uname -s)" in
    Darwin)
      mac_prepare_askpass
      mac_prepare_brew || fail "Nao foi possivel preparar o Brew para instalar AWS CLI."
      if command -v aws >/dev/null 2>&1 && mac_brew_run list --versions awscli >/dev/null 2>&1; then
        mac_run "Atualizando AWS CLI" mac_brew_run upgrade awscli
      else
        mac_run "Instalando AWS CLI" mac_brew_run install awscli
      fi;;
    Linux) install_aws_linux;;
    *) fail "Use local.ps1 no Windows.";;
  esac
  aws_version_ready || fail "AWS CLI 2.32.0 ou posterior ainda nao esta disponivel. Confira a instalacao antes de continuar."
}

aws_command() {
  AWS_PAGER="" AWS_CLI_AUTO_PROMPT=off aws --profile "${INSIGHTS_AWS_PROFILE:-avanti-insights-local}" \
    --region "${INSIGHTS_AWS_REGION:-us-east-1}" "$@"
}

ensure_aws_session() {
  if aws_command sts get-caller-identity --cli-connect-timeout 10 --cli-read-timeout 15 >/dev/null 2>&1; then return 0; fi
  if [ "$INSIGHTS_NONINTERACTIVE" = true ] || [ -n "${CI:-}" ]; then
    fail "Falta entrar na AWS. Retome setup com o Codex em modo interativo."
  fi
  printf '%s\n' "Entre na conta AWS da Avanti na janela do navegador, confirme o MFA e autorize o acesso local. A senha fica somente na AWS."
  case "${INSIGHTS_AWS_LOGIN_METHOD:-console}" in
    console)
      aws_command configure set region "${INSIGHTS_AWS_REGION:-us-east-1}"
      aws_command login || fail "O login AWS nao terminou. Confira a confirmacao no navegador e a permissao SignInLocalDevelopmentAccess.";;
    sso)
      aws_command sso login || fail "Configure o perfil SSO autorizado da Avanti e retome setup.";;
    *) fail "INSIGHTS_AWS_LOGIN_METHOD deve ser console ou sso.";;
  esac
  aws_command sts get-caller-identity --cli-connect-timeout 10 --cli-read-timeout 15 >/dev/null 2>&1 \
    || fail "A sessao AWS nao ficou disponivel. O Codex deve consultar a etapa de autenticacao."
}

fetch_integrations() {
  # Never put the secret in an argument, shell variable, log or raw JSON file.
  { aws_command secretsmanager get-secret-value --secret-id "${INSIGHTS_SECRET_ID:-synapse/review-app/env}" \
      --query SecretString --output json --cli-connect-timeout 10 --cli-read-timeout 30 \
      && printf '\nINSIGHTS_SECRET_COMPLETE\n'; } | \
    "${INSIGHTS_DOCKER[@]}" run --rm -i --network none --user "$(id -u):$(id -g)" \
      --mount "type=bind,source=$INSIGHTS_ROOT,target=/bootstrap" python:3.11-slim \
      python /bootstrap/scripts/bootstrap_local.py import-secret --require-complete \
    || fail "Nao foi possivel preparar as integracoes. Confira a permissao de leitura do segredo ou as variaveis faltantes; a configuracao anterior foi preservada."
}
