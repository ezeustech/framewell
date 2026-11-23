$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'MacInterface.ps1')
$script:calls=New-Object 'System.Collections.Generic.List[string]'
$script:timer=$false;$script:monitor=$false
function Get-GamingPreferences {[pscustomobject]@{Theme='Dark';CloseAfterActivation=$true}}
function Set-GamingPreferences {param($Preferences) $script:calls.Add('theme:'+ $Preferences.Theme);$Preferences}
function Get-GameLibrary {@([pscustomobject]@{Id='game-test';Name='Fixture game';ExecutablePath='C:\Games\Fixture.exe';Source='Manual';InstallDirectory='C:\Games';NeedsExecutableSelection=$false})}
function Get-GamingCpuTopology {[pscustomobject]@{LogicalProcessorCount=16;ProcessorGroups=1;SupportsAffinity=$true;Message='All available.'}}
function Get-GamingProcessPreference {param($GameId) [pscustomobject]@{GameId=$GameId;Priority='Normal';LogicalProcessors=@();ApplyOnLaunch=$false}}
function Get-GamingProcessTargets {param($GameId) @([pscustomobject]@{ProcessId=1234;Name='Fixture';Priority='Normal'})}
function Save-GamingProcessPreference {param($GameId,$Priority,$LogicalProcessors,$ApplyOnLaunch) $script:calls.Add('cpu-save:'+ $GameId+':'+$Priority+':'+($LogicalProcessors-join ','));[pscustomobject]@{Success=$true;Message='CPU saved.'}}
function Invoke-GamingProcessTuning {param($GameId) $script:calls.Add('cpu-apply:'+ $GameId);[pscustomobject]@{Success=$true;Message='CPU applied.'}}
function Restore-GamingProcessTuning {param($GameId) $script:calls.Add('cpu-restore:'+ $GameId);[pscustomobject]@{Success=$true;Message='CPU restored.'}}
function Get-GamingGameExecutableCandidates {param($GameId) @([pscustomobject]@{Name='Fixture.exe';Path='C:\Games\Fixture.exe'})}
function Get-GamingNvidiaGameProfile {param($ExecutablePath) [pscustomobject]@{CanApply=$false;CanRestore=$false;Message='Mock GPU';Settings=@();Notes=@()}}
function Get-GamingNvidiaSettingsCatalog {@()}
function Get-GamingMemorySnapshot {[pscustomobject]@{TotalMB=32768;AvailableMB=12000;StandbyMB=4000;FreeMB=8000;CurrentTimerMs=15.625;StandbyAvailable=$true}}
function Get-GamingMemoryRuntime {[pscustomobject]@{MonitorRunning=$script:monitor;TimerEnabled=$script:timer;TimerMilliseconds=1;PurgeCount=0;LastMessage='Mock memory';RequiresOpenApp=($script:monitor-or$script:timer)}}
function Get-GamingMemoryPreferences {[pscustomobject]@{StandbyThresholdMB=1024;AvailableThresholdMB=2048;IntervalSeconds=30;TimerMilliseconds=1}}
function Save-GamingMemoryPreferences {param($StandbyThresholdMB,$AvailableThresholdMB,$IntervalSeconds,$TimerMilliseconds) $script:calls.Add('memory-save');[pscustomobject]@{Success=$true;Message='Saved.'}}
function Invoke-GamingStandbyPurge {$script:calls.Add('memory-purge');[pscustomobject]@{Success=$true;Message='Mock purge.'}}
function Start-GamingMemoryMonitor {param($StandbyThresholdMB,$AvailableThresholdMB,$IntervalSeconds) $script:monitor=$true;$script:calls.Add('memory-monitor-start');[pscustomobject]@{Success=$true;Message='Mock monitor.'}}
function Stop-GamingMemoryMonitor {$script:monitor=$false;$script:calls.Add('memory-monitor-stop');[pscustomobject]@{Success=$true;Message='Stopped.'}}
function Set-GamingTimerResolution {param($Enabled,$Milliseconds) $script:timer=$Enabled;$script:calls.Add('timer:'+ $Enabled);if($Enabled -and $Milliseconds -ne 0.5){throw 'Fractional timer value was not passed to the backend.'};[pscustomobject]@{Success=$true;Message='Mock timer.'}}
function Get-GamingNetworkServers {param($GameId) @([pscustomobject]@{Id='fixture-server';Name='Fixture server';GameId=$GameId;GameName='Fixture game';HostName='example.com';Protocol='TCP';Port=443;Source='Saved';Notes='Fixture endpoint.';SourceUrl='https://example.com'})}
function Get-GamingNetworkGameGuidance {param($GameId) [pscustomobject]@{Message='Fixture route estimate.';SourceUrl='';SupportsPublishedEndpoints=$false}}
function Get-GamingActiveGameEndpoints {param($GameId) $script:calls.Add('active-endpoints:'+ $GameId);@()}
function Save-GamingNetworkServer {param($Name,$HostName,$Protocol,$Port,$GameId) $script:calls.Add('server-save:'+ $HostName+':'+$Protocol+':'+$Port);[pscustomobject]@{Id='fixture-server'}}
function Remove-GamingNetworkServer {param($Id) $script:calls.Add('server-remove:'+ $Id);[pscustomobject]@{Success=$true;Message='Removed.'}}
function Invoke-GamingNetworkTest {param($Samples,$InternetAddress,$Protocol,$Port,$TargetName,$GameId) $script:calls.Add('probe:'+ $InternetAddress+':'+$Protocol+':'+$Port);$summary=[pscustomobject]@{AverageMs=20;JitterMs=1;LossPercent=0};[pscustomobject]@{Success=$true;Gateway=$summary;Internet=$summary;Measurement='TCP handshake estimate.'}}
function Get-GamingSettingsProfiles {@([pscustomobject]@{Id='settings-fixture';Name='Fixture settings';Scope='All';Summary='Mock settings.'})}
function Save-GamingSettingsProfile {param($Name,$Scope) $script:calls.Add('settings-save:'+ $Scope);[pscustomobject]@{Id='settings-fixture'}}
function Export-GamingSettingsProfile {param($Id) $script:calls.Add('settings-export:'+ $Id)}
function Import-GamingSettingsProfile {$script:calls.Add('settings-import');[pscustomobject]@{Id='settings-fixture'}}
function Remove-GamingSettingsProfile {param($Id) $script:calls.Add('settings-remove:'+ $Id)}
function Get-GamingOptimizerFeatures {@([pscustomobject]@{Id='tool';Category='Windows';Name='Fixture optimizer option';Description='Mock integrated option'})}
function Get-GamingEmbeddedOptimizerInfo {[pscustomobject]@{Installed=$true;IsAdministrator=$false;Message='Mock component ready'}}
function Get-GamingEmbeddedOptimizerSections {param($View);@([pscustomobject]@{Id='windows10Tab';Name='Windows'})}
function New-GamingEmbeddedOptimizerView {param([IntPtr]$OwnerWindow);Add-Type -AssemblyName System.Windows.Forms;$script:calls.Add('optimizer-open');New-Object System.Windows.Forms.Panel}
function Set-GamingEmbeddedOptimizerSection {param($View,$Section)}
function Set-GamingEmbeddedOptimizerTheme {param($View,$Theme)}
function Remove-GamingEmbeddedOptimizerView {param($View);$View.Dispose()}
$ui=Show-MacGamingPanel -CreateOnly
function Click-Mock([string]$Name){$ui.Controls[$Name].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
Update-MacGamingGameList $ui -Reload
$ui.Controls.CpuPriority.SelectedItem='AboveNormal';$ui.Controls.CpuCoreSelection.Text='0-3, 7'
Click-Mock 'CpuSave';Click-Mock 'CpuApply';Click-Mock 'CpuRestore';Click-Mock 'CpuRefresh'
Update-MacGamingMemory $ui -LoadPreferences
Click-Mock 'MemorySave';Click-Mock 'QuickMemoryPurge'
$ui.Controls.MemoryMonitorToggle.IsChecked=$true;Click-Mock 'MemoryMonitorToggle'
$ui.Controls.MemoryMonitorToggle.IsChecked=$false;Click-Mock 'MemoryMonitorToggle'
$ui.Controls.MemoryTimerMilliseconds.Text='0.5';$ui.Controls.MemoryTimerToggle.IsChecked=$true;Click-Mock 'MemoryTimerToggle'
$ui.Controls.MemoryTimerMilliseconds.Text='invalid';$ui.Controls.MemoryTimerToggle.IsChecked=$false;Click-Mock 'MemoryTimerToggle'
Update-MacGamingServers $ui -ReloadGames
$ui.Controls.NetworkGame.SelectedIndex=1
Click-Mock 'NetworkActiveEndpoints';Click-Mock 'NetworkSaveServer';Click-Mock 'NetworkRemoveServer';Click-Mock 'RunNetworkTest'
Update-MacGamingSettingsProfiles $ui
$ui.Controls.SettingsProfileScope.SelectedItem='Memory'
Click-Mock 'SettingsProfileSave';Click-Mock 'SettingsProfileExport';Click-Mock 'SettingsProfileImport';Click-Mock 'SettingsProfileRemove'
Update-MacGamingOptimizer $ui -Reload
$ui.Controls.OptimizerSearch.Text='fixture';Click-Mock 'OptimizerLaunch'
$ui.Controls.AppearanceTheme.SelectedItem=($ui.Controls.AppearanceTheme.ItemsSource|Where-Object Id -eq 'DIO')
$expected=@('cpu-save:game-test:AboveNormal:0,1,2,3,7','cpu-apply:game-test','cpu-restore:game-test','memory-save','memory-purge','memory-monitor-start','memory-monitor-stop','timer:True','timer:False','active-endpoints:game-test','server-save:example.com:TCP:443','server-remove:fixture-server','probe:example.com:TCP:443','settings-save:Memory','settings-export:settings-fixture','settings-import','settings-remove:settings-fixture','optimizer-open','theme:DIO')
foreach($item in $expected){if($item -notin @($script:calls)){throw ('Missing mock event: '+$item+'; events: '+($script:calls -join ', '))}}
if($ui.Controls.InternetLoss.Text -notlike 'Probe failures*'){throw 'TCP result was mislabeled as packet loss.'}
$ui.Window.Close()
[pscustomobject]@{Success=$true;VerifiedEvents=$expected.Count;ActualMockCalls=$script:calls.Count;Message='UI handlers invoked only mocked services. No driver, process, memory, network or registry changes.'}|ConvertTo-Json
