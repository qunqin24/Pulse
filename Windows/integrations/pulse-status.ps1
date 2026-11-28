# Pulse Windows: format only the locally cached report; never fetch providers.
param([string]$Account = $env:PULSE_ACCOUNT, [int]$MaxAge = 1800, [switch]$Json)
$ErrorActionPreference = 'Stop'
if ($MaxAge -lt 0) { throw 'MaxAge must be non-negative.' }
$file = Join-Path $env:APPDATA 'pulse-windows-port\usage-report.json'
if (-not (Test-Path -LiteralPath $file)) { $report = [pscustomobject]@{ accounts = @() } }
else { $report = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json; if ($null -eq $report.accounts) { throw 'Invalid Pulse report.' } }
$now = [DateTimeOffset]::UtcNow
$report | Add-Member -NotePropertyName generatedAt -NotePropertyValue $now.ToString('o') -Force
foreach ($entry in $report.accounts) {
    $observed = [DateTimeOffset]::MinValue
    if ($entry.observedAt -and [DateTimeOffset]::TryParse($entry.observedAt, [ref]$observed)) {
        $age = [Math]::Max(0, [Math]::Round(($now - $observed).TotalSeconds))
        $entry | Add-Member -NotePropertyName ageSeconds -NotePropertyValue $age -Force
    } else { $entry.PSObject.Properties.Remove('ageSeconds') }
}
if ($Json) { $report | ConvertTo-Json -Depth 30; return }
$parts = @(
    foreach ($entry in $report.accounts) {
        if ($Account -and $entry.id -cne $Account) { continue }
        $label = if ($entry.label) { $entry.label } else { $entry.name }
        $label = [string]$label -replace '[\x00-\x1f\x7f]', ' '
        $headline = $entry.headline
        if ($null -ne $headline -and $null -ne $headline.usedPercent) {
            $window = @($entry.windows | Where-Object { $_.id -ceq $headline.windowId } | Select-Object -First 1)
            $prefix = if ($window.Count -and $window[0].estimated) { '≈' } else { '' }
            $value = $prefix + $headline.usedPercent + '% used'
        } elseif ($entry.creditBalance) { $value = [string]$entry.creditBalance -replace '[\x00-\x1f\x7f]', ' ' }
        else { $value = '—' }
        $suffix = if (-not $entry.observedAt -or $null -eq $entry.ageSeconds) { ' (no reading)' } elseif ($entry.ageSeconds -ge $MaxAge) { ' (old)' } else { '' }
        $label + ': ' + $value + $suffix
    }
)
if ($parts.Count) { $parts -join ' · ' } else { 'Pulse —' }
