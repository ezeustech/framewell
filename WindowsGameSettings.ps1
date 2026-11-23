# Fixed Windows gaming controls. Importing performs no system changes.
$script:GamingWindowsRoot=$PSScriptRoot
function Test-GamingWindowsAdministrator {
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-GamingWindowsDefinitions {
    @(
        [pscustomobject]@{Id='GameModeAuto';Group='GameMode';Hive='CurrentUser';Path='Software\Microsoft\GameBar';Name='AutoGameModeEnabled';Enabled=1;Disabled=0},
        [pscustomobject]@{Id='GameModeAllow';Group='GameMode';Hive='CurrentUser';Path='Software\Microsoft\GameBar';Name='AllowAutoGameMode';Enabled=1;Disabled=0},
        [pscustomobject]@{Id='HardwareScheduling';Group='HardwareScheduling';Hive='LocalMachine';Path='SYSTEM\CurrentControlSet\Control\GraphicsDrivers';Name='HwSchMode';Enabled=2;Disabled=1},
        [pscustomobject]@{Id='BackgroundCapture';Group='BackgroundCapture';Hive='CurrentUser';Path='Software\Microsoft\Windows\CurrentVersion\GameDVR';Name='HistoricalCaptureEnabled';Enabled=1;Disabled=0}
    )
}
function Read-GamingWindowsValue {
    param($Definition)
    $hive=if($Definition.Hive -eq 'LocalMachine'){[Microsoft.Win32.Registry]::LocalMachine}else{[Microsoft.Win32.Registry]::CurrentUser}
    $key=$hive.OpenSubKey($Definition.Path)
    try {$exists=$key -and $Definition.Name -in @($key.GetValueNames());[pscustomobject]@{Exists=[bool]$exists;Value=$(if($exists){$key.GetValue($Definition.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}else{$null});Kind=$(if($exists){[string]$key.GetValueKind($Definition.Name)}else{'DWord'})}}
    finally {if($key){$key.Dispose()}}
}
function Write-GamingWindowsValue {
    param($Definition,$Value)
    $Value=ConvertTo-GamingWindowsValue $Value
    $hive=if($Definition.Hive -eq 'LocalMachine'){[Microsoft.Win32.Registry]::LocalMachine}else{[Microsoft.Win32.Registry]::CurrentUser}
    $key=$hive.CreateSubKey($Definition.Path)
    try {if($Value.Exists){$kind=[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],[string]$Value.Kind,$false);$key.SetValue($Definition.Name,$Value.Value,$kind)}else{$key.DeleteValue($Definition.Name,$false)}}finally{$key.Dispose()}
}
function ConvertTo-GamingWindowsValue {
    param($Value)
    if($null -eq $Value -or @($Value.PSObject.Properties.Name|Where-Object {$_ -notin @('Exists','Value','Kind')}).Count -or $Value.Exists -isnot [bool] -or $Value.Kind -notin @('DWord','QWord','String','ExpandString','Binary','MultiString','None')){throw 'Invalid saved registry value.'}
    $converted=$null
    if($Value.Exists){
        switch([string]$Value.Kind){
            DWord {if(($Value.Value -isnot [int] -and $Value.Value -isnot [long]) -or $Value.Value -lt [int]::MinValue -or $Value.Value -gt [int]::MaxValue){throw 'Invalid saved DWORD.'};$converted=[int]$Value.Value}
            QWord {if($Value.Value -isnot [int] -and $Value.Value -isnot [long]){throw 'Invalid saved QWORD.'};$converted=[long]$Value.Value}
            {$_ -in @('String','ExpandString')} {if($Value.Value -isnot [string]){throw 'Invalid saved registry string.'};$converted=[string]$Value.Value}
            MultiString {if($null -eq $Value.Value -or $Value.Value -is [string] -or @($Value.Value|Where-Object {$_ -isnot [string]}).Count){throw 'Invalid saved string array.'};$converted=[string[]]@($Value.Value)}
            {$_ -in @('Binary','None')} {if($null -eq $Value.Value -or $Value.Value -is [string] -or @($Value.Value|Where-Object {($_ -isnot [byte] -and $_ -isnot [int] -and $_ -isnot [long]) -or $_ -lt 0 -or $_ -gt 255}).Count){throw 'Invalid saved binary value.'};$converted=[byte[]]@($Value.Value)}
        }
    }
    [pscustomobject]@{Exists=$Value.Exists;Kind=[string]$Value.Kind;Value=$converted}
}
function Test-GamingWindowsValueEqual {
    param($Left,$Right)
    $Left=ConvertTo-GamingWindowsValue $Left;$Right=ConvertTo-GamingWindowsValue $Right
    if($Left.Exists -ne $Right.Exists){return $false};if(-not $Left.Exists){return $true};if($Left.Kind -cne $Right.Kind){return $false}
    if($Left.Kind -in @('Binary','None','MultiString')){$a=@($Left.Value);$b=@($Right.Value);if($a.Count -ne $b.Count){return $false};for($i=0;$i -lt $a.Count;$i++){if([string]$a[$i] -cne [string]$b[$i]){return $false}};return $true}
    return [string]$Left.Value -ceq [string]$Right.Value
}
function Write-GamingWindowsJson {
    param([string]$Path,$Value)
    $folder=[IO.Path]::GetDirectoryName($Path);[void][IO.Directory]::CreateDirectory($folder)
    $pending=Join-Path $folder ([IO.Path]::GetFileName($Path)+'.'+[guid]::NewGuid().ToString('N')+'.pending')
    [IO.File]::WriteAllText($pending,($Value|ConvertTo-Json -Depth 16),(New-Object Text.UTF8Encoding($false)))
    if([IO.File]::Exists($Path)){[IO.File]::Replace($pending,$Path,[NullString]::Value)}else{[IO.File]::Move($pending,$Path)}
}
function Get-GamingWindowsSettings {
    $settings=[ordered]@{GameMode='Default';HardwareScheduling='Default';BackgroundCapture='Default';IsAdministrator=(Test-GamingWindowsAdministrator);HardwareSchedulingMessage='Saved scheduling preference. Windows requires a supported GPU/driver and a restart to activate changes.'}
    foreach($definition in Get-GamingWindowsDefinitions){if($definition.Id -eq 'GameModeAllow'){continue};$value=Read-GamingWindowsValue $definition;if($value.Exists -and $value.Kind -eq 'DWord'){$settings[$definition.Group]=if($value.Value -eq $definition.Enabled){'Enabled'}elseif($value.Value -eq $definition.Disabled){'Disabled'}else{'Default'}}}
    [pscustomobject]$settings
}
function Read-GamingWindowsJournal {
    $path=Join-Path $script:GamingWindowsRoot 'state\windows-settings-journal.json'
    if(-not(Test-Path -LiteralPath $path)){return [pscustomobject]@{Version=1;Entries=@()}}
    if((Get-Item -LiteralPath $path).Length -gt 1048576){throw 'Windows settings journal is too large.'}
    $value=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($value.Version -ne 1 -or @($value.Entries).Count -gt 4){throw 'Invalid Windows settings journal.'}
    if(@($value.PSObject.Properties.Name|Where-Object {$_ -notin @('Version','Entries')}).Count -or @($value.Entries|Group-Object Id|Where-Object Count -gt 1).Count){throw 'Invalid Windows settings journal.'}
    foreach($entry in @($value.Entries)){
        if($entry.Id -notin @(Get-GamingWindowsDefinitions|ForEach-Object Id) -or $entry.Status -notin @('Pending','Applied') -or @($entry.PSObject.Properties.Name|Where-Object {$_ -notin @('Id','Before','Applied','Status')}).Count){throw 'Invalid saved Windows setting.'}
        $entry.Before=ConvertTo-GamingWindowsValue $entry.Before;$entry.Applied=ConvertTo-GamingWindowsValue $entry.Applied
    }
    return $value
}
function Save-GamingWindowsJournal {
    param($Value)
    Write-GamingWindowsJson -Path (Join-Path $script:GamingWindowsRoot 'state\windows-settings-journal.json') -Value $Value
}
function Set-GamingWindowsSettings {
    param([ValidateSet('Default','Enabled','Disabled')][string]$GameMode,[ValidateSet('Default','Enabled','Disabled')][string]$HardwareScheduling,[ValidateSet('Default','Enabled','Disabled')][string]$BackgroundCapture)
    $current=Get-GamingWindowsSettings;$bound=$PSBoundParameters
    # Compare every backing value, including AllowAutoGameMode. The visible group
    # label alone cannot detect mixed or unrecognized registry values.
    $changes=@(Get-GamingWindowsDefinitions|Where-Object {
        if(-not $bound.ContainsKey($_.Group)){return $false}
        $choice=[string]$bound[$_.Group];$wanted=[pscustomobject]@{Exists=($choice -ne 'Default');Value=$(if($choice -eq 'Enabled'){$_.Enabled}elseif($choice -eq 'Disabled'){$_.Disabled}else{$null});Kind='DWord'}
        -not(Test-GamingWindowsValueEqual (Read-GamingWindowsValue $_) $wanted)
    })
    if(@($changes|Where-Object Hive -eq 'LocalMachine').Count -and -not $current.IsAdministrator){return [pscustomobject]@{Success=$false;RequiresElevation=$true;Message='Restart this app as administrator to change GPU scheduling. No changes were made.'}}
    $journal=Read-GamingWindowsJournal;$results=@()
    foreach($definition in $changes){
        try {
            $choice=[string]$bound[$definition.Group];$wanted=[pscustomobject]@{Exists=($choice -ne 'Default');Value=$(if($choice -eq 'Enabled'){$definition.Enabled}elseif($choice -eq 'Disabled'){$definition.Disabled}else{$null});Kind='DWord'}
            $entry=$journal.Entries|Where-Object Id -eq $definition.Id|Select-Object -First 1
            if(-not $entry){$entry=[pscustomobject]@{Id=$definition.Id;Before=(Read-GamingWindowsValue $definition);Applied=$wanted;Status='Pending'};$journal.Entries=@($journal.Entries)+@($entry)}
            $entry.Applied=$wanted;$entry.Status='Pending';Save-GamingWindowsJournal $journal
            Write-GamingWindowsValue $definition $wanted
            if(-not(Test-GamingWindowsValueEqual (Read-GamingWindowsValue $definition) $wanted)){throw 'Setting did not verify.'}
            $entry.Status='Applied';Save-GamingWindowsJournal $journal
            $results+=[pscustomobject]@{Name=$definition.Id;Success=$true;Message='Saved and verified.'}
        } catch {$results+=[pscustomobject]@{Name=$definition.Id;Success=$false;Message=$_.Exception.Message}}
    }
    $success=@($results|Where-Object{-not $_.Success}).Count -eq 0
    [pscustomobject]@{Success=$success;RequiresElevation=$false;Results=$results;RestartRequired=(@($results|Where-Object {$_.Name -eq 'HardwareScheduling' -and $_.Success}).Count -gt 0);Message=$(if(-not $success){'Some preferences could not be saved. Review the results; restore records are retained for any applied values.'}elseif(-not $results.Count){'These Windows preferences are already set.'}else{'Windows preferences saved and verified. Restart the game; GPU scheduling changes require restarting Windows. Restore is available here.'})}
}
function Restore-GamingWindowsSettings {
    $journal=Read-GamingWindowsJournal;$results=@()
    if(@($journal.Entries|Where-Object Id -eq 'HardwareScheduling').Count -and -not(Test-GamingWindowsAdministrator)){return [pscustomobject]@{Success=$false;RequiresElevation=$true;Message='Restart this app as administrator to restore GPU scheduling. No changes were made.'}}
    foreach($entry in @($journal.Entries)){
        try {
            $definition=Get-GamingWindowsDefinitions|Where-Object Id -eq $entry.Id|Select-Object -First 1
            $current=Read-GamingWindowsValue $definition
            $kept=-not(Test-GamingWindowsValueEqual $current $entry.Applied)
            if(-not $kept){Write-GamingWindowsValue $definition $entry.Before;if(-not(Test-GamingWindowsValueEqual (Read-GamingWindowsValue $definition) $entry.Before)){throw 'Restore did not verify.'}}
            $journal.Entries=@($journal.Entries|Where-Object Id -ne $entry.Id);Save-GamingWindowsJournal $journal
            $results+=[pscustomobject]@{Name=$entry.Id;Success=$true;Message=$(if($kept){'A later manual change was preserved.'}else{'Original value restored.'})}
        } catch {$results+=[pscustomobject]@{Name=$entry.Id;Success=$false;Message=$_.Exception.Message}}
    }
    [pscustomobject]@{Success=(@($results|Where-Object{-not $_.Success}).Count -eq 0);RequiresElevation=$false;Results=$results;Message='Windows settings restore processed. A restart may be needed for scheduling.'}
}
function Get-GamingGpuPreferenceDefinition {
    param([string]$ExecutablePath)
    if($ExecutablePath -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($ExecutablePath) -ine '.exe' -or $ExecutablePath -match '[\x00-\x1F]'){throw 'Choose a local game EXE.'}
    [pscustomobject]@{Hive='CurrentUser';Path='Software\Microsoft\DirectX\UserGpuPreferences';Name=[IO.Path]::GetFullPath($ExecutablePath)}
}
function Get-GamingGpuPreference {
    param([string]$ExecutablePath)
    $value=Read-GamingWindowsValue (Get-GamingGpuPreferenceDefinition $ExecutablePath)
    $match=[regex]::Match([string]$value.Value,'(?:^|;)GpuPreference=([012])(?:;|$)')
    [pscustomobject]@{Preference=$(if($match.Success -and $match.Groups[1].Value -eq '1'){'PowerSaving'}elseif($match.Success -and $match.Groups[1].Value -eq '2'){'HighPerformance'}else{'Default'});Message='Windows GPU preference; effective GPU selection also depends on the game and installed GPUs.'}
}
function Read-GamingGpuPreferenceJournal {
    $path=Join-Path $script:GamingWindowsRoot 'state\gpu-preference-journal.json'
    if(-not(Test-Path -LiteralPath $path)){return [pscustomobject]@{Version=1;Entries=@()}}
    if((Get-Item -LiteralPath $path).Length -gt 4194304){throw 'GPU preference journal is too large.'}
    $journal=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($journal.Version -ne 1 -or @($journal.Entries).Count -gt 4096 -or @($journal.PSObject.Properties.Name|Where-Object {$_ -notin @('Version','Entries')}).Count){throw 'Invalid GPU preference journal.'}
    $paths=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in @($journal.Entries)){
        if(@($entry.PSObject.Properties.Name|Where-Object {$_ -notin @('ExecutablePath','Before','Applied')}).Count){throw 'Invalid GPU preference entry.'}
        $definition=Get-GamingGpuPreferenceDefinition ([string]$entry.ExecutablePath)
        if(-not $paths.Add($definition.Name)){throw 'Duplicate GPU preference restore entry.'}
        $entry.ExecutablePath=$definition.Name
        $entry.Before=ConvertTo-GamingWindowsValue $entry.Before;$entry.Applied=ConvertTo-GamingWindowsValue $entry.Applied
        if($entry.Applied.Exists -and $entry.Applied.Kind -ne 'String'){throw 'Invalid applied GPU preference type.'}
    }
    return $journal
}
function Set-GamingGpuPreference {
    param([string]$ExecutablePath,[ValidateSet('Default','PowerSaving','HighPerformance')][string]$Preference)
    $definition=Get-GamingGpuPreferenceDefinition $ExecutablePath;$before=Read-GamingWindowsValue $definition
    $path=Join-Path $script:GamingWindowsRoot 'state\gpu-preference-journal.json';$journal=Read-GamingGpuPreferenceJournal;$rows=@($journal.Entries)
    $entry=$rows|Where-Object ExecutablePath -ieq $definition.Name|Select-Object -First 1
    if(-not $entry){$entry=[pscustomobject]@{ExecutablePath=$definition.Name;Before=$before;Applied=$null};$rows+=@($entry)}
    if($before.Exists -and $before.Kind -ne 'String'){throw 'This EXE has an unexpected registry value type. Its existing value was preserved.'}
    $tokens=@(([string]$before.Value).Split(';')|Where-Object{$_ -and $_ -notmatch '^GpuPreference='})
    if($Preference -ne 'Default'){$tokens+=@('GpuPreference='+$(if($Preference -eq 'PowerSaving'){'1'}else{'2'}))}
    $wanted=[pscustomobject]@{Exists=($tokens.Count -gt 0);Value=$(if($tokens.Count){($tokens -join ';')+';'}else{$null});Kind='String'};$entry.Applied=$wanted
    if(Test-GamingWindowsValueEqual $before $wanted){return [pscustomobject]@{Success=$true;Message='That Windows GPU preference is already set.'}}
    Write-GamingWindowsJson -Path $path -Value ([pscustomobject]@{Version=1;Entries=$rows})
    Write-GamingWindowsValue $definition $wanted
    if(-not(Test-GamingWindowsValueEqual (Read-GamingWindowsValue $definition) $wanted)){throw 'Windows GPU preference did not verify.'}
    [pscustomobject]@{Success=$true;Message='Windows GPU preference saved for this EXE. Restart the game.'}
}
function Restore-GamingGpuPreference {
    param([string]$ExecutablePath)
    $definition=Get-GamingGpuPreferenceDefinition $ExecutablePath;$path=Join-Path $script:GamingWindowsRoot 'state\gpu-preference-journal.json'
    if(-not(Test-Path -LiteralPath $path)){return [pscustomobject]@{Success=$true;Message='No saved Windows GPU preference to restore.'}}
    $journal=Read-GamingGpuPreferenceJournal
    $entry=$journal.Entries|Where-Object ExecutablePath -ieq $definition.Name|Select-Object -First 1
    if(-not $entry){return [pscustomobject]@{Success=$true;Message='No saved Windows GPU preference for this EXE.'}}
    $kept=-not(Test-GamingWindowsValueEqual (Read-GamingWindowsValue $definition) $entry.Applied)
    if(-not $kept){Write-GamingWindowsValue $definition $entry.Before;if(-not(Test-GamingWindowsValueEqual (Read-GamingWindowsValue $definition) $entry.Before)){throw 'GPU preference restore did not verify.'}}
    $journal.Entries=@($journal.Entries|Where-Object ExecutablePath -ine $definition.Name);Write-GamingWindowsJson -Path $path -Value $journal
    [pscustomobject]@{Success=$true;Message=$(if($kept){'A later GPU preference change was preserved.'}else{'Original Windows GPU preference restored.'})}
}
function Initialize-GamingWindowsDisplay {
    if('GamingWindowsDisplay' -as [type]){return}
    Add-Type -Path (Join-Path $script:GamingWindowsRoot 'WindowsDisplayNative.cs')
}
function Get-GamingDisplayModes {Initialize-GamingWindowsDisplay;[GamingWindowsDisplay]::Modes()|Sort-Object RefreshHz}
function Set-GamingDisplayMode {
    param([string]$Key)
    $mode=Get-GamingDisplayModes|Where-Object Key -ceq $Key|Select-Object -First 1
    if(-not $mode){throw 'Select a supported primary-display refresh rate.'}
    if($mode.IsCurrent){return [pscustomobject]@{Success=$true;RequiresConfirmation=$false;Message='That refresh rate is already active.'}}
    $folder=Join-Path $script:GamingWindowsRoot 'state';[void][IO.Directory]::CreateDirectory($folder)
    $token=[guid]::NewGuid().ToString('N');$stem=Join-Path $folder ('display-'+$token);$parent=Get-Process -Id $PID
    [pscustomobject]@{Version=1;Token=$token;Key=$Key;ParentProcessId=$PID;ParentStartTicks=[string]$parent.StartTime.ToUniversalTime().Ticks}|ConvertTo-Json|Set-Content -LiteralPath ($stem+'.request.json') -Encoding UTF8
    $worker=Join-Path $script:GamingWindowsRoot 'DisplayWorker.ps1'
    $null=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$worker+'" -RequestPath "'+$stem+'.request.json"') -WindowStyle Hidden -PassThru
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($clock.Elapsed.TotalSeconds -lt 5){if(Test-Path -LiteralPath ($stem+'.status.json')){$status=Get-Content -LiteralPath ($stem+'.status.json') -Raw|ConvertFrom-Json;if($status.Token -eq $token){return $status}};Start-Sleep -Milliseconds 50}
    [pscustomobject]@{Success=$false;RequiresConfirmation=$false;Message='The display worker did not respond. Any unconfirmed change automatically reverts.'}
}
function Confirm-GamingDisplayMode {
    param([string]$Token)
    if($Token -notmatch '^[a-f0-9]{32}$'){throw 'Invalid display confirmation.'}
    $stem=Join-Path $script:GamingWindowsRoot ('state\display-'+$Token)
    $status=Get-Content -LiteralPath ($stem+'.status.json') -Raw|ConvertFrom-Json
    $deadline=[DateTimeOffset]::Parse([string]$status.DeadlineUtc,[Globalization.CultureInfo]::InvariantCulture).UtcDateTime
    if($status.Token -ne $Token -or -not $status.RequiresConfirmation -or [datetime]::UtcNow -ge $deadline){return [pscustomobject]@{Success=$false;Message='Display confirmation expired; the original rate is being restored.'}}
    Set-Content -LiteralPath ($stem+'.keep') -Value $Token -Encoding ASCII
    $clock=[Diagnostics.Stopwatch]::StartNew()
    while($clock.Elapsed.TotalSeconds -lt 3){
        $reply=Get-Content -LiteralPath ($stem+'.status.json') -Raw|ConvertFrom-Json
        if($reply.Token -ne $Token){throw 'Display status belongs to a different request.'}
        if(-not $reply.RequiresConfirmation){return [pscustomobject]@{Success=($reply.Success -and $reply.State -eq 'Kept');Message=[string]$reply.Message}}
        Start-Sleep -Milliseconds 50
    }
    [pscustomobject]@{Success=$false;Message='Windows has not confirmed keeping this rate. Wait for confirmation or revert; unconfirmed previews expire automatically.'}
}
function Revert-GamingDisplayMode {
    param([string]$Token)
    if($Token -notmatch '^[a-f0-9]{32}$'){throw 'Invalid display confirmation.'}
    Set-Content -LiteralPath (Join-Path $script:GamingWindowsRoot ('state\display-'+$Token+'.revert')) -Value $Token -Encoding ASCII
    [pscustomobject]@{Success=$true;Message='Original display rate will be restored.'}
}
