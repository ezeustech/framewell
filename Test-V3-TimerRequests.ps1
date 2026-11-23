# Timer-controller tests use an injected fake API. No Windows timer request is made.
$ErrorActionPreference='Stop'
$native=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'GamingSystemNative.cs') -Raw
$fake=@'
public sealed class GamingFakeTimerApi : IGamingTimerApi {
 public uint Maximum=156250,Minimum=5000,Current=156250;
 public int NativeAcquires,NativeReleases,Begins,Ends,Queries;
 public uint LastAcquire,LastRelease;
 public bool FailQuery,FailAcquire,FailRelease,FailReadback,AfterAcquire;
 public int Query(out uint maximum,out uint minimum,out uint current){Queries++;maximum=Maximum;minimum=Minimum;current=Current;if(FailQuery||(FailReadback&&AfterAcquire)){AfterAcquire=false;return -1;}return 0;}
 public uint Begin(uint period){Begins++;Current=period*10000;return 0;}
 public uint End(uint period){Ends++;return FailRelease?1U:0U;}
 public int Native(uint resolution,bool acquire,out uint actual){
  actual=Current;
  if(acquire){NativeAcquires++;LastAcquire=resolution;if(FailAcquire)return -1;Current=resolution;actual=Current;AfterAcquire=true;}
  else{NativeReleases++;LastRelease=resolution;if(FailRelease)return -1;}
  return 0;
 }
 public static void ConcurrentEnable(GamingTimerRequest controller){System.Threading.Tasks.Parallel.For(0,24,delegate(int ignored){controller.Set(true,0.5);});}
}
'@
Add-Type -TypeDefinition ($native+"`r`n"+$fake)
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$checks.Add($Name)}
function Expect-Failure([scriptblock]$Action,[string]$Name){$failed=$false;try{&$Action|Out-Null}catch{$failed=$true};Assert $failed $Name}
$api=New-Object GamingFakeTimerApi;$controller=New-Object GamingTimerRequest $api
$controller.Set($true,0.5)
Assert ($controller.Active -and $controller.Native -and $api.LastAcquire -eq 5000 -and $controller.RequestedMilliseconds -eq 0.5 -and $controller.EffectiveMilliseconds -eq 0.5 -and $controller.ObservedMilliseconds -eq 0.5) '0.5 ms becomes a bounded 5000-unit native request with readback'
$controller.Set($true,0.5)
Assert ($api.NativeAcquires -eq 1) 'Repeated selection does not duplicate the native request'
$controller.Set($false,1)
Assert (-not $controller.Active -and $api.NativeReleases -eq 1 -and $api.LastRelease -eq 5000) 'Native stop pairs release with the exact acquired resolution'
$api=New-Object GamingFakeTimerApi;$api.Minimum=10000;$controller=New-Object GamingTimerRequest $api;$controller.Set($true,0.5)
Assert ($controller.RequestedMilliseconds -eq 0.5 -and $controller.EffectiveMilliseconds -eq 1 -and $api.LastAcquire -eq 10000) 'Unsupported fine resolution clamps to the OS minimum and reports both values'
$controller.Set($false,1)
$api=New-Object GamingFakeTimerApi;$controller=New-Object GamingTimerRequest $api;$controller.Set($true,1)
Assert ($api.Begins -eq 1 -and $api.NativeAcquires -eq 0 -and -not $controller.Native) 'Integer request retains the documented WinMM path'
$controller.Set($true,0.5)
Assert ($api.Ends -eq 1 -and $api.NativeAcquires -eq 1 -and $controller.Native) 'Switching methods releases the previous request first'
$controller.Set($false,1)
$api=New-Object GamingFakeTimerApi;$controller=New-Object GamingTimerRequest $api;$controller.Set($true,1);$api.FailQuery=$true
Expect-Failure {$controller.Set($true,0.5)} 'Unavailable native bounds reject the experiment'
Assert ($controller.Active -and -not $controller.Native -and $api.Ends -eq 0) 'Preflight failure preserves the prior request'
$api.FailQuery=$false;$controller.Set($false,1)
$api=New-Object GamingFakeTimerApi;$api.FailReadback=$true;$controller=New-Object GamingTimerRequest $api
Expect-Failure {$controller.Set($true,0.5)} 'Native readback failure is reported'
Assert (-not $controller.Active -and $api.NativeAcquires -eq 1 -and $api.NativeReleases -eq 1) 'Readback failure releases the acquired native request'
$api=New-Object GamingFakeTimerApi;$api.FailAcquire=$true;$controller=New-Object GamingTimerRequest $api
Expect-Failure {$controller.Set($true,0.5)} 'OS refusal is reported as a failed native request'
Assert (-not $controller.Active) 'OS refusal never reports an active timer'
$api=New-Object GamingFakeTimerApi;$controller=New-Object GamingTimerRequest $api;$controller.Set($true,0.5);$api.FailRelease=$true
Expect-Failure {$controller.Set($false,1)} 'Native release failure is reported'
Assert ($controller.Active -and $controller.EffectiveMilliseconds -eq 0.5) 'Failed release remains tracked for a safe retry'
$api.FailRelease=$false;$controller.Set($false,1)
Assert (-not $controller.Active) 'Retry releases the tracked request'
$api=New-Object GamingFakeTimerApi;$controller=New-Object GamingTimerRequest $api
foreach($invalid in @(0,0.25,0.7,16.5,[double]::NaN,[double]::PositiveInfinity)){Expect-Failure {$controller.Set($true,$invalid)} ('Invalid timer value rejected: '+$invalid)}
Assert ($api.Begins -eq 0 -and $api.NativeAcquires -eq 0) 'Invalid values never reach a timer API'
[GamingFakeTimerApi]::ConcurrentEnable($controller)
Assert ($api.NativeAcquires -eq 1) 'Concurrent enable requests share one tracked acquisition'
$controller.Set($false,1)
Assert ($api.NativeReleases -eq 1) 'Concurrent acquisition still has a single matching release'
$realRuntime=[GamingSystemNative]::Runtime()
Assert (-not $realRuntime.TimerEnabled -and -not $realRuntime.MonitorRunning) 'Production native timer and monitor remain untouched'
[pscustomobject]@{Passed=$checks.Count;Checks=@($checks.ToArray());LiveTimerRequests=$false;VerifiedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'test-results\v3-timer-requests-results.json') -Encoding UTF8
Write-Output ('PASS: '+$checks.Count+' timer lifecycle checks with fake API; no live timer requests.')
