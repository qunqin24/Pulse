# Pulse Integrations

`pulse-status.ps1` formats the Windows Pulse cache without contacting any service:

```powershell
& "C:\path\to\Pulse Integrations\pulse-status.ps1"
& "C:\path\to\Pulse Integrations\pulse-status.ps1" -Account codex
& "C:\path\to\Pulse Integrations\pulse-status.ps1" -Json
```

Keep Pulse running to update its cache. `-MaxAge` sets the age in seconds before a reading is marked old (default 1800). `PULSE_ACCOUNT` sets a default account ID. Use the JSON report to find IDs.

The `raycast`, `pulse-status.sh`, and `pulse-sketchybar.sh` files are the original macOS integrations, included for reference and licensed under Apache-2.0. They need their own macOS Pulse installation and tools; they do not connect to this Windows installation.
