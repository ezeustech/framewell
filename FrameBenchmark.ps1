# Optional, process-scoped PresentMon capture. Windows PowerShell 5.1.
[CmdletBinding()]
param([string]$FrameBenchmarkWorkerRequestFile)
$script:GamingFrameRoot=$PSScriptRoot
$script:GamingFrameScript=$PSCommandPath
$script:GamingPresentMon='C:\Program Files\NVIDIA Corporation\FrameViewSDK\bin\PresentMon_x64.exe'

function Write-GamingFrameProgress([string]$Message) {
    if(Get-Command Write-GamingStatus -ErrorAction SilentlyContinue){Write-GamingStatus $Message}
    if('System.Windows.Forms.Application' -as [type]){[System.Windows.Forms.Application]::DoEvents()}
}

function Get-GamingFrameStamp($Process) {
    ([datetime]$Process.CreationDate).ToUniversalTime().ToString('o')
}

function Test-GamingFramePathForGame {
    param([string]$Path,$Game)
    if(-not $Path -or -not $Game){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path)
        if($Game.PSObject.Properties['IsExecutableBound'] -and $Game.IsExecutableBound -and $Game.ExecutablePath){
            return [string]::Equals($full,[IO.Path]::GetFullPath([string]$Game.ExecutablePath),[StringComparison]::OrdinalIgnoreCase)
        }
        if($Game.Source -eq 'Manual') {
            return [string]::Equals($full,[IO.Path]::GetFullPath([string]$Game.ExecutablePath),[StringComparison]::OrdinalIgnoreCase)
        }
        if($Game.Source -in @('Steam','Epic','GOG','EA','Ubisoft','Xbox','Folder') -and $Game.InstallDirectory) {
            $root=[IO.Path]::GetFullPath([string]$Game.InstallDirectory).TrimEnd('\')+'\'
            return $full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)
        }
    } catch { }
    return $false
}

function Get-RunningGamingProcesses {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId)
    if(-not(Get-Command Get-GameLibrary -ErrorAction SilentlyContinue)){. (Join-Path $script:GamingFrameRoot 'GameLibrary.ps1')}
    $games=@(Get-GameLibrary | Where-Object Id -eq $GameId)
    if($games.Count -ne 1){return @()}
    $game=$games[0]
    $records=foreach($process in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
        if(-not $process.ExecutablePath -or -not(Test-GamingFramePathForGame $process.ExecutablePath $game)){continue}
        if($process.Name -match '(?i)crash|report|launcher|unins|setup|redist|cef|webhelper|installer|anticheat'){continue}
        [pscustomobject]@{
            Pid=[int]$process.ProcessId;Name=[string]$process.Name;Path=[string]$process.ExecutablePath
            WorkingSetMB=[math]::Round(([double]$process.WorkingSetSize/1MB),1)
            CreationDateUtc=Get-GamingFrameStamp $process;GameId=$GameId
        }
    }
    return @($records | Sort-Object WorkingSetMB -Descending)
}

function Get-GamingPresentMonInfo {
    if(-not(Test-Path -LiteralPath $script:GamingPresentMon -PathType Leaf)){throw 'The installed NVIDIA FrameView PresentMon tool was not found.'}
    $signature=Get-AuthenticodeSignature -FilePath $script:GamingPresentMon -ErrorAction Stop
    if($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch '(?i)(?:^|,\s*)O=NVIDIA Corporation(?:,|$)') {
        throw 'PresentMon must have a valid NVIDIA Corporation signature.'
    }
    [pscustomobject]@{Path=$script:GamingPresentMon;Version=(Get-Item -LiteralPath $script:GamingPresentMon).VersionInfo.FileVersion;Publisher='NVIDIA Corporation'}
}

function Get-GamingFrameStatePath {
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$CreateDirectory)
    $root=[IO.Path]::GetFullPath((Join-Path $script:GamingFrameRoot 'state')).TrimEnd('\')
    if($CreateDirectory -and -not(Test-Path -LiteralPath $root)){New-Item -ItemType Directory -Path $root -Force | Out-Null}
    $full=[IO.Path]::GetFullPath($Path)
    if(-not $full.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'Benchmark files must remain inside this app state directory.'}
    $check=$full
    while($check -and $check.Length -ge $root.Length) {
        if(Test-Path -LiteralPath $check){
            if((Get-Item -LiteralPath $check -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Benchmark state cannot use symbolic links or junctions.'}
        }
        if($check -ieq $root){break}
        $check=Split-Path $check -Parent
    }
    return $full
}

function New-GamingFrameFailure {
    param([string]$Message,[string]$ProcessName='',[string]$ReportPath='')
    [pscustomobject]@{Success=$false;ProcessName=$ProcessName;AverageFPS=$null;OnePercentLowFPS=$null;P95FrameTimeMs=$null;Samples=0;ReportPath=$ReportPath;Message=$Message}
}

function ConvertFrom-GamingFrameCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][int]$ProcessId,[string]$ProcessName='')
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return New-GamingFrameFailure 'No frame report was produced. Keep the selected game running and visible during capture.' $ProcessName $Path}
    $chains=@{};$headerChecked=$false;$foundInterval=$false
    foreach($row in (Import-Csv -LiteralPath $Path -ErrorAction Stop)) {
        if(-not $headerChecked){$foundInterval=[bool]$row.PSObject.Properties['msBetweenPresents'];$headerChecked=$true}
        if(-not $foundInterval){return New-GamingFrameFailure 'The report does not contain the required PresentMon v1 frame-interval metric.' $ProcessName $Path}
        $rowProcess=0
        if(-not [int]::TryParse([string]$row.ProcessID,[ref]$rowProcess) -or $rowProcess -ne $ProcessId){continue}
        [double]$interval=0
        if(-not [double]::TryParse([string]$row.msBetweenPresents,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$interval)){continue}
        if($interval -le 0 -or [double]::IsNaN($interval) -or [double]::IsInfinity($interval)){continue}
        $chain=[string]$row.SwapChainAddress
        if(-not $chain){$chain='default'}
        if(-not $chains.ContainsKey($chain)){$chains[$chain]=New-Object 'System.Collections.Generic.List[double]'}
        $chains[$chain].Add($interval)
    }
    if(-not $chains.Count){return New-GamingFrameFailure 'No usable frame intervals were captured for this process. Keep the game visible and try again.' $ProcessName $Path}
    $chosen=$chains.GetEnumerator() | Sort-Object @{Expression={$_.Value.Count};Descending=$true} | Select-Object -First 1
    $values=@($chosen.Value.ToArray() | Sort-Object)
    if($values.Count -lt 30){return New-GamingFrameFailure ('Only '+$values.Count+' frame intervals were captured; at least 30 are needed. Keep the game rendering during the test.') $ProcessName $Path}
    $average=($values | Measure-Object -Average).Average
    $slowCount=[math]::Max(1,[int][math]::Ceiling($values.Count*0.01))
    $slowAverage=($values | Select-Object -Last $slowCount | Measure-Object -Average).Average
    $percentileIndex=[math]::Max(0,[int][math]::Ceiling($values.Count*0.95)-1)
    [pscustomobject]@{
        Success=$true;ProcessName=$ProcessName;AverageFPS=[math]::Round((1000/$average),2)
        OnePercentLowFPS=[math]::Round((1000/$slowAverage),2);P95FrameTimeMs=[math]::Round([double]$values[$percentileIndex],3)
        Samples=$values.Count;ReportPath=$Path;SwapChain=[string]$chosen.Key;SwapChainsObserved=$chains.Count
        Message='CPU-present frame intervals; not physical input latency or displayed/generated-frame FPS. Repeat the same scene and settings for comparison.'
        Method='FPS=1000/mean(msBetweenPresents); 1% low=1000/mean(slowest ceil(N*0.01) intervals); P95=nearest rank. The most active swap chain is selected.'
    }
}

function Test-GamingFramePermission {
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    return ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or @($identity.Groups | ForEach-Object Value) -contains 'S-1-5-32-559')
}

function Invoke-GamingFrameWorker {
    param([Parameter(Mandatory=$true)][string]$RequestFile)
    $requestPath=Get-GamingFrameStatePath $RequestFile
    if([IO.Path]::GetFileName($requestPath) -notmatch '^benchmark-([a-f0-9]{32})\.request\.json$'){throw 'Invalid benchmark request name.'}
    $token=$Matches[1]
    if((Get-Item -LiteralPath $requestPath).Length -gt 65536){throw 'Benchmark request is too large.'}
    $request=Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
    if([int]$request.Version -ne 1 -or [int]$request.Seconds -lt 5 -or [int]$request.Seconds -gt 60){throw 'Invalid benchmark duration or request version.'}
    $tool=Get-GamingPresentMonInfo
    $targets=@(Get-RunningGamingProcesses -GameId ([string]$request.GameId) | Where-Object {
        $_.Pid -eq [int]$request.ProcessId -and $_.CreationDateUtc -eq [string]$request.CreationDateUtc -and $_.Path -ieq [string]$request.ExecutablePath
    })
    if($targets.Count -ne 1){throw 'The selected game process changed or exited. Start a fresh benchmark.'}
    $target=$targets[0]
    $reports=Join-Path $script:GamingFrameRoot 'state\benchmarks'
    $csv=Get-GamingFrameStatePath (Join-Path $reports ('benchmark-'+$token+'.csv'))
    if(-not(Test-Path -LiteralPath $reports)){New-Item -ItemType Directory -Path $reports -Force | Out-Null}
    $stdout=Get-GamingFrameStatePath ($csv+'.stdout.log')
    $stderr=Get-GamingFrameStatePath ($csv+'.stderr.log')
    $session='GamingMode-'+$token
    $arguments='--process_id {0} --output_file "{1}" --delay 3 --timed {2} --terminate_after_timed --terminate_on_proc_exit --session_name {3} --no_console_stats --v1_metrics --no_track_input --no_track_gpu --no_track_display' -f [int]$target.Pid,$csv,[int]$request.Seconds,$session
    $capture=$null;$timedOut=$false
    try {
        $capture=Start-Process -FilePath $tool.Path -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr -ErrorAction Stop
        $captureId=[int]$capture.Id
        $deadline=[datetime]::UtcNow.AddSeconds([int]$request.Seconds+18)
        while(-not $capture.HasExited) {
            if([datetime]::UtcNow -ge $deadline){$timedOut=$true;break}
            if('System.Windows.Forms.Application' -as [type]){[System.Windows.Forms.Application]::DoEvents()}
            Start-Sleep -Milliseconds 100
        }
        if($timedOut){return New-GamingFrameFailure 'The timed capture did not finish normally. The selected game was left untouched.' $target.Name $csv}
        if($capture.ExitCode -ne 0) {
            return New-GamingFrameFailure ('PresentMon exited with code '+$capture.ExitCode+'. Check the report logs; this game or its permissions may not support this capture.') $target.Name $csv
        }
        $result=ConvertFrom-GamingFrameCsv -Path $csv -ProcessId $target.Pid -ProcessName $target.Name
        $result | Add-Member -NotePropertyName CheckedUtc -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -Force
        $result | Add-Member -NotePropertyName GameId -NotePropertyValue ([string]$request.GameId) -Force
        $result | Add-Member -NotePropertyName RequestedSeconds -NotePropertyValue ([int]$request.Seconds) -Force
        $result | Add-Member -NotePropertyName ToolVersion -NotePropertyValue $tool.Version -Force
        $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath ($csv+'.summary.json') -Encoding UTF8
        return $result
    } finally {
        if($capture) {
            if(-not $capture.HasExited) {
                # Only terminate this invocation's unique ETW session; never
                # interfere with another profiler or the selected game.
                $cleanup=Start-Process -FilePath $tool.Path -ArgumentList ('--session_name '+$session+' --terminate_existing_session') -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
                if($cleanup){[void]$cleanup.WaitForExit(5000);$cleanup.Dispose()}
                [void]$capture.WaitForExit(5000)
                if(-not $capture.HasExited) {
                    $live=Get-CimInstance Win32_Process -Filter ('ProcessId='+$captureId) -ErrorAction SilentlyContinue
                    if($live -and $live.ExecutablePath -ieq $tool.Path -and [string]$live.CommandLine -match [regex]::Escape($session)) {
                        # This process handle belongs to the child we launched.
                        $capture.Kill()
                    }
                }
            }
            $capture.Dispose()
        }
    }
}

function Invoke-GamingFrameBenchmark {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId,[int]$ProcessId=0,[ValidateRange(5,60)][int]$Seconds=20)
    $selected=$null
    try {
        $null=Get-GamingPresentMonInfo
        $targets=@(Get-RunningGamingProcesses -GameId $GameId)
        if($ProcessId -gt 0){$targets=@($targets | Where-Object Pid -eq $ProcessId)}
        if(-not $targets.Count){return New-GamingFrameFailure 'Start the selected game first. No verified running game process was found.'}
        $selected=$targets[0]
        $requestPath=Get-GamingFrameStatePath (Join-Path $script:GamingFrameRoot ('state\benchmark-'+[guid]::NewGuid().ToString('N')+'.request.json')) -CreateDirectory
        [pscustomobject]@{Version=1;GameId=$GameId;ProcessId=$selected.Pid;CreationDateUtc=$selected.CreationDateUtc;ExecutablePath=$selected.Path;Seconds=$Seconds} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $requestPath -Encoding UTF8
        Write-GamingFrameProgress ('Benchmarking '+$selected.Name+'. Switch to the game: capture starts after 3 seconds and lasts '+$Seconds+' seconds.')
        if(Test-GamingFramePermission) {
            $result=Invoke-GamingFrameWorker -RequestFile $requestPath
        } else {
            Write-GamingFrameProgress ('Windows permission is needed for frame capture. After approving, switch to '+$selected.Name+'.')
            $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -FrameBenchmarkWorkerRequestFile "{1}"' -f $script:GamingFrameScript,$requestPath
            $worker=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
            try {
                $deadline=[datetime]::UtcNow.AddSeconds($Seconds+40)
                while(-not $worker.HasExited) {
                    if([datetime]::UtcNow -ge $deadline){return New-GamingFrameFailure 'The benchmark worker has not finished. Check its report before starting another capture.' $selected.Name}
                    Write-GamingFrameProgress ('Capturing '+$selected.Name+' frame times. Keep the game rendering...')
                    Start-Sleep -Milliseconds 200
                }
            } finally {$worker.Dispose()}
            $resultPath=Get-GamingFrameStatePath ($requestPath+'.result.json')
            if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){return New-GamingFrameFailure 'The capture worker exited without a report.' $selected.Name}
            $result=Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
        }
        if($result -and $result.PSObject.Properties['Success']) {
            $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Get-GamingFrameStatePath (Join-Path $script:GamingFrameRoot 'state\latest-benchmark.json')) -Encoding UTF8
            return $result
        }
        return New-GamingFrameFailure 'The benchmark returned an invalid report.' $selected.Name
    } catch {
        $cancelled=$false;$exception=$_.Exception
        while($exception){if($exception.PSObject.Properties['NativeErrorCode'] -and $exception.NativeErrorCode -eq 1223){$cancelled=$true};$exception=$exception.InnerException}
        $message=if($cancelled){'Administrator approval was cancelled; no benchmark was started.'}else{$_.Exception.Message}
        return New-GamingFrameFailure $message $(if($selected){$selected.Name}else{''})
    }
}

if($FrameBenchmarkWorkerRequestFile) {
    $resultPath=$null;$exitCode=1
    try {
        $validated=Get-GamingFrameStatePath $FrameBenchmarkWorkerRequestFile
        $resultPath=Get-GamingFrameStatePath ($validated+'.result.json')
        $result=Invoke-GamingFrameWorker -RequestFile $validated
        $exitCode=0
    } catch {$result=New-GamingFrameFailure $_.Exception.Message}
    if($resultPath){$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding UTF8}
    exit $exitCode
}
