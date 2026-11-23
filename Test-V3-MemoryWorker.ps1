# Exercise the real worker's lifecycle with a fake native provider. No elevation or memory writes.
$ErrorActionPreference='Stop'
$fixture=Join-Path $PSScriptRoot ('test-results\memory-worker-'+[guid]::NewGuid().ToString('N'))
$state=Join-Path $fixture 'state';New-Item -ItemType Directory -Path $state -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'MemoryWorker.ps1') -Destination (Join-Path $fixture 'MemoryWorker.ps1')
@'
function Initialize-GamingSystemNative {
 Add-Type -TypeDefinition @"
public class WorkerRuntime { public bool MonitorRunning; public long PurgeCount; public string LastMessage; }
public static class GamingSystemNative {
 static bool running;
 public static void StartMonitor(int a,int b,int c){running=true;}
 public static void PurgeStandby(){throw new System.Exception("No live purge allowed in this test.");}
 public static WorkerRuntime Runtime(){return new WorkerRuntime{MonitorRunning=running,PurgeCount=0,LastMessage="Fixture monitoring"};}
 public static void StopAll(){running=false;}
}
"@
}
'@|Set-Content -LiteralPath (Join-Path $fixture 'GameProcessTuning.ps1') -Encoding UTF8
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$checks=@()
foreach($mode in @('ParentExit','StopFile')){
    $parent=$null;$worker=$null
    try {
        $parent=Start-Process -FilePath $powershell -ArgumentList '-NoProfile -NonInteractive -Command "Start-Sleep -Seconds 30"' -WindowStyle Hidden -PassThru
        $token=[guid]::NewGuid().ToString('N');$stem=Join-Path $state ('memory-worker-'+$token)
        [pscustomobject]@{Version=1;Token=$token;Operation='Monitor';ParentProcessId=$parent.Id;ParentStartTicks=([string]$parent.StartTime.ToUniversalTime().Ticks);UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;StandbyThresholdMB=1024;AvailableThresholdMB=1024;IntervalSeconds=30}|ConvertTo-Json|Set-Content -LiteralPath ($stem+'.request.json') -Encoding UTF8
        $arguments='-NoProfile -NonInteractive -File "'+(Join-Path $fixture 'MemoryWorker.ps1')+'" -RequestPath "'+$stem+'.request.json"'
        $worker=Start-Process -FilePath $powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $clock=[Diagnostics.Stopwatch]::StartNew()
        while(-not(Test-Path -LiteralPath ($stem+'.status.json')) -and -not $worker.HasExited -and $clock.Elapsed.TotalSeconds -lt 8){Start-Sleep -Milliseconds 100}
        if(-not(Test-Path -LiteralPath ($stem+'.status.json'))){throw 'Worker did not initialize.'}
        $initial=Get-Content -LiteralPath ($stem+'.status.json') -Raw|ConvertFrom-Json
        if(-not $initial.MonitorRunning){throw ('Worker rejected fixture: '+$initial.Message)}
        if($mode -eq 'ParentExit'){$parent.Kill();$parent.WaitForExit()}
        else {Set-Content -LiteralPath ($stem+'.stop') -Value 'stop'}
        if(-not $worker.WaitForExit(6000)){throw 'Worker did not stop within its expected lifetime bound.'}
        $final=Get-Content -LiteralPath ($stem+'.status.json') -Raw|ConvertFrom-Json
        if($final.MonitorRunning -or $final.PurgeCount -ne 0){throw 'Worker did not report a clean non-mutating shutdown.'}
        $checks+=$mode
    }finally{
        if($worker){if(-not $worker.HasExited){$worker.Kill();$worker.WaitForExit()};$worker.Dispose()}
        if($parent){if(-not $parent.HasExited){$parent.Kill();$parent.WaitForExit()};$parent.Dispose()}
    }
}
[pscustomobject]@{Passed=$checks.Count;Checks=$checks;LiveNativeProvider=$false;Elevation=$false;VerifiedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'test-results\v3-memory-worker-results.json') -Encoding UTF8
Write-Output ('PASS: '+$checks.Count+' real-worker lifecycle checks using a fake native provider; no elevation or memory mutation.')
