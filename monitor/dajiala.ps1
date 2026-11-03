# Account-level WeChat monitoring via Dajiala API (mirror of AIHOT's providers/dajiala.ts pattern). ASCII-only.
# Setup: 1) signup dajiala.com, get key; 2) put DAJIALA_KEY=xxx in monitor/.env or environment;
#        3) fill "ghid" in accounts.json (the __biz param from any article URL of that account, e.g. mp.weixin.qq.com/s?__biz=MzA5NTM2OTUyNA==).
# Cost control: accounts.json "tier" field — 1 = monitored every run; 2 = rotated (one per run, round-robin by day);
#               3 = skipped (pending ghid or user decision). Default (no tier) = 1. Daily cost ~0.14 * (tier1Count + 1).
# Cost: post_history = 0.14 CNY per account per run; article_detail = 0.03 CNY (only with -Detail).
param([switch]$Detail, [int]$MaxAccounts = 10)
$ErrorActionPreference = 'Continue'
if (-not $WsRoot) { $WsRoot = Split-Path -Parent $PSScriptRoot }
$mon      = Join-Path $WsRoot 'monitor'
$reports  = Join-Path $mon 'reports'
$seenFile = Join-Path $mon 'dajiala-seen.txt'
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# resolve key
$key = $env:DAJIALA_KEY
$envFile = Join-Path $mon '.env'
if (-not $key -and (Test-Path $envFile)) {
  foreach ($l in [System.IO.File]::ReadAllLines($envFile)) {
    if ($l -match '^\s*DAJIALA_KEY\s*=\s*(\S+)\s*$') { $key = $Matches[1] }
  }
}
if (-not $key) {
  Write-Output 'DAJIALA SKIP: no DAJIALA_KEY configured (account-level monitoring inactive). Setup: dajiala.com key + fill ghid in accounts.json'
  exit 0
}
$accounts = [System.IO.File]::ReadAllText((Join-Path $mon 'accounts.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$seen = @()
if (Test-Path $seenFile) { $seen = @([System.IO.File]::ReadAllLines($seenFile, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() }) }
$seenSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in $seen) { [void]$seenSet.Add($s) }
$now = Get-Date
$stamp = $now.ToString('yyyy-MM-dd HH:mm')
$dateFile = $now.ToString('yyyy-MM-dd')
$cutoff = [int][double]::Parse((Get-Date).AddDays(-7).Subtract([datetime]'1970-01-01').TotalSeconds)
$allNew = @()
$tally = 0.0
$errors = @()
$done = 0
$ghidMissing = @()

# tier-based selection (cost control)
$tierOf = { param($x) if ($null -ne $x.tier) { [int]$x.tier } else { 1 } }
$tier1 = @($accounts | Where-Object { $_.ghid -and (& $tierOf $_) -eq 1 })
$tier2 = @($accounts | Where-Object { $_.ghid -and (& $tierOf $_) -eq 2 })
$selected = @($tier1)
if ($tier2.Count -gt 0) {
  $rotIdx = ((Get-Date).DayOfYear - 1) % $tier2.Count
  $selected += $tier2[$rotIdx]
  Write-Output ('DAJIALA rotation: today tier2 pick = ' + $tier2[$rotIdx].name)
}

foreach ($a in $selected) {
  if ($done -ge $MaxAccounts) { break }
  if (-not $a.ghid) { $ghidMissing += $a.name; continue }
  $done++
  $body = @{ ghid = $a.ghid; key = $key; verifycode = '' } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri 'https://www.dajiala.com/fbmain/monitor/v3/post_history' -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 30
    $tally += [double]($r.cost_money)
    if ($r.code -eq -1) { $errors += ($a.name + ': rate limited, retry later'); continue }
    if ($r.code -ne 0) { $errors += ($a.name + ': provider code ' + $r.code + ' ' + $r.msg); continue }
    $posts = @($r.data | Sort-Object { $_.post_time } -Descending)
    $newCount = 0
    foreach ($p in $posts) {
      if ($p.post_time -lt $cutoff) { break }
      $u = [string]$p.url
      if ($seenSet.Contains($u)) { continue }
      [void]$seenSet.Add($u)
      $allNew += @{ name = $a.name; title = [string]$p.title; url = $u; time = $p.post_time; digest = [string]$p.digest; sn = [string]$p.sn }
      $newCount++
      if ($newCount -ge 8) { break }
    }
  } catch {
    $errors += ($a.name + ': ' + $_.Exception.Message)
  }
}

# optional full-text via article_detail (0.03 CNY each, newest 3 only)
if ($Detail -and $allNew.Count -gt 0) {
  $take = @($allNew | Select-Object -First 3)
  foreach ($it in $take) {
    try {
      $q = 'https://www.dajiala.com/fbmain/monitor/v3/article_detail?url=' + [uri]::EscapeDataString($it.url) + '&key=' + [uri]::EscapeDataString($key) + '&mode=1&verifycode='
      $d = Invoke-RestMethod -Uri $q -TimeoutSec 30
      $tally += [double]($d.cost_money)
      if ($d.code -eq 0 -and $d.data -and $d.data.content) {
        $ex = [string]$d.data.content -replace '<[^>]+>', ' '
        $ex = $ex -replace '\s+', ' '
        if ($ex.Length -gt 300) { $ex = $ex.Substring(0, 300) + '...' }
        $it.excerpt = $ex
      }
    } catch {
      $errors += ('detail(' + $it.name + '): ' + $_.Exception.Message)
    }
  }
}

foreach ($it in $allNew) { $seen += $it.url }
if ($seen.Count -gt 1000) { $seen = @($seen | Select-Object -Last 1000) }
[System.IO.File]::WriteAllLines($seenFile, $seen, $Utf8)

Write-Output ('DAJIALA new=' + $allNew.Count + ' accounts=' + $done + ' cost=' + [math]::Round($tally, 2) + 'CNY errs=' + $errors.Count)
if ($ghidMissing.Count -gt 0) { Write-Output ('NO-GHID: ' + ($ghidMissing -join ', ') + ' (fill ghid in accounts.json to monitor these)') }
foreach ($e in $errors) { Write-Output ('ERR ' + $e) }
if ($allNew.Count -eq 0) { exit 0 }

$repFile = Join-Path $reports ($dateFile + '.md')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## ' + $stamp + ' - WeChat digest (accounts/dajiala)')
$cur = ''
foreach ($it in $allNew) {
  if ($it.name -ne $cur) { $cur = $it.name; [void]$sb.AppendLine('### ' + $cur) }
  $t = (Get-Date '1970-01-01').AddSeconds($it.time).ToString('MM-dd')
  $line = '- [' + $it.title + '](' + $it.url + ') (' + $t + ')'
  if ($it.excerpt) { $line += "`n  - excerpt: " + $it.excerpt }
  [void]$sb.AppendLine($line)
}
[System.IO.File]::AppendAllText($repFile, $sb.ToString(), $Utf8)
