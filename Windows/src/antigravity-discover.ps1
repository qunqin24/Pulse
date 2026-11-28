$ErrorActionPreference = 'Stop'
$processes = @(Get-CimInstance Win32_Process -Filter "Name='language_server.exe' OR Name='language_server_windows_x64.exe' OR Name='language_server_windows_arm64.exe'" | Select-Object ProcessId,ExecutablePath,CommandLine)
$eligible = @($processes | Where-Object { $_.ExecutablePath -match '(?i)\\antigravity(?: ide)?\\.*\\language_server(?:_windows_(?:x64|arm64))?\.exe$' -and $_.CommandLine -notmatch '(?:^|\s)--csrf_token(?:=|\s+)' })
$connections = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object OwningProcess,LocalAddress,LocalPort)
# The desktop hub publishes its current per-launch token in a local daemon record.
# Accept it only for the matching Antigravity process and its actual listener.
$daemon = Join-Path $env:USERPROFILE '.gemini\antigravity\daemon'
if ($eligible.Count -gt 0 -and (Test-Path -LiteralPath $daemon -PathType Container)) {
    foreach ($file in @(Get-ChildItem -LiteralPath $daemon -Filter 'hub_*.json' -File -ErrorAction SilentlyContinue)) {
        if ($file.Length -gt 16384 -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($record.csrfToken -isnot [string] -or $record.csrfToken -notmatch '^[0-9a-fA-F-]{36}$') { continue }
            $process = $eligible | Where-Object { $_.ProcessId -eq $record.pid -and -not $_.CsrfToken } | Select-Object -First 1
            if (-not $process) { continue }
            $listener = $connections | Where-Object { $_.OwningProcess -eq $process.ProcessId -and $_.LocalPort -eq $record.httpsPort -and $_.LocalAddress -in @('127.0.0.1','0.0.0.0','::','::1') } | Select-Object -First 1
            if ($listener) { $process | Add-Member -NotePropertyName CsrfToken -NotePropertyValue $record.csrfToken }
        } catch { }
    }
}
$missing = @($eligible | Where-Object { -not $_.CsrfToken })
if ($missing.Count -gt 0 -and [IntPtr]::Size -eq 8) {
    Add-Type -Path (Join-Path $PSScriptRoot 'antigravity-environment.cs')
    foreach ($process in $missing) {
        try { $token = [PulseAntigravityEnvironment]::ReadToken([int]$process.ProcessId); if ($token) { $process | Add-Member -NotePropertyName CsrfToken -NotePropertyValue $token } } catch { }
    }
}
@{processes=$processes;connections=$connections} | ConvertTo-Json -Depth 4 -Compress
