# Windows Notice to ntfy

Forward Windows toast notifications to an `ntfy` topic.

This repository contains:

- a local relay that receives notification payloads and publishes them to ntfy
- a free PowerShell-based Windows notification listener
- helper scripts to start, stop, and test the full pipeline

## Files

- `config.example.json`: sample relay config
- `Start-NtfyRelay.ps1`: local relay
- `Start-WindowsNotificationForwarder.ps1`: Windows notification listener
- `Run-All.cmd`: start relay and listener
- `Stop-All.cmd`: stop both windows
- `Send-TestWindowsNotification.ps1`: send a local Windows test toast

## Setup

1. Copy `config.example.json` to `config.json`
2. Edit `config.json`
3. Set your ntfy server and topic
4. Start the stack with `Run-All.cmd`

Example topic settings:

```json
{
  "ntfy": {
    "server": "https://ntfy.sh/",
    "topic": "replace-with-your-random-topic"
  }
}
```

## Usage

- Start everything: `Run-All.cmd`
- Stop everything: `Stop-All.cmd`
- Send a local test toast: `Send-TestWindowsNotification.cmd`

## Notes

- `config.json` is intentionally ignored and should stay local
- do not commit real ntfy topics, tokens, usernames, or passwords to a public repository
- if notification access is denied, run the listener once and allow notification access in Windows Settings
