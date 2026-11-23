param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference='Stop'
$folder=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'state')).TrimEnd('\')
$full=[IO.Path]::GetFullPath($RequestPath)
if([IO.Path]::GetDirectoryName($full) -ine $folder -or [IO.Path]::GetFileName($full) -notmatch '^memory-worker-([a-f0-9]{32})\.request\.json$'){throw 'Invalid memory-worker request path.'}
$token=$Matches[1];$stem='memory-worker-'+$token
$statusPath=Join-Path $folder ($stem+'.status.json');$stopPath=Join-Path $folder ($stem+'.stop')
function Write-WorkerStatus([bool]$Success,[bool]$Running,[string]$Message,[long]$PurgeCount=0){
    foreach($target in @($folder,$statusPath)){if((Test-Path -LiteralPath $target) -and ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Memory-worker output cannot use a reparse point.'}}
    $pending=$statusPath+'.'+[guid]::NewGuid().ToString('N')+'.pending'
    [pscustomobject]@{Token=$token;Success=$Success;MonitorRunning=$Running;Message=$Message;PurgeCount=$PurgeCount;UpdatedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination $statusPath -Force
}
try {
    if((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Memory state must be a local directory.'}
    if((Get-Item -LiteralPath $full).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Memory request cannot be a reparse point.'}
    $request=Get-Content -LiteralPath $full -Raw | ConvertFrom-Json
    $allowed=@('Version','Token','Operation','ParentProcessId','ParentStartTicks','UserSid','StandbyThresholdMB','AvailableThresholdMB','IntervalSeconds')
    if(@($request.PSObject.Properties.Name | Where-Object {$_ -notin $allowed}).Count -or @($allowed | Where-Object {$_ -notin $request.PSObject.Properties.Name}).Count){throw 'Unexpected memory-worker request fields.'}
    if([int]$request.Version -ne 1 -or $request.Token -ne $token -or $request.Operation -notin @('Purge','Monitor') -or $request.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'Invalid memory-worker identity or operation.'}
    if([int]$request.ParentProcessId -le 0 -or [long]$request.ParentStartTicks -le 0){throw 'Invalid parent process identity.'}
    foreach($key in @('StandbyThresholdMB','AvailableThresholdMB')){if([int]$request.$key -lt 128 -or [int]$request.$key -gt 1048576){throw 'Invalid memory threshold.'}}
    if([int]$request.IntervalSeconds -lt 15 -or [int]$request.IntervalSeconds -gt 600){throw 'Invalid monitor interval.'}
    $parent=Get-Process -Id ([int]$request.ParentProcessId) -ErrorAction Stop
    if($parent.StartTime.ToUniversalTime().Ticks -ne [long]$request.ParentStartTicks){throw 'The parent process no longer matches this request.'}
    # Retain the original process object/handle; PID reuse cannot keep this helper alive.
    $parentHandle=$parent.Handle
    . (Join-Path $PSScriptRoot 'GameProcessTuning.ps1')
    Initialize-GamingSystemNative
    if($request.Operation -eq 'Purge'){
        [GamingSystemNative]::PurgeStandby();Write-WorkerStatus $true $false 'Standby list cleared. Cached files may need to be read again.' 1
    }else{
        [GamingSystemNative]::StartMonitor([int]$request.StandbyThresholdMB,[int]$request.AvailableThresholdMB,[int]$request.IntervalSeconds)
        Write-WorkerStatus $true $true 'Memory monitor started. Both standby and available-memory thresholds must be met.'
        $lastReport=''
        while(-not $parent.HasExited -and -not(Test-Path -LiteralPath $stopPath)){
            Start-Sleep -Seconds 2
            $runtime=[GamingSystemNative]::Runtime()
            $report=([string]$runtime.MonitorRunning)+':'+$runtime.PurgeCount+':'+$runtime.LastMessage
            if($report -ne $lastReport){Write-WorkerStatus $runtime.MonitorRunning $runtime.MonitorRunning $runtime.LastMessage $runtime.PurgeCount;$lastReport=$report}
            if(-not $runtime.MonitorRunning){break}
        }
        $runtime=[GamingSystemNative]::Runtime();$message=if($runtime.MonitorRunning){'Memory monitor stopped.'}else{$runtime.LastMessage}
        [GamingSystemNative]::StopAll()
        Write-WorkerStatus $true $false $message $runtime.PurgeCount
    }
}catch{Write-WorkerStatus $false $false $_.Exception.Message}
finally{if('GamingSystemNative' -as [type]){[GamingSystemNative]::StopAll()};if($parent){$parent.Dispose()}}
