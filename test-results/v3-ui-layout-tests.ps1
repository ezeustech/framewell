$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'MacInterface.ps1')
function Get-GamingPreferences { [pscustomobject]@{Theme='Dark';CloseAfterActivation=$true} }
$ui=Show-MacGamingPanel -CreateOnly
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Ui($Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name)}
Assert-Ui ($ui.Controls.Count -ge 160) 'v3 controls were constructed'
foreach($name in @('QuickMemoryPurge','QuickNetwork','CpuPriority','CpuCoreSelection','NetworkHost','NetworkGame','NetworkServer','MemoryMonitorToggle','MemoryTimerToggle','SettingsProfileScope','OptimizerFeatures','ThemeSwatches')){Assert-Ui ($ui.Controls.ContainsKey($name)) ('control '+$name)}
Assert-Ui ($ui.Controls.AppearanceTheme.Items.Count -eq @(Get-GamingThemes).Count) 'every theme is selectable'
$layoutCount=0
foreach($theme in Get-GamingThemes){
    Apply-MacGamingTheme $ui $theme.Id
    foreach($page in @('Overview','Games','Profiles','Performance','Network','Tools','Settings')){
        Set-MacGamingPage $ui $page
        $ui.Window.Content.Measure((New-Object Windows.Size(1050,790)))
        $ui.Window.Content.Arrange((New-Object Windows.Rect(0,0,1050,790)))
        $ui.Window.Content.UpdateLayout()
        Assert-Ui ($ui.Controls[('Page'+$page)].Visibility -eq 'Visible') ($theme.Id+' '+$page+' visible')
        Assert-Ui ($ui.Controls[('Page'+$page)].ActualWidth -gt 600) ($theme.Id+' '+$page+' has usable width')
        $layoutCount++
    }
}
Apply-MacGamingTheme $ui 'OLED'
Assert-Ui ($ui.Window.Resources.MacBrushFFFFFF.Color.ToString() -eq '#FF000000') 'OLED cards use pure black'
Assert-Ui ((@(ConvertFrom-MacCpuSelection '0-3, 5, 7-8') -join ',') -eq '0,1,2,3,5,7,8') 'CPU ranges parse correctly'
Assert-Ui (@(ConvertFrom-MacCpuSelection '').Count -eq 0) 'empty CPU selection means all'
Assert-Ui ((ConvertFrom-MacTimerValue '0.5') -eq 0.5) 'fractional timer request remains fractional'
Assert-Ui ((ConvertFrom-MacTimerValue '16') -eq 16) 'maximum supported UI timer request'
foreach($value in @('0','0.75','17','NaN','Infinity','1;exit')){$rejected=$false;try{$null=ConvertFrom-MacTimerValue $value}catch{$rejected=$true};Assert-Ui $rejected ('timer request rejected: '+$value)}
foreach($value in @('3-1','1;x','-1','0-5000')){$rejected=$false;try{$null=ConvertFrom-MacCpuSelection $value}catch{$rejected=$true};Assert-Ui $rejected ('CPU malformed selection rejected: '+$value)}
$ui.Window.Close()
[pscustomobject]@{Success=$true;Checks=$checks.Count;Layouts=$layoutCount;Themes=@(Get-GamingThemes).Count;Message='Constructor and layout checks only; no live settings or apps changed.'} | ConvertTo-Json
