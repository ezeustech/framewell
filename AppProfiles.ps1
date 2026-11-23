# Named, editable local app groups. Importing this module never starts/stops apps.
$script:GamingProfilesRoot=$PSScriptRoot
function Get-GamingDefaultProfiles {
    $media=@(Get-GMMediaDefinitions|ForEach-Object Key)
    $apps=@(Get-OmCatalog|Where-Object Id -ne 'ChatGPT'|ForEach-Object Id)
    $mediaApps=@();if($media.Count){$mediaApps=@('ChatGPT')}
    @(
        [pscustomobject]@{Id='media-stack';Name='Media stack';Kind='Apps';Description='Your streaming, downloads and companion apps. Choose components or add your own EXEs.';MediaKeys=$media;AppIds=$mediaApps;CustomExecutables=@()},
        [pscustomobject]@{Id='super-performance';Name='Super Performance';Kind='Performance';Description='Close selected background apps and the media stack; apply your saved session preferences. Steam and Discord stay running.';MediaKeys=$media;AppIds=$apps;CustomExecutables=@()}
    )
}
function ConvertTo-GamingProfile {
    param($Profile,[switch]$New,[switch]$Read)
    $id=[string]$Profile.Id
    if(-not $id -and $New){$id='profile-'+[guid]::NewGuid().ToString('N')}
    if($id -notin @('media-stack','super-performance') -and $id -notmatch '^profile-[a-f0-9]{32}$'){throw 'Invalid profile identifier.'}
    $name=([string]$Profile.Name).Trim()
    if(-not $name -or $name.Length -gt 100 -or $name -match '[\x00-\x1F]'){throw 'Choose a profile name between 1 and 100 characters.'}
    $media=@($Profile.MediaKeys|Where-Object{$_}|Select-Object -Unique);$apps=@($Profile.AppIds|Where-Object{$_}|Select-Object -Unique)
    $mediaAllowed=@(Get-GMMediaDefinitions|ForEach-Object Key);$appAllowed=@(Get-OmCatalog|ForEach-Object Id)
    if(@($media|Where-Object{$_ -notin $mediaAllowed}).Count -or @($apps|Where-Object{$_ -notin $appAllowed}).Count){throw 'A profile contains an unknown app or service.'}
    # The tray starts the server itself; make this dependency explicit and visible.
    if('JellyfinTray' -in $media -and 'Jellyfin' -notin $media){$media+=@('Jellyfin')}
    $paths=@(@(foreach($path in @($Profile.CustomExecutables)){if($path){if(-not(Test-GamingProfileExecutable $path -AllowMissing:$Read)){throw 'Custom profile entries must be ordinary local application EXEs; Windows, security, drivers, Steam and Discord are preserved.'};[IO.Path]::GetFullPath($path)}})|Select-Object -Unique)
    [pscustomobject]@{Id=$id;Name=$name;Kind=$(if($id -eq 'super-performance'){'Performance'}else{'Apps'});Description=([string]$Profile.Description).Substring(0,[math]::Min(500,([string]$Profile.Description).Length));MediaKeys=$media;AppIds=$apps;CustomExecutables=$paths}
}
function Get-GamingProfiles {
    $profiles=@(Get-GamingDefaultProfiles);$path=Join-Path $script:GamingProfilesRoot 'state\profiles.json'
    if(Test-Path -LiteralPath $path){
        $saved=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
        if([int]$saved.Version -ne 2){throw 'Unknown app-profile format. The file has been preserved.'}
        foreach($item in @($saved.Profiles)){$p=ConvertTo-GamingProfile $item -Read;$profiles=@($profiles|Where-Object Id -ne $p.Id)+@($p)}
    }
    return @($profiles)
}
function Save-GamingProfile {
    param([Parameter(Mandatory=$true)]$Profile)
    $valid=ConvertTo-GamingProfile $Profile -New
    $all=@(Get-GamingProfiles|Where-Object Id -ne $valid.Id)+@($valid)
    $folder=Join-Path $script:GamingProfilesRoot 'state';[void][IO.Directory]::CreateDirectory($folder)
    $pending=Join-Path $folder ('profiles.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    [pscustomobject]@{Version=2;Profiles=$all}|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination (Join-Path $folder 'profiles.json') -Force
    return $valid
}
function Test-GamingProfileExecutable {
    param([string]$Path,[switch]$AllowMissing)
    if($AllowMissing){if($Path -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($Path) -ine '.exe'){return $false}}
    elseif(-not(Test-GamingLocalExecutable $Path)){return $false}
    $full=[IO.Path]::GetFullPath($Path)
    if($full.StartsWith(([IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){return $false}
    if([IO.Path]::GetFileName($full) -match '(?i)^(steam.*|discord.*|gamingmode|framewell|powershell|pwsh|cmd|wscript|cscript|rundll32|regsvr32|msiexec|msmpeng|securityhealth.*|nvcontainer|nvdisplay.container|dwm|explorer|lsass|services|svchost|csrss|winlogon|fontdrvhost|audiodg|.*anticheat.*|.*battleye.*|vgc|vgtray|.*defender.*|.*antimalware.*)\.exe$'){return $false}
    if($full -match '(?i)\\(?:Windows Defender|Windows Defender Advanced Threat Protection|Chrome Remote Desktop|EasyAntiCheat[^\\]*|BattlEye|Riot Vanguard|NVIDIA Corporation|DriverStore)\\'){return $false}
    return $true
}
function Get-GamingCustomProfileExecutable {
    Add-Type -AssemblyName System.Windows.Forms
    $picker=New-Object System.Windows.Forms.OpenFileDialog;$picker.Title='Add an application to this profile';$picker.Filter='Applications (*.exe)|*.exe';$picker.CheckFileExists=$true
    try{if($picker.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK){if(-not(Test-GamingProfileExecutable $picker.FileName)){throw 'This executable is protected or not a normal local application.'};return $picker.FileName}}finally{$picker.Dispose()}
}
function Get-GamingProfileComponents {
    $media=Get-MediaStackSnapshot;$apps=@(Get-OptionalAppSnapshot)
    Save-GamingKnownApps $apps
    [pscustomobject]@{Media=@($media.Components|ForEach-Object{[pscustomobject]@{Id=$_.Key;Name=$_.Name;Running=$_.Running}});Apps=@(Get-OmCatalog|ForEach-Object{[pscustomobject]@{Id=$_.Id;Name=$_.Name;Running=($_.Id -in @($apps.Id))}})}
}
function Save-GamingKnownApps {
    param([object[]]$Apps)
    $folder=Join-Path $script:GamingProfilesRoot 'state';$path=Join-Path $folder 'known-apps.json';$known=@()
    if(Test-Path -LiteralPath $path){try{$known=@(Get-Content -LiteralPath $path -Raw|ConvertFrom-Json)}catch{}}
    foreach($app in @($Apps)){if($app){$known=@($known|Where-Object Id -ne $app.Id)+@($app)}}
    [void][IO.Directory]::CreateDirectory($folder)
    ConvertTo-Json -InputObject @($known) -Depth 12|Set-Content -LiteralPath $path -Encoding UTF8
}
function Get-GamingAppLaunchSnapshot {
    param([string[]]$AppIds)
    $live=@(Get-OptionalAppSnapshot);Save-GamingKnownApps $live
    $known=@(Get-Content -LiteralPath (Join-Path $script:GamingProfilesRoot 'state\known-apps.json') -Raw|ConvertFrom-Json)
    $catalog=@(Get-OmCatalog)
    foreach($id in $AppIds){
        $entry=$catalog|Where-Object Id -eq $id|Select-Object -First 1
        if(-not $entry){continue}
        $record=$known|Where-Object Id -eq $id|Select-Object -First 1
        # Packaged apps resolve their current approved activation ID at launch.
        # EXE records are revalidated so an app update cannot leave a stale cached path.
        $exe=''
        if(-not $entry.PackageFamily -and $id -ne 'ChatGPT'){$exe=Resolve-OmLaunchExecutable -Entry $entry -PreviousPath ([string]$record.Restore.ExecutablePath)}
        [pscustomobject]@{Id=$id;Name=$entry.Name;Policy=$entry.Policy;Processes=@();Restore=[pscustomobject]@{Kind=$(if($entry.PackageFamily -or $id -eq 'ChatGPT'){'Appx'}else{'Exe'});ExecutablePath=$exe;Arguments=[string]$entry.RestoreArgs;AppId=''}}
    }
}
function Get-GamingCustomSnapshot {
    param([string[]]$Paths)
    if(-not @($Paths).Count){return @()}
    $all=@(Get-CimInstance Win32_Process)
    foreach($path in $Paths){
        if(-not(Test-GamingProfileExecutable $path -AllowMissing)){continue}
        $full=[IO.Path]::GetFullPath($path)
        [pscustomobject]@{Path=$full;Name=[IO.Path]::GetFileNameWithoutExtension($full);Processes=@($all|Where-Object{$_.ExecutablePath -ieq $full}|ForEach-Object{ConvertTo-OmIdentity $_})}
    }
}
function Invoke-GamingCustomApps {
    param([object[]]$Snapshot,[ValidateSet('Start','Stop','Restore')][string]$Operation)
    $results=@()
    foreach($entry in @($Snapshot)){
        try{
            if($Operation -eq 'Restore' -and -not @($entry.Processes).Count){continue}
            if($Operation -eq 'Stop' -and -not @($entry.Processes).Count){
                $results+=[pscustomobject]@{Name=$entry.Name;Success=$true;Status='AlreadyClosed';Message='No captured process was running.'};continue
            }
            if(-not(Test-GamingProfileExecutable $entry.Path)){throw 'The configured application is protected, missing, or moved.'}
            $live=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -ieq $entry.Path})
            if($Operation -eq 'Stop'){
                $remaining=@()
                foreach($identity in @($entry.Processes)){
                    $verified=Get-OmVerifiedProcess $identity;if(-not $verified){continue}
                    $p=Get-Process -Id $identity.ProcessId -ErrorAction Stop
                    if($p.MainWindowHandle -eq [intptr]::Zero -or -not $p.CloseMainWindow()){$remaining+=@($identity);continue}
                    $deadline=[datetime]::UtcNow.AddSeconds(4)
                    while(-not $p.HasExited -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 150}
                    if(-not $p.HasExited){$remaining+=@($identity)}
                }
                $ok=$remaining.Count -eq 0;$status=if($ok){'Closed'}else{'NeedsAttention'};$message=if($ok){'Closed normally.'}else{'Application stayed open or needs a save confirmation; it was not forced closed.'}
            }else{
                if($live.Count){$ok=$true;$status='AlreadyRunning';$message='Already running.'}else{
                    Start-Process -FilePath $entry.Path -WorkingDirectory ([IO.Path]::GetDirectoryName($entry.Path)) -WindowStyle Normal -ErrorAction Stop|Out-Null
                    $ok=$true;$status='LaunchRequested';$message='Launch requested; the app controls its own startup.'
                }
            }
            $results+=[pscustomobject]@{Name=$entry.Name;Success=$ok;Status=$status;Message=$message}
        }catch{$results+=[pscustomobject]@{Name=$entry.Name;Success=$false;Status='Failed';Message=$_.Exception.Message}}
    }
    [pscustomobject]@{Success=(@($results|Where-Object{-not $_.Success}).Count -eq 0);Results=$results}
}
function Get-GamingSessionTargets {
    param($Preferences,$Apps,$Media,$Helpers)
    $profiles=@(Get-GamingProfiles);$super=$profiles|Where-Object Id -eq 'super-performance';$mediaProfile=$profiles|Where-Object Id -eq 'media-stack'
    $wantedApps=@($super.AppIds)+@($mediaProfile.AppIds)
    $groups=@{}
    foreach($category in @('Browsers','Launchers','CloudSync','MediaApps','DesktopExtras')){$groups['Close'+$category]=@(Get-OmCatalog|Where-Object Category -eq $category|ForEach-Object Id)}
    foreach($key in @($groups.Keys)){if($Preferences.PSObject.Properties[$key] -and -not $Preferences.$key){$wantedApps=@($wantedApps|Where-Object{$_ -notin $groups[$key]})}}
    $Media.Components=@($Media.Components|Where-Object{$_.Key -in @($super.MediaKeys)})
    $helperSwitch=@{WSearch='PauseSearch';Spooler='PausePrinting';Fax='PausePrinting';OVRService='PauseVR';LGHUBUpdaterService='PausePeripheralHelpers';logi_lamparray_service='PausePeripheralHelpers'}
    $Helpers.Services=@($Helpers.Services|Where-Object{$key=$helperSwitch[$_.Name];-not $key -or -not $Preferences.PSObject.Properties[$key] -or $Preferences.$key})
    [pscustomobject]@{Apps=@($Apps|Where-Object{$_.Id -in $wantedApps});Media=$Media;Helpers=$Helpers;Custom=@(Get-GamingCustomSnapshot -Paths @($super.CustomExecutables))}
}
function Invoke-GamingProfile {
    param([Parameter(Mandatory=$true)][string]$ProfileId,[Parameter(Mandatory=$true)][ValidateSet('Start','Stop','Apply','Restore')][string]$Operation)
    $profile=Get-GamingProfiles|Where-Object Id -eq $ProfileId|Select-Object -First 1
    if(-not $profile){throw 'Profile was not found.'}
    if($profile.Kind -eq 'Performance'){
        if($Operation -in @('Apply','Start')){return Invoke-GamingAction 'Enter'}
        return Invoke-GamingAction 'Restore'
    }
    if($Operation -eq 'Apply'){$Operation='Start'}
    if($Operation -eq 'Restore'){$Operation='Start'}
    $mutex=New-Object Threading.Mutex($false,'Local\GamingModeActions');$locked=$false
    try{
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Another profile action is running. Wait for it to finish.'}
        $media=Get-MediaStackSnapshot;$media.Components=@($media.Components|Where-Object{$_.Key -in @($profile.MediaKeys)})
        $custom=@(Get-GamingCustomSnapshot -Paths @($profile.CustomExecutables));$results=@()
        if($Operation -eq 'Start'){
            foreach($component in $media.Components){$component.Running=$true}
            if($media.Components.Count){$r=Start-MediaStack -Snapshot $media -OnProgress {param($m)Write-GamingStatus $m};$results+=@($r.Results)}
            $apps=@(Get-GamingAppLaunchSnapshot -AppIds @($profile.AppIds))
            if($apps.Count){$r=Invoke-GamingAppRestore -Snapshot $apps -Recovery;$results+=@($r.Results)}
            $r=Invoke-GamingCustomApps -Snapshot $custom -Operation Start;$results+=@($r.Results)
        }else{
            $apps=@(Get-OptionalAppSnapshot|Where-Object{$_.Id -in @($profile.AppIds)});Save-GamingKnownApps $apps
            # Save intent before stopping for review/recovery. The next Start uses known app entry points.
            $folder=Join-Path $script:GamingProfilesRoot 'state';[void][IO.Directory]::CreateDirectory($folder)
            [pscustomobject]@{Id=$ProfileId;CapturedUtc=[datetime]::UtcNow.ToString('o');Media=$media;Apps=$apps;Custom=$custom}|ConvertTo-Json -Depth 15|Set-Content -LiteralPath (Join-Path $folder ('profile-stop-'+$ProfileId+'.json')) -Encoding UTF8
            if($media.Components.Count){$r=Stop-MediaStack -Snapshot $media -OnProgress {param($m)Write-GamingStatus $m};$results+=@($r.Results)}
            $r=Invoke-GamingAppStop -Snapshot $apps;$results+=@($r.Results)
            $r=Invoke-GamingCustomApps -Snapshot $custom -Operation Stop;$results+=@($r.Results)
            $r=Invoke-GamingAppStop -Snapshot $apps -ChatGPTOnly;$results+=@($r.Results)
        }
        [pscustomobject]@{Success=(@($results|Where-Object{-not $_.Success}).Count -eq 0);Action=$Operation;Results=$results;Message=($profile.Name+' '+$Operation.ToLowerInvariant()+' completed.')}
    }finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
