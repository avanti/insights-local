$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$launcher = Join-Path $root 'scripts/local.ps1'
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count -gt 0) { throw ($errors | Out-String) }
& $launcher help
if ($LASTEXITCODE -ne 0) { throw 'Help should work without installing anything.' }

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('insights-contract-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $fixture '.local') | Out-Null
$config = @("LOCAL_MODE='connected'", "LOCAL_WEB_PORT='3000'") -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $fixture '.local/compose.env'), $config)
$global:InsightsContractObserved = [Collections.Generic.List[string]]::new()
$originalProfiles = $env:COMPOSE_PROFILES
$env:COMPOSE_PROFILES = 'connected'

# Inherited functions shadow native binaries. These tests never install or stop real services.
function docker {
    $global:InsightsContractObserved.Add(($args -join ' ') + "|profiles=$env:COMPOSE_PROFILES")
    $global:LASTEXITCODE = 0
}
function Start-Process {
    param([string]$FilePath)
    $global:InsightsContractObserved.Add("open:$FilePath")
}
try {
    & $launcher status -Root $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Status contract failed.' }
    if (-not ($global:InsightsContractObserved | Where-Object { $_ -match 'compose .* ps\|profiles=$' })) {
        throw 'Status must clear caller profiles; all services are enabled without a mode.'
    }
    if ($env:COMPOSE_PROFILES -ne 'connected') { throw 'Caller environment was not restored.' }
    $global:InsightsContractObserved.Clear()
    & $launcher stop -Root $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Stop contract failed.' }
    if ($global:InsightsContractObserved | Where-Object { $_ -match '(--volumes| down -v)' }) {
        throw 'Stop must preserve data volumes.'
    }
    foreach ($name in @('frontend', 'backend')) {
        New-Item -ItemType Directory -Force (Join-Path $fixture "sources/$name/.git") | Out-Null
        New-Item -ItemType Directory -Force (Join-Path $fixture '.local/codex') | Out-Null
        [IO.File]::WriteAllText((Join-Path $fixture ".local/codex/$name.link"), "codex://new?path=C%3A%5CTest%20Folder%5Csources%5C$name")
    }
    $global:InsightsContractObserved.Clear()
    & $launcher codex -Root $fixture -Project frontend
    if ($LASTEXITCODE -ne 0) { throw 'Codex shortcut contract failed.' }
    if ($global:InsightsContractObserved.Count -ne 1 -or $global:InsightsContractObserved[0] -ne 'open:codex://new?path=C%3A%5CTest%20Folder%5Csources%5Cfrontend') {
        throw 'Codex must open only the selected host link without Docker.'
    }
    $global:InsightsContractObserved.Clear()
    [IO.File]::WriteAllText((Join-Path $fixture '.local/codex/backend.link'), 'https://unexpected.invalid')
    & $launcher codex -Root $fixture
    if ($LASTEXITCODE -ne 2 -or $global:InsightsContractObserved.Count -ne 0) {
        throw 'Validate all shortcuts before opening any project.'
    }
    $global:InsightsContractObserved.Clear()
    & $launcher setup -Root $fixture -NonInteractive
    if ($LASTEXITCODE -ne 2 -or $global:InsightsContractObserved.Count -ne 0) {
        throw 'An incomplete clone must fail before installing dependencies or accessing Docker.'
    }
    $progress = [IO.File]::ReadAllText((Join-Path $fixture '.local/setup-progress.txt'))
    if (-not $progress.Contains('Preparando as ferramentas') -or -not $progress.Contains('interrompido')) {
        throw 'A failed setup must record its stage for the next attempt.'
    }
    Write-Host 'PowerShell syntax, status, profile isolation, stop, shortcuts and interrupted setup contracts passed.'
} finally {
    Remove-Item Function:docker -ErrorAction SilentlyContinue
    Remove-Item Function:Start-Process -ErrorAction SilentlyContinue
    Remove-Variable InsightsContractObserved -Scope Global -ErrorAction SilentlyContinue
    $env:COMPOSE_PROFILES = $originalProfiles
    Remove-Item -Recurse -Force $fixture
}
# The expected rejection above leaves exit code 2; CI propagates LASTEXITCODE.
# Reach this line only after all assertions and cleanup complete successfully.
$global:LASTEXITCODE = 0

# Test the real AWS functions without invoking the launcher's top-level actions.
& {
    $Root = Join-Path ([IO.Path]::GetTempPath()) ('insights-aws-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $Root | Out-Null
    $savedEnvironment = @{}
    foreach ($key in @('INSIGHTS_AWS_PROFILE', 'INSIGHTS_AWS_REGION', 'INSIGHTS_AWS_LOGIN_METHOD', 'AWS_PAGER', 'AWS_CLI_AUTO_PROMPT', 'CI')) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key)
        [Environment]::SetEnvironmentVariable($key, $null)
    }
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($launcher, [ref]$tokens, [ref]$errors)
    foreach ($functionName in @('Invoke-Native', 'Invoke-Docker', 'Get-AwsArguments', 'Test-AwsVersion', 'Test-AwsSession', 'Ensure-AwsSession', 'Fetch-Integrations')) {
        $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName }, $true)
        Invoke-Expression $definition.Extent.Text
    }
    $script:DockerContext = ''
    $NonInteractive = $false
    $script:AwsReady = $false
    $script:AwsVersion = '2.32.0'
    $script:AwsFetchCode = 0
    $script:AwsEvents = [Collections.Generic.List[string]]::new()
    $script:DockerInput = ''
    function aws {
        $global:LASTEXITCODE = 0
        $joined = $args -join ' '
        if ($joined -eq '--version') { "aws-cli/$script:AwsVersion Python/3.13"; return }
        $script:AwsEvents.Add($joined)
        if ($joined.Contains('get-caller-identity')) {
            if (-not $script:AwsReady) { $global:LASTEXITCODE = 1 }
        } elseif ($joined.EndsWith(' login')) { $script:AwsReady = $true }
        elseif ($joined.Contains('get-secret-value')) {
            '"synthetic-json"'
            $global:LASTEXITCODE = $script:AwsFetchCode
        }
    }
    function docker {
        $script:AwsEvents.Add('docker:' + ($args -join ' '))
        $script:DockerInput = $input -join "`n"
        $global:LASTEXITCODE = 0
    }
    function Protect-LocalFiles { }
    try {
        if (-not (Test-AwsVersion)) { throw 'CLI 2.32.0 must support browser login.' }
        $script:AwsVersion = '2.31.9'
        if (Test-AwsVersion) { throw 'Older CLI must be upgraded.' }
        Ensure-AwsSession
        if (-not ($script:AwsEvents | Where-Object { $_ -eq '--profile avanti-insights-local --region us-east-1 login' })) {
            throw 'Default AWS authentication must use dedicated profile and console login.'
        }
        $script:AwsEvents.Clear()
        Ensure-AwsSession
        if ($script:AwsEvents.Count -ne 1) { throw 'Valid AWS sessions must be reused.' }
        Fetch-Integrations
        if ($script:DockerInput -ne '"synthetic-json"') { throw 'Secret must reach Docker through stdin.' }
        if ($script:AwsEvents | Where-Object { $_.Contains('synthetic-json') }) { throw 'Secrets must never enter command arguments.' }
        $script:AwsEvents.Clear()
        $script:AwsFetchCode = 7
        $failed = $false
        try { Fetch-Integrations } catch { $failed = $true }
        if (-not $failed -or ($script:AwsEvents | Where-Object { $_.StartsWith('docker:') })) { throw 'AWS failures must preserve the previous configuration.' }
        $script:AwsReady = $false
        $NonInteractive = $true
        $script:AwsEvents.Clear()
        $failed = $false
        try { Ensure-AwsSession } catch { $failed = $true }
        if (-not $failed -or $script:AwsEvents.Count -ne 1) { throw 'Noninteractive authentication must not open a browser.' }
        Write-Host 'PowerShell AWS browser login, session reuse, CLI version and stdin secret contracts passed.'
    } finally {
        foreach ($key in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key]) }
        Remove-Item -Recurse -Force $Root
    }
}
$global:LASTEXITCODE = 0
