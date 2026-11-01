# Tavily daily discovery: rotate one query/day, dedup by URL, append "Web digest (tavily)" to daily report. ASCII-only.
param([string]$WsRoot)
$ErrorActionPreference = 'Continue'
if (-not $WsRoot) { $WsRoot = Split-Path -Parent $PSScriptRoot }
$mon      = Join-Path $WsRoot 'monitor'
$reports  = Join-Path $mon 'reports'
$seenFile = Join-Path $mon 'tavily-seen.txt'
if (-not (Test-Path $reports)) { New-Item -ItemType Directory -Path $reports | Out-Null }
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$key = $env:TAVILY_KEY
$envFile = Join-Path $mon '.env'
if (-not $key -and (Test-Path $envFile)) {
  foreach ($l in [System.IO.File]::ReadAllLines($envFile)) {
    if ($l -match '^\s*TAVILY_KEY\s*=\s*(\S+)\s*$') { $key = $Matches[1] }
  }
}
if (-not $key) { Write-Output 'TAVILY SKIP: no TAVILY_KEY configured'; exit 0 }

$qs = [System.IO.File]::ReadAllText((Join-Path $mon 'discovery.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$doy = (Get-Date).DayOfYear
$q = $qs[($doy - 1) % $qs.Count].q
$seen = @()
if (Test-Path $seenFile) { $seen = @([System.IO.File]::ReadAllLines($seenFile, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() }) }
$seenSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in $seen) { [void]$seenSet.Add($s) }

$body = @{ query = $q; topic = 'news'; days = 7; max_results = 5 } | ConvertTo-Json -Compress
$r = $null
for ($attempt = 1; $attempt -le 2; $attempt++) {
  try {
    $r = Invoke-RestMethod -Uri 'https://api.tavily.com/search' -Method Post -ContentType 'application/json' -Headers @{ Authorization = ('Bearer ' + $key) } -Body $body -TimeoutSec 30
    break
  } catch {
    if ($attempt -ge 2) { Write-Output ('TAVILY FAIL: ' + $_.Exception.Message); exit 0 }
    Start-Sleep -Seconds 3
  }
}
$stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
$dateFile = (Get-Date).ToString('yyyy-MM-dd')
$allNew = @()
foreach ($p in @($r.results)) {
  $u = [string]$p.url
  if ($seenSet.Contains($u)) { continue }
  [void]$seenSet.Add($u)
  $allNew += @{ title = [string]$p.title; url = $u; content = ([string]$p.content) }
}
foreach ($it in $allNew) { $seen += $it.url }
if ($seen.Count -gt 1200) { $seen = @($seen | Select-Object -Last 1200) }
[System.IO.File]::WriteAllLines($seenFile, $seen, $Utf8)

Write-Output ('TAVILY query="' + $q + '" new=' + $allNew.Count + '/' + @($r.results).Count)

if ($allNew.Count -eq 0) { exit 0 }
$repFile = Join-Path $reports ($dateFile + '.md')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## ' + $stamp + ' - Web digest (tavily)')
[void]$sb.AppendLine('### query: ' + $q)
foreach ($it in $allNew) {
  $c = $it.content -replace '\s+', ' '
  if ($c.Length -gt 160) { $c = $c.Substring(0, 160) + '...' }
  [void]$sb.AppendLine('- [' + $it.title + '](' + $it.url + ')')
  [void]$sb.AppendLine('  - ' + $c)
}
[System.IO.File]::AppendAllText($repFile, $sb.ToString(), $Utf8)
