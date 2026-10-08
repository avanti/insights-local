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
$config = @("LOCAL_MODE='demo'", "LOCAL_WEB_PORT='3000'") -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $fixture '.local/compose.env'), $config)
$global:InsightsContractObserved = [Collections.Generic.List[string]]::new()
$originalProfiles = $env:COMPOSE_PROFILES
$env:COMPOSE_PROFILES = 'connected'

# Inherited functions shadow native binaries. These tests never install or stop real services.
function docker {
    $global:InsightsContractObserved.Add(($args -join ' ') + "|profiles=$env:COMPOSE_PROFILES")
    $global:LASTEXITCODE = 0
}
try {
    & $launcher status -Root $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Status contract failed.' }
    if (-not ($global:InsightsContractObserved | Where-Object { $_ -match '--profile demo ps\|profiles=$' })) {
        throw 'Demo status must clear caller profiles and explicitly select demo.'
    }
    if ($env:COMPOSE_PROFILES -ne 'connected') { throw 'Caller environment was not restored.' }
    $global:InsightsContractObserved.Clear()
    & $launcher stop -Root $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Stop contract failed.' }
    if ($global:InsightsContractObserved | Where-Object { $_ -match '(--volumes| down -v)' }) {
        throw 'Stop must preserve data volumes.'
    }
    Write-Host 'PowerShell syntax, status, profile isolation and stop contracts passed.'
} finally {
    Remove-Item Function:docker -ErrorAction SilentlyContinue
    Remove-Variable InsightsContractObserved -Scope Global -ErrorAction SilentlyContinue
    $env:COMPOSE_PROFILES = $originalProfiles
    Remove-Item -Recurse -Force $fixture
}
