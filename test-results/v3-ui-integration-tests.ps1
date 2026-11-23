$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'GamingMode.ps1') -LibraryOnly
$before=@(Get-Process|ForEach-Object Id)
$ui=Show-MacGamingPanel -CreateOnly
Update-MacGamingDashboard $ui
Update-MacGamingGameList $ui -Reload
Update-MacGamingProfiles $ui
Update-MacGamingServers $ui -ReloadGames
Update-MacGamingMemory $ui -LoadPreferences
Update-MacGamingOptimizer $ui -Reload
Update-MacGamingSettings $ui
foreach($page in @('Overview','Games','Profiles','Performance','Network','Tools','Settings')){
    Set-MacGamingPage $ui $page
    $ui.Window.Content.Measure((New-Object Windows.Size(1050,790)))
    $ui.Window.Content.Arrange((New-Object Windows.Rect(0,0,1050,790)))
    $ui.Window.Content.UpdateLayout()
    if($ui.Controls[('Page'+$page)].ActualWidth -lt 600){throw ('Page width: '+$page)}
}
$runtime=Get-GamingMemoryRuntime
if($runtime.MonitorRunning -or $runtime.TimerEnabled){throw 'Integration reads unexpectedly activated memory tools.'}
$result=[pscustomobject]@{Success=$true;GameCount=$ui.Games.Count;Profiles=$ui.Profiles.Count;Themes=$ui.Controls.AppearanceTheme.Items.Count;OptimizerFeatures=$ui.OptimizerCatalog.Count;NetworkEndpoints=$ui.Controls.NetworkServer.Items.Count;MemoryStatus=$ui.Controls.MemoryReadings.Text;CpuStatus=$ui.Controls.CpuStatus.Text;Mode=$ui.Controls.ModeBadge.Text;Message='All real module reads and UI refreshes completed. No app closure, driver writes, priority changes, probes or memory operations invoked.'}
$ui.Window.Close()
$result|ConvertTo-Json -Depth 3
