param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:LogFile = Join-Path $PSScriptRoot 'relay-events.log'

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -LiteralPath $script:LogFile -Value $line
}

function Get-JsonConfig {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Config file not found: $Path"
    }

    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}

function Get-PropertyValue {
    param(
        [object[]]$Objects,
        [string[]]$Names
    )

    foreach ($item in $Objects) {
        if ($null -eq $item) {
            continue
        }

        foreach ($name in $Names) {
            $property = $item.PSObject.Properties[$name]
            if ($null -eq $property) {
                continue
            }

            $value = $property.Value
            if ($null -eq $value) {
                continue
            }

            if ($value -is [string]) {
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    return $value.Trim()
                }

                continue
            }

            return $value
        }
    }

    return $null
}

function Get-StringArray {
    param([object]$Value)

    $result = @()
    if ($null -eq $Value) {
        return $result
    }

    if ($Value -is [string]) {
        if (-not [string]::IsNullOrWhiteSpace($Value)) {
            $result += $Value.Trim()
        }

        return $result
    }

    foreach ($item in @($Value)) {
        if ($null -eq $item) {
            continue
        }

        $text = [string]$item
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $result += $text.Trim()
        }
    }

    return $result
}

function Add-OptionalField {
    param(
        [hashtable]$Target,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Value) {
        return
    }

    if ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $Target[$Name] = $Value
}

function Get-ListenSettings {
    param([string]$ListenPrefix)

    $match = [regex]::Match($ListenPrefix, '^http://([^/:]+):(\d+)(/.*)$')
    if (-not $match.Success) {
        throw "Unsupported listenPrefix format: $ListenPrefix"
    }

    $listenHost = $match.Groups[1].Value
    $port = [int]$match.Groups[2].Value
    $path = $match.Groups[3].Value

    if (-not $path.StartsWith('/')) {
        $path = "/$path"
    }

    $bindAddress = [System.Net.IPAddress]::Any
    if ($listenHost -eq 'localhost') {
        $bindAddress = [System.Net.IPAddress]::Loopback
    } elseif ($listenHost -notin @('+', '*', '0.0.0.0')) {
        $parsedIp = $null
        if ([System.Net.IPAddress]::TryParse($listenHost, [ref]$parsedIp)) {
            $bindAddress = $parsedIp
        } else {
            $candidate = [System.Net.Dns]::GetHostAddresses($listenHost) |
                Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } |
                Select-Object -First 1
            if ($null -eq $candidate) {
                throw "Cannot resolve listen host: $listenHost"
            }

            $bindAddress = $candidate
        }
    }

    return @{
        BindAddress = $bindAddress
        Host        = $listenHost
        Port        = $port
        Path        = $path
    }
}

function ConvertTo-NtfyMessage {
    param(
        [string]$RawJson,
        [object]$Payload,
        [object]$Config
    )

    $candidates = @($Payload)
    foreach ($nestedName in @('NotificationData', 'notificationData', 'Notification', 'notification', 'Toast', 'toast', 'Data', 'data')) {
        $nested = Get-PropertyValue -Objects @($Payload) -Names @($nestedName)
        if ($null -ne $nested) {
            $candidates += $nested
        }
    }

    $appName = Get-PropertyValue -Objects $candidates -Names @(
        'AppDisplayName', 'appDisplayName', 'ApplicationDisplayName', 'applicationDisplayName',
        'ApplicationName', 'applicationName', 'AppName', 'appName', 'Source', 'source'
    )
    $title = Get-PropertyValue -Objects $candidates -Names @(
        'Title', 'title', 'Heading', 'heading', 'Summary', 'summary', 'NotificationTitle', 'notificationTitle'
    )
    $content = Get-PropertyValue -Objects $candidates -Names @(
        'Content', 'content', 'Body', 'body', 'Message', 'message', 'Text', 'text', 'Description', 'description'
    )

    if ([string]::IsNullOrWhiteSpace([string]$content)) {
        $textArray = Get-PropertyValue -Objects $candidates -Names @('Texts', 'texts', 'Lines', 'lines', 'TextsArray', 'textsArray')
        $content = (Get-StringArray -Value $textArray) -join "`n"
    }

    $when = Get-PropertyValue -Objects $candidates -Names @(
        'CreationTime', 'creationTime', 'Timestamp', 'timestamp', 'ArrivalTime', 'arrivalTime'
    )

    $messageLines = @()
    if ($Config.forwarding.includeComputerNameInMessage) {
        $messageLines += "Host: $env:COMPUTERNAME"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$appName)) {
        $messageLines += "App: $appName"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$title)) {
        $messageLines += "Title: $title"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$content)) {
        $messageLines += "Content: $content"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$when)) {
        $messageLines += "Time: $when"
    }

    $message = ($messageLines -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($message)) {
        $message = [string]$Config.forwarding.fallbackMessage
        if ($Config.forwarding.appendRawJsonOnEmpty -and -not [string]::IsNullOrWhiteSpace($RawJson)) {
            $message = "$message`n`nRaw JSON:`n$RawJson"
        }
    }

    $maxLength = [int]$Config.forwarding.maxMessageLength
    if ($maxLength -gt 0 -and $message.Length -gt $maxLength) {
        $message = $message.Substring(0, $maxLength) + "`n...[truncated]"
    }

    $ntfyTitle = [string]$Config.forwarding.fallbackTitle
    if ($Config.forwarding.includeAppNameInTitle -and -not [string]::IsNullOrWhiteSpace([string]$appName)) {
        $ntfyTitle = $appName
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$title)) {
        $ntfyTitle = $title
    }

    $tags = Get-StringArray -Value $Config.ntfy.tags
    if ($tags.Count -eq 0) {
        $tags = @('windows')
    }

    $messageBody = @{
        topic    = [string]$Config.ntfy.topic
        title    = $ntfyTitle
        message  = $message
        priority = [int]$Config.ntfy.priority
        tags     = $tags
    }

    Add-OptionalField -Target $messageBody -Name 'markdown' -Value ([bool]$Config.ntfy.markdown)
    Add-OptionalField -Target $messageBody -Name 'click' -Value ([string]$Config.ntfy.click)
    Add-OptionalField -Target $messageBody -Name 'icon' -Value ([string]$Config.ntfy.icon)

    return $messageBody
}

function Invoke-NtfyPublish {
    param(
        [hashtable]$MessageBody,
        [object]$Config
    )

    $headers = @{
        'Content-Type' = 'application/json; charset=utf-8'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Config.ntfy.token)) {
        $headers['Authorization'] = "Bearer $($Config.ntfy.token)"
    } elseif (
        -not [string]::IsNullOrWhiteSpace([string]$Config.ntfy.username) -and
        -not [string]::IsNullOrWhiteSpace([string]$Config.ntfy.password)
    ) {
        $authBytes = [System.Text.Encoding]::UTF8.GetBytes("$($Config.ntfy.username):$($Config.ntfy.password)")
        $headers['Authorization'] = 'Basic ' + [Convert]::ToBase64String($authBytes)
    }

    $server = [string]$Config.ntfy.server
    if ([string]::IsNullOrWhiteSpace($server)) {
        throw 'Config ntfy.server is empty.'
    }

    $uri = if ($server.EndsWith('/')) { $server } else { "$server/" }
    $body = $MessageBody | ConvertTo-Json -Depth 16 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $bodyBytes -TimeoutSec 30
}

function Get-CharsetEncoding {
    param([string]$ContentType)

    if ([string]::IsNullOrWhiteSpace($ContentType)) {
        return [System.Text.Encoding]::UTF8
    }

    $match = [regex]::Match($ContentType, 'charset=([^;]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return [System.Text.Encoding]::UTF8
    }

    return [System.Text.Encoding]::GetEncoding($match.Groups[1].Value.Trim())
}

function Find-HeaderBoundary {
    param([byte[]]$Bytes)

    for ($i = 0; $i -le ($Bytes.Length - 4); $i++) {
        if (
            $Bytes[$i] -eq 13 -and
            $Bytes[$i + 1] -eq 10 -and
            $Bytes[$i + 2] -eq 13 -and
            $Bytes[$i + 3] -eq 10
        ) {
            return $i
        }
    }

    return -1
}

function Read-HttpRequest {
    param([System.Net.Sockets.NetworkStream]$Stream)

    $buffer = New-Object byte[] 4096
    $memory = New-Object System.IO.MemoryStream
    $headerEnd = -1

    while ($headerEnd -lt 0) {
        $read = $Stream.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) {
            throw 'Client closed connection before sending HTTP headers.'
        }

        $memory.Write($buffer, 0, $read)
        $headerEnd = Find-HeaderBoundary -Bytes $memory.ToArray()
    }

    $allBytes = $memory.ToArray()
    $headerBytes = New-Object byte[] $headerEnd
    [Array]::Copy($allBytes, 0, $headerBytes, 0, $headerEnd)
    $headerText = [System.Text.Encoding]::ASCII.GetString($headerBytes)
    $headerLines = $headerText -split "`r`n"

    if ($headerLines.Count -eq 0) {
        throw 'Invalid HTTP request.'
    }

    $requestLineParts = $headerLines[0].Split(' ')
    if ($requestLineParts.Count -lt 2) {
        throw 'Invalid HTTP request line.'
    }

    $headers = @{}
    for ($i = 1; $i -lt $headerLines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($headerLines[$i])) {
            continue
        }

        $separatorIndex = $headerLines[$i].IndexOf(':')
        if ($separatorIndex -lt 1) {
            continue
        }

        $name = $headerLines[$i].Substring(0, $separatorIndex).Trim().ToLowerInvariant()
        $value = $headerLines[$i].Substring($separatorIndex + 1).Trim()
        $headers[$name] = $value
    }

    $contentLength = 0
    if ($headers.ContainsKey('content-length')) {
        $contentLength = [int]$headers['content-length']
    }

    $bodyStart = $headerEnd + 4
    $alreadyBuffered = $allBytes.Length - $bodyStart
    $bodyBytes = New-Object byte[] $contentLength

    if ($contentLength -gt 0 -and $alreadyBuffered -gt 0) {
        $copyLength = [Math]::Min($alreadyBuffered, $contentLength)
        [Array]::Copy($allBytes, $bodyStart, $bodyBytes, 0, $copyLength)
        $offset = $copyLength
    } else {
        $offset = 0
    }

    while ($offset -lt $contentLength) {
        $chunkSize = [Math]::Min($buffer.Length, $contentLength - $offset)
        $read = $Stream.Read($buffer, 0, $chunkSize)
        if ($read -le 0) {
            throw 'Client closed connection before sending the full HTTP body.'
        }

        [Array]::Copy($buffer, 0, $bodyBytes, $offset, $read)
        $offset += $read
    }

    $encoding = Get-CharsetEncoding -ContentType $headers['content-type']
    $body = if ($contentLength -gt 0) { $encoding.GetString($bodyBytes) } else { '' }

    return @{
        Method = $requestLineParts[0].ToUpperInvariant()
        Path   = $requestLineParts[1]
        Body   = $body
        Header = $headers
    }
}

function Send-HttpResponse {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [int]$StatusCode,
        [string]$ReasonPhrase,
        [hashtable]$Body
    )

    $json = $Body | ConvertTo-Json -Depth 8 -Compress
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $responseText = "HTTP/1.1 $StatusCode $ReasonPhrase`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($bodyBytes.Length)`r`nConnection: close`r`n`r`n"
    $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($responseText)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    $Stream.Write($bodyBytes, 0, $bodyBytes.Length)
    $Stream.Flush()
}

$resolvedConfigPath = Resolve-Path -LiteralPath $ConfigPath
$config = Get-JsonConfig -Path $resolvedConfigPath
$listen = Get-ListenSettings -ListenPrefix ([string]$config.listenPrefix)
$listener = New-Object System.Net.Sockets.TcpListener($listen.BindAddress, $listen.Port)

Write-Log "Starting relay on $($config.listenPrefix)"
Write-Log "Publishing to $($config.ntfy.server) topic $($config.ntfy.topic)"

try {
    $listener.Start()

    while ($true) {
        $client = $listener.AcceptTcpClient()
        try {
            $stream = $client.GetStream()
            $request = Read-HttpRequest -Stream $stream
            $requestPath = ($request.Path -split '\?')[0]

            if ($request.Method -eq 'GET' -and $requestPath -eq '/health') {
                Write-Log "Health check from local client."
                Send-HttpResponse -Stream $stream -StatusCode 200 -ReasonPhrase 'OK' -Body @{
                    status = 'ok'
                    topic  = [string]$config.ntfy.topic
                }
                continue
            }

            if ($request.Method -notin @('POST', 'PUT')) {
                Write-Log "Rejected method $($request.Method) on path $requestPath." 'WARN'
                Send-HttpResponse -Stream $stream -StatusCode 405 -ReasonPhrase 'Method Not Allowed' -Body @{
                    status = 'error'
                    error  = 'Only POST or PUT are supported.'
                }
                continue
            }

            if ($requestPath -ne $listen.Path) {
                Write-Log "Rejected unexpected path $requestPath." 'WARN'
                Send-HttpResponse -Stream $stream -StatusCode 404 -ReasonPhrase 'Not Found' -Body @{
                    status = 'error'
                    error  = "Unexpected path: $requestPath"
                }
                continue
            }

            if ([string]::IsNullOrWhiteSpace($request.Body)) {
                Write-Log "Rejected empty request body." 'WARN'
                Send-HttpResponse -Stream $stream -StatusCode 400 -ReasonPhrase 'Bad Request' -Body @{
                    status = 'error'
                    error  = 'Empty request body.'
                }
                continue
            }

            Write-Log "Incoming notification request on $requestPath."
            $payload = $request.Body | ConvertFrom-Json
            $ntfyBody = ConvertTo-NtfyMessage -RawJson $request.Body -Payload $payload -Config $config

            if ($config.logging.logPayloadPreview) {
                $preview = $ntfyBody.message
                if ($preview.Length -gt 180) {
                    $preview = $preview.Substring(0, 180) + '...'
                }
                Write-Log "Forwarding payload. Title=$($ntfyBody.title) Preview=$preview"
            }

            $publishResult = Invoke-NtfyPublish -MessageBody $ntfyBody -Config $config
            Write-Log "Published to ntfy successfully. Id=$($publishResult.id) Topic=$($publishResult.topic)"
            Send-HttpResponse -Stream $stream -StatusCode 200 -ReasonPhrase 'OK' -Body @{
                status = 'ok'
                id     = $publishResult.id
                topic  = $publishResult.topic
            }
        } catch {
            Write-Log $_.Exception.Message 'ERROR'
            if ($null -ne $stream) {
                Send-HttpResponse -Stream $stream -StatusCode 500 -ReasonPhrase 'Internal Server Error' -Body @{
                    status = 'error'
                    error  = $_.Exception.Message
                }
            }
        } finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }

            $client.Dispose()
        }
    }
} finally {
    $listener.Stop()
}
