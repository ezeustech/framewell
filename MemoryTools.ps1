# Memory tools are opt-in. Loading this file starts no timers, monitor, or elevated helper.
if(-not(Get-Command Initialize-GamingSystemNative -ErrorAction SilentlyContinue)){. (Join-Path $PSScriptRoot 'GameProcessTuning.ps1')}
$script:GamingMemoryRoot=$PSScriptRoot
$script:GamingMemoryWorker=$null
$script:GamingMemoryCompletedPurges=0L
function Get-GamingMemorySnapshot {
    Initialize-GamingSystemNative
    [GamingSystemNative]::ReadMemory()
}
function Get-GamingMemoryPreferences {
    $saved=Read-GamingSystemJson 'memory-preferences'
    if($saved -and -not(Test-GamingMemoryPreferencesData $saved)){throw 'Invalid or unsupported memory settings. The file was preserved.'}
    $result=[ordered]@{Version=1;StandbyThresholdMB=1024;AvailableThresholdMB=1024;IntervalSeconds=30;TimerMilliseconds=1}
    if($saved){foreach($key in @('StandbyThresholdMB','AvailableThresholdMB','IntervalSeconds','TimerMilliseconds')){if($null -ne $saved.$key){$result[$key]=if($key -eq 'TimerMilliseconds'){[double]$saved.$key}else{[int]$saved.$key}}}}
    [pscustomobject]$result
}
function Test-GamingMemoryPreferencesData {
    param($Value)
    if(-not $Value -or ($Value.Version -isnot [int] -and $Value.Version -isnot [long]) -or $Value.Version -ne 1 -or @($Value.PSObject.Properties.Name | Where-Object {$_ -notin @('Version','StandbyThresholdMB','AvailableThresholdMB','IntervalSeconds','TimerMilliseconds')}).Count){return $false}
    foreach($key in @('StandbyThresholdMB','AvailableThresholdMB','IntervalSeconds')){if($Value.$key -isnot [int] -and $Value.$key -isnot [long]){return $false}}
    if($Value.TimerMilliseconds -isnot [int] -and $Value.TimerMilliseconds -isnot [long] -and $Value.TimerMilliseconds -isnot [double] -and $Value.TimerMilliseconds -isnot [decimal]){return $false}
    return ($Value.StandbyThresholdMB -ge 128 -and $Value.StandbyThresholdMB -le 1048576 -and $Value.AvailableThresholdMB -ge 128 -and $Value.AvailableThresholdMB -le 1048576 -and $Value.IntervalSeconds -ge 15 -and $Value.IntervalSeconds -le 600 -and $Value.TimerMilliseconds -ge 0.5 -and $Value.TimerMilliseconds -le 16 -and [math]::Abs($Value.TimerMilliseconds*2-[math]::Round($Value.TimerMilliseconds*2)) -lt 0.000001)
}
function Test-GamingMemoryAdministrator {Initialize-GamingSystemNative;[GamingSystemNative]::IsAdministrator()}
function Invoke-GamingMemoryNativePurge {Initialize-GamingSystemNative;[GamingSystemNative]::PurgeStandby()}
function Start-GamingMemoryNativeMonitor {param([int]$StandbyThresholdMB,[int]$AvailableThresholdMB,[int]$IntervalSeconds);Initialize-GamingSystemNative;[GamingSystemNative]::StartMonitor($StandbyThresholdMB,$AvailableThresholdMB,$IntervalSeconds)}
function Stop-GamingMemoryNativeMonitor {if('GamingSystemNative' -as [type]){[GamingSystemNative]::StopMonitor()}}
function Set-GamingMemoryNativeTimer {param([bool]$Enabled,[double]$Milliseconds);Initialize-GamingSystemNative;[GamingSystemNative]::SetTimer($Enabled,$Milliseconds)}
function Stop-GamingMemoryNativeTools {if('GamingSystemNative' -as [type]){[GamingSystemNative]::StopAll()}}
function Save-GamingMemoryPreferences {
    param([ValidateRange(128,1048576)][int]$StandbyThresholdMB=1024,[ValidateRange(128,1048576)][int]$AvailableThresholdMB=1024,[ValidateRange(15,600)][int]$IntervalSeconds=30,[ValidateRange(0.5,16)][ValidateScript({[math]::Abs($_*2-[math]::Round($_*2)) -lt 0.000001})][double]$TimerMilliseconds=1)
    $value=[pscustomobject]@{Version=1;StandbyThresholdMB=$StandbyThresholdMB;AvailableThresholdMB=$AvailableThresholdMB;IntervalSeconds=$IntervalSeconds;TimerMilliseconds=$TimerMilliseconds}
    Write-GamingSystemJson 'memory-preferences' $value
    [pscustomobject]@{Success=$true;Message='Memory thresholds saved. Monitoring and timer requests remain opt-in.';Preferences=$value}
}
function Get-GamingMemoryRuntime {
    Initialize-GamingSystemNative
    $native=[GamingSystemNative]::Runtime()
    $running=[bool]$native.MonitorRunning;$count=[long]$native.PurgeCount+$script:GamingMemoryCompletedPurges;$message=$native.LastMessage
    if($script:GamingMemoryWorker){
        $worker=$script:GamingMemoryWorker
        try {
            $process=Get-Process -Id $worker.ProcessId -ErrorAction Stop
            if($process.StartTime.ToUniversalTime().Ticks -ne $worker.StartTimeTicks){throw 'Worker process ended.'}
            if(Test-Path -LiteralPath $worker.StatusPath -PathType Leaf){
                $status=Get-Content -LiteralPath $worker.StatusPath -Raw | ConvertFrom-Json
                if($status.Token -eq $worker.Token){$running=([bool]$status.MonitorRunning -and -not(Test-Path -LiteralPath $worker.StopPath));$count+=[long]$status.PurgeCount;$message=[string]$status.Message}
            }else{$running=($worker.Operation -eq 'Monitor');$message='Waiting for memory monitor to initialize.'}
        } catch {
            try {if(Test-Path -LiteralPath $worker.StatusPath -PathType Leaf){$ended=Get-Content -LiteralPath $worker.StatusPath -Raw|ConvertFrom-Json;if($ended.Token -eq $worker.Token){$script:GamingMemoryCompletedPurges+=[long]$ended.PurgeCount;$count=[long]$native.PurgeCount+$script:GamingMemoryCompletedPurges;$message=[string]$ended.Message}}}catch{ }
            $script:GamingMemoryWorker=$null;$running=$false
        }
    }
    [pscustomobject]@{MonitorRunning=$running;TimerEnabled=[bool]$native.TimerEnabled;TimerMilliseconds=[double]$native.TimerMilliseconds;RequestedTimerMilliseconds=[double]$native.RequestedTimerMilliseconds;ObservedTimerMilliseconds=[double]$native.ObservedTimerMilliseconds;NativeTimer=[bool]$native.NativeTimer;PurgeCount=$count;LastMessage=$message;RequiresOpenApp=($running -or $native.TimerEnabled)}
}
function Start-GamingMemoryWorker {
    param([ValidateSet('Purge','Monitor')][string]$Operation,[int]$StandbyThresholdMB=1024,[int]$AvailableThresholdMB=1024,[int]$IntervalSeconds=30)
    $folder=Get-GamingSystemStateDirectory
    $token=[guid]::NewGuid().ToString('N');$stem='memory-worker-'+$token
    $requestPath=Join-Path $folder ($stem+'.request.json');$statusPath=Join-Path $folder ($stem+'.status.json');$stopPath=Join-Path $folder ($stem+'.stop')
    $parent=Get-Process -Id $PID
    $request=[pscustomobject]@{Version=1;Token=$token;Operation=$Operation;ParentProcessId=$PID;ParentStartTicks=([string]$parent.StartTime.ToUniversalTime().Ticks);UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;StandbyThresholdMB=$StandbyThresholdMB;AvailableThresholdMB=$AvailableThresholdMB;IntervalSeconds=$IntervalSeconds}
    $request | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $requestPath -Encoding UTF8
    $workerPath=Join-Path $script:GamingMemoryRoot 'MemoryWorker.ps1'
    $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        # Only a fixed shipped script plus a validated request filename cross the elevation boundary.
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$workerPath+'" -RequestPath "'+$requestPath+'"'
        $process=Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        $worker=[pscustomobject]@{ProcessId=$process.Id;StartTimeTicks=$process.StartTime.ToUniversalTime().Ticks;Token=$token;Operation=$Operation;RequestPath=$requestPath;StatusPath=$statusPath;StopPath=$stopPath}
        if($Operation -eq 'Monitor'){$script:GamingMemoryWorker=$worker}
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while($clock.Elapsed.TotalSeconds -lt 8){
            if(Test-Path -LiteralPath $statusPath -PathType Leaf){
                try {$status=Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json;if($status.Token -eq $token){if($Operation -eq 'Purge' -and $status.Success){$script:GamingMemoryCompletedPurges+=[long]$status.PurgeCount};return [pscustomobject]@{Success=[bool]$status.Success;Message=[string]$status.Message;RequiresElevation=$false;Worker=$worker}}}catch{ }
            }
            if($process.HasExited){break};Start-Sleep -Milliseconds 100
        }
        if($Operation -eq 'Monitor' -and -not $process.HasExited){return [pscustomobject]@{Success=$true;Message='Memory monitor is initializing. Keep Gaming Mode open while monitoring.';RequiresElevation=$false;Worker=$worker}}
        [pscustomobject]@{Success=$false;Message='The memory helper did not report completion. No success is assumed.';RequiresElevation=$false}
    }catch{[pscustomobject]@{Success=$false;Message=('Memory action was not started: '+$_.Exception.Message);RequiresElevation=$true}}
}
function Invoke-GamingStandbyPurge {
    Initialize-GamingSystemNative
    if(-not(Test-GamingMemoryAdministrator)){return Start-GamingMemoryWorker -Operation Purge}
    try {Invoke-GamingMemoryNativePurge;[pscustomobject]@{Success=$true;Message='Standby cache cleared. Windows can normally reclaim this memory itself; cached reads may be slower temporarily.';RequiresElevation=$false}}
    catch {[pscustomobject]@{Success=$false;Message=$_.Exception.Message;RequiresElevation=$false}}
}
function Start-GamingMemoryMonitor {
    param([ValidateRange(128,1048576)][int]$StandbyThresholdMB=1024,[ValidateRange(128,1048576)][int]$AvailableThresholdMB=1024,[ValidateRange(15,600)][int]$IntervalSeconds=30)
    Initialize-GamingSystemNative
    $state=Get-GamingMemoryRuntime
    if($state.MonitorRunning){return [pscustomobject]@{Success=$true;Message='Memory monitor is already running. Stop it before applying different thresholds.'}}
    if(-not(Test-GamingMemoryAdministrator)){return Start-GamingMemoryWorker -Operation Monitor -StandbyThresholdMB $StandbyThresholdMB -AvailableThresholdMB $AvailableThresholdMB -IntervalSeconds $IntervalSeconds}
    try {Start-GamingMemoryNativeMonitor $StandbyThresholdMB $AvailableThresholdMB $IntervalSeconds;[pscustomobject]@{Success=$true;Message='Monitor started. Standby clears only when BOTH thresholds are met. Keep this app open.'}}
    catch {[pscustomobject]@{Success=$false;Message=$_.Exception.Message}}
}
function Stop-GamingMemoryMonitor {
    Initialize-GamingSystemNative
    Stop-GamingMemoryNativeMonitor
    if($script:GamingMemoryWorker){Set-Content -LiteralPath $script:GamingMemoryWorker.StopPath -Value 'stop' -Encoding ASCII}
    [pscustomobject]@{Success=$true;Message='Memory monitor stop requested. Its helper exits within two seconds.'}
}
function Set-GamingTimerResolution {
    param([Parameter(Mandatory=$true)][bool]$Enabled,[ValidateRange(0.5,16)][ValidateScript({[math]::Abs($_*2-[math]::Round($_*2)) -lt 0.000001})][double]$Milliseconds=1)
    Initialize-GamingSystemNative
    try {
        Set-GamingMemoryNativeTimer $Enabled $Milliseconds
        $runtime=[GamingSystemNative]::Runtime()
        $message=if(-not $Enabled){'This app''s timer request was released.'}elseif(($Milliseconds % 1) -ne 0){'Experimental native timer request: '+$Milliseconds+' ms requested, '+$runtime.TimerMilliseconds+' ms within Windows bounds; '+$runtime.ObservedTimerMilliseconds+' ms observed. Readback does not prove a game uses this resolution; power use may increase.'}else{'Documented timer request enabled for this app. Current Windows does not guarantee it changes another game''s timing; power use may increase.'}
        [pscustomobject]@{Success=$true;Message=$message;RequestedMilliseconds=$Milliseconds;EffectiveMilliseconds=$runtime.TimerMilliseconds;ObservedMilliseconds=$runtime.ObservedTimerMilliseconds;ExperimentalNative=(($Milliseconds % 1) -ne 0)}
    }
    catch {[pscustomobject]@{Success=$false;Message=$_.Exception.Message}}
}
function Stop-GamingMemoryTools {
    try {Stop-GamingMemoryNativeTools}
    finally {if($script:GamingMemoryWorker){try{Set-Content -LiteralPath $script:GamingMemoryWorker.StopPath -Value 'stop' -Encoding ASCII}catch{ }}}
}
