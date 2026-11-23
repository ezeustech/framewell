param([string]$AppRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run in Windows PowerShell with -STA.'}
. (Join-Path $AppRoot 'GamingMode.ps1') -LibraryOnly
Initialize-GamingEmbeddedOptimizer
Add-Type -AssemblyName WindowsFormsIntegration
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class EmbeddedHostTestNative {
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
}
'@
$fixture=Join-Path $PSScriptRoot ('embedded-host-fixture-'+[guid]::NewGuid().ToString('N'))
$checks=New-Object 'System.Collections.Generic.List[string]'
$coverage=New-Object 'System.Collections.Generic.List[object]'
$binding=[Reflection.BindingFlags]'Instance,NonPublic,Public'
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$checks.Add($Name)}
function Get-Descendants($Control){foreach($child in $Control.Controls){$child;Get-Descendants $child}}
function Pump-Layout($UI){$UI.Window.UpdateLayout();[Windows.Forms.Application]::DoEvents();$UI.Window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::Background)}
# Only the factory is redirected: real bridge, real controls and real WPF host, with a private fixture and action gate closed.
function New-GamingEmbeddedOptimizerView {
    param([IntPtr]$OwnerWindow=[IntPtr]::Zero)
    [Optimizer.EmbeddedHost]::SetOwnerWindow($OwnerWindow)
    return [Optimizer.EmbeddedHost]::CreateView($fixture,$false)
}
$baseline=@(Get-Process -ErrorAction SilentlyContinue|Where-Object ProcessName -Like '*Optimizer*'|ForEach-Object Id)
$ui=$null;$view=$null
try{
    $ui=Show-MacGamingPanel -CreateOnly
    $ui.Actions.Refresh={}
    $ui.Window.WindowStartupLocation='Manual';$ui.Window.Left=-30000;$ui.Window.Top=-30000;$ui.Window.ShowActivated=$false;$ui.Window.ShowInTaskbar=$false
    $ui.Window.Show();Pump-Layout $ui
    Assert (-not $ui.Window.AllowsTransparency) 'Main window supports native HWND content'
    Show-MacGamingWindowsTools $ui
    Pump-Layout $ui
    $view=$ui.EmbeddedOptimizerView
    Assert ($null -ne $view) ('Real embedded view loads: '+$ui.Controls.WindowsToolsStatus.Text)
    Assert ($ui.EmbeddedOptimizerHost -is [Windows.Forms.Integration.WindowsFormsHost]) 'Actual WindowsFormsHost is mounted inside the WPF page'
    Assert ([object]::ReferenceEquals($ui.EmbeddedOptimizerHost.Child,$view)) 'Hosted child is the actual Optimizer form'
    Assert ($view.TopLevel -eq $false -and $view.FormBorderStyle -eq 'None' -and -not $view.ShowInTaskbar) 'Embedded form has no independent app window'
    [uint32]$ownerProcess=0;[void][EmbeddedHostTestNative]::GetWindowThreadProcessId($view.Handle,[ref]$ownerProcess)
    Assert ($ownerProcess -eq $PID) 'Native tool HWND belongs to this exact host process'
    Assert ($ui.EmbeddedOptimizerHost.ActualWidth -gt 500 -and $ui.EmbeddedOptimizerHost.ActualHeight -gt 250) 'Native host receives useful layout dimensions'
    $tabs=$view.GetType().GetField('tabCollection',$binding).GetValue($view)
    $expected=@('universalTab','windows10Tab','advancedTab','advancedExtrasTab','modernAppsTab','startupTab','appsTab','cleanerTab','pingerTab','hostsEditorTab','registryFixerTab','indiciumTab','fileHandlesTab','diskActivityTab','integratorTab','optionsTab')
    $sections=@([Optimizer.EmbeddedHost]::GetSections($view))
    Assert ($sections.Count -eq 16 -and @($expected|Where-Object {$_ -notin $sections.Id}).Count -eq 0) 'All fifteen upstream sections and added CLI controls are actual tab pages'
    foreach($id in $expected){
        $page=@($tabs.TabPages|Where-Object Name -eq $id)[0]
        # Expensive read-only hardware/disk scans are already covered separately; select those content containers directly.
        if($id -in @('indiciumTab','cleanerTab')){$tabs.SelectedTab=$page}else{[Optimizer.EmbeddedHost]::SelectSection($view,$id)}
        Pump-Layout $ui
        $all=@(Get-Descendants $page)
        $inputs=@($all|Where-Object {$_ -is [Windows.Forms.ButtonBase] -or $_ -is [Windows.Forms.TextBoxBase] -or $_ -is [Windows.Forms.ListControl] -or $_ -is [Windows.Forms.TreeView] -or $_ -is [Windows.Forms.ListView] -or $_ -is [Windows.Forms.NumericUpDown] -or $_.GetType().Name -match 'Toggle|FluentButton|MoonCheck|ActivityList'})
        $visible=@($inputs|Where-Object {$_.Visible -and $_.Width -gt 0 -and $_.Height -gt 0})
        Assert ($page.Visible -and $all.Count -ge 3 -and $visible.Count -ge 1) ($id+' shows real interactive controls, not a catalog placeholder')
        $coverage.Add([pscustomobject]@{Section=$id;Title=$page.Text;TotalControls=$all.Count;VisibleInputs=$visible.Count;Width=$page.Width;Height=$page.Height})
    }
    $extra=@($tabs.TabPages|Where-Object Name -eq 'advancedExtrasTab')[0]
    $advancedChoice=@(Get-Descendants $extra|Where-Object Name -eq 'EmbeddedAdvancedAction')[0]
    Assert ($advancedChoice.Items.Count -eq 5) 'CLI-only core, service and process choices have an actual native selector'
    $disk=$view.GetType().GetField('_daMonitor',$binding).GetValue($view)
    Assert (-not $disk.GetType().GetProperty('Running',$binding).GetValue($disk,$null)) 'Opening and navigating tools does not start filesystem monitoring'
    Assert (@(Get-Process -ErrorAction SilentlyContinue|Where-Object {$_.ProcessName -like '*Optimizer*' -and $_.Id -notin $baseline}).Count -eq 0) 'No standalone Optimizer process appears during view initialization or navigation'
    $settings=Get-Content -LiteralPath (Join-Path $fixture 'Optimizer.json') -Raw|ConvertFrom-Json
    Assert (-not $settings.AutoStart -and -not $settings.EnableTray -and -not $settings.UpdateOnLaunch) 'Private embedded preferences disable standalone startup, tray and updater'
    Remove-MacGamingEmbeddedOptimizer $ui
    Assert ($view.IsDisposed -and $null -eq $ui.EmbeddedOptimizerView -and $null -eq $ui.EmbeddedOptimizerHost) 'Unload disposes native controls and detaches WPF hosting resources'
    Show-MacGamingWindowsTools $ui 'advancedExtrasTab';Pump-Layout $ui
    Assert ($null -ne $ui.EmbeddedOptimizerView -and -not [object]::ReferenceEquals($view,$ui.EmbeddedOptimizerView)) 'Tool workspace can be reopened without restarting the app'
    $view=$ui.EmbeddedOptimizerView
    $ui.Window.Close();$ui=$null
    Assert ($view.IsDisposed) 'Closing the real WPF window disposes the embedded workspace'
    [pscustomobject]@{Passed=$checks.Count;Checks=@($checks.ToArray());Coverage=@($coverage.ToArray());HostPID=$PID;LiveWindowsWrites=$false;LiveElevation=$false;ActionsInvoked=$false;Scope='Actual offscreen WPF/WinForms rendering, native process ownership, navigation, fixture state and lifecycle. System-changing controls were disabled; no user action was clicked.';VerifiedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'v31-embedded-host-results.json') -Encoding UTF8
    Write-Output ('PASS: '+$checks.Count+' real embedded host checks; all 16 sections contain visible controls.')
}finally{if($ui){$ui.Window.Close()};if($view -and -not $view.IsDisposed){[Optimizer.EmbeddedHost]::DisposeView($view)}}
