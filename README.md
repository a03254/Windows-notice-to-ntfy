# Windows Notice to ntfy

Forward Windows toast notifications to an `ntfy` topic.

This project provides a fully local Windows pipeline:

1. Listen to Windows toast notifications
2. Convert them into a simple JSON payload
3. Forward them to a local relay
4. Publish them to your `ntfy` server or `ntfy.sh`
5. Receive them on your phone or desktop subscriber

This repository does not include any personal topic, token, or private server configuration.

## Features

- Free local Windows notification forwarder
- Local relay for ntfy publishing
- One-click start and stop scripts
- Local test toast generator
- Supports Chinese content
- Works with public `ntfy.sh` or a self-hosted ntfy server

## Project Files

- `config.example.json`: sample relay configuration
- `Start-NtfyRelay.ps1`: local relay, receives JSON and publishes to ntfy
- `Start-WindowsNotificationForwarder.ps1`: Windows toast listener
- `Run-NtfyRelay.cmd`: start only the relay
- `Run-WindowsNotificationForwarder.cmd`: start only the Windows listener
- `Run-All.cmd`: start relay and listener together
- `Stop-All.cmd`: stop both windows
- `Send-TestWindowsNotification.ps1`: send a local Windows toast
- `Send-TestWindowsNotification.cmd`: double-click wrapper for the test toast

## Requirements

- Windows 10 or Windows 11
- PowerShell 5.1 or newer
- Notification access enabled for the PowerShell process when prompted
- Network access to your ntfy server

## Quick Start

### 1. Create local config

Copy the example config:

```powershell
Copy-Item config.example.json config.json
```

Edit `config.json` and set your own ntfy server and topic.

Example:

```json
{
  "listenPrefix": "http://127.0.0.1:8787/notify/",
  "ntfy": {
    "server": "https://ntfy.sh/",
    "topic": "replace-with-your-random-topic",
    "token": "",
    "username": "",
    "password": "",
    "priority": 3,
    "tags": ["windows", "desktop"],
    "markdown": false,
    "click": "",
    "icon": ""
  }
}
```

### 2. Start the full pipeline

Double-click:

```text
Run-All.cmd
```

This opens two windows:

- `ntfy relay`
- `windows notification forwarder`

You can also start them separately:

```text
Run-NtfyRelay.cmd
Run-WindowsNotificationForwarder.cmd
```

### 3. Allow notification access

On first run, Windows may deny notification access.

If that happens:

1. Run the listener once
2. Windows Settings will open
3. Allow notification access for the current PowerShell / terminal process
4. Start the listener again

### 4. Subscribe in the ntfy app

Open your ntfy app and subscribe to the topic you configured in `config.json`.

If you use the public service, the subscription format is:

```text
https://ntfy.sh/<your-topic>
```

## Usage Tutorial

### Normal daily usage

1. Edit `config.json` once
2. Start `Run-All.cmd`
3. Keep the two windows open
4. Use Windows normally
5. Notifications that appear in Windows Notification Center will be forwarded to ntfy

### Stop the program

Double-click:

```text
Stop-All.cmd
```

Or close the two command windows manually.

## Test Tutorial

### Test relay only

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-NtfyRelay.ps1
```

If your phone receives the message, the relay and ntfy publishing are working.

### Test full Windows notification forwarding

Run:

```text
Send-TestWindowsNotification.cmd
```

This sends a local Windows toast notification.

If your phone receives that message, the full pipeline is working:

`Windows toast -> listener -> relay -> ntfy -> phone`

## Configuration Guide

### `listenPrefix`

Local HTTP endpoint for the relay.

Default:

```text
http://127.0.0.1:8787/notify/
```

### `ntfy.server`

The ntfy server root URL.

Examples:

```text
https://ntfy.sh/
https://your-ntfy-server.example.com/
```

### `ntfy.topic`

Your target topic.

Use a random, hard-to-guess topic if the topic is public.

### `ntfy.token`

Bearer token for authenticated ntfy publishing.

### `ntfy.username` / `ntfy.password`

Optional basic authentication credentials.

### `forwarding.includeAppNameInTitle`

Use the Windows app name as the ntfy title.

### `forwarding.includeComputerNameInMessage`

Adds the local computer name into the message body.

## Troubleshooting

### Notifications do not arrive on the phone

Check:

1. `Run-All.cmd` is still running
2. The correct topic is subscribed in the ntfy app
3. `config.json` points to the correct ntfy server and topic
4. Notification access is allowed in Windows

### Windows notifications are not being captured

Not every popup is readable through the Windows notification listener API.

Prefer testing with notifications that appear in Windows Notification Center, such as:

- Mail
- Edge download finished
- Windows Security
- Other standard toast notifications

### Android app only updates after manual refresh

On Android, check:

1. Notification permission is enabled for ntfy
2. Battery optimization is disabled for ntfy
3. Background activity is allowed
4. Vendor-specific app protection is enabled if needed

### Logs

Useful log files:

- `relay-events.log`
- `windows-forwarder.log`

## Privacy and Security

- `config.json` is intentionally ignored by git
- Do not commit real topics, tokens, usernames, or passwords
- Prefer your own ntfy topic
- Prefer authentication if you use a shared or self-hosted ntfy server

## License

Add your preferred open source license to this repository if you plan to publish it publicly.
