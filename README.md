# Windows Notice to ntfy

Forward Windows toast notifications to an `ntfy` topic with a Python implementation.

This project is no longer based on PowerShell-first logic. The core pieces are now implemented as a structured Python CLI:

- a local relay HTTP server
- a Windows notification listener
- a local test toast sender
- a combined `run` mode for normal daily use

## Features

- Python-based relay and listener
- Windows toast capture via WinRT
- UTF-8 safe forwarding, including Chinese content
- Works with `ntfy.sh` or a self-hosted ntfy server
- Local config kept out of git
- Optional `.cmd` wrappers for double-click usage on Windows

## Repository Layout

- `windows_notice_to_ntfy/`: main Python package
- `requirements.txt`: Python dependencies
- `config.example.json`: sample configuration
- `Run-All.cmd`: double-click wrapper for `python -m windows_notice_to_ntfy run`
- `Send-TestWindowsNotification.cmd`: double-click wrapper for `python -m windows_notice_to_ntfy test-toast`

## Requirements

- Windows 10 or Windows 11
- Python 3.11 or newer
- Network access to your ntfy server
- Notification access enabled for the current Python process when prompted

## Installation

### 1. Install the project

Recommended editable install:

```powershell
python -m pip install -e .
```

Alternative dependency-only install:

```powershell
python -m pip install -r requirements.txt
```

### 2. Create local config

```powershell
Copy-Item config.example.json config.json
```

Edit `config.json` and set your own ntfy server and topic.

Minimal example:

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

## Quick Start

### Start the full pipeline

Recommended:

```powershell
python -m windows_notice_to_ntfy run --config config.json
```

Windows double-click wrapper:

```text
Run-All.cmd
```

This starts:

- the local relay server
- the Windows notification listener

Press `Ctrl+C` to stop the process.

## CLI Usage

### Run relay only

```powershell
python -m windows_notice_to_ntfy relay --config config.json
```

### Run listener only

```powershell
python -m windows_notice_to_ntfy listener --config config.json
```

### Run relay + listener together

```powershell
python -m windows_notice_to_ntfy run --config config.json
```

### Send a local Windows test toast

```powershell
python -m windows_notice_to_ntfy test-toast
```

Custom test content:

```powershell
python -m windows_notice_to_ntfy test-toast --title "中文测试" --message "这是一条中文通知"
```

Windows double-click wrapper:

```text
Send-TestWindowsNotification.cmd
```

## Usage Tutorial

### First run

1. Install dependencies
2. Copy `config.example.json` to `config.json`
3. Configure your ntfy server and topic
4. Start the full pipeline with `python -m windows_notice_to_ntfy run --config config.json`
5. If Windows opens notification privacy settings, allow notification access
6. Subscribe to your topic in the ntfy app

### Normal daily use

1. Start the program
2. Keep the process running
3. Use Windows normally
4. Notifications that appear in Windows Notification Center will be forwarded to ntfy

## Testing

### Test ntfy publishing end to end

1. Start the full pipeline
2. Run:

```powershell
python -m windows_notice_to_ntfy test-toast
```

3. Check your phone

If your phone receives the notification, the full path is working:

`Windows toast -> listener -> relay -> ntfy -> phone`

## Configuration Reference

### `listenPrefix`

Local relay address.

Default:

```text
http://127.0.0.1:8787/notify/
```

### `ntfy.server`

Root URL of your ntfy server.

Examples:

```text
https://ntfy.sh/
https://your-ntfy-server.example.com/
```

### `ntfy.topic`

Your destination topic.

Use a random, hard-to-guess topic if it is public.

### `ntfy.token`

Optional bearer token.

### `ntfy.username` and `ntfy.password`

Optional basic authentication credentials.

### `ntfy.tags`

Default ntfy tags added to outgoing notifications.

### `forwarding.includeAppNameInTitle`

Use the Windows app name as the ntfy title.

### `forwarding.includeComputerNameInMessage`

Include the local computer name in the message body.

## Logs

The program writes useful runtime logs to:

- `relay-events.log`
- `windows-forwarder.log`

## Troubleshooting

### No notifications arrive on the phone

Check:

1. The process is still running
2. The topic in `config.json` matches the subscribed topic
3. `config.json` points to the correct ntfy server
4. Windows notification access was granted

### Windows notifications are not being captured

Not every popup is exposed through the Windows notification listener API.

Prefer testing with notifications that appear in Windows Notification Center, for example:

- Mail
- Edge download complete
- Windows Security
- Standard app toast notifications

### Android does not notify instantly

On Android, check:

1. Notification permission is enabled for ntfy
2. Battery optimization is disabled for ntfy
3. Background activity is allowed
4. Vendor-specific background restrictions are disabled

## Privacy and Security

- `config.json` is ignored by git and should remain local
- Do not commit real topics, tokens, usernames, or passwords
- Prefer authentication if you use a shared or self-hosted ntfy server

## License

Add your preferred open source license before publishing broadly.
