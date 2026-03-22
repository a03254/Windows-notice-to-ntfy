param(
    [string]$RelayUrl = 'http://127.0.0.1:8787/notify/',
    [int]$PollIntervalSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ForwarderLog = Join-Path $PSScriptRoot 'windows-forwarder.log'
$script:SeenNotifications = @{}
$script:MaxFieldLength = 1500

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -LiteralPath $script:ForwarderLog -Value $line
}

function Import-WinRtTypes {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime

    [Windows.UI.Notifications.Management.UserNotificationListener, Windows, ContentType=WindowsRuntime] > $null
    [Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus, Windows, ContentType=WindowsRuntime] > $null
    [Windows.UI.Notifications.NotificationKinds, Windows.UI, ContentType=WindowsRuntime] > $null
    [Windows.UI.Notifications.UserNotification, Windows.UI, ContentType=WindowsRuntime] > $null
    [Windows.UI.Notifications.Notification, Windows.UI, ContentType=WindowsRuntime] > $null
    [Windows.UI.Notifications.NotificationVisual, Windows.UI, ContentType=WindowsRuntime] > $null
    [Windows.UI.Notifications.NotificationBinding, Windows.UI, ContentType=WindowsRuntime] > $null
    [Windows.ApplicationModel.AppInfo, Windows.ApplicationModel, ContentType=WindowsRuntime] > $null
}

function Invoke-WinRtAsync {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Operation,
        [Parameter(Mandatory = $true)]
        [Type]$ResultType
    )

    $method = [System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object {
            $_.Name -eq 'AsTask' -and
            $_.IsGenericMethod -and
            $_.GetParameters().Count -eq 1
        } |
        Select-Object -First 1

    if ($null -eq $method) {
        throw 'Unable to locate System.WindowsRuntimeSystemExtensions.AsTask<T>.'
    }

    $genericMethod = $method.MakeGenericMethod($ResultType)
    $task = $genericMethod.Invoke($null, @($Operation))
    $task.Wait()
    return $task.Result
}

function Get-NotificationAccessStatus {
    $listener = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
    return $listener.GetAccessStatus()
}

function Request-NotificationAccess {
    $listener = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
    return Invoke-WinRtAsync `
        -Operation ($listener.RequestAccessAsync()) `
        -ResultType ([Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus])
}

function Get-NotificationList {
    $listener = [Windows.UI.Notifications.Management.UserNotificationListener]::Current
    $listType = [System.Collections.Generic.IReadOnlyList``1].MakeGenericType(
        [Windows.UI.Notifications.UserNotification, Windows.UI, ContentType=WindowsRuntime]
    )

    return Invoke-WinRtAsync `
        -Operation ($listener.GetNotificationsAsync([Windows.UI.Notifications.NotificationKinds]::Toast)) `
        -ResultType $listType
}

function Get-AppDisplayName {
    param([object]$Notification)

    try {
        $appInfo = $Notification.AppInfo
        if ($null -ne $appInfo) {
            $displayInfo = $appInfo.DisplayInfo
            if ($null -ne $displayInfo -and -not [string]::IsNullOrWhiteSpace([string]$displayInfo.DisplayName)) {
                return [string]$displayInfo.DisplayName
            }

            if (-not [string]::IsNullOrWhiteSpace([string]$appInfo.PackageFamilyName)) {
                return [string]$appInfo.PackageFamilyName
            }
        }
    } catch {
    }

    return 'Windows'
}

function Get-NotificationTexts {
    param([object]$Notification)

    $texts = New-Object System.Collections.Generic.List[string]

    try {
        $visual = $Notification.Notification.Visual
        if ($null -eq $visual) {
            return $texts
        }

        $bindings = @()
        foreach ($bindingPair in $visual.Bindings) {
            if ($null -ne $bindingPair) {
                if ($bindingPair.PSObject.Properties['Value']) {
                    $bindings += $bindingPair.Value
                } else {
                    $bindings += $bindingPair
                }
            }
        }

        foreach ($binding in $bindings) {
            foreach ($textElement in $binding.GetTextElements()) {
                $value = $null
                if ($textElement.PSObject.Properties['Text']) {
                    $value = [string]$textElement.Text
                } else {
                    $value = [string]$textElement.InnerText
                }

                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    $texts.Add($value.Trim())
                }
            }
        }
    } catch {
        Write-Log "Failed to extract notification texts: $($_.Exception.Message)" 'WARN'
    }

    return $texts
}

function Normalize-Text {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $normalized = $Text `
        -replace "`0", '' `
        -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', ' ' `
        -replace '\s+', ' '

    $normalized = $normalized.Trim()

    if ($normalized.Length -gt $script:MaxFieldLength) {
        $normalized = $normalized.Substring(0, $script:MaxFieldLength) + '...[truncated]'
    }

    return $normalized
}

function Convert-NotificationToPayload {
    param([object]$Notification)

    $texts = @(Get-NotificationTexts -Notification $Notification)
    $appDisplayName = Get-AppDisplayName -Notification $Notification
    $title = ''
    $content = ''

    if ($texts.Count -ge 1) {
        $title = $texts[0]
    }

    if ($texts.Count -ge 2) {
        $content = ($texts | Select-Object -Skip 1) -join "`n"
    } elseif ($texts.Count -eq 1) {
        $content = $texts[0]
    }

    return @{
        AppDisplayName = (Normalize-Text -Text $appDisplayName)
        Title          = (Normalize-Text -Text $title)
        Content        = (Normalize-Text -Text $content)
        CreationTime   = [string]$Notification.CreationTime
        NotificationId = [string]$Notification.Id
    }
}

function Send-ToRelay {
    param([hashtable]$Payload)

    $body = $Payload | ConvertTo-Json -Depth 8
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
    return Invoke-RestMethod `
        -Method Post `
        -Uri $RelayUrl `
        -ContentType 'application/json; charset=utf-8' `
        -Body $bodyBytes
}

function Test-RelayHealth {
    $healthUrl = 'http://127.0.0.1:8787/health'

    try {
        Invoke-RestMethod -Uri $healthUrl -Method Get | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Open-NotificationSettings {
    Start-Process 'ms-settings:privacy-notifications' | Out-Null
}

function Remove-StaleSeenNotifications {
    $cutoff = (Get-Date).AddHours(-12)
    foreach ($key in @($script:SeenNotifications.Keys)) {
        if ($script:SeenNotifications[$key] -lt $cutoff) {
            $script:SeenNotifications.Remove($key)
        }
    }
}

Import-WinRtTypes

Write-Log 'Starting Windows notification forwarder.'
Write-Log "Relay target: $RelayUrl"

if (-not (Test-RelayHealth)) {
    Write-Log 'Relay health check failed. Start Run-NtfyRelay.cmd first.' 'WARN'
}

$accessStatus = Get-NotificationAccessStatus
Write-Log "Current notification access status: $accessStatus"

if ($accessStatus -ne [Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus]::Allowed) {
    $accessStatus = Request-NotificationAccess
    Write-Log "RequestAccessAsync result: $accessStatus"
}

if ($accessStatus -eq [Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus]::Denied) {
    Write-Log 'Notification access is denied. Opening Windows settings. Allow notification access for this app, then rerun.' 'ERROR'
    Open-NotificationSettings
    exit 1
}

if ($accessStatus -eq [Windows.UI.Notifications.Management.UserNotificationListenerAccessStatus]::Unspecified) {
    Write-Log 'Notification access is unspecified. Rerun the script and allow access when prompted.' 'WARN'
}

Write-Log 'Monitoring Windows toast notifications. Press Ctrl+C to stop.'

while ($true) {
    try {
        Remove-StaleSeenNotifications
        $notifications = Get-NotificationList

        foreach ($notification in $notifications) {
            $key = '{0}:{1:O}' -f $notification.Id, ([DateTimeOffset]$notification.CreationTime)
            if ($script:SeenNotifications.ContainsKey($key)) {
                continue
            }

            $script:SeenNotifications[$key] = Get-Date
            $payload = Convert-NotificationToPayload -Notification $notification

            if ([string]::IsNullOrWhiteSpace([string]$payload.Title) -and [string]::IsNullOrWhiteSpace([string]$payload.Content)) {
                Write-Log "Skipping notification $($payload.NotificationId) because no text content was extracted." 'WARN'
                continue
            }

            try {
                $result = Send-ToRelay -Payload $payload
                Write-Log "Forwarded notification $($payload.NotificationId) from $($payload.AppDisplayName). ntfy id=$($result.id)"
            } catch {
                Write-Log "Failed to forward notification $($payload.NotificationId) from $($payload.AppDisplayName): $($_.Exception.Message)" 'ERROR'
            }
        }
    } catch {
        Write-Log $_.Exception.Message 'ERROR'
    }

    Start-Sleep -Seconds $PollIntervalSeconds
}
