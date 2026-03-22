param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [string]$TaskName = 'ntfy-relay',
    [switch]$ReserveUrl,
    [switch]$RegisterFirewallRule,
    [switch]$StartNow
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-JsonConfig {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Ensure-ConfigFile {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        return
    }

    $examplePath = Join-Path (Split-Path -Parent $Path) 'config.example.json'
    if (-not (Test-Path -LiteralPath $examplePath)) {
        throw "Config file not found, and no example is available: $Path"
    }

    Copy-Item -LiteralPath $examplePath -Destination $Path
    Write-Host "Created config file from example: $Path"
}

Ensure-ConfigFile -Path $ConfigPath

$resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
$config = Get-JsonConfig -Path $resolvedConfig
$powershellExe = (Get-Command powershell.exe).Source
$runScript = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'Start-NtfyRelay.ps1')
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$runScript`" -ConfigPath `"$resolvedConfig`""
$taskAction = New-ScheduledTaskAction -Execute $powershellExe -Argument $taskArgs
$taskTrigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$taskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 0)

Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null
Write-Host "Scheduled task registered: $TaskName"

if ($ReserveUrl) {
    Write-Host 'TcpListener mode does not require URL ACL. -ReserveUrl is ignored.'
}

if ($RegisterFirewallRule) {
    if (-not (Test-IsAdministrator)) {
        throw 'Administrator privileges are required when using -RegisterFirewallRule.'
    }
}

if ($RegisterFirewallRule) {
    $prefixUri = [Uri][string]$config.listenPrefix
    $ruleName = "ntfy relay $($prefixUri.Port)"
    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $existingRule) {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $prefixUri.Port | Out-Null
        Write-Host "Firewall rule created: $ruleName"
    } else {
        Write-Host "Firewall rule already exists: $ruleName"
    }
}

if ($StartNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "Scheduled task started: $TaskName"
}

Write-Host "Listen prefix: $($config.listenPrefix)"
Write-Host "ntfy server: $($config.ntfy.server)"
Write-Host "ntfy topic: $($config.ntfy.topic)"
