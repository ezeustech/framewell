$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'MacInterface.ps1')
$script:realDisplayConfirmation=(Get-Command Show-MacGamingDisplayConfirmation).ScriptBlock
Add-Type -AssemblyName System.Windows.Forms
function Get-GamingPreferences {[pscustomobject]@{Theme='Dark';CloseAfterActivation=$true}}
$script:calls=New-Object 'System.Collections.Generic.List[string]'
$script:created=0;$script:disposed=0;$script:failTheme=$false
function Get-GamingEmbeddedOptimizerInfo {[pscustomobject]@{Installed=$true;IsAdministrator=$false;Message='Mock component'}}
function Get-GamingEmbeddedOptimizerSections {@([pscustomobject]@{Id='universalTab';Name='Universal'},[pscustomobject]@{Id='pingerTab';Name='DNS & ping'},[pscustomobject]@{Id='advancedExtrasTab';Name='Advanced'})}
function New-GamingEmbeddedOptimizerView {param([IntPtr]$OwnerWindow);$script:created++;return (New-Object System.Windows.Forms.Panel)}
function Set-GamingEmbeddedOptimizerTheme {param($View,$Theme);if($script:failTheme){throw 'Mock theme failure'};$script:calls.Add('theme:'+ $Theme)}
function Set-GamingEmbeddedOptimizerSection {param($View,$Section);$script:calls.Add('section:'+ $Section)}
function Remove-GamingEmbeddedOptimizerView {param($View);$script:disposed++;$View.Dispose()}
function Restart-GamingModeElevated {param($InitialPage);$script:calls.Add('elevate:'+ $InitialPage);[pscustomobject]@{Success=$false;Message='Elevation declined in mock'}}
function Get-GamingWindowsSettings {[pscustomobject]@{GameMode='Enabled';HardwareScheduling='Default';BackgroundCapture='Disabled';IsAdministrator=$false}}
function Get-GamingDisplayModes {@([pscustomobject]@{Key='display-60';Label='60 Hz';RefreshHz=60;IsCurrent=$false},[pscustomobject]@{Key='display-144';Label='144 Hz';RefreshHz=144;IsCurrent=$true})}
function Set-GamingWindowsSettings {param($GameMode,$HardwareScheduling,$BackgroundCapture);$script:calls.Add('windows:'+ $GameMode+':'+$HardwareScheduling+':'+$BackgroundCapture);[pscustomobject]@{Success=$true;Message='Mock preferences applied'}}
function Restore-GamingWindowsSettings {$script:calls.Add('windows:restore');[pscustomobject]@{Success=$true;Message='Mock restored'}}
function Set-GamingDisplayMode {param($Key);$script:calls.Add('display:'+ $Key);[pscustomobject]@{Success=$true;RequiresConfirmation=$true;ConfirmationToken='mock-token';TimeoutSeconds=15;Message='Mock preview'}}
function Show-MacGamingDisplayConfirmation {param($UI,$Result);$script:calls.Add('display-confirm:'+ $Result.ConfirmationToken)}
function Revert-GamingDisplayMode {param($Token);$script:calls.Add('display-revert:'+ $Token);[pscustomobject]@{Success=$true;Message='Mock reverted'}}
function Get-GamingGpuPreference {param($ExecutablePath);[pscustomobject]@{Preference='HighPerformance'}}
function Set-GamingGpuPreference {param($ExecutablePath,$Preference);$script:calls.Add('gpu:'+ $ExecutablePath+':'+$Preference);[pscustomobject]@{Success=$true;Message='Mock GPU preference'}}
function Restore-GamingGpuPreference {param($ExecutablePath);$script:calls.Add('gpu:restore');[pscustomobject]@{Success=$true;Message='Mock GPU restore'}}
function Update-MacGamingSelectedGame {param($UI);Update-MacGamingGpuPreference $UI}
function Open-GamingSetting {param($Name);$script:calls.Add('external:'+ $Name)}
$script:checks=0
function Assert-Ui($Condition,[string]$Name){if(-not $Condition){throw $Name};$script:checks++}
function Click($Control){$Control.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
$ui=Show-MacGamingPanel -CreateOnly
Assert-Ui ($script:created -eq 0) 'Constructing WPF must not load the native component'
Assert-Ui (-not $ui.Window.AllowsTransparency) 'Native host requires non-layered WPF window'
foreach($name in @('NavWindowsTools','WindowsToolsSection','WindowsToolsArea','WindowsSettingsApply','WindowsDisplayPreview','WindowsGpuPreference')){Assert-Ui ($ui.Controls.ContainsKey($name)) ('Required control '+$name)}
$minimum=$null;$layouts=0
foreach($theme in Get-GamingThemes){
    Apply-MacGamingTheme $ui $theme.Id
    foreach($page in @('Overview','Games','Profiles','Performance','Network','Tools','WindowsTools','Settings')){
        Set-MacGamingPage $ui $page
        $ui.Window.Content.Measure((New-Object Windows.Size(1050,790)))
        $ui.Window.Content.Arrange((New-Object Windows.Rect(0,0,1050,790)))
        $ui.Window.Content.UpdateLayout()
        Assert-Ui ($ui.Controls[('Page'+$page)].ActualWidth -gt 600) ('Layout '+$theme.Id+' '+$page)
        if($page -eq 'WindowsTools'){$minimum=[pscustomobject]@{Width=$ui.Controls.WindowsToolsArea.ActualWidth;Height=$ui.Controls.WindowsToolsArea.ActualHeight}}
        $layouts++
    }
}
Assert-Ui ($script:created -eq 0) 'Page layout must not create native component'
Click $ui.Controls.NavWindowsTools
Assert-Ui ($script:created -eq 1) 'Explicit Windows tools navigation loads once'
Assert-Ui ($ui.EmbeddedOptimizerHost -is [Windows.Forms.Integration.WindowsFormsHost]) 'Real WindowsFormsHost embeds mock component'
Assert-Ui ($ui.EmbeddedOptimizerHost.Child -eq $ui.EmbeddedOptimizerView) 'Native child is in the same app host'
Assert-Ui ($ui.Controls.WindowsToolsPlaceholder.Visibility -eq 'Collapsed') 'Loaded component replaces placeholder'
$ui.OptimizerCatalog=@([pscustomobject]@{Id='fixture-feature';Category='Fixture';Name='Fixture feature';SectionId='pingerTab';Availability='Available';Description='Fixture feature description'},[pscustomobject]@{Id='retired-feature';Category='Fixture';Name='Retired feature';Availability='Retired';Description='This entry has no upstream implementation.'})
$ui.Controls.OptimizerFeatures.ItemsSource=$ui.OptimizerCatalog;$ui.Controls.OptimizerFeatures.SelectedIndex=0
Click $ui.Controls.OptimizerOpenFeature
Assert-Ui ($ui.Controls.WindowsToolsSection.SelectedItem.Id -eq 'pingerTab') 'Catalog SectionId controls feature navigation'
$ui.Controls.OptimizerFeatures.SelectedIndex=1
Assert-Ui (-not $ui.Controls.OptimizerOpenFeature.IsEnabled) 'Retired upstream entries cannot be applied'
Show-MacGamingWindowsTools $ui 'retired-feature'
Assert-Ui ($ui.Controls.StatusText.Text -eq 'This entry has no upstream implementation.') 'Retired entry explains unavailable implementation'
foreach($theme in Get-GamingThemes){Apply-MacGamingTheme $ui $theme.Id;Assert-Ui ($script:calls.Contains('theme:'+ $theme.Id)) ('Embedded theme '+$theme.Id)}
Show-MacGamingWindowsTools $ui 'Pinger'
Assert-Ui ($script:created -eq 1) 'Repeated navigation reuses component'
Assert-Ui ($ui.Controls.WindowsToolsSection.SelectedItem.Id -eq 'pingerTab') 'Catalog category routes to actual component section'
Click $ui.Controls.WindowsToolsAdministrator
Assert-Ui ($script:calls.Contains('elevate:WindowsTools')) 'Elevation is an explicit action'
Assert-Ui ($ui.Controls.StatusText.Text -like '*declined*') 'Declined elevation surfaces result'
Click $ui.Controls.WindowsToolsUnload
Assert-Ui ($script:disposed -eq 1 -and -not $ui.EmbeddedOptimizerView) 'Unload disposes native component'
Remove-MacGamingEmbeddedOptimizer $ui
Assert-Ui ($script:disposed -eq 1) 'Repeated cleanup is idempotent'
$script:failTheme=$true
Click $ui.Controls.WindowsToolsLoad
Assert-Ui ($script:created -eq 2 -and $script:disposed -eq 2) 'Partial initialization failure disposes native component'
Assert-Ui ($ui.Controls.WindowsToolsStatus.Text -eq 'Mock theme failure') 'Initialization failure remains readable'
$script:failTheme=$false
Click $ui.Controls.NavPerformance
Assert-Ui ($ui.Controls.WindowsGameMode.SelectedItem -eq 'Enabled') 'Windows preferences populate through getter'
Assert-Ui ($ui.Controls.WindowsDisplayMode.SelectedItem.Key -eq 'display-144') 'Current display mode selected'
$ui.Controls.WindowsGameMode.SelectedItem='Disabled';Click $ui.Controls.WindowsSettingsApply
Assert-Ui ($script:calls.Contains('windows:Disabled:Default:Disabled')) 'Explicit Apply sends selected preferences'
Click $ui.Controls.WindowsSettingsRestore
Assert-Ui ($script:calls.Contains('windows:restore')) 'Windows preference restore is wired'
$ui.Controls.WindowsDisplayMode.SelectedIndex=0;Click $ui.Controls.WindowsDisplayPreview
Assert-Ui ($script:calls.Contains('display:display-60') -and $script:calls.Contains('display-confirm:mock-token')) 'Display preview routes to confirmation'
& $script:realDisplayConfirmation $ui ([pscustomobject]@{DeadlineUtc=[datetime]::UtcNow.AddSeconds(-1).ToString('o');TimeoutSeconds=15;ConfirmationToken='expired-token'})
Assert-Ui ($script:calls.Contains('display-revert:expired-token')) 'Expired worker deadline reverts without opening confirmation'
$game=[pscustomobject]@{Id='mock-game';Name='Mock game';ExecutablePath='C:\Mock\Game.exe';NeedsExecutableSelection=$false}
$ui.Controls.GameList.ItemsSource=@($game);$ui.Controls.GameList.SelectedItem=$game
Assert-Ui ($ui.Controls.WindowsGpuPreference.SelectedItem -eq 'HighPerformance') 'Game GPU preference loads'
$ui.Controls.WindowsGpuPreference.SelectedItem='PowerSaving';Click $ui.Controls.WindowsGpuApply
Assert-Ui ($script:calls.Contains('gpu:C:\Mock\Game.exe:PowerSaving')) 'GPU preference is scoped to selected EXE'
Click $ui.Controls.WindowsGpuRestore
Assert-Ui ($script:calls.Contains('gpu:restore')) 'Per-game GPU restore is wired'
foreach($name in @('OpenGameMode','OpenGraphics','OpenCaptures','OpenDisplay')){Click $ui.Controls[$name];Assert-Ui ($ui.CurrentPage -eq 'Performance') ($name+' stays inside app')}
Click $ui.Controls.OpenNetwork
Assert-Ui ($ui.CurrentPage -eq 'WindowsTools') 'Network settings route to integrated DNS tools'
Click $ui.Controls.OpenNvidia
Assert-Ui ((@($script:calls|Where-Object{$_ -like 'external:*'}) -join ',') -eq 'external:Nvidia') 'Only NVIDIA opens external settings'
Remove-MacGamingEmbeddedOptimizer $ui
$ui.Window.Close()
[pscustomobject]@{Success=$true;Checks=$script:checks;Layouts=$layouts;Themes=@(Get-GamingThemes).Count;ToolArea=$minimum;NativeCreates=$script:created;NativeDisposes=$script:disposed;Message='Pure UI layout and mocked event tests. No real system changes, elevation, probes, or native Optimizer initialization.'}|ConvertTo-Json -Depth 3
