# Bocha Chinese web search - budget-paced (quota: 1000 calls / 3 months).
# Daily allowance = ceil(remaining / daysLeft), capped by maxPerDay. Rotates through bocha-queries.json.
# ASCII-only. Optional: -Force (ignore allowance), -Query "..." (ad-hoc, still budget-tracked), -NumQueries N.
param([string]$WsRoot, [switch]$Force, [string]$Query, [int]$NumQueries = 0)
$ErrorActionPreference = 'Continue'
if (-not $WsRoot) { $WsRoot = Split-Path -Parent $PSScriptRoot }
$mon       = Join-Path $WsRoot 'monitor'
$reports   = Join-Path $mon 'reports'
$seenFile  = Join-Path $mon 'bocha-seen.txt'
$usageFile = Join-Path $mon 'bocha-usage.log'
if (-not (Test-Path $reports)) { New-Item -ItemType Directory -Path $reports | Out-Null }
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$key = $env:BOCHA_KEY
$envFile = Join-Path $mon '.env'
if (-not $key -and (Test-Path $envFile)) {
  foreach ($l in [System.IO.File]::ReadAllLines($envFile)) {
    if ($l -match '^\s*BOCHA_KEY\s*=\s*(\S+)\s*$') { $key = $Matches[1] }
  }
}
if (-not $key) { Write-Output 'BOCHA SKIP: no BOCHA_KEY configured'; exit 0 }

# budget pacing
$budget = [System.IO.File]::ReadAllText((Join-Path $mon 'bocha-budget.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$today = Get-Date
$start = [datetime]::Parse($budget.startISO)
$expiry = $start.AddMonths($budget.months)
$daysLeft = [math]::Ceiling(($expiry - $today).TotalDays)
if ($daysLeft -lt 1) { $daysLeft = 1 }
$used = 0
if (Test-Path $usageFile) { $used = @([System.IO.File]::ReadAllLines($usageFile) | Where-Object { $_.Trim() }).Count }
$remaining = $budget.total - $used
if ($remaining -le 0) { Write-Output ('BOCHA SKIP: budget exhausted (' + $used + '/' + $budget.total + ')'); exit 0 }
$usedToday = 0
if (Test-Path $usageFile) { $usedToday = @([System.IO.File]::ReadAllLines($usageFile) | Where-Object { $_ -match ('^\d{4}-\d{2}-\d{2} ') -and $_.StartsWith($today.ToString('yyyy-MM-dd')) }).Count }
$allowance = [math]::Ceiling($remaining / $daysLeft)
if ($allowance -gt $budget.maxPerDay) { $allowance = $budget.maxPerDay }
$allowance = [math]::Min($allowance, $remaining)
$n = $budget.perRun
if ($NumQueries -gt 0) { $n = $NumQueries }
if (-not $Force) {
  $n = [math]::Min($n, [math]::Max(0, $allowance - $usedToday))
  if ($n -le 0) { Write-Output ('BOCHA SKIP: daily allowance used (' + $usedToday + '/' + $allowance + '), used=' + $used + '/' + $budget.total + ', daysLeft=' + $daysLeft); exit 0 }
} else {
  $n = [math]::Min($n, [math]::Max(1, $allowance))
}

# pick queries (rotate by day, then sequence)
$ql = [System.IO.File]::ReadAllText((Join-Path $mon 'bocha-queries.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$doy = $today.DayOfYear
$idxs = @()
for ($i = 0; $i -lt $n; $i++) { $idxs += (($doy - 1) * $budget.perRun + $i) % $ql.Count }
if ($Query) { $idxs = @(-1) }

$seen = @()
if (Test-Path $seenFile) { $seen = @([System.IO.File]::ReadAllLines($seenFile, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() }) }
$seenSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in $seen) { [void]$seenSet.Add($s) }

$stamp = $today.ToString('yyyy-MM-dd HH:mm')
$dateFile = $today.ToString('yyyy-MM-dd')
$allNew = @()
$calls = 0
$errors = @()

foreach ($ix in $idxs) {
  $q = if ($ix -eq -1) { $Query } else { $ql[$ix].q }
  $body = @{ query = $q; count = 5; freshness = 'oneWeek'; summary = $false } | ConvertTo-Json -Compress
  try {
    $r = Invoke-WebRequest -Uri 'https://api.bochaai.com/v1/web-search' -Method Post -ContentType 'application/json' -Headers @{ Authorization = ('Bearer ' + $key) } -Body $body -TimeoutSec 30 -UseBasicParsing
    $json = ([System.Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())) | ConvertFrom-Json
    $calls++
    [System.IO.File]::AppendAllText($usageFile, ($today.ToString('yyyy-MM-dd HH:mm') + ' ' + $q) + [Environment]::NewLine, $Utf8)
    if ($json.code -and $json.code -ne 200) { $errors += ($q + ': code ' + $json.code); continue }
    $pages = @()
    if ($json.data -and $json.data.webPages) { $pages = @($json.data.webPages.value) }
    foreach ($p in $pages) {
      $u = [string]$p.url
      if ($seenSet.Contains($u)) { continue }
      [void]$seenSet.Add($u)
      $allNew += @{ q = $q; name = $p.siteName; title = [string]$p.name; url = $u; snippet = ([string]$p.summary -replace '\s+', ' ') }
    }
  } catch {
    $resp = $_.Exception.Response; $code = 'ERR'; $eb = ''
    if ($resp) { $code = [int]$resp.StatusCode; try { $rd = New-Object System.IO.StreamReader($resp.GetResponseStream()); $eb = $rd.ReadToEnd() } catch {} }
    $hint = if ($code -eq 403) { ' | hint: check console (service/quota/real-name/key)' } else { '' }
    $errors += ($q + ': HTTP ' + $code + $hint)
  }
}

foreach ($it in $allNew) { $seen += $it.url }
if ($seen.Count -gt 2000) { $seen = @($seen | Select-Object -Last 2000) }
[System.IO.File]::WriteAllLines($seenFile, $seen, $Utf8)

$used2 = $used + $calls
Write-Output ('BOCHA calls=' + $calls + ' new=' + $allNew.Count + ' budget=' + $used2 + '/' + $budget.total + ' daysLeft=' + $daysLeft + ' allowanceToday=' + $allowance)
foreach ($e in $errors) { Write-Output ('ERR ' + $e) }
if ($allNew.Count -eq 0) { exit 0 }

$repFile = Join-Path $reports ($dateFile + '.md')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## ' + $stamp + ' - Web digest (bocha)')
foreach ($ix in $idxs) {
  $q = if ($ix -eq -1) { $Query } else { $ql[$ix].q }
  [void]$sb.AppendLine('### query: ' + $q)
  foreach ($it in ($allNew | Where-Object { $_.q -eq $q })) {
    $c = $it.snippet
    if ($c.Length -gt 160) { $c = $c.Substring(0, 160) + '...' }
    [void]$sb.AppendLine('- [' + $it.title + '](' + $it.url + ')')
    if ($c) { [void]$sb.AppendLine('  - ' + $c) }
  }
}
[System.IO.File]::AppendAllText($repFile, $sb.ToString(), $Utf8)
