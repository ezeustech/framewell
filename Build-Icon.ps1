$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$bitmap=New-Object System.Drawing.Bitmap(256,256)
$graphics=[System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode='AntiAlias'
$graphics.Clear([System.Drawing.Color]::Transparent)
$round=New-Object System.Drawing.Drawing2D.GraphicsPath
$round.AddArc(8,8,104,104,180,90);$round.AddArc(144,8,104,104,270,90)
$round.AddArc(144,144,104,104,0,90);$round.AddArc(8,144,104,104,90,90);$round.CloseFigure()
$gradient=New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Point(0,0)),(New-Object System.Drawing.Point(256,256)),[System.Drawing.Color]::FromArgb(67,154,255),[System.Drawing.Color]::FromArgb(12,72,210))
$graphics.FillPath($gradient,$round)
$pad=New-Object System.Drawing.Drawing2D.GraphicsPath
$pad.StartFigure();$pad.AddBezier(82,80,60,80,52,94,46,122)
$pad.AddLine(46,122,36,169);$pad.AddBezier(36,169,32,190,49,198,65,184)
$pad.AddLine(65,184,91,158);$pad.AddLine(91,158,165,158);$pad.AddLine(165,158,191,184)
$pad.AddBezier(191,184,207,198,224,190,220,169);$pad.AddLine(220,169,210,122)
$pad.AddBezier(210,122,204,94,196,80,174,80);$pad.AddLine(174,80,82,80);$pad.CloseFigure()
$graphics.FillPath([System.Drawing.Brushes]::White,$pad)
$ink=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(31,106,228))
$graphics.FillRectangle($ink,68,115,42,12);$graphics.FillRectangle($ink,83,100,12,42)
$graphics.FillEllipse($ink,162,101,17,17);$graphics.FillEllipse($ink,184,121,17,17)
$graphics.FillEllipse($ink,122,139,10,10)
$memory=New-Object IO.MemoryStream
$bitmap.Save($memory,[System.Drawing.Imaging.ImageFormat]::Png)
$bytes=$memory.ToArray()
$stream=[IO.File]::Create((Join-Path $PSScriptRoot 'GamingMode.ico'))
$writer=New-Object IO.BinaryWriter($stream)
$writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]1)
$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([byte]0)
$writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$bytes.Length);$writer.Write([uint32]22);$writer.Write($bytes)
$writer.Dispose();$memory.Dispose();$ink.Dispose();$pad.Dispose();$gradient.Dispose();$round.Dispose();$graphics.Dispose();$bitmap.Dispose()
