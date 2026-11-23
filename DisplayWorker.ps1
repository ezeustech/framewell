param([Parameter(Mandatory=$true)][string]$RequestPath)
$ErrorActionPreference='Stop'
$folder=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'state')).TrimEnd('\')
$path=[IO.Path]::GetFullPath($RequestPath)
if([IO.Path]::GetDirectoryName($path) -ine $folder -or [IO.Path]::GetFileName($path) -notmatch '^display-([a-f0-9]{32})\.request\.json$'){throw 'Invalid display worker request.'}
$token=$Matches[1];$stem=Join-Path $folder ('display-'+$token)
$applied=$false;$kept=$false;$previousKey='';$parent=$null;$displayLock=$null;$ownsDisplayLock=$false
function Write-DisplayStatus([bool]$Success,[bool]$Confirm,[string]$Message,[datetime]$Deadline=[datetime]::MinValue,[string]$State='Failed'){
    $value=[pscustomobject]@{Token=$token;ConfirmationToken=$token;Success=$Success;RequiresConfirmation=$Confirm;State=$State;Message=$Message;PreviousKey=$previousKey;TimeoutSeconds=15;DeadlineUtc=$Deadline.ToUniversalTime().ToString('o')}
    [IO.File]::WriteAllText(($stem+'.status.pending'),($value|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    if([IO.File]::Exists($stem+'.status.json')){[IO.File]::Replace(($stem+'.status.pending'),($stem+'.status.json'),[NullString]::Value)}else{[IO.File]::Move(($stem+'.status.pending'),($stem+'.status.json'))}
}
try {
    if((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Display requests require ordinary local files.'}
    if((Get-Item -LiteralPath $path).Length -gt 8192 -or [datetime]::UtcNow.Subtract((Get-Item -LiteralPath $path).LastWriteTimeUtc).TotalSeconds -gt 10){throw 'Display request expired or is too large.'}
    $request=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($request.Version -ne 1 -or $request.Token -ne $token -or @($request.PSObject.Properties.Name|Where-Object{$_ -notin @('Version','Token','Key','ParentProcessId','ParentStartTicks')}).Count){throw 'Invalid display request data.'}
    $parent=Get-Process -Id ([int]$request.ParentProcessId) -ErrorAction Stop
    if($parent.StartTime.ToUniversalTime().Ticks -ne [long]$request.ParentStartTicks -or $parent.Path -ine (Join-Path $PSScriptRoot 'GamingMode.exe')){throw 'Display request no longer belongs to this app instance.'}
    $parentHandle=$parent.Handle
    # One primary display preview per Windows session, including other app copies.
    $displayLock=New-Object Threading.Mutex($false,'Local\GamingModeDisplayPreview-v1')
    try{$ownsDisplayLock=$displayLock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsDisplayLock=$true}
    if(-not $ownsDisplayLock){throw 'Another display preview is still active. Keep or revert it before starting another.'}
    [void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'GamingMode.exe'))
    if(-not('GamingWindowsDisplay' -as [type])){throw 'The display API is missing from this build.'}
    $key=[string]$request.Key
    if(-not @([GamingWindowsDisplay]::Modes()|Where-Object Key -ceq $key).Count){throw 'Display mode is no longer supported.'}
    $previousKey=[GamingWindowsDisplay]::CurrentKey()
    # Set before calling so a failed readback still attempts to undo a changed mode.
    $applied=$true;[GamingWindowsDisplay]::Apply($key,$false)
    $deadline=[datetime]::UtcNow.AddSeconds(15)
    Write-DisplayStatus $true $true 'Keep this refresh rate? It will revert automatically after 15 seconds.' $deadline 'Preview'
    while(-not $parent.HasExited -and [datetime]::UtcNow -lt $deadline -and -not(Test-Path -LiteralPath ($stem+'.revert'))){
        if(Test-Path -LiteralPath ($stem+'.keep')){
            $confirmation=(Get-Content -LiteralPath ($stem+'.keep') -Raw).Trim()
            if($confirmation -eq $token -and [GamingWindowsDisplay]::CurrentKey() -ceq $key){[GamingWindowsDisplay]::Apply($key,$true);$kept=$true;break}
        }
        Start-Sleep -Milliseconds 100
    }
    if($kept){Write-DisplayStatus $true $false 'Display refresh rate kept and saved.' -State 'Kept'}
    else {[GamingWindowsDisplay]::Apply($previousKey,$false);$applied=$false;Write-DisplayStatus $true $false 'Original display refresh rate restored.' -State 'Reverted'}
} catch {
    $message=$_.Exception.Message
    if($applied -and -not $kept -and $previousKey){try{[GamingWindowsDisplay]::Apply($previousKey,$false);$applied=$false}catch{$message+=' Automatic restore could not be verified: '+$_.Exception.Message}}
    Write-DisplayStatus $false $false $message
} finally {
    if($applied -and -not $kept -and $previousKey){try{[GamingWindowsDisplay]::Apply($previousKey,$false)}catch{}}
    if($parent){$parent.Dispose()}
    if($displayLock){if($ownsDisplayLock){$displayLock.ReleaseMutex()};$displayLock.Dispose()}
}
