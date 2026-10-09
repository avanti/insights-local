#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('setup', 'start', 'stop', 'status', 'doctor', 'codex', 'help')]
    [string]$Command = 'help',
    [string]$Root,
    [ValidateRange(1024, 65535)]
    [int]$Port,
    [ValidateRange(1024, 65535)]
    [int]$ApiPort,
    [switch]$NoBrowser,
    [switch]$NonInteractive,
    [ValidateSet('frontend', 'backend', 'all')]
    [string]$Project = 'all'
)
$ErrorActionPreference = 'Stop'
$script:DockerContext = $env:INSIGHTS_DOCKER_CONTEXT
if (-not $Root) {
    if ((Split-Path $PSScriptRoot -Leaf) -eq 'scripts') {
        $Root = Split-Path $PSScriptRoot -Parent
    } else {
        $Root = Join-Path (Get-Location).Path 'insights-local'
    }
}
$Root = [IO.Path]::GetFullPath($Root)

function Show-Usage {
    Write-Host 'Avanti Insights local'
    Write-Host '.\scripts\local.ps1 <setup|start|stop|status|doctor|codex|help>'
    Write-Host 'Opcoes: -Root PASTA -Port 3000 -ApiPort 8000 -NoBrowser -NonInteractive'
    Write-Host 'setup instala dependencias ausentes, clona, configura e inicia.'
    Write-Host 'Os outros comandos nao instalam software.'
    Write-Host 'codex -Project frontend|backend|all abre as pastas no Codex (padrao all).'
    Write-Host 'Confira o cadastro dos projetos na barra lateral do aplicativo.'
}

function Open-Codex {
    $links = @()
    foreach ($name in @('frontend', 'backend')) {
        if ($Project -ne 'all' -and $Project -ne $name) { continue }
        $link = Join-Path $Root (".local\codex\$name.link")
        if (-not (Test-Path $link)) { throw 'Atalhos Codex ausentes. Execute setup novamente na mesma pasta.' }
        if (-not (Test-Path (Join-Path $Root "sources\$name\.git") -PathType Container)) {
            throw "Pasta do aplicativo $name ausente. Execute setup."
        }
        $url = [IO.File]::ReadAllText($link).Trim()
        if ($url -cnotmatch '^codex://new\?path=[a-zA-Z0-9%._~-]+$') { throw 'Atalho Codex invalido. Execute setup novamente.' }
        $links += $url
    }
    foreach ($url in $links) { Start-Process -FilePath $url }
    Write-Host 'Solicitada a abertura das pastas no Codex. Confira se aparecem como projetos na barra lateral.'
}

function Invoke-Native {
    param([string]$Executable, [string[]]$Arguments, [string]$InputText)
    if ($PSBoundParameters.ContainsKey('InputText')) {
        $savedEncoding = $OutputEncoding
        try {
            $OutputEncoding = New-Object Text.UTF8Encoding($false)
            $InputText | & $Executable @Arguments
        } finally { $OutputEncoding = $savedEncoding }
    } else { & $Executable @Arguments }
    if ($LASTEXITCODE -ne 0) { throw "Falha em $Executable (codigo $LASTEXITCODE)." }
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath;$env:Path"
}

function Write-SetupProgress {
    param([string]$Stage)
    $script:SetupStage = $Stage
    $local = Join-Path $Root '.local'
    New-Item -ItemType Directory -Force -Path $local | Out-Null
    [IO.File]::WriteAllText((Join-Path $local 'setup-progress.txt'), "Etapa: $Stage`nPasta: $Root`n")
    Write-Host $Stage
}

function Install-Package {
    param([string]$Id, [string]$Operation = 'install')
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Instale ou atualize o App Installer da Microsoft Store para disponibilizar winget, e execute setup novamente.'
    }
    # Package prompts remain visible; Docker terms are completed in its own app.
    & winget $Operation --exact --id $Id --source winget --accept-source-agreements
    if ($LASTEXITCODE -eq 3010) {
        throw 'A instalacao requer reinicializacao. Reinicie o computador e diga continuar ao Codex para retomar.'
    }
    if ($LASTEXITCODE -ne 0) { throw "Instalacao de $Id interrompida (codigo $LASTEXITCODE)." }
    Refresh-Path
}

function Test-Docker {
    param([string]$Context)
    $ErrorActionPreference = 'Continue'
    $dockerArgs = @()
    if ($Context) { $dockerArgs += @('--context', $Context) }
    $dockerArgs += 'info'
    & docker @dockerArgs *> $null
    return $LASTEXITCODE -eq 0
}

function Install-Dependencies {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') {
        throw 'Use local.sh no macOS e no Linux.'
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Install-Package 'Git.Git' }
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Install-Package 'GitHub.cli' }
    Install-Aws
    $wslReady = $false
    if (Get-Command wsl.exe -ErrorAction SilentlyContinue) {
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & wsl.exe --status *> $null
        $wslReady = $LASTEXITCODE -eq 0
        $ErrorActionPreference = $savedPreference
    }
    if (-not $wslReady) {
        Write-Host 'O Windows vai solicitar autorizacao para preparar o WSL.'
        $process = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-Command',
            '"wsl.exe --install --no-distribution; exit $LASTEXITCODE"'
        )
        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
            throw "Configuracao do WSL interrompida (codigo $($process.ExitCode))."
        }
        throw 'Conclua a preparacao do Windows e reinicie se solicitado. Depois diga continuar ao Codex para retomar na mesma pasta.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Install-Package 'Docker.DockerDesktop' }
    if (-not (Test-Docker $script:DockerContext)) {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (-not (Test-Path $desktop)) {
            $desktop = Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'
        }
        if (Test-Path $desktop) { Start-Process $desktop }
        Write-Host 'Na janela do Docker, aceite os termos se concordar. Vou aguardar a inicializacao e continuar.'
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            if (Test-Docker $script:DockerContext) { return }
            Start-Sleep -Seconds 5
        }
        throw 'Conclua a janela do Docker e diga continuar ao Codex para retomar.'
    }
}

function Test-AwsVersion {
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) { return $false }
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $versionText = (& aws --version 2>&1 | Out-String) } finally { $ErrorActionPreference = $saved }
    return ($versionText -match 'aws-cli/(2\.(\d+)\.\d+)' -and [int]$Matches[2] -ge 32)
}

function Install-Aws {
    if (Test-AwsVersion) { return }
    Write-Host 'Preparando o acesso a AWS para entrar pelo navegador.'
    if (Get-Command aws -ErrorAction SilentlyContinue) { Install-Package 'Amazon.AWSCLI' 'upgrade' }
    else { Install-Package 'Amazon.AWSCLI' }
    if (-not (Test-AwsVersion)) { throw 'AWS CLI 2.32.0 ou posterior ainda nao esta disponivel.' }
}

function Get-AwsArguments {
    $profile = $env:INSIGHTS_AWS_PROFILE
    if (-not $profile) { $profile = 'avanti-insights-local' }
    $region = $env:INSIGHTS_AWS_REGION
    if (-not $region) { $region = 'us-east-1' }
    return @('--profile', $profile, '--region', $region)
}

function Test-AwsSession {
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $arguments = (Get-AwsArguments) + @('sts', 'get-caller-identity', '--cli-connect-timeout', '10', '--cli-read-timeout', '15')
        & aws @arguments *> $null
        return $LASTEXITCODE -eq 0
    } finally { $ErrorActionPreference = $saved }
}

function Ensure-AwsSession {
    $env:AWS_PAGER = ''
    $env:AWS_CLI_AUTO_PROMPT = 'off'
    if (Test-AwsSession) { return }
    if ($NonInteractive -or $env:CI) { throw 'Falta entrar na AWS. Retome setup com o Codex em modo interativo.' }
    Write-Host 'Entre na conta AWS da Avanti na janela do navegador, confirme o MFA e autorize o acesso local. A senha fica somente na AWS.'
    $arguments = Get-AwsArguments
    $method = $env:INSIGHTS_AWS_LOGIN_METHOD
    if (-not $method) { $method = 'console' }
    if ($method -eq 'console') {
        $region = $env:INSIGHTS_AWS_REGION
        if (-not $region) { $region = 'us-east-1' }
        Invoke-Native 'aws' ($arguments + @('configure', 'set', 'region', $region))
        Invoke-Native 'aws' ($arguments + @('login'))
    } elseif ($method -eq 'sso') {
        Invoke-Native 'aws' ($arguments + @('sso', 'login'))
    } else { throw 'INSIGHTS_AWS_LOGIN_METHOD deve ser console ou sso.' }
    if (-not (Test-AwsSession)) { throw 'A sessao AWS nao ficou disponivel. Confira a autenticacao no navegador.' }
}

function Protect-LocalFiles {
    $local = Join-Path $Root '.local'
    New-Item -ItemType Directory -Force $local | Out-Null
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    Invoke-Native 'icacls.exe' @($local, '/inheritance:r', '/grant:r', "${identity}:(OI)(CI)F",
        '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '/T', '/Q')
}

function Fetch-Integrations {
    $secretId = $env:INSIGHTS_SECRET_ID
    if (-not $secretId) { $secretId = 'synapse/review-app/env' }
    $arguments = (Get-AwsArguments) + @('secretsmanager', 'get-secret-value', '--secret-id', $secretId,
        '--query', 'SecretString', '--output', 'json', '--cli-connect-timeout', '10', '--cli-read-timeout', '30')
    # Keep the response in memory; never echo it or write raw JSON to disk.
    $secretJson = & aws @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel obter as integracoes. Confira a permissao de leitura do segredo AWS.' }
    try {
        Invoke-Docker @('run', '--rm', '-i', '--network', 'none', '--mount', "type=bind,source=$Root,target=/bootstrap",
            'python:3.11-slim', 'python', '/bootstrap/scripts/bootstrap_local.py', 'import-secret') -InputText ($secretJson -join "`n")
    } finally { $secretJson = $null }
    Protect-LocalFiles
}

function Select-Docker {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker ausente. Execute setup.' }
    if (-not (Test-Docker $script:DockerContext)) {
        if (-not $script:DockerContext -and (Test-Docker 'default')) {
            $script:DockerContext = 'default'
        } else {
            throw 'Docker inacessivel. Inicie o Docker Desktop e execute novamente.'
        }
    }
    Invoke-Docker @('compose', 'version')
}

function Invoke-Docker {
    param([Parameter(Position = 0)][string[]]$DockerArguments, [string]$InputText)
    $prefix = @()
    if ($script:DockerContext) { $prefix += @('--context', $script:DockerContext) }
    if ($PSBoundParameters.ContainsKey('InputText')) {
        Invoke-Native 'docker' ($prefix + $DockerArguments) -InputText $InputText
    } else { Invoke-Native 'docker' ($prefix + $DockerArguments) }
}

function Ensure-Checkout {
    foreach ($file in @('scripts/bootstrap_local.py', 'scripts/macos.sh', 'scripts/macos-askpass.sh', 'scripts/aws.sh', 'scripts/aws-cli-public-key.asc', 'templates/nginx.conf', 'compose.local.yml', 'sources.lock')) {
        if (-not (Test-Path (Join-Path $Root $file) -PathType Leaf)) {
            throw "Repositorio incompleto: falta $file. O Codex deve usar o clone completo do insights-local, preservando esta pasta."
        }
    }
}

function Get-LiteralValue {
    param([string]$Key, [string]$Path)
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line.StartsWith("$Key=")) {
            return $line.Substring($Key.Length + 1).Trim().Trim("'")
        }
    }
    return ''
}

function Ensure-Source {
    param([string]$Name, [string]$Prefix)
    $lock = Join-Path $Root 'sources.lock'
    $repository = Get-LiteralValue ($Prefix + '_REPOSITORY') $lock
    $revision = Get-LiteralValue ($Prefix + '_REF') $lock
    if ($repository -notmatch '^avanti/[a-zA-Z0-9._-]+$' -or $revision -notmatch '^[0-9a-f]{40}$') {
        throw 'Repositorio ou revisao invalida em sources.lock.'
    }
    $destination = Join-Path $Root ("sources\" + $Name)
    if (-not (Test-Path (Join-Path $destination '.git'))) {
        if (Test-Path $destination) { throw "A pasta $destination ja existe e nao e um checkout gerenciado." }
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
        Invoke-Native 'git' @('init', '-q', $destination)
        Invoke-Native 'git' @('-C', $destination, 'remote', 'add', 'origin', "https://github.com/$repository.git")
    }
    $savedPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & git -C $destination rev-parse --verify HEAD *> $null
    $hasHead = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $savedPreference
    if (-not $hasHead) {
        $origin = & git -C $destination remote get-url origin
        if ($LASTEXITCODE -ne 0 -or $origin -ne "https://github.com/$repository.git") {
            throw 'A origem do checkout incompleto difere de sources.lock.'
        }
        $savedPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & gh auth status --hostname github.com *> $null
        $authenticated = $LASTEXITCODE -eq 0
        $ErrorActionPreference = $savedPreference
        if (-not $authenticated) {
            if ($NonInteractive -or $env:CI) { throw 'Falta conectar sua conta GitHub. O Codex deve iniciar o login permitido e orientar a confirmacao no navegador.' }
            Write-Host 'Conecte sua conta GitHub no navegador e autorize o acesso aos projetos Avanti. Vou continuar depois da confirmacao.'
            Invoke-Native 'gh' @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web')
        }
        $auth = @('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', '-C', $destination)
        Invoke-Native 'git' ($auth + @('fetch', '--depth', '1', 'origin', $revision))
        Invoke-Native 'git' ($auth + @('checkout', '--detach', '-q', $revision))
    }
    $origin = & git -C $destination remote get-url origin
    if ($LASTEXITCODE -ne 0 -or $origin -ne "https://github.com/$repository.git") {
        throw "O checkout existente de $Name aponta para outro repositorio. Nenhum arquivo foi sobrescrito."
    }
    Write-Host "Projeto $Name pronto. Codigo e alteracoes locais preservados."
}

function Invoke-Compose {
    param([Parameter(Position = 0)][string[]]$ComposeArguments)
    $config = Join-Path $Root '.local\compose.env'
    if (-not (Test-Path $config)) { throw 'Configuracao ausente. Execute setup.' }
    $projectName = $env:INSIGHTS_PROJECT_NAME
    if (-not $projectName) { $projectName = 'insights-local' }
    $composeArgs = @('compose', '--project-name', $projectName, '--project-directory', $Root,
        '--env-file', $config, '-f', (Join-Path $Root 'compose.local.yml'))
    $savedProfiles = $env:COMPOSE_PROFILES
    try {
        $env:COMPOSE_PROFILES = ''
        Invoke-Docker ($composeArgs + $ComposeArguments)
    } finally { $env:COMPOSE_PROFILES = $savedProfiles }
}

function Start-Stack {
    if ((Get-LiteralValue 'LOCAL_MODE' (Join-Path $Root '.local/compose.env')) -ne 'connected') {
        throw 'Instalacao anterior ainda usa demonstracao. Execute setup para preparar as integracoes reais.'
    }
    Invoke-Compose @('config', '--quiet')
    Invoke-Compose @('up', '-d', '--build', '--wait', '--wait-timeout', '600', '--remove-orphans')
    Invoke-Compose @('exec', '-T', 'api', 'python', '/opt/insights-local/scripts/bootstrap_local.py', 'smoke')
    $webPort = Get-LiteralValue 'LOCAL_WEB_PORT' (Join-Path $Root '.local\compose.env')
    Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$webPort/login" -TimeoutSec 30 | Out-Null
    Write-Host "Interface: http://localhost:$webPort"
    Write-Host ('Usuario e senha: ' + (Join-Path $Root '.local\access.txt'))
    Write-Host ('Atalhos para o Codex: ' + (Join-Path $Root '.local\codex-projects.html'))
    if (-not $NoBrowser) { Start-Process "http://localhost:$webPort" }
}

try {
    if ($Command -eq 'help') { Show-Usage; exit 0 }
    if ($Command -ne 'codex' -and $Project -ne 'all') { throw 'Use codex para selecionar um projeto.' }
    if ($Command -ne 'setup' -and ($Port -or $ApiPort)) { throw 'Use setup para alterar portas.' }
    switch ($Command) {
        'setup' {
            Write-SetupProgress 'Preparando as ferramentas do computador.'
            Ensure-Checkout
            Install-Dependencies
            Select-Docker
            Write-SetupProgress 'Conectando o GitHub e preparando os projetos.'
            Ensure-Source 'backend' 'BACKEND'
            Ensure-Source 'frontend' 'FRONTEND'
            Write-SetupProgress 'Conectando a AWS e preparando as integracoes.'
            Protect-LocalFiles
            Ensure-AwsSession
            Fetch-Integrations
            Write-SetupProgress 'Configurando o ambiente local.'
            $configArgs = @('configure', '--host-root', $Root, '--host-platform', 'windows')
            if ($Port) { $configArgs += @('--port', "$Port") }
            if ($ApiPort) { $configArgs += @('--api-port', "$ApiPort") }
            Invoke-Docker (@('run', '--rm', '--network', 'none', '--mount', "type=bind,source=$Root,target=/bootstrap",
                'python:3.11-slim', 'python', '/bootstrap/scripts/bootstrap_local.py') + $configArgs)
            Protect-LocalFiles
            if (Test-Path (Join-Path $Root '.local\compose.env')) { Invoke-Compose @('down', '--remove-orphans') }
            Write-SetupProgress 'Iniciando o Avanti Insights. O primeiro inicio pode levar varios minutos.'
            Start-Stack
            Write-SetupProgress 'Avanti Insights pronto. Interface, login, workers e Hub verificados.'
        }
        'start' { Select-Docker; Start-Stack }
        'stop' { Select-Docker; Invoke-Compose @('down', '--remove-orphans') }
        'codex' { Open-Codex }
        'status' {
            Select-Docker
            Invoke-Compose @('ps')
            $config = Join-Path $Root '.local\compose.env'
            Write-Host ('Modo: ' + (Get-LiteralValue 'LOCAL_MODE' $config))
            Write-Host ('Interface: http://localhost:' + (Get-LiteralValue 'LOCAL_WEB_PORT' $config))
        }
        'doctor' {
            Write-Host ("Sistema: " + [Environment]::OSVersion.VersionString)
            Write-Host "Pasta: $Root"
            foreach ($tool in @('git', 'gh', 'docker', 'aws')) {
                if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Dependencia ausente: $tool. Execute setup." }
            }
            Select-Docker
            Invoke-Compose @('config', '--quiet')
            Invoke-Compose @('ps')
            Invoke-Compose @('exec', '-T', 'api', 'python', '/opt/insights-local/scripts/bootstrap_local.py', 'smoke')
            foreach ($service in @('worker', 'playwright_worker')) {
                Invoke-Compose @('exec', '-T', $service, 'sh', '-c', 'celery -A app.core.celery inspect ping -d "celery@$HOSTNAME" --timeout=10')
            }
            Invoke-Compose @('exec', '-T', 'scheduler', 'python', '-c', "print('Scheduler local em execucao.')")
        }
    }
    exit 0
} catch {
    $setupError = $_.Exception.Message
    if ($Command -eq 'setup' -and $script:SetupStage) {
        try {
            [IO.File]::WriteAllText((Join-Path $Root '.local/setup-progress.txt'), "Etapa: $script:SetupStage`nPasta: $Root`nResultado: interrompido`n")
            Write-Host 'O Codex pode retomar na mesma pasta. A etapa foi registrada em .local/setup-progress.txt.'
        } catch {
            Write-Host 'Nao foi possivel salvar a etapa. O Codex pode retomar usando a mesma pasta.'
        }
    }
    Write-Host $setupError -ForegroundColor Red
    exit 2
}
