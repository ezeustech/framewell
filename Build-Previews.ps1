$ErrorActionPreference='Stop'
$root=$PSScriptRoot
. (Join-Path $root 'MacInterface.ps1')
function Get-GamingPreferences {[pscustomobject]@{Theme='OLED';CloseAfterActivation=$true}}
$ui=Show-MacGamingPanel -CreateOnly
try{
 $ui.Controls.SidebarComputer.Text='DEMO PC'
 $ui.Controls.ProcessCount.Text='124';$ui.Controls.MemoryCount.Text='8.2 GB';$ui.Controls.MemoryTotal.Text='of 32 GB in use';$ui.Controls.MemoryMeter.Value=26
 $ui.Controls.RefreshCount.Text='144 Hz';$ui.Controls.QuickMemoryAvailable.Text='23.8 GB available';$ui.Controls.QuickMemoryStandby.Text='Standby cache: 5.4 GB'
 $ui.Controls.QuickMemoryState.Text='Monitor off - timer request off';$ui.Controls.MediaSummary.Text='Choose an app profile to get started.'
 $ui.Controls.StatusText.Text='Preview with demonstration data. No optimizations applied.'
 foreach($row in @(@('Overview','OLED','overview-oled.png'),@('Performance','Jotaro','windows-gaming-settings.png'),@('Tools','DIO','memory-dio-theme.png'))){
  Apply-MacGamingTheme $ui $row[1];Set-MacGamingPage $ui $row[0]
  $content=$ui.Window.Content;$content.Measure((New-Object Windows.Size(1050,790)));$content.Arrange((New-Object Windows.Rect(0,0,1050,790)));$content.UpdateLayout()
  $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(1050,790,96,96,[Windows.Media.PixelFormats]::Pbgra32)
  $bitmap.Render($content);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
  $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
  $stream=[IO.File]::Create((Join-Path $root ('docs/images/'+$row[2])))
  try{$encoder.Save($stream)}finally{$stream.Dispose()}
 }
}finally{$ui.Window.Close()}
