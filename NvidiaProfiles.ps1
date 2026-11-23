#requires -Version 5.1
# Per-executable NVIDIA DRS settings. Import defines functions only.
[CmdletBinding()]
param([string]$GamingNvidiaWorkerRequest)
$script:GamingNvidiaRoot=$PSScriptRoot
$script:GamingNvidiaScript=$PSCommandPath

function Initialize-GamingNvidia {
    if(-not ('GamingNvidia.Session' -as [type])) {Add-Type -Path (Join-Path $script:GamingNvidiaRoot 'NvidiaDrs.cs') -ErrorAction Stop}
}
function Get-GamingNvidiaSettingsCatalog {
    $options=@{
        PowerMode=@(@('Normal','Normal / driver controlled'),@('PreferMaximum','Prefer maximum performance'))
        TextureQuality=@(@('HighQuality','High quality'),@('Quality','Quality'),@('Performance','Performance'),@('HighPerformance','High performance'))
        AnisotropicOptimization=@(@('Off','Off'),@('On','On'))
        TrilinearOptimization=@(@('Off','Off'),@('On','On'))
        NegativeLodBias=@(@('Allow','Allow'),@('Clamp','Clamp'))
        VSync=@(@('Application','Use game setting'),@('Off','Off — may tear'),@('On','On'),@('Fast','Fast sync'))
        PreferredRefresh=@(@('Application','Use game setting'),@('Highest','Highest available'))
        LowLatency=@(@('Off','Off'),@('On','On'),@('Ultra','Ultra'))
    }
    $rows=@(
        @('PowerMode','GPU power management','Maximum performance may raise power use and temperatures. It does not overclock the GPU.','Normal'),
        @('TextureQuality','Texture filtering quality','Higher quality reduces filtering shortcuts. Performance modes may soften textures or add shimmer.','Quality'),
        @('AnisotropicOptimization','Anisotropic sample optimization','Filtering shortcuts may improve performance at the expense of image quality. Game/API dependent.','Off'),
        @('TrilinearOptimization','Trilinear optimization','Allows filtering shortcuts. Effects depend on the game and graphics API.','Off'),
        @('NegativeLodBias','Negative texture LOD bias','Clamp can reduce texture shimmer when anisotropic filtering is used. Some modern APIs ignore this override.','Allow'),
        @('VSync','Vertical sync','Off can reduce latency but allow tearing. On/Fast depend on your refresh rate, VRR setup and game.','Application'),
        @('PreferredRefresh','Preferred refresh rate','Requests the highest available refresh rate where the game and display mode support it.','Application'),
        @('MaxFrameRate','Maximum frame rate','0 disables the driver cap; otherwise 20–1000 FPS. A sustainable cap can improve pacing.','0'),
        @('LowLatency','Driver low latency','Prefer in-game NVIDIA Reflex where available. This control is enabled only when all required driver settings can be identified.','Off')
    )
    foreach($r in $rows){
        [pscustomobject]@{Id=$r[0];Name=$r[1];Description=$r[2];Default=$r[3];Kind=$(if($r[0] -eq 'MaxFrameRate'){'Integer'}else{'Choice'});Minimum=20;Maximum=1000;Options=@(foreach($o in $options[$r[0]]){[pscustomobject]@{Value=$o[0];Name=$o[1]}})}
    }
}
function Get-GamingNvidiaMappings {
    @{
        PowerMode=@{Ids=@([uint32]0x1057EB71);Values=@{Normal=@([uint32]2);PreferMaximum=@([uint32]1)}}
        TextureQuality=@{Ids=@([uint32]0x00CE2691);Values=@{HighQuality=@([uint32]4294967286);Quality=@([uint32]0);Performance=@([uint32]10);HighPerformance=@([uint32]20)}}
        AnisotropicOptimization=@{Ids=@([uint32]0x00E73211);Values=@{Off=@([uint32]0);On=@([uint32]1)}}
        TrilinearOptimization=@{Ids=@([uint32]0x002ECAF2);Values=@{Off=@([uint32]0);On=@([uint32]1)}}
        NegativeLodBias=@{Ids=@([uint32]0x0019BB68);Values=@{Allow=@([uint32]0);Clamp=@([uint32]1)}}
        VSync=@{Ids=@([uint32]0x00A879CF);Values=@{Application=@([uint32]0x60925292);Off=@([uint32]0x08416747);On=@([uint32]0x47814940);Fast=@([uint32]0x18888888)}}
        PreferredRefresh=@{Ids=@([uint32]0x0064B541);Values=@{Application=@([uint32]0);Highest=@([uint32]1)}}
        MaxFrameRate=@{Ids=@([uint32]0x10835002);Values=@{}}
        LowLatency=@{Ids=@([uint32]0x0005F543,[uint32]0x10835000,[uint32]0x007BA09E);Values=@{Off=@([uint32]0,[uint32]0,[uint32]0);On=@([uint32]1,[uint32]0,[uint32]1);Ultra=@([uint32]2,[uint32]1,[uint32]1)}}
    }
}
function ConvertTo-GamingNvidiaPlan {
    param([ValidateSet('Performance','Quality','Custom')][string]$Preset,$Settings)
    $choices=switch($Preset){
        Performance {@{PowerMode='PreferMaximum';PreferredRefresh='Highest';TextureQuality='HighPerformance';AnisotropicOptimization='On';TrilinearOptimization='On';NegativeLodBias='Allow';VSync='Off';MaxFrameRate=0}}
        Quality {@{PowerMode='PreferMaximum';PreferredRefresh='Highest';TextureQuality='HighQuality';AnisotropicOptimization='Off';TrilinearOptimization='Off';NegativeLodBias='Clamp';VSync='On';MaxFrameRate=0}}
        Custom {
            $map=@{}
            if($Settings -is [Collections.IDictionary]){foreach($key in $Settings.Keys){$map[[string]$key]=$Settings[$key]}}
            elseif($Settings){foreach($p in $Settings.PSObject.Properties){$map[$p.Name]=$p.Value}}
            $map
        }
    }
    if(-not $choices.Count){throw 'Choose at least one NVIDIA setting.'}
    $mappings=Get-GamingNvidiaMappings;$plan=@()
    foreach($key in @($choices.Keys | Sort-Object)){
        if(-not $mappings.ContainsKey($key)){throw "Unknown NVIDIA setting: $key"}
        $mapping=$mappings[$key];$choice=[string]$choices[$key]
        if($key -eq 'MaxFrameRate'){
            $fps=0
            if($choice -notmatch '^\d{1,4}$' -or -not [int]::TryParse($choice,[ref]$fps) -or ($fps -ne 0 -and ($fps -lt 20 -or $fps -gt 1000))){throw 'Frame cap must be 0 (off) or 20–1000 FPS.'}
            $values=@([uint32]$fps)
        }else{
            if(-not $mapping.Values.ContainsKey($choice)){throw "Invalid choice for $key"}
            $values=@($mapping.Values[$choice])
        }
        for($i=0;$i -lt $mapping.Ids.Count;$i++){$plan+=[pscustomobject]@{Key=$key;Id=[uint32]$mapping.Ids[$i];Value=[uint32]$values[$i];Choice=$choice}}
    }
    return $plan
}
function Get-GamingNvidiaExecutable {
    param([Parameter(Mandatory=$true)][string]$ExecutablePath,[switch]$AllowMissing)
    if($ExecutablePath -notmatch '^[A-Za-z]:\\' -or $ExecutablePath.Contains('"') -or $ExecutablePath.Contains([char]0)){throw 'Select a local game executable using its full path.'}
    $full=[IO.Path]::GetFullPath($ExecutablePath)
    if([IO.Path]::GetExtension($full) -ine '.exe' -or $full.Length -gt 1800){throw 'Select the actual game .exe file.'}
    if(-not $AllowMissing -and -not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'The selected game executable no longer exists.'}
    return $full
}
function Get-GamingNvidiaKey([string]$ExecutablePath) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($ExecutablePath.ToLowerInvariant())))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-GamingNvidiaStatePath {
    param([Parameter(Mandatory=$true)][string]$Name,[switch]$Create)
    if($Name -notmatch '^(?:profile-[a-f0-9]{64}\.json|request-[a-f0-9]{32}\.json(?:\.result\.json)?)(?:\.pending)?$'){throw 'Invalid NVIDIA state filename.'}
    $state=Join-Path $script:GamingNvidiaRoot 'state';$root=Join-Path $state 'nvidia'
    foreach($folder in @($state,$root)){
        if($Create -and -not(Test-Path -LiteralPath $folder)){[void][IO.Directory]::CreateDirectory($folder)}
        if(Test-Path -LiteralPath $folder){$item=Get-Item -LiteralPath $folder;if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'NVIDIA state folders must not be links.'}}
    }
    $path=Join-Path $root $Name
    if(Test-Path -LiteralPath $path){$item=Get-Item -LiteralPath $path;if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'NVIDIA state files must not be links.'}}
    return $path
}
function Read-GamingNvidiaJournal([string]$ExecutablePath) {
    $path=Get-GamingNvidiaStatePath ('profile-'+(Get-GamingNvidiaKey $ExecutablePath)+'.json')
    if(-not(Test-Path -LiteralPath $path)){return $null}
    if((Get-Item -LiteralPath $path).Length -gt 262144){throw 'NVIDIA restore file is unexpectedly large.'}
    $j=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if($j.Version -ne 1 -or $j.ExecutablePath -ine $ExecutablePath -or $j.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'NVIDIA restore file identity does not match.'}
    if($j.Active -isnot [bool] -or $j.CreatedProfile -isnot [bool] -or [string]::IsNullOrWhiteSpace([string]$j.ProfileName) -or ([string]$j.ProfileName).Length -gt 2047){throw 'Invalid NVIDIA restore profile metadata.'}
    if($j.CreatedProfile -and ([string]$j.ProfileName) -cne ('Gaming Mode - '+[IO.Path]::GetFileNameWithoutExtension($ExecutablePath)+' - '+(Get-GamingNvidiaKey $ExecutablePath).Substring(0,12))){throw 'The saved private profile identity is invalid.'}
    $allowed=@((Get-GamingNvidiaMappings).Values | ForEach-Object Ids);$seen=@{}
    foreach($row in @($j.Original)){
        if([uint32]$row.Id -notin $allowed -or $seen.ContainsKey([string]$row.Id) -or $row.Before.Type -ne 0 -or $row.Before.Found -isnot [bool] -or $row.Before.Location -notin @(0,1,2,3) -or $row.Before.IsCurrentPredefined -notin @(0,1)){throw 'Invalid saved NVIDIA setting.'}
        [void][uint32]$row.Before.Value;[void][uint32]$row.LastApplied;if($null -ne $row.PendingValue){[void][uint32]$row.PendingValue};$seen[[string]$row.Id]=$true
    }
    return $j
}
function Save-GamingNvidiaJournal($Journal) {
    $name='profile-'+(Get-GamingNvidiaKey $Journal.ExecutablePath)+'.json'
    $path=Get-GamingNvidiaStatePath $name -Create;$temp=Get-GamingNvidiaStatePath ($name+'.pending') -Create
    $Journal.UpdatedUtc=[datetime]::UtcNow.ToString('o')
    $Journal | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $path -Force
}
function Get-GamingNvidiaCapabilities {
    $s=$null
    try{Initialize-GamingNvidia;$s=New-Object GamingNvidia.Session;[pscustomobject]@{Success=$true;Available=$true;Status='Ready';Driver=$s.Driver;AvailableSettingIds=@($s.AvailableIds());Message='Per-game NVIDIA profiles are available. Shared profiles are protected.'}}
    catch{[pscustomobject]@{Success=$false;Available=$false;Status='Unavailable';Driver='';Message=$_.Exception.Message}}
    finally{if($s){$s.Dispose()}}
}
function Get-GamingNvidiaGameProfile {
    param([Parameter(Mandatory=$true)][string]$ExecutablePath)
    $s=$null
    try{
        $exe=Get-GamingNvidiaExecutable $ExecutablePath;Initialize-GamingNvidia;$s=New-Object GamingNvidia.Session
        $info=$s.Inspect($exe);$available=@($s.AvailableIds());$mappings=Get-GamingNvidiaMappings;$rows=@()
        foreach($definition in Get-GamingNvidiaSettingsCatalog){
            $mapping=$mappings[$definition.Id];$states=@($mapping.Ids | ForEach-Object {$s.Read($exe,[uint32]$_)})
            $supported=@($states | Where-Object {-not $_.Found -and $_.Id -notin $available}).Count -eq 0 -and @($states | Where-Object {$_.Found -and $_.Type -ne 0}).Count -eq 0
            $choice=$null
            if($definition.Id -eq 'MaxFrameRate' -and $states[0].Found){$choice=[string]$states[0].Value}
            else{foreach($key in $mapping.Values.Keys){$v=@($mapping.Values[$key]);$same=$true;for($i=0;$i -lt $states.Count;$i++){if(-not $states[$i].Found -or $states[$i].Value -ne $v[$i]){$same=$false}};if($same){$choice=$key;break}}}
            $display=if($null -eq $choice){if($supported){'Driver default / other value'}else{'Unavailable in driver catalog'}}elseif($definition.Id -eq 'MaxFrameRate'){if($choice -eq '0'){'Off'}else{$choice+' FPS'}}else{($definition.Options | Where-Object Value -eq $choice | Select-Object -First 1).Name}
            $rows+=[pscustomobject]@{Id=$definition.Id;Name=$definition.Name;Value=$choice;DisplayValue=$display;Supported=$supported;Source=$(if($info.Found -and @($states | Where-Object {$_.Found -and $_.Location -eq 0}).Count){'Game profile'}else{'Inherited / driver default'});Raw=$states}
        }
        $journal=Read-GamingNvidiaJournal $exe
        $shared=@($info.Applications).Count -gt 1
        $safe=-not $info.IsBase -and (-not $info.Found -or @($info.Applications).Count -eq 1) -and @($info.Applications | Where-Object {$_.Flags -ne 0 -or $_.CommandLine}).Count -eq 0
        $message=if($shared){'This NVIDIA profile is shared by multiple executables. Changes are blocked to protect the other games/apps.'}elseif(-not $safe){'This association cannot be changed safely.'}else{'Ready. Close the game before applying; restart it to use the new settings.'}
        [pscustomobject]@{Success=$true;Status=$(if($safe){'Ready'}elseif($shared){'NeedsSeparateProfile'}else{'Protected'});ExecutablePath=$exe;ProfileName=$(if($info.Found){$info.Name}else{'New profile for this executable'});SharedApplications=@($info.Applications | ForEach-Object Name);IsShared=$shared;CanApply=$safe;CanRestore=[bool]($journal -and $journal.Active);Settings=$rows;Driver=$s.Driver;Message=$message;Notes=@('Only this game profile is changed. Windows Gaming Mode toggles do not undo these persistent game preferences. Use Restore previous.','Performance uses maximum filtering shortcuts and VSync off: softer textures, shimmer or tearing are possible. Quality uses high-quality filtering and VSync on, which can add latency. Both remove the driver FPS cap and may increase GPU power use.','These are driver preferences; in-game resolution, detail and Reflex remain game controlled. Benchmark the same scene before and after.','Unsupported low-latency settings can still be configured in NVIDIA Control Panel or through in-game Reflex.')}
    }catch{[pscustomobject]@{Success=$false;Status='Unavailable';CanApply=$false;CanRestore=$false;Settings=@();SharedApplications=@();Message=$_.Exception.Message}}
    finally{if($s){$s.Dispose()}}
}
function Test-GamingNvidiaOriginalMatch($Current,$Before) {
    if([bool]$Current.Found -ne [bool]$Before.Found){return $false}
    if(-not $Before.Found){return $true}
    return $Current.Type -eq $Before.Type -and $Current.Value -eq $Before.Value -and $Current.Location -eq $Before.Location -and $Current.IsCurrentPredefined -eq $Before.IsCurrentPredefined
}
function Invoke-GamingNvidiaTransaction {
    param([string]$ExecutablePath,[ValidateSet('Performance','Quality','Custom','Restore')][string]$Preset,$Settings)
    # Called by the fixed elevated worker only. Mutations stay in one DRS session
    # and are saved only after every requested setting has staged successfully.
    $exe=Get-GamingNvidiaExecutable $ExecutablePath -AllowMissing:($Preset -eq 'Restore')
    Initialize-GamingNvidia;$s=$null;$mutex=New-Object Threading.Mutex($false,'Local\GamingModeNvidiaProfiles');$locked=$false
    try{
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Another NVIDIA profile operation is running.'}
        $journal=Read-GamingNvidiaJournal $exe
        if($Preset -eq 'Restore' -and (-not $journal -or -not $journal.Active)){return [pscustomobject]@{Success=$true;Status='NoAction';Message='No saved NVIDIA changes to restore.';Results=@()}}
        $s=New-Object GamingNvidia.Session;$info=$s.Inspect($exe)
        if($info.IsBase -or @($info.Applications).Count -gt 1){throw 'The selected profile is global or shared. No driver settings were changed.'}
        if(@($info.Applications | Where-Object {$_.Flags -ne 0 -or $_.CommandLine}).Count){throw 'This executable association cannot be changed safely.'}
        $results=@();$retained=$false
        if($Preset -eq 'Restore'){
            if(-not $info.Found -and $journal.CreatedProfile){$journal.Active=$false;$journal.Phase='Restored';Save-GamingNvidiaJournal $journal;return [pscustomobject]@{Success=$true;Status='Restored';Message='The temporary NVIDIA profile is already absent.';Results=@()}}
            if(-not $info.Found -or $info.Name -cne $journal.ProfileName){throw 'The game profile association changed. Saved restore data was kept.'}
            foreach($row in @($journal.Original)){
                $current=$s.Read($exe,[uint32]$row.Id)
                $alreadyOriginal=Test-GamingNvidiaOriginalMatch $current $row.Before
                if($journal.CreatedProfile){$alreadyOriginal=((-not $current.Found -and -not $row.Before.Found) -or ($current.Found -and $row.Before.Found -and $current.Location -ne 0 -and $current.Type -eq $row.Before.Type -and $current.Value -eq $row.Before.Value))}
                if($alreadyOriginal){continue}
                $expected=@([uint32]$row.LastApplied);if($null -ne $row.PendingValue){$expected+=@([uint32]$row.PendingValue)}
                if(-not $current.Found -or $current.Type -ne 0 -or $current.Location -ne 0 -or $current.IsCurrentPredefined -ne 0 -or $current.Value -notin $expected){$retained=$true;$results+=[pscustomobject]@{Name=$row.Key;Status='KeptUserChange';Success=$true;Message='A later driver setting was kept.'};continue}
                if(-not $journal.CreatedProfile -and $row.Before.Found -and $row.Before.Location -eq 0 -and $row.Before.IsCurrentPredefined -eq 0){$s.Write($exe,$journal.ProfileName,[uint32]$row.Id,[uint32]$row.Before.Value)}
                else{$s.RemoveOverride($exe,$journal.ProfileName,[uint32]$row.Id)}
                $results+=[pscustomobject]@{Name=$row.Key;Status='Restored';Success=$true;Message='Original profile override restored.'}
            }
            if($journal.CreatedProfile -and -not $retained){try{$s.DeleteOwned($exe,$journal.ProfileName)}catch{if($_.Exception.Message -match 'contains other settings'){$retained=$true}else{throw}}}
            $journal.Phase='Restoring';Save-GamingNvidiaJournal $journal;$s.Save();$s.Dispose();$s=New-Object GamingNvidia.Session
            $restoredProfile=$s.Inspect($exe)
            if($journal.CreatedProfile -and -not $retained -and $restoredProfile.Found){throw 'The private profile association was not removed; the restore record was retained.'}
            foreach($row in @($journal.Original)){
                if(@($results | Where-Object {$_.Name -eq $row.Key -and $_.Status -eq 'KeptUserChange'}).Count){continue}
                if($journal.CreatedProfile -and -not $restoredProfile.Found){continue}
                $after=$s.Read($exe,[uint32]$row.Id)
                $hadUserOverride=-not $journal.CreatedProfile -and $row.Before.Found -and $row.Before.Location -eq 0 -and $row.Before.IsCurrentPredefined -eq 0
                if($hadUserOverride){if(-not(Test-GamingNvidiaOriginalMatch $after $row.Before)){throw 'Restored setting did not verify; the restore record was retained.'}}
                elseif($after.Found -and $after.Location -eq 0 -and $after.IsCurrentPredefined -eq 0){throw 'A temporary profile override remains; the restore record was retained.'}
                # Inherited/predefined values may legitimately change after a
                # driver/global preference update. Restore override absence only.
            }
            $journal.Active=$false;$journal.Phase='Restored';Save-GamingNvidiaJournal $journal
            return [pscustomobject]@{Success=$true;Status='Restored';Message=$(if($retained){'Previous overrides restored; later changes were preserved. Restart the game.'}else{'Previous NVIDIA settings restored. Restart the game.'});Results=$results}
        }
        $plan=@(ConvertTo-GamingNvidiaPlan -Preset $Preset -Settings $Settings);$available=@($s.AvailableIds())
        foreach($row in $plan){$current=$s.Read($exe,[uint32]$row.Id);if(((-not $current.Found) -and $row.Id -notin $available) -or ($current.Found -and $current.Type -ne 0)){throw ('The driver does not expose '+$row.Key+'. No driver settings were changed.')}}
        if(-not $journal -or -not $journal.Active){
            $profileName=if($info.Found){$info.Name}else{'Gaming Mode - '+[IO.Path]::GetFileNameWithoutExtension($exe)+' - '+(Get-GamingNvidiaKey $exe).Substring(0,12)}
            $journal=[pscustomobject]@{Version=1;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;ExecutablePath=$exe;ProfileName=$profileName;CreatedProfile=(-not $info.Found);Active=$true;Phase='Prepared';Original=@();UpdatedUtc='';Driver=$s.Driver;LastPreset=$Preset}
        }elseif($info.Found -and $info.Name -cne $journal.ProfileName){throw 'The game profile changed since the backup. Restore or review it before applying again.'}
        foreach($row in $plan){
            $original=$journal.Original | Where-Object Id -eq $row.Id | Select-Object -First 1
            if(-not $original){$original=[pscustomobject]@{Id=$row.Id;Key=$row.Key;Before=$s.Read($exe,[uint32]$row.Id);LastApplied=$row.Value;PendingValue=$null};$journal.Original=@($journal.Original)+@($original)}
            $original | Add-Member -NotePropertyName PendingValue -NotePropertyValue $row.Value -Force
        }
        $journal.Phase='Prepared';$journal.LastPreset=$Preset;Save-GamingNvidiaJournal $journal
        if(-not $info.Found){[void]$s.CreateForExecutable($exe,$journal.ProfileName)}
        foreach($row in $plan){$s.Write($exe,$journal.ProfileName,[uint32]$row.Id,[uint32]$row.Value)}
        $s.Save();$s.Dispose();$s=New-Object GamingNvidia.Session
        foreach($row in $plan){$current=$s.Read($exe,[uint32]$row.Id);if(-not $current.Found -or $current.Type -ne 0 -or $current.Location -ne 0 -or $current.Value -ne $row.Value){throw 'The saved NVIDIA setting did not verify. Original state remains available through Restore previous.'};$results+=[pscustomobject]@{Name=$row.Key;Status='Applied';Success=$true;Message=$row.Choice}}
        foreach($row in $plan){$saved=$journal.Original | Where-Object Id -eq $row.Id | Select-Object -First 1;$saved.LastApplied=$row.Value;$saved.PendingValue=$null}
        $journal.Phase='Applied';Save-GamingNvidiaJournal $journal
        return [pscustomobject]@{Success=$true;Status='Applied';Message=($Preset+' NVIDIA preferences applied to this game. Restart the game.');Results=$results}
    }finally{if($s){$s.Dispose()};if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Invoke-GamingNvidiaProfile {
    param([Parameter(Mandatory=$true)][string]$ExecutablePath,[Parameter(Mandatory=$true)][ValidateSet('Performance','Quality','Custom','Restore')][string]$Preset,$Settings)
    try{
        $exe=Get-GamingNvidiaExecutable $ExecutablePath -AllowMissing:($Preset -eq 'Restore')
        if($Preset -ne 'Restore'){
            $plan=@(ConvertTo-GamingNvidiaPlan -Preset $Preset -Settings $Settings);$profile=Get-GamingNvidiaGameProfile $exe
            if(-not $profile.Success -or -not $profile.CanApply){return [pscustomobject]@{Success=$false;Status=$profile.Status;Message=$profile.Message;SharedApplications=$profile.SharedApplications;Results=@()}}
            $unsupported=@($profile.Settings | Where-Object {-not $_.Supported -and $_.Id -in @($plan | ForEach-Object Key)} | ForEach-Object Name)
            if($unsupported.Count){return [pscustomobject]@{Success=$false;Status='Unsupported';Message=('The driver does not expose: '+($unsupported -join ', ')+'. No settings were changed.');Results=@()}}
        }else{
            $prior=Read-GamingNvidiaJournal $exe
            if(-not $prior -or -not $prior.Active){return [pscustomobject]@{Success=$true;Status='NoAction';Message='No saved NVIDIA changes to restore.';Results=@()}}
        }
        $requestName='request-'+[guid]::NewGuid().ToString('N')+'.json';$path=Get-GamingNvidiaStatePath $requestName -Create;$resultPath=Get-GamingNvidiaStatePath ($requestName+'.result.json')
        $request=[pscustomobject]@{Version=1;UserSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;ExecutablePath=$exe;Preset=$Preset;Settings=$Settings}
        $request | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -GamingNvidiaWorkerRequest "{1}"' -f $script:GamingNvidiaScript,$path
        $worker=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        try{$deadline=[datetime]::UtcNow.AddSeconds(120);while(-not $worker.HasExited){if([datetime]::UtcNow -gt $deadline){throw 'NVIDIA worker is still running. Wait before retrying; the original state is saved.'};if(Get-Command Write-GamingStatus -ErrorAction SilentlyContinue){Write-GamingStatus 'Applying the approved NVIDIA game profile...'};Start-Sleep -Milliseconds 150}}finally{$worker.Dispose()}
        if(-not(Test-Path -LiteralPath $resultPath -PathType Leaf)){throw 'The NVIDIA worker returned no result.'}
        $validated=Get-GamingNvidiaStatePath ($requestName+'.result.json');$result=Get-Content -LiteralPath $validated -Raw | ConvertFrom-Json
        if($result.Success -isnot [bool]){throw 'Invalid NVIDIA worker result.'};return $result
    }catch{
        $errorObject=$_.Exception;$cancelled=$false;while($errorObject){if($errorObject.PSObject.Properties['NativeErrorCode'] -and $errorObject.NativeErrorCode -eq 1223){$cancelled=$true};$errorObject=$errorObject.InnerException}
        return [pscustomobject]@{Success=$false;Status=$(if($cancelled){'Skipped'}else{'Failed'});Message=$(if($cancelled){'Administrator approval was cancelled. No driver changes were made.'}else{$_.Exception.Message});Results=@()}
    }
}

if($GamingNvidiaWorkerRequest){
    $resultPath=$null;$exitCode=1
    try{
        $requestName=[IO.Path]::GetFileName($GamingNvidiaWorkerRequest)
        if($requestName -notmatch '^request-[a-f0-9]{32}\.json$'){throw 'Invalid worker request name.'}
        $requestPath=Get-GamingNvidiaStatePath $requestName
        if([IO.Path]::GetFullPath($GamingNvidiaWorkerRequest) -ine [IO.Path]::GetFullPath($requestPath)){throw 'Request is outside the fixed NVIDIA state folder.'}
        $resultPath=Get-GamingNvidiaStatePath ($requestName+'.result.json');if(Test-Path -LiteralPath $resultPath){throw 'NVIDIA request already completed.'}
        if((Get-Item -LiteralPath $requestPath).Length -gt 65536){throw 'NVIDIA request is too large.'}
        $request=Get-Content -LiteralPath $requestPath -Raw | ConvertFrom-Json
        if($request.Version -ne 1 -or $request.UserSid -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){throw 'The elevated account does not match the requesting user.'}
        $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Administrator approval is required for NVIDIA profile changes.'}
        $result=Invoke-GamingNvidiaTransaction -ExecutablePath $request.ExecutablePath -Preset $request.Preset -Settings $request.Settings
        $exitCode=if($result.Success){0}else{1}
    }catch{$result=[pscustomobject]@{Success=$false;Status='Failed';Message=$_.Exception.Message;Results=@()}}
    if($resultPath){try{$stream=[IO.File]::Open($resultPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$writer=New-Object IO.StreamWriter($stream,(New-Object Text.UTF8Encoding($false)));try{$writer.Write(($result | ConvertTo-Json -Depth 12))}finally{$writer.Dispose()}}finally{$stream.Dispose()}}catch{$exitCode=1}}
    exit $exitCode
}
