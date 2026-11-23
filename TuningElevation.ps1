#requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('Worker')][switch]$TuningElevationWorker,
    [Alias('Operation')][ValidateSet('Apply','Restore')][string]$TuningElevationWorkerOperation,
    [Alias('RequestFile')][string]$TuningElevationWorkerRequestFile
)

$script:TuningElevationRoot=$PSScriptRoot
$script:TuningElevationScriptPath=$PSCommandPath
$script:TuningElevationIds=@('BackgroundCapture','Transparency','EdgeBackground','EdgeStartup','ChromeBackground')

function Get-TuningElevationSid {
    return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Get-TuningElevationPath {
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$CreateDirectory)
    $stateRoot=[IO.Path]::GetFullPath((Join-Path $script:TuningElevationRoot 'state'))
    if($CreateDirectory -and -not(Test-Path -LiteralPath $stateRoot)){
        [void][IO.Directory]::CreateDirectory($stateRoot)
    }
    $directory=Get-Item -LiteralPath $stateRoot -ErrorAction Stop
    if(-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)){
        throw 'Tuning state must be a normal directory beneath this application.'
    }
    $full=[IO.Path]::GetFullPath($Path)
    if(-not [string]::Equals([IO.Path]::GetDirectoryName($full),$stateRoot,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($full) -notmatch '^tuning-[0-9a-f]{32}\.request\.json(?:\.result\.json)?$'){
        throw 'Tuning request path is outside the permitted state directory.'
    }
    if(Test-Path -LiteralPath $full){
        $item=Get-Item -LiteralPath $full -ErrorAction Stop
        if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
            throw 'Tuning state must not be a directory or link.'
        }
    }
    return $full
}

function ConvertTo-TuningElevationSnapshot {
    param([Parameter(Mandatory=$true)]$Snapshot)
    if([int]$Snapshot.Version -ne 1){throw 'Unsupported tuning snapshot.'}
    $definitions=@(Get-GamingRegistryDefinitions)
    $seen=@{}
    $rows=@()
    foreach($row in @($Snapshot.Registry)){
        if($null -eq $row){continue}
        $id=[string]$row.Id
        if($id -notin $script:TuningElevationIds -or $seen.ContainsKey($id)){
            throw 'Unknown or duplicate elevated tuning setting.'
        }
        $definition=$definitions | Where-Object Id -eq $id | Select-Object -First 1
        if(-not $definition){throw 'The tuning definition is unavailable.'}
        # Paths and value names are never accepted from a request.
        $expected=@{
            BackgroundCapture=@('Software\Microsoft\Windows\CurrentVersion\GameDVR','HistoricalCaptureEnabled')
            Transparency=@('Software\Microsoft\Windows\CurrentVersion\Themes\Personalize','EnableTransparency')
            EdgeBackground=@('Software\Policies\Microsoft\Edge','BackgroundModeEnabled')
            EdgeStartup=@('Software\Policies\Microsoft\Edge','StartupBoostEnabled')
            ChromeBackground=@('Software\Policies\Google\Chrome','BackgroundModeEnabled')
        }[$id]
        if([string]$definition.Path -ine $expected[0] -or [string]$definition.Name -ine $expected[1] -or [int]$definition.Value -ne 0){
            throw 'The tuning definition does not match the fixed current-user allowlist.'
        }
        if($null -eq $row.Before -or $row.Before.Exists -isnot [bool]){throw 'The prior registry state is invalid.'}
        $beforeValue=$null
        if($row.Before.Exists){
            if([string]$row.Before.Kind -ine 'DWord'){throw 'Only original DWORD settings can be restored by this helper.'}
            $v=$row.Before.Value
            if($v -isnot [int] -and $v -isnot [long] -and $v -isnot [uint32] -and $v -isnot [int16] -and $v -isnot [byte]){
                throw 'The prior DWORD value is not an integer.'
            }
            if([long]$v -lt [int32]::MinValue -or [long]$v -gt [uint32]::MaxValue){throw 'The prior DWORD value is out of range.'}
            # RegistryKey.SetValue accepts signed Int32 for a DWORD, preserving its bits.
            $beforeValue=if([long]$v -gt [int32]::MaxValue){[int]([long]$v-4294967296)}else{[int]$v}
        }
        $seen[$id]=$true
        $rows+=[pscustomobject]@{Id=$id;Before=[pscustomobject]@{Exists=[bool]$row.Before.Exists;Value=$beforeValue;Kind='DWord'};Desired=0}
    }
    return [pscustomobject]@{
        Version=1;Registry=@($rows);PowerMode='Current';AnimationBefore=$null
        PowerBefore=[pscustomobject]@{Guid='';Name=''}
    }
}

function New-TuningElevationFailure {
    param([string]$Operation,[string]$Message,[bool]$Cancelled=$false,$Snapshot=$null)
    $status=if($Cancelled){'Skipped'}else{'Failed'}
    $definitions=@(Get-GamingRegistryDefinitions)
    $results=@(foreach($row in @($Snapshot.Registry)){
        if($null -eq $row){continue}
        $definition=$definitions | Where-Object Id -eq $row.Id | Select-Object -First 1
        [pscustomobject]@{Id=$row.Id;Name=$(if($definition){$definition.Label}else{'Elevated tuning'});Status=$status;Success=$false;Message=$Message}
    })
    if(-not $results.Count){$results=@([pscustomobject]@{Id='TuningWorker';Name='Elevated tuning';Status=$status;Success=$false;Message=$Message})}
    return [pscustomobject]@{Success=$false;Status=$status;Operation=$Operation;Cancelled=$Cancelled;Results=$results}
}

function Invoke-ElevatedGamingTuning {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Snapshot,[Parameter(Mandatory=$true)][ValidateSet('Apply','Restore')][string]$Operation)
    $safe=$null
    try{
        $safe=ConvertTo-TuningElevationSnapshot $Snapshot
        if(-not @($safe.Registry).Count){return [pscustomobject]@{Success=$true;Status='NoAction';Operation=$Operation;Results=@()}}
        $name='tuning-'+[guid]::NewGuid().ToString('N')+'.request.json'
        $requestPath=Get-TuningElevationPath (Join-Path (Join-Path $script:TuningElevationRoot 'state') $name) -CreateDirectory
        $resultPath=Get-TuningElevationPath ($requestPath+'.result.json')
        $request=[pscustomobject]@{Version=1;Operation=$Operation;UserSid=Get-TuningElevationSid;Snapshot=$safe}
        $request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8 -ErrorAction Stop
        if($requestPath.Contains('"') -or $script:TuningElevationScriptPath.Contains('"')){throw 'Invalid tuning worker path.'}
        $powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Worker -Operation {1} -RequestFile "{2}"' -f $script:TuningElevationScriptPath,$Operation,$requestPath
        $worker=Start-Process -FilePath $powershell -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        try{
            # This timer begins after the user's UAC decision. The application
            # stays responsive; it never accepts or dismisses the UAC dialog.
            $deadline=[datetime]::UtcNow.AddSeconds(120)
            $formsType='System.Windows.Forms.Application' -as [type]
            while(-not $worker.HasExited){
                if([datetime]::UtcNow -ge $deadline){throw 'The tuning worker timed out and may still be finishing. Check the saved result before retrying.'}
                if($null -ne $formsType){[System.Windows.Forms.Application]::DoEvents()}
                elseif(Get-Command Write-GamingStatus -ErrorAction SilentlyContinue){Write-GamingStatus 'Waiting for the approved settings change...' | Out-Null}
                Start-Sleep -Milliseconds 150
            }
            $exitCode=$worker.ExitCode
        }finally{$worker.Dispose()}
        if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw "The tuning worker exited ($exitCode) without a result."}
        $resultPath=Get-TuningElevationPath $resultPath
        $result=Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if($result.Operation -ne $Operation -or $result.Success -isnot [bool]){throw 'The tuning worker returned an invalid result.'}
        return $result
    }catch{
        $cancelled=$false
        $exception=$_.Exception
        while($exception){
            if($exception.PSObject.Properties['NativeErrorCode'] -and $exception.NativeErrorCode -eq 1223){$cancelled=$true}
            $exception=$exception.InnerException
        }
        $message=if($cancelled){'Administrator approval was cancelled; these settings were not changed.'}else{$_.Exception.Message}
        return New-TuningElevationFailure -Operation $Operation -Message $message -Cancelled $cancelled -Snapshot $safe
    }
}

if($TuningElevationWorker){
    $resultPath=$null
    $workerExit=1
    try{
        if(-not $TuningElevationWorkerOperation -or -not $TuningElevationWorkerRequestFile){throw 'A worker request and operation are required.'}
        $requestPath=Get-TuningElevationPath $TuningElevationWorkerRequestFile
        if($requestPath -notmatch '\.request\.json$'){throw 'The worker requires a request file.'}
        $resultPath=Get-TuningElevationPath ($requestPath+'.result.json')
        if(Test-Path -LiteralPath $resultPath){throw 'The worker result already exists; the request will not be replayed.'}
        if((Get-Item -LiteralPath $requestPath -ErrorAction Stop).Length -gt 65536){throw 'The tuning request is too large.'}
        $request=Get-Content -LiteralPath $requestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if([int]$request.Version -ne 1 -or $request.Operation -ne $TuningElevationWorkerOperation){throw 'The tuning request operation does not match.'}
        if([string]$request.UserSid -ne (Get-TuningElevationSid)){throw 'The elevated account differs from the requesting user; no settings were changed.'}
        $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'The tuning worker requires administrator approval.'}
        . (Join-Path $script:TuningElevationRoot 'Performance.ps1')
        $safe=ConvertTo-TuningElevationSnapshot $request.Snapshot
        $workerResult=Invoke-GamingTuning -Snapshot $safe -Operation $TuningElevationWorkerOperation -NoElevation
        $workerResult | Add-Member -NotePropertyName Operation -NotePropertyValue $TuningElevationWorkerOperation -Force
        $workerResult | Add-Member -NotePropertyName Status -NotePropertyValue $(if($workerResult.Success){'Completed'}else{'Partial'}) -Force
        $workerExit=if($workerResult.Success){0}else{1}
    }catch{
        $workerResult=[pscustomobject]@{Success=$false;Status='Failed';Operation=$TuningElevationWorkerOperation;Results=@([pscustomobject]@{Id='TuningWorker';Name='Elevated tuning';Status='Failed';Success=$false;Message=$_.Exception.Message})}
    }
    if($resultPath){
        try{
            $resultPath=Get-TuningElevationPath $resultPath
            $stream=[IO.File]::Open($resultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{
                $writer=New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false)))
                try{$writer.Write(($workerResult | ConvertTo-Json -Depth 12))}finally{$writer.Dispose()}
            }finally{$stream.Dispose()}
        }catch{$workerExit=1}
    }
    exit $workerExit
}
