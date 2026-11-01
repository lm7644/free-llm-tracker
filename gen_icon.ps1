# Generate PWA icon PNGs: green square, white punched-ticket, deep-green "0". ASCII-only.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$ws = 'C:\Users\Administrator\.zcode\workspace\draft-cf65791b-1509-4511-9b32-23bdd953e6f7'
function New-TicketIcon([int]$size, [string]$path) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
  $g.Clear([System.Drawing.Color]::FromArgb(138, 98, 21))
  $tw = [int]($size * 0.72); $th = [int]($size * 0.52)
  $tx = [int](($size - $tw) / 2); $ty = [int](($size - $th) / 2)
  $rad = [int]($size * 0.055)
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.FillMode = [System.Drawing.Drawing2D.FillMode]::Alternate
  $r = $rad * 2
  $gp.AddArc($tx, $ty, $r, $r, 180, 90)
  $gp.AddArc($tx + $tw - $r, $ty, $r, $r, 270, 90)
  $gp.AddArc($tx + $tw - $r, $ty + $th - $r, $r, $r, 0, 90)
  $gp.AddArc($tx, $ty + $th - $r, $r, $r, 90, 90)
  $gp.CloseFigure()
  $hw = [int]($size * 0.075); $hh = [int]($size * 0.10)
  $gp.AddEllipse($tx - [int]($hw / 2), $ty + [int](($th - $hh) / 2), $hw, $hh)
  $gp.AddEllipse($tx + $tw - [int]($hw / 2), $ty + [int](($th - $hh) / 2), $hw, $hh)
  $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
  $g.FillPath($white, $gp)
  $deep = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(138, 98, 21))
  $font = New-Object System.Drawing.Font('Consolas', ($th * 0.68), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
  $fmt = New-Object System.Drawing.StringFormat
  $fmt.Alignment = [System.Drawing.StringAlignment]::Center
  $fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
  $rect = New-Object System.Drawing.RectangleF($tx, $ty, $tw, $th)
  $g.DrawString('0', $font, $deep, $rect, $fmt)
  $g.Dispose()
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host ('OK ' + $path)
}
New-TicketIcon 512 (Join-Path $ws 'icon-512.png')
New-TicketIcon 192 (Join-Path $ws 'icon-192.png')
New-TicketIcon 180 (Join-Path $ws 'icon-180.png')
