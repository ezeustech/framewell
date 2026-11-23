$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'GamingMode.ps1') -LibraryOnly
$testRoot=Join-Path $PSScriptRoot ('test-results\'+[Guid]::NewGuid().ToString('N'))
$script:GamingStateDirectory=$testRoot
$script:GamingProfilesRoot=$testRoot
$script:GamingStatePath=Join-Path $testRoot 'session.json'
$script:Calls=New-Object 'System.Collections.Generic.List[string]'
$script:RestoredIds=@()
$script:FailMedia=$false
function Assert-Check($Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Get-GamingBootId {'test-boot'}
function Get-GMMediaDefinitions { @([pscustomobject]@{Key='Jellyfin'}) }
function Get-OptionalAppSnapshot {
    [pscustomobject]@{Id='Firefox';Name='Firefox';Processes=@()}
    [pscustomobject]@{Id='ChatGPT';Name='ChatGPT';Processes=@()}
}
function Get-MediaStackSnapshot {[pscustomobject]@{SchemaVersion=1;Components=@([pscustomobject]@{Key='Jellyfin';Running=$true})}}
function Get-OptionalHelperSnapshot([bool]$DeepTrim) {[pscustomobject]@{Version=1;Services=@();ISLC=@()}}
function Get-GamingPreferences {[pscustomobject]@{DeepTrim=$true;KeepISLC=$false;CloseChatGPT=$true;PowerMode='Current'}}
function Get-GamingTuningSnapshot($Preferences) {[pscustomobject]@{Version=1;Marker=[Guid]::NewGuid().ToString('N')}}
function Invoke-GamingTuning($Snapshot,$Operation) {[pscustomobject]@{Success=$true;Results=@()}}
function Stop-MediaStack($Snapshot,$OnProgress) {
    $script:Calls.Add('media-stop')
    Assert-Check ((Read-GamingState).Passes.Count -gt 0) 'Snapshot must be saved before anything stops.'
    if($script:FailMedia){throw 'Injected stop interruption'}
    [pscustomobject]@{Success=$true;Results=@([pscustomobject]@{Name='Jellyfin';Status='Stopped';Success=$true})}
}
function Start-MediaStack($Snapshot,[switch]$All,$OnProgress) {
    $script:Calls.Add($(if($All){'media-all'}else{'media-restore'}))
    [pscustomobject]@{Success=$true;Results=@([pscustomobject]@{Name='Jellyfin';Status='Started';Success=$true})}
}
function Invoke-OptionalHelpers($Snapshot,$Operation,$PreviousResults,[switch]$RecoverSnapshot) {
    $script:Calls.Add('helpers-'+$Operation)
    if($RecoverSnapshot){$script:HelperRecovered=$true}
    [pscustomobject]@{Success=$true;Results=@()}
}
function Stop-OptionalApps($Snapshot,[bool]$IncludeChatGPT,[switch]$ChatGPTOnly) {
    if($ChatGPTOnly) {
        $script:Calls.Add('chat-stop')
        [pscustomobject]@{Id='ChatGPT';Name='ChatGPT';Closed=$false;Status='Skipped';Detail='Protected test host'}
    } else {
        $script:Calls.Add('apps-stop')
        [pscustomobject]@{Id='Firefox';Name='Firefox';Closed=$true;Status='Closed';Detail='Test closed'}
    }
}
function Start-OptionalApps($Snapshot,$Results=$null) {
    $script:Calls.Add('apps-restore')
    $wanted=if($null -eq $Results){@($Snapshot | ForEach-Object Id)}else{@($Results | Where-Object Closed | ForEach-Object Id)}
    $script:RestoredIds+=@($wanted)
    foreach($id in $wanted){[pscustomobject]@{Id=$id;Name=$id;Restored=$true;Status='Started';Detail='Test restored'}}
}

$enter=Invoke-GamingAction 'Enter'
Assert-Check (-not $enter.Success) 'Skipped ChatGPT should report partial completion.'
Assert-Check ((Read-GamingState).Active) 'Partial mode must retain its restore state.'
Assert-Check (($script:Calls -join ',') -eq 'media-stop,apps-stop,helpers-Stop,chat-stop') 'ChatGPT must close last.'
$media=Invoke-GamingAction 'Media'
Assert-Check ($media.Success -and (Read-GamingState).Mode -eq 'GamingWithMedia') 'Media-only start must preserve the gaming session.'
Assert-Check (($script:RestoredIds -join ',') -eq 'ChatGPT') 'Media profile must start ChatGPT without reopening unrelated apps.'
$script:RestoredIds=@()
$again=Invoke-GamingAction 'Enter'
Assert-Check ((Read-GamingState).Passes.Count -eq 2) 'Repeated Enter must preserve the original snapshot.'
$restore=Invoke-GamingAction 'Restore'
Assert-Check ($restore.Success -and -not (Read-GamingState).Active) 'Successful restore must exit gaming mode.'
Assert-Check (($script:RestoredIds -notcontains 'ChatGPT') -and ($script:RestoredIds -contains 'Firefox')) 'Restore must reopen only apps recorded closed.'
$callCount=$script:Calls.Count
$empty=Invoke-GamingAction 'Restore'
Assert-Check ($empty.Success -and $script:Calls.Count -eq $callCount) 'Second Restore must be a no-op.'
$script:FailMedia=$true
$caught=$false
try{$null=Invoke-GamingAction 'Enter'}catch{$caught=$true}
Assert-Check ($caught -and (Read-GamingState).Active -and (Read-GamingState).LastError -eq 'Injected stop interruption') 'Interrupted shutdown must preserve a recoverable snapshot.'
$script:FailMedia=$false
$script:RestoredIds=@()
$script:HelperRecovered=$false
$recovery=Invoke-GamingAction 'Restore'
Assert-Check ($recovery.Success -and $script:RestoredIds -contains 'Firefox') 'Interrupted mode must support snapshot recovery.'
Assert-Check $script:HelperRecovered 'Interrupted helper shutdown must support snapshot recovery.'
$receipt=[pscustomobject]@{Passed=$true;Checks=11;LiveApplicationsStopped=$false;StateDirectory=$testRoot;CompletedUtc=[datetime]::UtcNow.ToString('o')}
$receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $testRoot 'receipt.json') -Encoding UTF8
$receipt | ConvertTo-Json
