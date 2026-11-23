# Per-game scheduling preferences. Dot-sourcing never changes a process.
$script:GamingSystemRoot=$PSScriptRoot
function Initialize-GamingSystemNative {
    if('GamingSystemNative' -as [type]){return}
    Add-Type -Path (Join-Path $script:GamingSystemRoot 'GamingSystemNative.cs')
}
function Get-GamingSystemStateDirectory {
    $path=Join-Path $script:GamingSystemRoot 'state'
    if(-not(Test-Path -LiteralPath $path -PathType Container)){New-Item -ItemType Directory -Path $path -Force | Out-Null}
    return $path
}
function Read-GamingSystemJson {
    param([ValidateSet('game-process-preferences','game-process-snapshots','memory-preferences')][string]$Name)
    $path=Join-Path (Get-GamingSystemStateDirectory) ($Name+'.json')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    try {return (Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json)} catch {throw ('Could not read '+$Name+'.json. The saved file was preserved.')}
}
function Write-GamingSystemJson {
    param([ValidateSet('game-process-preferences','game-process-snapshots','memory-preferences')][string]$Name,$Value)
    $folder=Get-GamingSystemStateDirectory;$pending=Join-Path $folder ($Name+'.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination (Join-Path $folder ($Name+'.json')) -Force
}
function Get-GamingCpuTopology {
    Initialize-GamingSystemNative
    $groups=[int][GamingSystemNative]::GetActiveProcessorGroupCount();$count=[int][GamingSystemNative]::GetActiveProcessorCount(65535)
    [pscustomobject]@{LogicalProcessorCount=$count;ProcessorGroups=$groups;SupportsAffinity=($groups -eq 1 -and [IntPtr]::Size -eq 8);Message=$(if($groups -ne 1){'Priority is available. Core selection is disabled on multi-group CPUs to avoid restricting a game to the wrong processor group.'}else{'Logical processors include SMT threads. Let Windows use all processors unless a repeatable benchmark supports a restriction.'})}
}
function Get-GamingProcessPreference {
    param([Parameter(Mandatory=$true)][string]$GameId)
    $saved=Read-GamingSystemJson 'game-process-preferences'
    if($saved -and -not(Test-GamingProcessPreferencesData $saved)){throw 'Invalid or unsupported process preferences. The file was preserved.'}
    $value=@($saved.Games | Where-Object GameId -eq $GameId | Select-Object -First 1)
    if($value.Count){return $value[0]}
    [pscustomobject]@{GameId=$GameId;Priority='Unchanged';LogicalProcessors=@();ApplyOnLaunch=$false}
}
function Test-GamingProcessPreferencesData {
    param($Value)
    if(-not $Value -or ($Value.Version -isnot [int] -and $Value.Version -isnot [long]) -or $Value.Version -ne 1 -or @($Value.PSObject.Properties.Name | Where-Object {$_ -notin @('Version','Games')}).Count){return $false}
    if($null -eq $Value.Games -or @($Value.Games).Count -gt 2000){return $false}
    $seen=@{}
    foreach($entry in @($Value.Games)){
        if(-not $entry -or @($entry.PSObject.Properties.Name|Where-Object{$_ -notin @('GameId','Priority','LogicalProcessors','ApplyOnLaunch')}).Count){return $false}
        if($entry.GameId -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.GameId) -or $entry.GameId.Length -gt 180 -or $entry.GameId -match '[\x00-\x1F]' -or $seen.ContainsKey($entry.GameId)){return $false}
        $seen[$entry.GameId]=$true
        if($entry.Priority -notin @('Unchanged','Idle','BelowNormal','Normal','AboveNormal','High') -or $entry.ApplyOnLaunch -isnot [bool] -or $null -eq $entry.LogicalProcessors){return $false}
        $indices=@($entry.LogicalProcessors)
        if($indices.Count -gt 64 -or @($indices | Where-Object {($_ -isnot [int] -and $_ -isnot [long]) -or $_ -lt 0 -or $_ -gt 63}).Count -or @($indices | Sort-Object -Unique).Count -ne $indices.Count){return $false}
    }
    return $true
}
function Save-GamingProcessPreference {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId,[ValidateSet('Unchanged','Idle','BelowNormal','Normal','AboveNormal','High')][string]$Priority='Unchanged',[int[]]$LogicalProcessors=@(),[bool]$ApplyOnLaunch=$false)
    if([string]::IsNullOrWhiteSpace($GameId) -or $GameId.Length -gt 180){throw 'Choose a valid game.'}
    $topology=Get-GamingCpuTopology
    $indices=@($LogicalProcessors | Sort-Object -Unique)
    if($indices.Count -and -not $topology.SupportsAffinity){throw $topology.Message}
    if(@($indices | Where-Object {$_ -lt 0 -or $_ -ge $topology.LogicalProcessorCount}).Count){throw 'A selected logical processor is not present on this PC.'}
    $saved=Read-GamingSystemJson 'game-process-preferences'
    if($saved -and -not(Test-GamingProcessPreferencesData $saved)){throw 'Invalid or unsupported process preferences. The file was preserved.'}
    $rows=@($saved.Games | Where-Object {$_ -and $_.GameId -ne $GameId})
    $entry=[pscustomobject]@{GameId=$GameId;Priority=$Priority;LogicalProcessors=$indices;ApplyOnLaunch=$ApplyOnLaunch}
    $rows+=$entry;Write-GamingSystemJson 'game-process-preferences' ([pscustomobject]@{Version=1;Games=$rows})
    [pscustomobject]@{Success=$true;Message='CPU preferences saved. They affect only the selected game process when applied.';Preference=$entry}
}
function Get-GamingProcessExecutable {
    param([string]$GameId)
    $game=Get-GameLibrary | Where-Object Id -eq $GameId | Select-Object -First 1
    if(-not $game -or -not $game.ExecutablePath){throw 'Select the actual game EXE first.'}
    $path=[IO.Path]::GetFullPath([string]$game.ExecutablePath)
    if($path -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($path) -ine '.exe'){throw 'Select a local game EXE.'}
    $name=[IO.Path]::GetFileNameWithoutExtension($path)
    if($path.StartsWith(($env:WINDIR.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase) -or $name -match '^(?i)(GamingMode|Framewell|steam|discord|explorer|powershell|pwsh|cmd|conhost|msmpeng|securityhealthservice|nissrv|lsass|csrss|smss|wininit|services|svchost|winlogon|dwm|taskmgr|eac_launcher|EasyAntiCheat.*|BEService.*|vgc|vgtray|nvcontainer|nvidia.*|RiotClientServices|EADesktop|EpicGamesLauncher)$') {throw 'Choose the game renderer, not Windows, security software, this app, or a launcher.'}
    return $path
}
function Read-GamingNativeProcess {
    param([int]$ProcessId)
    Initialize-GamingSystemNative
    return [GamingSystemNative]::ReadProcess($ProcessId)
}
function Write-GamingNativeProcess {
    param([int]$ProcessId,[string]$ExecutablePath,[long]$StartTimeTicks,[string]$Priority,[uint64]$Affinity,[bool]$ChangeAffinity)
    Initialize-GamingSystemNative
    return [GamingSystemNative]::WriteProcess($ProcessId,$ExecutablePath,$StartTimeTicks,$Priority,$Affinity,$ChangeAffinity)
}
function Get-GamingProcessTargets {
    param([Parameter(Mandatory=$true)][string]$GameId)
    $path=Get-GamingProcessExecutable $GameId
    $name=[IO.Path]::GetFileNameWithoutExtension($path)
    foreach($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)){
        try {
            $row=Read-GamingNativeProcess $process.Id
            if($row.ExecutablePath -ine $path){continue}
            [pscustomobject]@{ProcessId=$row.ProcessId;Name=$name;ExecutablePath=$row.ExecutablePath;StartTimeTicks=$row.StartTimeTicks;StartTimeUtc=([datetime]::new($row.StartTimeTicks,[DateTimeKind]::Utc)).ToString('o');Priority=$row.Priority;LogicalProcessors=@([GamingSystemNative]::Indices($row.Affinity));Affinity=[uint64]$row.Affinity;SystemAffinity=[uint64]$row.SystemAffinity}
        } catch { }
    }
}
function Invoke-GamingProcessTuning {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId,[int]$ProcessId=0)
    $results=@()
    try {
        $path=Get-GamingProcessExecutable $GameId;$preference=Get-GamingProcessPreference $GameId;$topology=Get-GamingCpuTopology
        if($preference.Priority -notin @('Unchanged','Idle','BelowNormal','Normal','AboveNormal','High')){throw 'Invalid saved process priority.'}
        $indices=@($preference.LogicalProcessors | ForEach-Object {[int]$_})
        if($indices.Count -and -not $topology.SupportsAffinity){throw $topology.Message}
        $targets=@(if($ProcessId -gt 0){[pscustomobject]@{ProcessId=$ProcessId}}else{Get-GamingProcessTargets $GameId})
        if(-not $targets.Count){throw 'The selected game is not running or Windows denied access. Start its actual game EXE, then apply again.'}
        $journal=Read-GamingSystemJson 'game-process-snapshots'
        if($journal -and [int]$journal.Version -ne 1){throw 'Unsupported CPU restore snapshot version.'}
        $entries=@(if($journal){$journal.Entries})
        foreach($target in $targets){
            try {
                $current=Read-GamingNativeProcess ([int]$target.ProcessId)
                if($current.ExecutablePath -ine $path){throw 'The selected process no longer belongs to this game.'}
                if($current.Priority -in @('RealTime','Unknown')){throw 'This process has an unsupported priority. It was left unchanged.'}
                $changeAffinity=[bool]$topology.SupportsAffinity
                $wantedAffinity=if($changeAffinity){if($indices.Count){[GamingSystemNative]::Mask([int[]]$indices)}else{[uint64]$current.SystemAffinity}}else{[uint64]0}
                if($changeAffinity -and -not $wantedAffinity){throw 'Windows did not expose a usable affinity mask for this process.'}
                $key=([string]$current.ProcessId)+':'+([string]$current.StartTimeTicks)
                $entry=$entries | Where-Object Key -eq $key | Select-Object -First 1
                if($entry -and $entry.Status -notin @('Applied','Pending')){$entries=@($entries | Where-Object Key -ne $key);$entry=$null}
                if(-not $entry){
                    $entry=[pscustomobject]@{Key=$key;GameId=$GameId;ProcessId=$current.ProcessId;ExecutablePath=$path;StartTimeTicks=([string]$current.StartTimeTicks);BeforePriority=$current.Priority;BeforeAffinity=([string]$current.Affinity);AppliedPriority=$current.Priority;AppliedAffinity=([string]$current.Affinity);AffinityChanged=$false;Status='Pending'}
                    $entries+=$entry
                }
                $entry.AppliedPriority=if($preference.Priority -eq 'Unchanged'){$current.Priority}else{$preference.Priority}
                $entry.AppliedAffinity=if($changeAffinity){[string]$wantedAffinity}else{[string]$current.Affinity};$entry.AffinityChanged=$changeAffinity;$entry.Status='Pending'
                Write-GamingSystemJson 'game-process-snapshots' ([pscustomobject]@{Version=1;Entries=$entries})
                $after=Write-GamingNativeProcess -ProcessId $current.ProcessId -ExecutablePath $path -StartTimeTicks $current.StartTimeTicks -Priority $preference.Priority -Affinity $wantedAffinity -ChangeAffinity $changeAffinity
                if($after.Priority -ne $entry.AppliedPriority -or ($changeAffinity -and [string]$after.Affinity -ne $entry.AppliedAffinity)){throw 'Windows did not retain the requested CPU settings.'}
                $entry.Status='Applied';Write-GamingSystemJson 'game-process-snapshots' ([pscustomobject]@{Version=1;Entries=$entries})
                $results+=[pscustomobject]@{ProcessId=$current.ProcessId;Success=$true;Message='CPU settings applied to this game process.'}
            } catch {$results+=[pscustomobject]@{ProcessId=$target.ProcessId;Success=$false;Message=$_.Exception.Message}}
        }
        [pscustomobject]@{Success=(@($results | Where-Object {-not $_.Success}).Count -eq 0);Message=($results.Message -join ' ');Results=$results}
    } catch {[pscustomobject]@{Success=$false;Message=$_.Exception.Message;Results=$results}}
}
function Restore-GamingProcessTuning {
    param([Parameter(Mandatory=$true)][string]$GameId)
    $results=@()
    try {
        $journal=Read-GamingSystemJson 'game-process-snapshots';if(-not $journal){return [pscustomobject]@{Success=$true;Message='No CPU settings need restoring.';Results=@()}}
        if([int]$journal.Version -ne 1){throw 'Unsupported CPU restore snapshot version.'}
        foreach($entry in @($journal.Entries | Where-Object {$_.GameId -eq $GameId -and $_.Status -in @('Applied','Pending')})){
            try {
                if($entry.BeforePriority -notin @('Idle','BelowNormal','Normal','AboveNormal','High')){throw 'Invalid CPU restore priority.'}
                $current=Read-GamingNativeProcess ([int]$entry.ProcessId)
                if($current.StartTimeTicks -ne [long]$entry.StartTimeTicks -or $current.ExecutablePath -ine $entry.ExecutablePath){$entry.Status='ProcessEnded';$results+=[pscustomobject]@{ProcessId=$entry.ProcessId;Success=$true;Message='Original game process ended; its replacement was left unchanged.'};continue}
                $priority=if($current.Priority -eq $entry.AppliedPriority){$entry.BeforePriority}else{'Unchanged'}
                $affinity=([bool]$entry.AffinityChanged -and [string]$current.Affinity -eq [string]$entry.AppliedAffinity)
                $after=Write-GamingNativeProcess -ProcessId $current.ProcessId -ExecutablePath $entry.ExecutablePath -StartTimeTicks $current.StartTimeTicks -Priority $priority -Affinity ([uint64]$entry.BeforeAffinity) -ChangeAffinity $affinity
                $entry.Status='Restored';$results+=[pscustomobject]@{ProcessId=$entry.ProcessId;Success=$true;Message='Original CPU settings restored; later manual changes were preserved.'}
            } catch {
                if(-not(Get-Process -Id ([int]$entry.ProcessId) -ErrorAction SilentlyContinue)){$entry.Status='ProcessEnded';$results+=[pscustomobject]@{ProcessId=$entry.ProcessId;Success=$true;Message='Game process has ended.'}}
                else {$results+=[pscustomobject]@{ProcessId=$entry.ProcessId;Success=$false;Message=$_.Exception.Message}}
            }
        }
        Write-GamingSystemJson 'game-process-snapshots' $journal
        [pscustomobject]@{Success=(@($results|Where-Object {-not $_.Success}).Count -eq 0);Message=$(if($results.Count){$results.Message -join ' '}else{'No CPU settings need restoring.'});Results=$results}
    }catch{[pscustomobject]@{Success=$false;Message=$_.Exception.Message;Results=$results}}
}
function Invoke-GamingLaunchProcessTuning {
    # Bounded launch integration; no permanent game watcher is installed.
    param([Parameter(Mandatory=$true)][string]$GameId,[ValidateRange(0,30)][int]$WaitSeconds=15)
    $preference=Get-GamingProcessPreference $GameId
    if(-not $preference.ApplyOnLaunch){return [pscustomobject]@{Success=$true;Message='Automatic CPU tuning is off.';Applied=$false}}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    do {
        $targets=@(Get-GamingProcessTargets $GameId)
        if($targets.Count){return Invoke-GamingProcessTuning $GameId}
        if($clock.Elapsed.TotalSeconds -ge $WaitSeconds){break}
        Start-Sleep -Milliseconds 400
    }while($true)
    [pscustomobject]@{Success=$false;Applied=$false;Message='The renderer did not appear during the launch window. Use Apply CPU settings once the game is running.'}
}
