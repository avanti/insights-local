#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('setup', 'start', 'stop', 'status', 'doctor', 'codex', 'help')]
    [string]$Command = 'help',
    [string]$Root,
    [ValidateSet('demo', 'connected')]
    [string]$Mode,
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
    Write-Host 'Opcoes: -Root PASTA -Mode demo|connected -Port 3000 -ApiPort 8000 -NoBrowser -NonInteractive'
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
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Falha em $Executable (codigo $LASTEXITCODE)." }
}

function Refresh-Path {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machinePath;$userPath;$env:Path"
}

function Install-Package {
    param([string]$Id)
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'Instale ou atualize o App Installer da Microsoft Store para disponibilizar winget, e execute setup novamente.'
    }
    # Package prompts remain visible; Docker terms are completed in its own app.
    & winget install --exact --id $Id --source winget --accept-source-agreements
    if ($LASTEXITCODE -eq 3010) {
        throw 'A instalacao requer reinicializacao. Reinicie o computador e execute setup novamente.'
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
        throw 'Conclua a instalacao do WSL, reinicie o Windows se solicitado e execute setup novamente.'
    }
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Install-Package 'Docker.DockerDesktop' }
    if (-not (Test-Docker $script:DockerContext)) {
        $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
        if (-not (Test-Path $desktop)) {
            $desktop = Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\Docker Desktop.exe'
        }
        if (Test-Path $desktop) { Start-Process $desktop }
        Write-Host 'Conclua os termos e a configuracao inicial na janela do Docker Desktop.'
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            if (Test-Docker $script:DockerContext) { return }
            Start-Sleep -Seconds 5
        }
        throw 'Docker ainda nao esta pronto. Conclua sua janela e execute setup novamente.'
    }
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
    param([Parameter(Position = 0)][string[]]$DockerArguments)
    $prefix = @()
    if ($script:DockerContext) { $prefix += @('--context', $script:DockerContext) }
    Invoke-Native 'docker' ($prefix + $DockerArguments)
}

function Ensure-Bundle {
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    if (Test-Path (Join-Path $Root 'scripts\bootstrap_local.py')) { return }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('insights-local-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        $zip = Join-Path $temp 'starter.zip'
        Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/avanti/insights-local/archive/refs/tags/v0.1.1.zip' -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $temp
        Get-ChildItem -Force (Join-Path $temp 'insights-local-0.1.1') |
            Copy-Item -Destination $Root -Recurse -Force
    } finally {
        Remove-Item -Recurse -Force $temp
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
    $dirty = & git -C $destination status --porcelain
    if ($LASTEXITCODE -ne 0 -or $dirty) { throw "Existem alteracoes em $destination. Nenhum arquivo foi sobrescrito." }
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
            if ($NonInteractive -or $env:CI) { throw 'Execute gh auth login e autorize acesso aos repositorios Avanti.' }
            Invoke-Native 'gh' @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web')
        }
        $auth = @('-c', 'credential.helper=', '-c', 'credential.helper=!gh auth git-credential', '-C', $destination)
        Invoke-Native 'git' ($auth + @('fetch', '--depth', '1', 'origin', $revision))
        Invoke-Native 'git' ($auth + @('checkout', '--detach', '-q', $revision))
    }
    $head = & git -C $destination rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $head -ne $revision) { throw "Checkout $Name difere de sources.lock. Preserve suas alteracoes antes de continuar." }
}

function Invoke-Compose {
    param([Parameter(Position = 0)][string[]]$ComposeArguments)
    $config = Join-Path $Root '.local\compose.env'
    if (-not (Test-Path $config)) { throw 'Configuracao ausente. Execute setup.' }
    $projectName = $env:INSIGHTS_PROJECT_NAME
    if (-not $projectName) { $projectName = 'insights-local' }
    $composeArgs = @('compose', '--project-name', $projectName, '--project-directory', $Root,
        '--env-file', $config, '-f', (Join-Path $Root 'compose.local.yml'))
    if ((Get-LiteralValue 'LOCAL_MODE' $config) -eq 'connected') {
        $composeArgs += @('--profile', 'connected')
    } else {
        $composeArgs += @('--profile', 'demo')
    }
    $savedProfiles = $env:COMPOSE_PROFILES
    try {
        $env:COMPOSE_PROFILES = ''
        Invoke-Docker ($composeArgs + $ComposeArguments)
    } finally { $env:COMPOSE_PROFILES = $savedProfiles }
}

function Start-Stack {
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
    if ($Command -ne 'setup' -and ($Mode -or $Port -or $ApiPort)) { throw 'Use setup para alterar modo ou portas.' }
    switch ($Command) {
        'setup' {
            Install-Dependencies
            Select-Docker
            Ensure-Bundle
            Ensure-Source 'backend' 'BACKEND'
            Ensure-Source 'frontend' 'FRONTEND'
            if (Test-Path (Join-Path $Root '.local\compose.env')) { Invoke-Compose @('down', '--remove-orphans') }
            $configArgs = @('configure', '--host-root', $Root, '--host-platform', 'windows')
            if ($Mode) { $configArgs += @('--mode', $Mode) }
            if ($Port) { $configArgs += @('--port', "$Port") }
            if ($ApiPort) { $configArgs += @('--api-port', "$ApiPort") }
            Invoke-Docker (@('run', '--rm', '--network', 'none', '--mount', "type=bind,source=$Root,target=/bootstrap",
                'python:3.11-slim', 'python', '/bootstrap/scripts/bootstrap_local.py') + $configArgs)
            Start-Stack
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
            foreach ($tool in @('git', 'gh', 'docker')) {
                if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Dependencia ausente: $tool. Execute setup." }
            }
            Select-Docker
            Invoke-Compose @('config', '--quiet')
            Invoke-Compose @('ps')
            Invoke-Compose @('exec', '-T', 'api', 'python', '/opt/insights-local/scripts/bootstrap_local.py', 'smoke')
        }
    }
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 2
}
