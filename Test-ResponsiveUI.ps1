param()
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework
. (Join-Path $PSScriptRoot 'ResponsiveUI.ps1')
$script:GamingRoot=$PSScriptRoot
$ui=@{Controls=@{StatusText=[pscustomobject]@{Text=''}};Result=$null}
Initialize-FramewellReads $ui
$ticks=@{Count=0};$pulse=New-Object Windows.Threading.DispatcherTimer
$pulse.Interval=[timespan]::FromMilliseconds(20)
$pulse.Add_Tick({$ticks.Count++}.GetNewClosure());$pulse.Start()
$watch=[Diagnostics.Stopwatch]::StartNew()
Start-FramewellRead $ui 'test' 'Start-Sleep -Milliseconds 800; "finished"' {param($data)$ui.Result=$data}.GetNewClosure()
$dispatchMs=$watch.Elapsed.TotalMilliseconds
Start-FramewellRead $ui 'test' 'throw "Duplicate job was not suppressed"' {param($data)}
if($ui.ReadJobs.Count -ne 1){throw 'Duplicate read was queued'}
while($ui.ReadJobs.Count -and $watch.Elapsed.TotalSeconds -lt 15){
 $frame=New-Object Windows.Threading.DispatcherFrame
 $exit=New-Object Windows.Threading.DispatcherTimer;$exit.Interval=[timespan]::FromMilliseconds(30)
 $exit.Add_Tick({$frame.Continue=$false;$exit.Stop()}.GetNewClosure());$exit.Start()
 [Windows.Threading.Dispatcher]::PushFrame($frame)
}
$pulse.Stop()
if($ui.Result -ne 'finished'){throw ('Background completion failed: '+$ui.Controls.StatusText.Text)}
if($ticks.Count -lt 10){throw 'Dispatcher did not remain responsive during background work'}
if($ui.ReadTimer.IsEnabled){throw 'Polling timer remained active while idle'}
$pool=$ui.ReadPool
Start-FramewellRead $ui 'cancel' 'Start-Sleep -Seconds 30' {param($data)}
$stop=[Diagnostics.Stopwatch]::StartNew();Stop-FramewellReads $ui;$stop.Stop()
if($ui.ReadJobs.Count -or $ui.ReadPool -or $pool.RunspacePoolStateInfo.State -ne 'Closed'){throw 'Background runspace was not shut down'}
if($stop.Elapsed.TotalSeconds -gt 5){throw 'Background cancellation took too long'}
[pscustomobject]@{Passed=6;DispatchMilliseconds=[math]::Round($dispatchMs);DispatcherTicks=$ticks.Count;ShutdownMilliseconds=$stop.ElapsedMilliseconds;IdlePolling=$false;SystemSettingsChanged=$false}|ConvertTo-Json
