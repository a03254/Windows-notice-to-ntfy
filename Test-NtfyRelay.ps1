Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$body = @{
    AppDisplayName = 'Relay Test'
    Title          = 'Manual test'
    Content        = 'If your phone receives this, relay to ntfy is working.'
} | ConvertTo-Json

Invoke-RestMethod `
    -Method Post `
    -Uri 'http://127.0.0.1:8787/notify/' `
    -ContentType 'application/json' `
    -Body $body |
    ConvertTo-Json -Compress
