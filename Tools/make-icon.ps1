# Draws the 1024x1024 app icon: blue-to-purple gradient with a white phone outline.
# Run from the project root:  powershell -File Tools\make-icon.ps1
Add-Type -AssemblyName System.Drawing

$size = 1024
$out = Join-Path $PSScriptRoot "..\Resources\Assets.xcassets\AppIcon.appiconset\AppIcon.png"

$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

$rect = New-Object System.Drawing.Rectangle(0, 0, $size, $size)
$blue = [System.Drawing.Color]::FromArgb(47, 107, 255)
$purple = [System.Drawing.Color]::FromArgb(138, 77, 255)
$brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $blue, $purple, 45.0)
$g.FillRectangle($brush, $rect)

function New-RoundedPath([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc($x, $y, $d, $d, 180, 90)
    $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Phone body
$white = [System.Drawing.Color]::White
$pen = New-Object System.Drawing.Pen($white, 44)
$body = New-RoundedPath 312 172 400 680 84
$g.DrawPath($pen, $body)

# Speaker pill
$pill = New-RoundedPath 452 222 120 30 15
$g.FillPath((New-Object System.Drawing.SolidBrush($white)), $pill)

# Three bars, a small chart on the screen
$barBrush = New-Object System.Drawing.SolidBrush($white)
$g.FillPath($barBrush, (New-RoundedPath 400 560 56 180 20))
$g.FillPath($barBrush, (New-RoundedPath 484 460 56 280 20))
$g.FillPath($barBrush, (New-RoundedPath 568 370 56 370 20))

$g.Dispose()
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
Write-Output "Wrote $out"
