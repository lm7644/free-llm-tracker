# Sogou WeChat search digest: rotate keywords daily, dedup seen titles, append new items to daily report. ASCII-only.
param([string]$WsRoot)
$ErrorActionPreference = 'Continue'
if (-not $WsRoot) { $WsRoot = Split-Path -Parent $PSScriptRoot }
$mon      = Join-Path $WsRoot 'monitor'
$reports  = Join-Path $mon 'reports'
$seenFile = Join-Path $mon 'sogou-seen.txt'
if (-not (Test-Path $reports)) { New-Item -ItemType Directory -Path $reports | Out-Null }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$kws = [System.IO.File]::ReadAllText((Join-Path $mon 'keywords.json'), [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$seen = @()
if (Test-Path $seenFile) { $seen = @([System.IO.File]::ReadAllLines($seenFile, [System.Text.Encoding]::UTF8) | Where-Object { $_.Trim() }) }
$seenSet = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($s in $seen) { [void]$seenSet.Add($s) }

$doy = (Get-Date).DayOfYear
$n = $kws.Count
$picks = @($kws[($doy - 1) % $n], $kws[($doy + 1) % $n] | Where-Object { $_ -ne $null })
$now = Get-Date
$stamp = $now.ToString('yyyy-MM-dd HH:mm')
$dateFile = $now.ToString('yyyy-MM-dd')
$allNew = @()
$captcha = $false
$errors = @()

function StripTags([string]$s) {
  $s = $s -replace '(?s)<[^>]+>', ''
  $s = $s -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'" -replace '&nbsp;', ' '
  return $s.Trim()
}

foreach ($p in $picks) {
  if (-not $p) { continue }
  $kw = $p.kw
  try {
    $enc = [uri]::EscapeDataString($kw)
    $url = 'https://weixin.sogou.com/weixin?type=2&query=' + $enc
    $resp = Invoke-WebRequest -Uri $url -TimeoutSec 20 -UseBasicParsing -MaximumRedirection 4 -Headers @{
      'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36'
      'Referer' = 'https://weixin.sogou.com/'
      'Accept-Language' = 'zh-CN,zh;q=0.9'
    }
    $html = [string]$resp.Content
    if ($html -match 'antispider' -or $html -match 'weixin\.sogou\.com/antispider') { $captcha = $true; $errors += ($kw + ': captcha page'); continue }
    $chunks = [regex]::Split($html, '<h3')
    $newCount = 0
    foreach ($ch in $chunks) {
      if ($ch -notmatch 'href="([^"]+)"') { continue }
      $href = $Matches[1]
      # capture the WHOLE anchor inner content, then strip tags (handles <em> highlights anywhere)
      if ($ch -notmatch '(?s)^[^>]*>\s*<a[^>]*>([\s\S]*?)</a>') {
        if ($ch -notmatch '(?s)<a[^>]*>([\s\S]*?)</a>') { continue }
      }
      $title = (StripTags $Matches[1]) -replace '\s+', ' '
      if ($title.Length -lt 6) { continue }
      $acc = ''
      if ($ch -match 'class="account[^"]*"[^>]*>([\s\S]*?)</a>') { $acc = StripTags $Matches[1] }
      elseif ($ch -match '(?s)<span[^>]*>\s*([^<>]{2,24})\s*</span>\s*<span[^>]*class="s2') { $acc = $Matches[1].Trim() }
      if ($acc -match '公众|账号|未知') { $acc = '' }
      if ($href.StartsWith('/link')) { $href = 'https://weixin.sogou.com' + $href }
      if (-not $href.StartsWith('http')) { continue }
      if ($seenSet.Contains($title)) { continue }
      [void]$seenSet.Add($title)
      $allNew += @{ kw = $kw; title = $title; acc = $acc; href = $href }
      $newCount++
      if ($newCount -ge 8) { break }
    }
  } catch {
    $errors += ($kw + ': ' + $_.Exception.Message)
  }
}

# update seen store (cap 800 lines, newest last)
foreach ($it in $allNew) { $seen += $it.title }
if ($seen.Count -gt 800) { $seen = @($seen | Select-Object -Last 800) }
[System.IO.File]::WriteAllLines($seenFile, $seen, $Utf8)

Write-Output ('SOGOU new=' + $allNew.Count + ' captcha=' + $captcha + ' errs=' + $errors.Count)
foreach ($e in $errors) { Write-Output ('ERR ' + $e) }

if ($allNew.Count -eq 0) { exit 0 }

$repFile = Join-Path $reports ($dateFile + '.md')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## ' + $stamp + ' - WeChat digest (sogou)')
$curKw = ''
foreach ($it in $allNew) {
  if ($it.kw -ne $curKw) { $curKw = $it.kw; [void]$sb.AppendLine('### keyword: ' + $curKw) }
  $accTxt = if ($it.acc) { ' - ' + $it.acc } else { '' }
  [void]$sb.AppendLine('- [' + $it.title + '](' + $it.href + ')' + $accTxt)
}
[System.IO.File]::AppendAllText($repFile, $sb.ToString(), $Utf8)
