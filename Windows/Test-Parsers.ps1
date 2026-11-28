$ErrorActionPreference='Stop'
. "$PSScriptRoot\ProviderParsers.ps1"
$fixtures=Join-Path $PSScriptRoot '..\upstream\Tests\PulseTests\Fixtures'
$normal=Get-Content (Join-Path $fixtures 'kimi-code-normal.json') -Raw | ConvertFrom-Json
$rows=Convert-KimiUsage $normal
if ($rows.Count -ne 3 -or $rows[0].usedPercent -ne 40 -or $rows[1].usedPercent -ne 70 -or $rows[2].usedPercent -ne 25) { throw 'Kimi normal fixture failed' }
$monthly=Get-Content (Join-Path $fixtures 'kimi-code-monthly.json') -Raw | ConvertFrom-Json
$rows=Convert-KimiUsage $monthly
if (($rows | Where-Object { $_.name -eq '月度 Coding' }).Count -ne 1) { throw 'Kimi monthly fixture failed' }
$balance=Get-Content (Join-Path $fixtures 'deepseek-two-currencies.json') -Raw | ConvertFrom-Json
$rows=Convert-DeepSeekBalance $balance
if ($rows.Count -ne 2) { throw 'DeepSeek fixture failed' }
'Provider fixture checks passed'
