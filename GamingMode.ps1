param(
    [ValidateSet('Panel','Enter','Restore','Media','Preview','Status','WindowsTools','Performance','Games')][string]$Action='Panel',
    [switch]$NoUI,
    [switch]$LibraryOnly
)
$ErrorActionPreference='Stop'
$script:GamingRoot=$PSScriptRoot
$script:GamingStateDirectory=Join-Path $PSScriptRoot 'state'
$script:GamingStatePath=Join-Path $script:GamingStateDirectory 'session.json'
$script:GamingStatusControl=$null
$script:GamingStatusCallback=$null
foreach($module in @('OptionalApps.ps1','MediaStack.ps1','OptionalHelpers.ps1','SessionExtras.ps1','ThemeCatalog.ps1','Performance.ps1','TuningElevation.ps1','GameLibrary.ps1','AppProfiles.ps1','NvidiaProfiles.ps1','NetworkDiagnostics.ps1','FrameBenchmark.ps1','GameProcessTuning.ps1','MemoryTools.ps1','SettingsProfiles.ps1','OptimizerTools.ps1','WindowsGameSettings.ps1','EmbeddedOptimizer.ps1','MacInterface.ps1','ResponsiveUI.ps1','FramewellUpdateUI.ps1')) {
    . (Join-Path $PSScriptRoot $module)
}

function Restart-GamingModeElevated {
    param([ValidateSet('WindowsTools','Performance','Games')][string]$InitialPage='WindowsTools')
    try {
        $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){return [pscustomobject]@{Success=$false;Message='This dashboard already has administrator rights.'}}
        $exe=Join-Path $script:GamingRoot 'GamingMode.exe'
        if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'The Gaming Mode executable is missing.'}
        $current=Get-Process -Id $PID
        if($current.Path -ine $exe){throw 'Open the installed Gaming Mode app before using its administrator restart.'}
        $child=Start-Process -FilePath $exe -ArgumentList @($InitialPage,[string]$PID,[string]$current.StartTime.ToUniversalTime().Ticks) -Verb RunAs -WindowStyle Normal -PassThru -ErrorAction Stop
        [pscustomobject]@{Success=$true;Message='Administrator restart accepted. The current dashboard will close; optional memory tools stop until you enable them again.';ProcessId=$child.Id}
    } catch {[pscustomobject]@{Success=$false;Message=('Administrator restart was not completed: '+$_.Exception.Message)}}
}

function Get-GamingBootId {
    (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
}
function Read-GamingState {
    if(Test-Path -LiteralPath $script:GamingStatePath) {
        $state=Get-Content -LiteralPath $script:GamingStatePath -Raw | ConvertFrom-Json
        if($state.Version -ne 1){throw 'Unrecognized restore file. The saved file has been preserved.'}
        return $state
    }
    return $null
}
function Save-GamingState($State) {
    if(-not(Test-Path -LiteralPath $script:GamingStateDirectory)) {
        New-Item -ItemType Directory -Path $script:GamingStateDirectory -Force | Out-Null
    }
    $State.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
    $temporary=Join-Path $script:GamingStateDirectory 'session.pending.json'
    $State | ConvertTo-Json -Depth 45 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $script:GamingStatePath -Force
}
function Write-GamingStatus([string]$Message) {
    if($script:GamingStatusCallback){& $script:GamingStatusCallback $Message;return}
    if($script:GamingStatusControl) {
        $script:GamingStatusControl.Text=$Message
        $script:GamingStatusControl.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
    }
}
function Get-GamingPreview {
    $preferences=Get-GamingPreferences
    $apps=Get-OptionalAppSnapshot
    $media=Get-MediaStackSnapshot
    $helpers=Get-OptionalHelperSnapshot -DeepTrim:$preferences.DeepTrim
    if($preferences.KeepISLC){$helpers.ISLC=@()}
    $selection=Get-GamingSessionTargets -Preferences $preferences -Apps $apps -Media $media -Helpers $helpers
    [pscustomobject]@{
        ProcessCount=@(Get-Process).Count
        Apps=@($selection.Apps)
        Media=$selection.Media
        Helpers=$selection.Helpers
        State=Read-GamingState
        Preserved=@('Steam','Discord','Active games','Windows and security','Audio and display drivers','Networking and remote access')
    }
}
function New-GamingPass {
    $preferences=Get-GamingPreferences
    $apps=@(Get-OptionalAppSnapshot)
    $helpers=Get-OptionalHelperSnapshot -DeepTrim:$preferences.DeepTrim
    if($preferences.KeepISLC){$helpers.ISLC=@()}
    $selection=Get-GamingSessionTargets -Preferences $preferences -Apps $apps -Media (Get-MediaStackSnapshot) -Helpers $helpers
    [pscustomobject]@{
        Id=[Guid]::NewGuid().ToString('N'); StartedUtc=[DateTime]::UtcNow.ToString('o')
        Apps=@($selection.Apps); Media=$selection.Media; Helpers=$selection.Helpers; Preferences=$preferences
        Custom=@($selection.Custom);CustomStop=$null;CustomRestore=$null
        Tuning=Get-GamingTuningSnapshot -Preferences $preferences;TuningApply=$null;TuningRestore=$null
        AppStop=$null; MediaStop=$null; HelperStop=$null; ChatStop=$null
        AppRestore=$null; MediaRestore=$null; HelperRestore=$null
    }
}
function Get-GamingResultSuccess($Result) {
    if($null -eq $Result){return $false}
    return [bool]$Result.Success
}
function Invoke-GamingAppStop($Snapshot,[switch]$ChatGPTOnly) {
    $records=@()
    if(@($Snapshot).Count) {
        if($ChatGPTOnly){$records=@(Stop-OptionalApps -Snapshot $Snapshot -IncludeChatGPT:$true -ChatGPTOnly)}
        else{$records=@(Stop-OptionalApps -Snapshot $Snapshot -IncludeChatGPT:$false)}
    }
    foreach($record in $records){
        $record | Add-Member -NotePropertyName Message -NotePropertyValue $record.Detail -Force
        $record | Add-Member -NotePropertyName Success -NotePropertyValue ($record.Status -in @('Closed','AlreadyClosed')) -Force
    }
    [pscustomobject]@{Success=(@($records | Where-Object {-not $_.Success}).Count -eq 0);Results=$records}
}
function Invoke-GamingAppRestore($Snapshot,$Results,[switch]$Recovery) {
    $records=@()
    if(@($Snapshot).Count) {
        if($Recovery){$records=@(Start-OptionalApps -Snapshot $Snapshot)}
        else{$records=@(Start-OptionalApps -Snapshot $Snapshot -Results $Results)}
    }
    foreach($record in $records){
        $record | Add-Member -NotePropertyName Message -NotePropertyValue $record.Detail -Force
        $record | Add-Member -NotePropertyName Success -NotePropertyValue ([bool]$record.Restored) -Force
    }
    [pscustomobject]@{Success=(@($records | Where-Object {-not $_.Success}).Count -eq 0);Results=$records}
}
function Invoke-GamingEnter {
    Write-GamingStatus 'Saving the running apps and media services...'
    $state=Read-GamingState
    if($null -eq $state -or -not $state.Active) {
        $state=[pscustomobject]@{
            Version=1; Active=$true; Mode='Entering'; BootId=Get-GamingBootId
            CreatedUtc=[DateTime]::UtcNow.ToString('o'); UpdatedUtc=''
            BeforeCount=@(Get-Process).Count; AfterCount=$null; Passes=@(); LastError=$null
        }
    }
    $pass=New-GamingPass
    $state.Passes=@($state.Passes)+@($pass)
    $state.Mode='Entering'; $state.Active=$true; $state.LastError=$null
    Save-GamingState $state
    try {
        Write-GamingStatus 'Applying your temporary performance preferences...'
        $pass.TuningApply=Invoke-GamingTuning -Snapshot $pass.Tuning -Operation Apply
        Save-GamingState $state
        Write-GamingStatus 'Stopping Jellyfin, requests, downloads and HTTPS...'
        $pass.MediaStop=if(@($pass.Media.Components).Count){Stop-MediaStack -Snapshot $pass.Media -OnProgress {param($m) Write-GamingStatus $m}}else{[pscustomobject]@{Success=$true;Results=@()}}
        Save-GamingState $state
        Write-GamingStatus 'Closing optional apps. Steam and Discord stay open...'
        $pass.AppStop=Invoke-GamingAppStop -Snapshot $pass.Apps
        Save-GamingState $state
        Write-GamingStatus 'Stopping optional helpers. Windows may request administrator approval...'
        $pass.HelperStop=Invoke-OptionalHelpers -Snapshot $pass.Helpers -Operation Stop
        Save-GamingState $state
        $pass.CustomStop=Invoke-GamingCustomApps -Snapshot @($pass.Custom) -Operation Stop
        Save-GamingState $state
        Write-GamingStatus 'Closing ChatGPT and its tools last...'
        $pass.ChatStop=Invoke-GamingAppStop -Snapshot $pass.Apps -ChatGPTOnly
        $state.AfterCount=@(Get-Process).Count
        $ok=(Get-GamingResultSuccess $pass.TuningApply) -and (Get-GamingResultSuccess $pass.MediaStop) -and (Get-GamingResultSuccess $pass.AppStop) -and (Get-GamingResultSuccess $pass.HelperStop) -and (Get-GamingResultSuccess $pass.ChatStop) -and (Get-GamingResultSuccess $pass.CustomStop)
        $state.Mode=if($ok){'Gaming'}else{'GamingPartial'}
        Save-GamingState $state
        return [pscustomobject]@{Success=$ok;Action='Enter';Mode=$state.Mode;BeforeCount=$state.BeforeCount;AfterCount=$state.AfterCount;Results=@($pass.TuningApply.Results)+@($pass.MediaStop.Results)+@($pass.AppStop.Results)+@($pass.HelperStop.Results)+@($pass.CustomStop.Results)+@($pass.ChatStop.Results)}
    } catch {
        $state.Mode='GamingPartial';$state.LastError=$_.Exception.Message
        Save-GamingState $state
        throw
    }
}
function Invoke-GamingRestore {
    $state=Read-GamingState
    if($null -eq $state -or -not $state.Active) {
        return [pscustomobject]@{Success=$true;Action='Restore';Mode='Normal';Results=@();Message='There is no active Gaming Mode session to restore. Use Start Media Stack to start all media services.'}
    }
    $state.Mode='Restoring';Save-GamingState $state
    $results=@();$allOk=$true
    try {
        # Oldest snapshot first: repeated Enter calls never replace the original restore record.
        foreach($pass in @($state.Passes)) {
            Write-GamingStatus 'Restoring media services that were running...'
            $pass.MediaRestore=if(@($pass.Media.Components).Count){Start-MediaStack -Snapshot $pass.Media -OnProgress {param($m) Write-GamingStatus $m}}else{[pscustomobject]@{Success=$true;Results=@()}}
            $results+=@($pass.MediaRestore.Results)
            $allOk=$allOk -and (Get-GamingResultSuccess $pass.MediaRestore)
            Save-GamingState $state
            Write-GamingStatus 'Restoring optional helpers...'
            if($null -ne $pass.HelperStop) {
                $pass.HelperRestore=Invoke-OptionalHelpers -Snapshot $pass.Helpers -Operation Restore -PreviousResults $pass.HelperStop
            } else {
                $pass.HelperRestore=Invoke-OptionalHelpers -Snapshot $pass.Helpers -Operation Restore -RecoverSnapshot
            }
            $results+=@($pass.HelperRestore.Results)
            $allOk=$allOk -and (Get-GamingResultSuccess $pass.HelperRestore)
            Save-GamingState $state
            Write-GamingStatus 'Reopening the apps Gaming Mode closed...'
            if($null -ne $pass.AppStop -and $null -ne $pass.ChatStop) {
                $closed=@($pass.AppStop.Results)+@($pass.ChatStop.Results)
                $pass.AppRestore=Invoke-GamingAppRestore -Snapshot $pass.Apps -Results $closed
            } else {
                # Recover from interruption after a close but before its result was written.
                $pass.AppRestore=Invoke-GamingAppRestore -Snapshot $pass.Apps -Recovery
            }
            $results+=@($pass.AppRestore.Results)
            $allOk=$allOk -and (Get-GamingResultSuccess $pass.AppRestore)
            if($pass.PSObject.Properties['Custom']){
                $pass.CustomRestore=Invoke-GamingCustomApps -Snapshot @($pass.Custom) -Operation Restore
                $results+=@($pass.CustomRestore.Results);$allOk=$allOk -and $pass.CustomRestore.Success
            }
            Save-GamingState $state
        }
        # Settings nest across repeated activations; unwind newest to oldest.
        for($index=@($state.Passes).Count-1;$index -ge 0;$index--){
            $pass=$state.Passes[$index]
            if($pass.PSObject.Properties['Tuning'] -and $pass.Tuning){
                Write-GamingStatus 'Restoring your previous performance settings...'
                $pass.TuningRestore=Invoke-GamingTuning -Snapshot $pass.Tuning -Operation Restore
                $results+=@($pass.TuningRestore.Results)
                $allOk=$allOk -and (Get-GamingResultSuccess $pass.TuningRestore)
                Save-GamingState $state
            }
        }
        $state.Active=-not $allOk
        $state.Mode=if($allOk){'Normal'}else{'RestorePartial'}
        $state.LastError=$null
        Save-GamingState $state
        return [pscustomobject]@{Success=$allOk;Action='Restore';Mode=$state.Mode;Results=$results}
    } catch {
        $state.Mode='RestorePartial';$state.LastError=$_.Exception.Message
        Save-GamingState $state
        throw
    }
}
function Invoke-GamingMedia {
    Write-GamingStatus 'Starting the full media stack...'
    $result=Invoke-GamingProfile -ProfileId 'media-stack' -Operation Start
    $state=Read-GamingState
    if($state -and $state.Active -and $result.Success) {
        $state.Mode='GamingWithMedia';Save-GamingState $state
    }
    [pscustomobject]@{Success=[bool]$result.Success;Action='Media';Results=@($result.Results);Message='Media stack profile started, including its selected apps.'}
}
function Invoke-GamingAction([string]$RequestedAction) {
    $mutex=New-Object System.Threading.Mutex($false,'Local\GamingModeActions')
    $locked=$false
    try {
        try {$locked=$mutex.WaitOne(0)}catch [System.Threading.AbandonedMutexException] {$locked=$true}
        if(-not $locked){throw 'A Gaming Mode action is already running. Wait for that window to finish.'}
        switch($RequestedAction) {
            'Enter' {Invoke-GamingEnter}
            'Restore' {Invoke-GamingRestore}
            'Media' {Invoke-GamingMedia}
            'Preview' {Get-GamingPreview}
            'Status' {Read-GamingState}
            default {throw 'Unknown Gaming Mode action.'}
        }
    } finally {
        if($locked){$mutex.ReleaseMutex()}
        $mutex.Dispose()
    }
}


if(-not $LibraryOnly) {
    if($NoUI) {
        Invoke-GamingAction $Action | ConvertTo-Json -Depth 45
    } else {
        try {Show-MacGamingPanel -InitialAction $Action}
        finally {if(Get-Command Stop-GamingMemoryTools -ErrorAction SilentlyContinue){Stop-GamingMemoryTools|Out-Null}}
    }
}
