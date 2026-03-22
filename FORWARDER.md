# Windows Notification Forwarder

This project includes a free local Windows notification forwarder implemented in PowerShell.

## Start order

1. Start the relay
2. Start the Windows notification listener
3. Subscribe to your own ntfy topic in the mobile app

The easiest way is to use:

```text
Run-All.cmd
```

## Test

To send a local Windows toast notification:

```text
Send-TestWindowsNotification.cmd
```

If your phone receives that message, the full pipeline is working.

## Privacy

- keep `config.json` local
- use your own topic
- if you use authentication, store the credentials only in local config
