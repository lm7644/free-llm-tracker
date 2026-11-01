# FreeLLM channel monitor: fetch sources, diff against store, write change report + RSS feed.
# ASCII-only on purpose (PowerShell 5.1 reads no-BOM files as ANSI). Chinese text lives in UTF-8 data files.
param([string]$WsRoot)
$ErrorActionPreference = 'Continue'
if (-not $WsRoot) { $WsRoot = Split-Path -Parent $PSScriptRoot }
$mon       = Join-Path $WsRoot 'monitor'
$storeDir  = Join-Path $mon 'store'
$reports   = Join-Path $mon 'reports'
$feedPath  = Join-Path $mon 'feed.xml'
$heartbeat = Join-Path $mon 'heartbeat.log'
foreach ($d in @($storeDir, $reports)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$srcJson = [System.IO.File]::ReadAllText((Join-Path $mon 'sources.json'), [System.Text.Encoding]::UTF8)
$sources = $srcJson | ConvertFrom-Json
$now = Get-Date
$stamp = $now.ToString('yyyy-MM-dd HH:mm')
$dateFile = $now.ToString('yyyy-MM-dd')

function Normalize([string]$Text, [string]$Mode) {
  if ($Mode -eq 'html') {
    $t = $Text -replace '(?is)<script\b.*?</script>', ' '
    $t = $t -replace '(?is)<style\b.*?</style>', ' '
    $t = $t -replace '(?is)<br\s*/?>', "`n"
    $t = $t -replace '(?is)</(p|div|li|h[1-6]|tr|section|article)>', "`n"
    $t = $t -replace '(?s)<[^>]+>', ' '
    $t = $t -replace '&nbsp;', ' '
    $t = $t -replace '&amp;', '&' -replace '&lt;', '<' -replace '&gt;', '>' -replace '&quot;', '"' -replace '&#39;', "'"
  } else {
    $t = $Text
  }
  # canonical form: per-line trim, drop empty lines -> whitespace-only differences never count as changes
  $lines = @($t -split "`r?`n" | ForEach-Object { ($_ -replace '[ \t]+', ' ').Trim() } | Where-Object { $_.Length -gt 0 })
  return ($lines -join "`n")
}

function ShowLines([string[]]$Lines, [int]$Max) {
  $out = @()
  foreach ($l in $Lines) {
    if ($out.Count -ge $Max) { break }
    $s = $l.Trim()
    if ($s.Length -gt 200) { $s = $s.Substring(0, 200) + '...' }
    if ($s.Length -gt 0) { $out += $s }
  }
  return $out
}

$okCount = 0; $failCount = 0; $baselineCount = 0
$changeItems = @()   # hashtables: slug, name, url, added, removed, addedN, removedN
$failMsgs = @()

foreach ($s in $sources) {
  $slug = $s.slug
  try {
    $resp = Invoke-WebRequest -Uri $s.url -TimeoutSec 25 -UseBasicParsing -MaximumRedirection 4 -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 FreeLLM-Monitor/1.0' }
    $text = Normalize ([string]$resp.Content) $s.mode
    $storeFile = Join-Path $storeDir ($slug + '.txt')
    $isNew = -not (Test-Path $storeFile)
    if ($isNew) {
      [System.IO.File]::WriteAllText($storeFile, $text, $Utf8)
      $baselineCount++
      continue
    }
    $old = [System.IO.File]::ReadAllText($storeFile, [System.Text.Encoding]::UTF8)
    if ($old -eq $text) { $okCount++; continue }
    $oldLines = @($old -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $newLines = @($text -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    $oldSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($l in $oldLines) { [void]$oldSet.Add($l) }
    $newSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($l in $newLines) { [void]$newSet.Add($l) }
    $added = @($newLines | Where-Object { -not $oldSet.Contains($_) })
    $removed = @($oldLines | Where-Object { -not $newSet.Contains($_) })
    [System.IO.File]::WriteAllText($storeFile, $text, $Utf8)
    $okCount++
    if ($added.Count -eq 0 -and $removed.Count -eq 0) { continue }
    $changeItems += @{ slug = $slug; name = $s.name; url = $s.url; added = $added; removed = $removed; addedN = $added.Count; removedN = $removed.Count }
  } catch {
    $failCount++
    $failMsgs += ($s.name + ': ' + $_.Exception.Message)
  }
}

# heartbeat (every run)
$hb = "$stamp ok=$okCount fail=$failCount baseline=$baselineCount changed=$($changeItems.Count)"
if ($failMsgs.Count -gt 0) { $hb += ' | ' + ($failMsgs -join ' ; ') }
[System.IO.File]::AppendAllText($heartbeat, $hb + [Environment]::NewLine, $Utf8)

if ($changeItems.Count -eq 0) { Write-Output ("DONE no-changes " + $hb); exit 0 }

# markdown report (append by date)
$repFile = Join-Path $reports ($dateFile + '.md')
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## ' + $stamp)
foreach ($c in $changeItems) {
  [void]$sb.AppendLine('### ' + $c.name + ' (' + $c.slug + ')')
  [void]$sb.AppendLine('- URL: ' + $c.url)
  [void]$sb.AppendLine('- Changed: +' + $c.addedN + ' / -' + $c.removedN + ' lines')
  if ($c.added.Count -gt 0) {
    [void]$sb.AppendLine('- Added samples:')
    foreach ($l in (ShowLines $c.added 5)) { [void]$sb.AppendLine('  - + ' + $l) }
  }
  if ($c.removed.Count -gt 0) {
    [void]$sb.AppendLine('- Removed samples:')
    foreach ($l in (ShowLines $c.removed 5)) { [void]$sb.AppendLine('  - - ' + $l) }
  }
}
[System.IO.File]::AppendAllText($repFile, $sb.ToString(), $Utf8)

# RSS feed (keep newest 60 items)
$items = @()
foreach ($c in $changeItems) {
  $title = $c.name + ' changed (+' + $c.addedN + '/-' + $c.removedN + ' lines)'
  $desc = ''
  foreach ($l in (ShowLines $c.added 3)) { $desc += '+ ' + $l + ' &lt;br/&gt; ' }
  $items += '    <item><title>' + $title + '</title><link>' + $c.url + '</link><description>' + $desc + '</description><pubDate>' + $now.ToString('r') + '</pubDate><guid isPermaLink="false">' + $c.slug + '-' + $now.ToString('yyyyMMddHHmmss') + '</guid></item>'
}
$feedItems = $items
if (Test-Path $feedPath) {
  $oldFeed = [System.IO.File]::ReadAllText($feedPath, [System.Text.Encoding]::UTF8)
  $m = [regex]::Matches($oldFeed, '(?s)<item>.*?</item>')
  foreach ($mm in $m) { $feedItems += $mm.Value }
}
$feedItems = @($feedItems | Select-Object -First 60)
$feed = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<rss version="2.0"><channel>' + "`n" +
  '<title>FreeLLM channel monitor</title>' + "`n" + '<link>https://localhost/</link>' + "`n" +
  '<description>Change monitor for official LLM free-tier pages (locally generated)</description>' + "`n" +
  ($feedItems -join "`n") + "`n" + '</channel></rss>'
[System.IO.File]::WriteAllText($feedPath, $feed, $Utf8)

Write-Output ("DONE changes=" + $changeItems.Count + " " + $hb)
