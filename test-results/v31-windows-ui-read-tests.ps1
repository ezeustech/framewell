$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'WindowsGameSettings.ps1')
. (Join-Path $root 'MacInterface.ps1')
function Get-GamingPreferences {[pscustomobject]@{Theme='Dark';CloseAfterActivation=$true}}
function Update-MacGamingSelectedGame {param($UI);Update-MacGamingGpuPreference $UI}
$ui=Show-MacGamingPanel -CreateOnly
try{
    Update-MacGamingWindowsSettings $ui -IncludeDisplay
    foreach($name in @('WindowsGameMode','WindowsHardwareScheduling','WindowsBackgroundCapture')){if($ui.Controls[$name].SelectedItem -notin @('Default','Enabled','Disabled')){throw ('Invalid preference '+$name)}}
    if(-not $ui.Controls.WindowsDisplayMode.Items.Count){throw 'No primary display modes loaded'}
    if(-not $ui.Controls.WindowsDisplayMode.SelectedItem.IsCurrent){throw 'Current primary display refresh rate not selected'}
    $game=[pscustomobject]@{Id='readonly-fixture';Name='Read-only preference fixture';ExecutablePath=(Join-Path $env:SystemRoot 'System32\notepad.exe');NeedsExecutableSelection=$false}
    $ui.Controls.GameList.ItemsSource=@($game);$ui.Controls.GameList.SelectedItem=$game
    if($ui.Controls.WindowsGpuPreference.SelectedItem -notin @('Default','PowerSaving','HighPerformance')){throw 'GPU preference getter did not populate selector'}
    [pscustomobject]@{Success=$true;GameMode=[string]$ui.Controls.WindowsGameMode.SelectedItem;HardwareScheduling=[string]$ui.Controls.WindowsHardwareScheduling.SelectedItem;BackgroundCapture=[string]$ui.Controls.WindowsBackgroundCapture.SelectedItem;DisplayModeCount=$ui.Controls.WindowsDisplayMode.Items.Count;CurrentRefreshHz=$ui.Controls.WindowsDisplayMode.SelectedItem.RefreshHz;GpuPreference=[string]$ui.Controls.WindowsGpuPreference.SelectedItem;Message='Live getters integrated with WPF only. No registry, display, GPU, elevation or app-state writes requested.'}|ConvertTo-Json
}finally{$ui.Window.Close()}
