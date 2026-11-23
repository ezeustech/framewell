$ErrorActionPreference='Stop'
$appRoot=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path $PSScriptRoot ('display-worker-fixture-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'state'))
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$checks.Add($Name)}
# This EXE is only an assembly fixture: it contains no display PInvoke and is never run.
$fakeCode=@'
using System;
using System.Collections.Generic;
using System.Threading;
public sealed class GamingDisplayMode { public string Key; }
public static class GamingWindowsDisplay {
 public static readonly List<string> Calls=new List<string>();
 public static bool FailPersist; public static string Current="original";
 public static void Main() {}
 public static void Reset(bool fail) {Calls.Clear();Current="original";FailPersist=fail;}
 public static GamingDisplayMode[] Modes(){return new[]{new GamingDisplayMode{Key="requested"}};}
 public static string CurrentKey(){return Current;}
 public static void Apply(string key,bool persist){Calls.Add(key+":"+persist);if(persist&&FailPersist)throw new InvalidOperationException("Mock persistence refused");Current=key;}
}
public static class DisplayTestMutexHolder {
 static ManualResetEvent ready,release;static Thread worker;
 public static void Start(string name){ready=new ManualResetEvent(false);release=new ManualResetEvent(false);worker=new Thread(()=>{using(var mutex=new Mutex(false,name)){mutex.WaitOne();ready.Set();release.WaitOne();mutex.ReleaseMutex();}});worker.IsBackground=true;worker.Start();if(!ready.WaitOne(5000))throw new Exception("Fixture mutex was not acquired");}
 public static void Stop(){release.Set();worker.Join(5000);ready.Dispose();release.Dispose();}
}
'@
$fakeAssembly=Join-Path $fixture 'GamingMode.exe'
Add-Type -TypeDefinition $fakeCode -OutputAssembly $fakeAssembly -OutputType ConsoleApplication
[void][Reflection.Assembly]::LoadFrom($fakeAssembly)
$workerSource=Get-Content -LiteralPath (Join-Path $appRoot 'DisplayWorker.ps1') -Raw
$workerCopy=Join-Path $fixture 'DisplayWorker.ps1'
# Isolate the synchronization object as well as all files from the running app.
$mutexName='GamingModeDisplayPreview-test-'+[guid]::NewGuid().ToString('N')
[IO.File]::WriteAllText($workerCopy,$workerSource.Replace('GamingModeDisplayPreview-v1',$mutexName))
$script:fakeParentStart=[datetime]::UtcNow.AddMinutes(-5)
$script:fakeParentExited=$false
$global:GamingDisplayWorkerTestStart=$script:fakeParentStart
$global:GamingDisplayWorkerTestAssembly=$fakeAssembly
$global:GamingDisplayWorkerTestExited=$false
function Get-Process {
    param([int]$Id)
    $parent=[pscustomobject]@{StartTime=$global:GamingDisplayWorkerTestStart;Path=$global:GamingDisplayWorkerTestAssembly;Handle=[IntPtr]1;HasExited=$global:GamingDisplayWorkerTestExited}
    $parent|Add-Member ScriptMethod Dispose {};return $parent
}
function Invoke-FixtureWorker([string]$Signal,[bool]$FailPersist=$false){
    [GamingWindowsDisplay]::Reset($FailPersist)
    $token=[guid]::NewGuid().ToString('N');$stem=Join-Path $fixture ('state\display-'+$token)
    [pscustomobject]@{Version=1;Token=$token;Key='requested';ParentProcessId=31415;ParentStartTicks=[string]$script:fakeParentStart.Ticks}|ConvertTo-Json|Set-Content -LiteralPath ($stem+'.request.json') -Encoding UTF8
    if($Signal){Set-Content -LiteralPath ($stem+'.'+$Signal) -Value $token -Encoding ASCII}
    & $workerCopy -RequestPath ($stem+'.request.json')
    Get-Content -LiteralPath ($stem+'.status.json') -Raw|ConvertFrom-Json
}
$result=Invoke-FixtureWorker 'keep'
Assert ($result.Success -and $result.State -eq 'Kept' -and -not $result.RequiresConfirmation) 'Worker acknowledges Keep only after the persistent apply succeeds'
Assert (([GamingWindowsDisplay]::Calls -join ',') -eq 'requested:False,requested:True' -and [GamingWindowsDisplay]::Current -eq 'requested') 'Confirmed worker applies the preview then persists it exactly once'
$result=Invoke-FixtureWorker 'revert'
Assert ($result.Success -and $result.State -eq 'Reverted' -and [GamingWindowsDisplay]::Current -eq 'original') 'Explicit Revert restores the original mode without persistence'
Assert (([GamingWindowsDisplay]::Calls -join ',') -eq 'requested:False,original:False') 'Revert does not write the saved display configuration'
$result=Invoke-FixtureWorker 'keep' $true
Assert (-not $result.Success -and $result.State -eq 'Failed' -and $result.Message -match 'Mock persistence refused') 'Persistent apply failure is reported as failure, not Kept'
Assert ([GamingWindowsDisplay]::Current -eq 'original' -and ([GamingWindowsDisplay]::Calls -join ',') -eq 'requested:False,requested:True,original:False') 'A failed keep restores the active original mode'
$script:fakeParentExited=$true
$global:GamingDisplayWorkerTestExited=$true
$result=Invoke-FixtureWorker ''
Assert ($result.State -eq 'Reverted' -and [GamingWindowsDisplay]::Current -eq 'original') 'Closing the parent prevents retaining an unconfirmed display mode'
$script:fakeParentExited=$false
$global:GamingDisplayWorkerTestExited=$false
[DisplayTestMutexHolder]::Start('Local\'+$mutexName)
try{
    $result=Invoke-FixtureWorker 'keep'
    Assert (-not $result.Success -and $result.Message -match 'Another display preview' -and [GamingWindowsDisplay]::Calls.Count -eq 0) 'A concurrent preview is rejected before touching the display API'
}finally{[DisplayTestMutexHolder]::Stop()}
$result=Invoke-FixtureWorker 'revert'
Assert ($result.State -eq 'Reverted') 'Another preview can run after the prior worker releases its mutex'
[pscustomobject]@{Passed=$checks.Count;Checks=@($checks.ToArray());NativeDisplayApi='Mock-only assembly without PInvoke';LiveDisplayChanges=$false;LiveChildProcesses=$false;VerifiedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'v31-display-worker-results.json') -Encoding UTF8
Write-Output ('PASS: '+$checks.Count+' actual worker-flow checks with a fake display API; no live mode changes.')
