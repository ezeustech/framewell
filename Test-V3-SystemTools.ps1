$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'GameProcessTuning.ps1')
. (Join-Path $PSScriptRoot 'MemoryTools.ps1')
Initialize-GamingSystemNative
$originalRoot=$script:GamingSystemRoot
$testRoot=Join-Path $PSScriptRoot ('test-results\system-tools-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force|Out-Null
$script:GamingSystemRoot=$testRoot
$script:checks=New-Object 'System.Collections.Generic.List[string]'
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$script:checks.Add($Name)}
function Expect-Failure([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Name}
function Get-GameLibrary {[pscustomobject]@{Id='test-game';ExecutablePath='D:\Games\Fixture\Fixture.exe'}}
function Get-GamingCpuTopology {[pscustomobject]@{LogicalProcessorCount=8;ProcessorGroups=$script:fakeGroups;SupportsAffinity=($script:fakeGroups -eq 1);Message='Multi-group affinity is unavailable.'}}
$script:fakeGroups=1
$script:fakeProcess=[pscustomobject]@{ProcessId=424242;ExecutablePath='D:\Games\Fixture\Fixture.exe';StartTimeTicks=638000000000000000L;Priority='Normal';Affinity=[uint64]255;SystemAffinity=[uint64]255}
$script:writes=0
function Read-GamingNativeProcess {param([int]$ProcessId);if($ProcessId -ne 424242){throw 'Access denied'};[pscustomobject]@{ProcessId=$script:fakeProcess.ProcessId;ExecutablePath=$script:fakeProcess.ExecutablePath;StartTimeTicks=$script:fakeProcess.StartTimeTicks;Priority=$script:fakeProcess.Priority;Affinity=$script:fakeProcess.Affinity;SystemAffinity=$script:fakeProcess.SystemAffinity}}
function Write-GamingNativeProcess {
    param([int]$ProcessId,[string]$ExecutablePath,[long]$StartTimeTicks,[string]$Priority,[uint64]$Affinity,[bool]$ChangeAffinity)
    if($ProcessId -ne 424242 -or $ExecutablePath -ne $script:fakeProcess.ExecutablePath -or $StartTimeTicks -ne $script:fakeProcess.StartTimeTicks){throw 'Identity mismatch'}
    $journal=Read-GamingSystemJson 'game-process-snapshots';if(-not @($journal.Entries|Where-Object ProcessId -eq $ProcessId).Count){throw 'Missing write-ahead restore snapshot'}
    $script:writes++
    if($Priority -ne 'Unchanged'){$script:fakeProcess.Priority=$Priority}
    if($ChangeAffinity){$script:fakeProcess.Affinity=$Affinity}
    Read-GamingNativeProcess $ProcessId
}
try {
    $default=Get-GamingProcessPreference test-game
    Assert ($default.Priority -eq 'Unchanged' -and -not $default.ApplyOnLaunch -and @($default.LogicalProcessors).Count -eq 0) 'CPU defaults make no automatic changes'
    Save-GamingProcessPreference test-game -Priority AboveNormal -LogicalProcessors @(0,2,4) -ApplyOnLaunch $true|Out-Null
    $saved=Get-GamingProcessPreference test-game
    Assert (($saved.LogicalProcessors -join ',') -eq '0,2,4' -and $saved.ApplyOnLaunch) 'Per-game CPU preferences persist'
    Expect-Failure {Save-GamingProcessPreference test-game -Priority Realtime} 'Realtime priority rejected'
    Expect-Failure {Save-GamingProcessPreference test-game -LogicalProcessors @(20)} 'Out-of-range CPU index rejected'
    $result=Invoke-GamingProcessTuning test-game -ProcessId 424242
    Assert ($result.Success -and $script:fakeProcess.Priority -eq 'AboveNormal' -and $script:fakeProcess.Affinity -eq 21) 'Selected game receives requested CPU settings after snapshot'
    $journal=Read-GamingSystemJson 'game-process-snapshots'
    Assert (@($journal.Entries).Count -eq 1 -and $journal.Entries[0].BeforePriority -eq 'Normal' -and $journal.Entries[0].BeforeAffinity -eq '255') 'Original process values journaled'
    Save-GamingProcessPreference test-game -Priority High -LogicalProcessors @(1,3)|Out-Null
    Invoke-GamingProcessTuning test-game -ProcessId 424242|Out-Null
    $journal=Read-GamingSystemJson 'game-process-snapshots'
    Assert ($journal.Entries[0].BeforePriority -eq 'Normal' -and $journal.Entries[0].BeforeAffinity -eq '255') 'Repeated apply retains first original values'
    $script:fakeProcess.Priority='BelowNormal'
    $result=Restore-GamingProcessTuning test-game
    Assert ($result.Success -and $script:fakeProcess.Priority -eq 'BelowNormal' -and $script:fakeProcess.Affinity -eq 255) 'Restore preserves later manual priority and restores untouched affinity'
    Invoke-GamingProcessTuning test-game -ProcessId 424242|Out-Null
    $newCycle=Read-GamingSystemJson 'game-process-snapshots'
    Assert ($newCycle.Entries[0].BeforePriority -eq 'BelowNormal') 'A new apply cycle captures the current baseline after restore'
    $writeCount=$script:writes;$script:fakeProcess.StartTimeTicks++
    $result=Restore-GamingProcessTuning test-game
    Assert ($result.Success -and $script:writes -eq $writeCount) 'PID reuse prevents restore writes'
    $script:fakeProcess.ExecutablePath='D:\Games\Different\Different.exe'
    $result=Invoke-GamingProcessTuning test-game -ProcessId 424242
    Assert (-not $result.Success -and $script:writes -eq $writeCount) 'Wrong executable prevents apply writes'
    $script:fakeProcess.ExecutablePath='D:\Games\Fixture\Fixture.exe';$script:fakeGroups=2
    Expect-Failure {Save-GamingProcessPreference test-game -LogicalProcessors @(0)} 'Multi-group core selection fails explicitly'
    Save-GamingProcessPreference test-game -Priority Normal -LogicalProcessors @()|Out-Null
    $beforeAffinity=$script:fakeProcess.Affinity;$result=Invoke-GamingProcessTuning test-game -ProcessId 424242
    Assert ($result.Success -and $script:fakeProcess.Affinity -eq $beforeAffinity) 'Priority remains available without changing multi-group affinity'
    $validCpu=Read-GamingSystemJson 'game-process-preferences'
    Assert (Test-GamingProcessPreferencesData $validCpu) 'Valid CPU profile import accepted'
    $validCpu.Games[0]|Add-Member NoteProperty Command 'malicious'
    Assert (-not(Test-GamingProcessPreferencesData $validCpu)) 'Unexpected CPU import fields rejected'
    $memory=Get-GamingMemoryPreferences
    Assert ($memory.IntervalSeconds -eq 30 -and $memory.StandbyThresholdMB -eq 1024) 'Memory defaults use conservative opt-in polling'
    Save-GamingMemoryPreferences -StandbyThresholdMB 2048 -AvailableThresholdMB 512 -IntervalSeconds 60 -TimerMilliseconds 1|Out-Null
    $memory=Get-GamingMemoryPreferences
    Assert ($memory.StandbyThresholdMB -eq 2048 -and (Test-GamingMemoryPreferencesData $memory)) 'Memory threshold preferences persist and validate'
    Expect-Failure {Save-GamingMemoryPreferences -IntervalSeconds 1} 'Busy memory polling rejected'
    Expect-Failure {Set-GamingTimerResolution -Enabled $true -Milliseconds 0} 'Invalid zero timer request rejected'
    Save-GamingMemoryPreferences -TimerMilliseconds 0.5|Out-Null
    $fractional=Get-GamingMemoryPreferences
    Assert ($fractional.TimerMilliseconds -eq 0.5 -and (Test-GamingMemoryPreferencesData $fractional)) 'Experimental 0.5 ms preference survives save and import validation'
    Expect-Failure {Save-GamingMemoryPreferences -TimerMilliseconds 0.7} 'Non-half-step timer preference rejected'
    $memory|Add-Member NoteProperty Operation 'command'
    Assert (-not(Test-GamingMemoryPreferencesData $memory)) 'Unexpected memory import fields rejected'
    $sample=New-Object GamingMemoryState;$sample.StandbyAvailable=$true;$sample.StandbyMB=2048;$sample.AvailableMB=256
    Assert ([GamingSystemNative]::ShouldPurge($sample,1024,512)) 'Threshold purge requires both limits and available counters'
    $sample.AvailableMB=1024
    Assert (-not [GamingSystemNative]::ShouldPurge($sample,1024,512)) 'Enough available RAM prevents purge'
    $sample.AvailableMB=256;$sample.StandbyMB=128
    Assert (-not [GamingSystemNative]::ShouldPurge($sample,1024,512)) 'Small standby cache prevents purge'
    $sample.StandbyMB=2048;$sample.StandbyAvailable=$false
    Assert (-not [GamingSystemNative]::ShouldPurge($sample,1024,512)) 'Unavailable counters prevent purge'
    $script:admin=$false;$script:workerCalls=@();$script:nativePurges=0;$script:timerCalls=@();$script:monitorCalls=0;$script:stopCalls=0
    function Test-GamingMemoryAdministrator {return $script:admin}
    function Start-GamingMemoryWorker {param($Operation,$StandbyThresholdMB,$AvailableThresholdMB,$IntervalSeconds);$script:workerCalls+=$Operation;[pscustomobject]@{Success=$true;Message='Mock worker'}}
    function Invoke-GamingMemoryNativePurge {$script:nativePurges++}
    function Set-GamingMemoryNativeTimer {param($Enabled,$Milliseconds);$script:timerCalls+=([string]$Enabled+':'+$Milliseconds)}
    function Start-GamingMemoryNativeMonitor {param($StandbyThresholdMB,$AvailableThresholdMB,$IntervalSeconds);$script:monitorCalls++}
    function Stop-GamingMemoryNativeMonitor {$script:stopCalls++}
    function Stop-GamingMemoryNativeTools {$script:stopCalls++}
    Invoke-GamingStandbyPurge|Out-Null;Start-GamingMemoryMonitor -IntervalSeconds 30|Out-Null
    Assert (($script:workerCalls -join ',') -eq 'Purge,Monitor' -and $script:nativePurges -eq 0) 'Unelevated memory actions use only the fixed worker'
    $script:admin=$true;Invoke-GamingStandbyPurge|Out-Null;Start-GamingMemoryMonitor|Out-Null
    Assert ($script:nativePurges -eq 1 -and $script:monitorCalls -eq 1) 'Elevated actions route to dedicated native operations'
    Set-GamingTimerResolution -Enabled $true -Milliseconds 1|Out-Null;Set-GamingTimerResolution -Enabled $false|Out-Null
    Assert (($script:timerCalls -join ',') -eq 'True:1,False:1') 'Timer start and release are paired at the public API'
    Set-GamingTimerResolution -Enabled $true -Milliseconds 0.5|Out-Null;Set-GamingTimerResolution -Enabled $false|Out-Null
    Assert ($script:timerCalls[2] -eq 'True:0.5' -and $script:timerCalls[3] -eq 'False:1') 'Experimental fractional request reaches the native adapter without integer truncation'
    Stop-GamingMemoryMonitor|Out-Null;Stop-GamingMemoryTools
    Assert ($script:stopCalls -eq 2) 'Explicit stop and app-close cleanup both release tools'
    $live=[GamingSystemNative]::ReadMemory();$nativeRuntime=[GamingSystemNative]::Runtime()
    Assert ($live.TotalMB -gt 0 -and $live.AvailableMB -ge 0 -and $live.AvailableMB -le $live.TotalMB) 'Read-only live memory counters are coherent'
    Assert (-not $nativeRuntime.MonitorRunning -and -not $nativeRuntime.TimerEnabled -and $nativeRuntime.PurgeCount -eq 0) 'Tests performed no live memory mutation or timer request'
    [pscustomobject]@{Passed=$script:checks.Count;Checks=@($script:checks.ToArray());LiveWrites=$false;LiveElevation=$false;VerifiedUtc=[datetime]::UtcNow.ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'test-results\v3-system-tools-results.json') -Encoding UTF8
    Write-Output ('PASS: '+$script:checks.Count+' system-tool checks; no live mutations or UAC.')
}finally{
    $script:GamingSystemRoot=$originalRoot
    # Leave the isolated fixture receipt available for inspection; publication excludes test-results.
}
