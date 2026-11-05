$ErrorActionPreference='Stop'
$ws=$PSScriptRoot
$h=[System.Net.HttpListener]::new()
$h.Prefixes.Add('http://127.0.0.1:8477/')
$h.Start()
Write-Host 'serving on 8477'
while($h.IsListening){
  try{
    $c=$h.GetContext()
    $p=[uri]::UnescapeDataString($c.Request.Url.AbsolutePath)
    if($p -eq '/'){$p='/大模型免费渠道全景表.html'}
    $f=Join-Path $ws ($p.TrimStart('/') -replace '/','\')
    $full=[System.IO.Path]::GetFullPath($f)
    $root=[System.IO.Path]::GetFullPath($ws)
    $inside = $full -eq $root -or $full.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
    if(-not $inside){ $c.Response.StatusCode=403; $c.Response.OutputStream.Close(); continue }
    if([System.IO.File]::Exists($f)){
      $b=[System.IO.File]::ReadAllBytes($f)
      $ct='text/html; charset=utf-8'
      if($f -match '\.png$'){$ct='image/png'}
      elseif($f -match '\.webmanifest$'){$ct='application/manifest+json; charset=utf-8'}
      elseif($f -match '\.xml$'){$ct='application/rss+xml; charset=utf-8'}
      elseif($f -match '\.(md|txt|json)$'){$ct='text/plain; charset=utf-8'}
      $c.Response.ContentType=$ct
      $c.Response.ContentLength64=$b.Length
      $c.Response.OutputStream.Write($b,0,$b.Length)
    } else {
      $c.Response.StatusCode=404
      $msg=[System.Text.Encoding]::UTF8.GetBytes('not found')
      $c.Response.OutputStream.Write($msg,0,$msg.Length)
    }
    $c.Response.OutputStream.Close()
  } catch { Write-Host ('ERR '+$_.Exception.Message) }
}
