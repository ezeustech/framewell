# Configuration presets contain data only. Applying one never starts/stops apps,
# writes driver settings, starts a memory worker, or changes Windows startup.
$script:GamingSettingsProfilesRoot=$PSScriptRoot
function Get-GamingSettingsProfileScopeFiles {
    param([string]$Scope)
    switch($Scope){
        'All' {@('game-process-preferences.json','games.json','game-bindings.json','game-scan-folders.json','network-servers.json','network-preferences.json','profiles.json','memory-preferences.json','optimizer-view.json')}
        'Games' {@('game-process-preferences.json','games.json','game-bindings.json','game-scan-folders.json')}
        'Network' {@('network-servers.json','network-preferences.json')}
        'Profiles' {@('profiles.json')}
        'Memory' {@('memory-preferences.json')}
        'Tools' {@('optimizer-view.json')}
        default {@()}
    }
}
function Get-GamingSettingsProfileScopes { @('All','Overview','Performance','Games','Network','Profiles','Appearance','Memory','Tools','Settings') }
function Test-GamingPortableConfiguration {
    param([string]$Name,$Value)
    switch($Name){
        'network-servers.json' {
            if($Value.Version -ne 1 -or @($Value.Servers).Count -gt 1000 -or @($Value.PSObject.Properties.Name|Where-Object{$_ -notin @('Version','Servers')}).Count){throw 'Invalid server configuration.'}
            foreach($server in @($Value.Servers)){if(-not(Test-GamingNetworkServerData -Value $server)){throw 'Invalid saved server.'}}
        }
        'network-preferences.json' {if($Value.Version -ne 1 -or -not(Test-GamingNetworkPreferences -Value $Value)){throw 'Invalid network test configuration.'}}
        'game-process-preferences.json' {if(-not(Test-GamingProcessPreferencesData -Value $Value)){throw 'Invalid CPU preferences.'}}
        'memory-preferences.json' {if(-not(Test-GamingMemoryPreferencesData -Value $Value)){throw 'Invalid memory preferences.'}}
        {$_ -in @('games.json','game-bindings.json','game-scan-folders.json')} {
            if($Value.Version -ne 1){throw 'Unsupported game settings version.'}
            $rows=switch($Name){'games.json' {@($Value.Games)} 'game-bindings.json' {@($Value.Bindings)} default {@($Value.Folders)}}
            if($rows.Count -gt 1000){throw 'Too many game settings.'}
            foreach($entry in $rows){
                $path=if($Name -eq 'game-scan-folders.json'){[string]$entry.Path}else{[string]$entry.ExecutablePath}
                if($path -notmatch '^[A-Za-z]:\\' -or $path -match '[\x00-\x1F]' -or $path.Length -gt 1024){throw 'Game entries must use normal local paths.'}
                $full=[IO.Path]::GetFullPath($path)
                if($Name -ne 'game-scan-folders.json'){
                    if([IO.Path]::GetExtension($full) -ine '.exe' -or [IO.Path]::GetFileName($full) -match '(?i)^(powershell|pwsh|cmd|wscript|cscript|rundll32|regsvr32|msiexec|explorer)\.exe$' -or $full.StartsWith(($env:WINDIR.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'A game profile contains a script host or system executable.'}
                }elseif($full.TrimEnd('\').Length -le 3 -or $full.TrimEnd('\') -in @($env:WINDIR,$env:USERPROFILE,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:ProgramData)){throw 'Choose a specific games folder.'}
                if($Name -eq 'games.json'){
                    if([string]$entry.Id -notmatch '^manual-[a-f0-9]{32}$' -or $entry.Source -ne 'Manual' -or $entry.LaunchUri -or -not [string]$entry.Name -or ([string]$entry.Name).Length -gt 120){throw 'Invalid manual game entry.'}
                }
                if($Name -eq 'game-bindings.json' -and ([string]$entry.GameId -notmatch '^[a-zA-Z0-9_-]{1,100}$')){throw 'Invalid game binding ID.'}
            }
        }
        default {throw 'Unrecognized portable configuration.'}
    }
}
function Read-GamingSettingsProfilesDocument {
    $path=Join-Path $script:GamingSettingsProfilesRoot 'state\settings-profiles.json'
    if(-not(Test-Path -LiteralPath $path)){return [pscustomobject]@{Version=1;Profiles=@()}}
    if((Get-Item -LiteralPath $path).Length -gt 8MB){throw 'Settings profile storage is too large.'}
    $document=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($document.Version -ne 1){throw 'Unsupported settings profile format.'}
    return $document
}
function Write-GamingSettingsProfilesDocument {
    param($Document)
    $dir=Join-Path $script:GamingSettingsProfilesRoot 'state';[void][IO.Directory]::CreateDirectory($dir)
    $pending=Join-Path $dir ('settings-profiles.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    $Document|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination (Join-Path $dir 'settings-profiles.json') -Force
}
function ConvertTo-GamingSettingsProfile {
    param($Profile,[switch]$New)
    $id=[string]$Profile.Id;if($New){$id='settings-'+[guid]::NewGuid().ToString('N')}
    if($id -notmatch '^settings-[a-f0-9]{32}$'){throw 'Invalid settings profile ID.'}
    $name=([string]$Profile.Name).Trim()
    if(-not $name -or $name.Length -gt 100 -or $name -match '[\x00-\x1F]'){throw 'Choose a profile name between 1 and 100 characters.'}
    if($Profile.Scope -notin @(Get-GamingSettingsProfileScopes)){throw 'Unknown settings profile scope.'}
    $allowed=@(Get-GamingSettingsProfileScopeFiles $Profile.Scope)
    if($Profile.Files -and $Profile.Files -isnot [pscustomobject]){throw 'Profile files must be a JSON object.'}
    foreach($property in $Profile.Files.PSObject.Properties){if($property.Name -notin $allowed){throw 'A profile contains a file outside its allowed scope.'}}
    if($Profile.Preferences -and $Profile.Preferences -isnot [pscustomobject]){throw 'Preferences must be a JSON object.'}
    $known=Get-GamingPreferences
    foreach($property in $Profile.Preferences.PSObject.Properties){
        if(-not $known.PSObject.Properties[$property.Name] -or $property.Name -eq 'Version'){throw 'Unknown preference in profile.'}
        if($property.Name -eq 'Theme'){
            $themes=@('Dark','Light','OLED','Midnight','System');if(Get-Command Get-GamingThemes -ErrorAction SilentlyContinue){$themes+=@(Get-GamingThemes|ForEach-Object Id)}
            if($property.Value -notin $themes){throw 'Unknown profile theme.'}
        }elseif($property.Name -eq 'PowerMode'){if($property.Value -notin @('Current','HighPerformance','Balanced')){throw 'Unknown power mode.'}}
        elseif($property.Value -isnot [bool]){throw 'Profile switches must be booleans.'}
        if($Profile.Scope -in @('Appearance','Settings') -and $property.Name -notin @('Theme','CloseAfterActivation')){throw 'Preference is outside the selected scope.'}
        if($Profile.Scope -eq 'Overview' -and $property.Name -ne 'CloseAfterActivation'){throw 'Preference is outside the selected scope.'}
        if($Profile.Scope -eq 'Performance' -and $property.Name -in @('Theme','CloseAfterActivation')){throw 'Preference is outside the selected scope.'}
        if($Profile.Scope -notin @('All','Overview','Appearance','Settings','Performance')){throw 'This scope does not contain general preferences.'}
    }
    # File-specific schemas are checked again before any writes.
    foreach($property in $Profile.Files.PSObject.Properties){Test-GamingSettingsProfileFile $property.Name $property.Value}
    $count=@($Profile.Preferences.PSObject.Properties).Count+@($Profile.Files.PSObject.Properties).Count
    [pscustomobject]@{Id=$id;Name=$name;Scope=[string]$Profile.Scope;CreatedUtc=[datetime]::UtcNow.ToString('o');Summary=($count.ToString()+' saved settings/configuration groups');Preferences=$Profile.Preferences;Files=$Profile.Files}
}
function Test-GamingSettingsProfileFile {
    param([string]$Name,$Value)
    if($Value -isnot [pscustomobject]){throw 'Saved configuration must be a JSON object.'}
    if(([string]($Value|ConvertTo-Json -Depth 30 -Compress)).Length -gt 1MB){throw 'A profile configuration is too large.'}
    switch($Name){
        'profiles.json' {
            if($Value.Version -ne 2 -or @($Value.Profiles).Count -gt 100){throw 'Invalid app-profile collection.'}
            foreach($item in @($Value.Profiles)){
                # Private media integrations are local, not portable. Keep known components only.
                $clone=$item|ConvertTo-Json -Depth 12|ConvertFrom-Json
                $clone.MediaKeys=@($clone.MediaKeys|Where-Object{$_ -in @(Get-GMMediaDefinitions|ForEach-Object Key)})
                $null=ConvertTo-GamingProfile $clone -Read
            }
        }
        'optimizer-view.json' {if($Value.Version -ne 1 -or [string]$Value.Search -match '[\x00-\x1F]' -or ([string]$Value.Search).Length -gt 200){throw 'Invalid tools view.'}}
        default {
            if(Get-Command Test-GamingPortableConfiguration -ErrorAction SilentlyContinue){Test-GamingPortableConfiguration -Name $Name -Value $Value}
            else {throw ('Configuration validator not loaded: '+$Name)}
        }
    }
}
function Get-GamingSettingsProfiles { return @((Read-GamingSettingsProfilesDocument).Profiles) }
function Save-GamingSettingsProfile {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$Scope)
    if($Scope -notin @(Get-GamingSettingsProfileScopes)){throw 'Unknown profile scope.'}
    $prefs=Get-GamingPreferences;$selected=[ordered]@{}
    foreach($property in $prefs.PSObject.Properties){
        if($property.Name -eq 'Version'){continue}
        if($Scope -eq 'All' -or ($Scope -eq 'Performance' -and $property.Name -notin @('Theme','CloseAfterActivation')) -or ($Scope -in @('Appearance','Settings') -and $property.Name -in @('Theme','CloseAfterActivation')) -or ($Scope -eq 'Overview' -and $property.Name -eq 'CloseAfterActivation')){$selected[$property.Name]=$property.Value}
    }
    $files=[ordered]@{}
    foreach($file in @(Get-GamingSettingsProfileScopeFiles $Scope)){
        $path=Join-Path $script:GamingSettingsProfilesRoot ('state\'+$file)
        if(Test-Path -LiteralPath $path -PathType Leaf){$files[$file]=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}
    }
    $profile=ConvertTo-GamingSettingsProfile ([pscustomobject]@{Name=$Name;Scope=$Scope;Preferences=[pscustomobject]$selected;Files=[pscustomobject]$files}) -New
    $document=Read-GamingSettingsProfilesDocument
    if(@($document.Profiles).Count -ge 100){throw 'Remove an unused profile before adding more than 100.'}
    $document.Profiles=@($document.Profiles)+@($profile);Write-GamingSettingsProfilesDocument $document
    return $profile
}
function Apply-GamingSettingsProfile {
    param([Parameter(Mandatory=$true)][string]$Id)
    $profile=@(Get-GamingSettingsProfiles|Where-Object Id -eq $Id)|Select-Object -First 1
    if(-not $profile){throw 'Settings profile not found.'}
    $profile=ConvertTo-GamingSettingsProfile $profile
    $state=Join-Path $script:GamingSettingsProfilesRoot 'state';$writes=[ordered]@{};$before=@{}
    foreach($property in $profile.Files.PSObject.Properties){
        $value=$property.Value
        if($property.Name -eq 'profiles.json'){foreach($item in @($value.Profiles)){$item.MediaKeys=@($item.MediaKeys|Where-Object{$_ -in @(Get-GMMediaDefinitions|ForEach-Object Key)})}}
        $writes[$property.Name]=$value|ConvertTo-Json -Depth 30
    }
    $prefBefore=Get-GamingPreferences
    try {
        foreach($file in $writes.Keys){$path=Join-Path $state $file;$before[$file]=if(Test-Path -LiteralPath $path){[IO.File]::ReadAllText($path)}else{$null}}
        if(@($profile.Preferences.PSObject.Properties).Count){$null=Set-GamingPreferences $profile.Preferences}
        foreach($file in $writes.Keys){$pending=Join-Path $state ($file+'.'+[guid]::NewGuid().ToString('N')+'.pending');[IO.File]::WriteAllText($pending,$writes[$file],(New-Object Text.UTF8Encoding($false)));Move-Item -LiteralPath $pending -Destination (Join-Path $state $file) -Force}
        [pscustomobject]@{Success=$true;Message=($profile.Name+' loaded. Saved choices changed; no applications or system settings were changed.');Profile=$profile}
    } catch {
        foreach($file in $before.Keys){$path=Join-Path $state $file;if($null -eq $before[$file]){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}else{[IO.File]::WriteAllText($path,$before[$file])}}
        $null=Set-GamingPreferences $prefBefore
        throw
    }
}
function Remove-GamingSettingsProfile {
    param([Parameter(Mandatory=$true)][string]$Id)
    if($Id -notmatch '^settings-[a-f0-9]{32}$'){throw 'Invalid settings profile ID.'}
    $document=Read-GamingSettingsProfilesDocument;$document.Profiles=@($document.Profiles|Where-Object Id -ne $Id);Write-GamingSettingsProfilesDocument $document
    [pscustomobject]@{Success=$true;Message='Settings profile removed. Current settings were kept.'}
}
function Export-GamingSettingsProfile {
    param([Parameter(Mandatory=$true)][string]$Id,[string]$Path)
    $profile=@(Get-GamingSettingsProfiles|Where-Object Id -eq $Id)|Select-Object -First 1
    if(-not $profile){throw 'Settings profile not found.'}
    if(-not $Path){Add-Type -AssemblyName System.Windows.Forms;$picker=New-Object Windows.Forms.SaveFileDialog;$picker.Filter='Gaming Mode profile (*.json)|*.json';$picker.FileName='gaming-profile.json';try{if($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return};$Path=$picker.FileName}finally{$picker.Dispose()}}
    if([IO.Path]::GetExtension($Path) -ine '.json'){throw 'Choose a .json profile file.'}
    [pscustomobject]@{Format='GamingMode.SettingsProfile';Version=1;Profile=$profile}|ConvertTo-Json -Depth 30|Set-Content -LiteralPath $Path -Encoding UTF8
    [pscustomobject]@{Success=$true;Message='Profile exported. It may contain your game/app paths and server addresses.';Path=$Path}
}
function Import-GamingSettingsProfile {
    param([string]$Path)
    if(-not $Path){Add-Type -AssemblyName System.Windows.Forms;$picker=New-Object Windows.Forms.OpenFileDialog;$picker.Filter='Gaming Mode profile (*.json)|*.json';try{if($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return};$Path=$picker.FileName}finally{$picker.Dispose()}}
    if((Get-Item -LiteralPath $Path).Length -gt 2MB){throw 'Profile exceeds the 2 MB limit.'}
    $document=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
    if($document.Format -ne 'GamingMode.SettingsProfile' -or $document.Version -ne 1){throw 'Not a supported Gaming Mode profile.'}
    $profile=ConvertTo-GamingSettingsProfile $document.Profile -New
    $profiles=Read-GamingSettingsProfilesDocument
    if(@($profiles.Profiles).Count -ge 100){throw 'The 100 profile limit has been reached.'}
    $profiles.Profiles=@($profiles.Profiles)+@($profile);Write-GamingSettingsProfilesDocument $profiles
    return $profile
}
