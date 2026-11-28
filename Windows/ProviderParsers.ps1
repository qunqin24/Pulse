# Pulse Windows provider response parsers. Derived from Pulse, Apache-2.0.
function Convert-KimiUsage($reply) {
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($reply.limits)) {
        if (-not $entry -or -not $entry.window -or -not $entry.detail) { continue }
        $unit = switch ($entry.window.timeUnit) { 'TIME_UNIT_MINUTE' { '分钟' } 'TIME_UNIT_HOUR' { '小时' } 'TIME_UNIT_DAY' { '天' } default { $null } }
        if (-not $unit -or -not $entry.window.duration) { continue }
        $limit = 0.0; $used = 0.0; $remaining = 0.0
        if (-not [double]::TryParse([string]$entry.detail.limit, [ref]$limit) -or $limit -le 0) { continue }
        if ([double]::TryParse([string]$entry.detail.used, [ref]$used)) { $percent=100*$used/$limit }
        elseif ([double]::TryParse([string]$entry.detail.remaining, [ref]$remaining)) { $percent=100*($limit-$remaining)/$limit }
        else { continue }
        $result.Add([pscustomobject]@{name=('{0} {1}' -f $entry.window.duration,$unit); usedPercent=[Math]::Max(0,[Math]::Min(100,$percent)); reset=$entry.detail.resetTime})
    }
    $detail=$reply.usage
    if ($detail) {
        $limit=0.0; $used=0.0; $remaining=0.0
        if ([double]::TryParse([string]$detail.limit,[ref]$limit) -and $limit -gt 0) {
            $valid=$false
            if ([double]::TryParse([string]$detail.used,[ref]$used)) { $percent=100*$used/$limit; $valid=$true }
            elseif ([double]::TryParse([string]$detail.remaining,[ref]$remaining)) { $percent=100*($limit-$remaining)/$limit; $valid=$true }
            if ($valid) { $result.Add([pscustomobject]@{name='每周';usedPercent=[Math]::Max(0,[Math]::Min(100,$percent));reset=$detail.resetTime}) }
        }
    }
    foreach ($pair in @(@('limit_month_code','月度 Coding'),@('limit_month_total','月度总计'))) {
        $entry=$reply.usages.($pair[0]); if ($null -ne $entry -and $null -ne $entry.used_ratio) { $result.Add([pscustomobject]@{name=$pair[1]; usedPercent=[Math]::Max(0,[Math]::Min(100,100*[double]$entry.used_ratio));reset=$entry.reset_time}) }
    }
    return ,$result.ToArray()
}
function Convert-DeepSeekBalance($reply) {
    $result=[System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($reply.balance_infos)) {
        $amount=0.0
        if ($entry.currency -and [double]::TryParse([string]$entry.total_balance,[ref]$amount)) { $result.Add([pscustomobject]@{currency=$entry.currency;balance=$amount}) }
    }
    return ,$result.ToArray()
}
