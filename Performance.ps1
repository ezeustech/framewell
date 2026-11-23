# Local status and reversible session settings. No changes occur on import.
$script:GamingPerformanceRoot=$PSScriptRoot
function Get-GamingPreferences {
    $defaults=[ordered]@{Version=2;Theme='Dark';DeepTrim=$true;KeepISLC=$false;PowerMode='Current';ReduceAnimations=$false;ReduceTransparency=$false;DisableBackgroundCapture=$true;DisableBrowserBackground=$true;CloseBrowsers=$true;CloseLaunchers=$true;CloseCloudSync=$true;CloseMediaApps=$true;CloseDesktopExtras=$true;PauseSearch=$true;PausePrinting=$true;PauseVR=$true;PausePeripheralHelpers=$true;ReduceMenuAnimation=$false;ReduceTooltipAnimation=$false;ReduceComboAnimation=$false;DisableCursorShadow=$false;DisableMouseAcceleration=$false;PreventSleep=$false;CloseAfterActivation=$true}
    $path=Join-Path $script:GamingPerformanceRoot 'state\preferences.json'
    if(Test-Path -LiteralPath $path){
        $saved=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach($key in @($defaults.Keys)){if($saved.PSObject.Properties[$key]){$defaults[$key]=$saved.$key}}
    }
    $defaults.Version=2
    [pscustomobject]$defaults
}
function Set-GamingPreferences {
    param([Parameter(Mandatory=$true)]$Preferences)
    $checked=Get-GamingPreferences
    foreach($key in @('DeepTrim','KeepISLC','ReduceAnimations','ReduceTransparency','DisableBackgroundCapture','DisableBrowserBackground','CloseBrowsers','CloseLaunchers','CloseCloudSync','CloseMediaApps','CloseDesktopExtras','PauseSearch','PausePrinting','PauseVR','PausePeripheralHelpers','ReduceMenuAnimation','ReduceTooltipAnimation','ReduceComboAnimation','DisableCursorShadow','DisableMouseAcceleration','PreventSleep','CloseAfterActivation')){
        if($Preferences.PSObject.Properties[$key]){
            if($Preferences.$key -isnot [bool]){throw "Invalid preference: $key"}
            $checked.$key=[bool]$Preferences.$key
        }
    }
    if($Preferences.PSObject.Properties['PowerMode']){
        if($Preferences.PowerMode -notin @('Current','HighPerformance','Balanced')){throw 'Unknown power mode.'}
        $checked.PowerMode=$Preferences.PowerMode
    }
    if($Preferences.PSObject.Properties['Theme']){
        $themes=@('Dark','Light','OLED','Midnight','System')
        if(Get-Command Get-GamingThemes -ErrorAction SilentlyContinue){$themes+=@(Get-GamingThemes|ForEach-Object Id)}
        if($Preferences.Theme -notin $themes){throw 'Unknown appearance.'}
        $checked.Theme=[string]$Preferences.Theme
    }
    $folder=Join-Path $script:GamingPerformanceRoot 'state'
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $temporary=Join-Path $folder ('preferences.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    $checked | ConvertTo-Json | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination (Join-Path $folder 'preferences.json') -Force
    return $checked
}
function Initialize-GamingNative {
    if('GamingNativeMetrics' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GamingNativeMetrics {
 [DllImport("ntdll.dll")] public static extern int NtQueryTimerResolution(out uint maximum, out uint minimum, out uint current);
 [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)] static extern bool GetParameter(uint action,uint value,out int result,uint flags);
 [DllImport("user32.dll", EntryPoint="SystemParametersInfoW", SetLastError=true)] static extern bool SetParameter(uint action,uint value,IntPtr result,uint flags);
 public static bool Animations() { int result; if(!GetParameter(0x1042,0,out result,0))throw new System.ComponentModel.Win32Exception();return result!=0; }
 public static void SetAnimations(bool enabled) { if(!SetParameter(0x1043,0,new IntPtr(enabled?1:0),3))throw new System.ComponentModel.Win32Exception(); }
}
'@
}
function Get-GamingPowerPlan {
    $line=(& "$env:WINDIR\System32\powercfg.exe" /getactivescheme | Out-String).Trim()
    $guid=[regex]::Match($line,'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}').Value
    $name=[regex]::Match($line,'\((.*)\)').Groups[1].Value
    [pscustomobject]@{Guid=$guid;Name=$name}
}
function Get-GamingRegistryDefinitions {
    @(
        [pscustomobject]@{Id='BackgroundCapture';Preference='DisableBackgroundCapture';Path='Software\Microsoft\Windows\CurrentVersion\GameDVR';Name='HistoricalCaptureEnabled';Value=0;Label='Background game recording'},
        [pscustomobject]@{Id='Transparency';Preference='ReduceTransparency';Path='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';Name='EnableTransparency';Value=0;Label='Windows transparency'},
        [pscustomobject]@{Id='EdgeBackground';Preference='DisableBrowserBackground';Path='Software\Policies\Microsoft\Edge';Name='BackgroundModeEnabled';Value=0;Label='Edge background mode'},
        [pscustomobject]@{Id='EdgeStartup';Preference='DisableBrowserBackground';Path='Software\Policies\Microsoft\Edge';Name='StartupBoostEnabled';Value=0;Label='Edge startup boost'},
        [pscustomobject]@{Id='ChromeBackground';Preference='DisableBrowserBackground';Path='Software\Policies\Google\Chrome';Name='BackgroundModeEnabled';Value=0;Label='Chrome background mode'}
    )
}
function Read-GamingRegistryValue([string]$Path,[string]$Name) {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Path)
    try{
        $exists=$null -ne $key -and @($key.GetValueNames()) -contains $Name
        [pscustomobject]@{Exists=$exists;Value=$(if($exists){$key.GetValue($Name)}else{$null});Kind=$(if($exists){[string]$key.GetValueKind($Name)}else{'DWord'})}
    }finally{if($key){$key.Dispose()}}
}
function Get-GamingTuningSnapshot {
    param($Preferences)
    if(-not $Preferences){$Preferences=Get-GamingPreferences}
    $registry=@(foreach($definition in Get-GamingRegistryDefinitions){
        if($Preferences.($definition.Preference)){
            [pscustomobject]@{Id=$definition.Id;Before=Read-GamingRegistryValue $definition.Path $definition.Name;Desired=$definition.Value}
        }
    })
    $animations=$null
    if($Preferences.ReduceAnimations){Initialize-GamingNative;$animations=[GamingNativeMetrics]::Animations()}
    $extra=if(Get-Command Get-GamingExtraSnapshot -ErrorAction SilentlyContinue){Get-GamingExtraSnapshot -Preferences $Preferences}else{$null}
    [pscustomobject]@{Version=1;PowerBefore=Get-GamingPowerPlan;PowerMode=$Preferences.PowerMode;AnimationBefore=$animations;Registry=$registry;Extra=$extra}
}
function Invoke-GamingTuning {
    param([Parameter(Mandatory=$true)]$Snapshot,[ValidateSet('Apply','Restore')][string]$Operation='Apply',[switch]$NoElevation)
    if($Snapshot.Version -ne 1){throw 'Unknown performance snapshot.'}
    $results=@()
    foreach($entry in @($Snapshot.Registry)){
        $definition=Get-GamingRegistryDefinitions | Where-Object Id -eq $entry.Id | Select-Object -First 1
        if(-not $definition){throw 'Unknown saved performance setting.'}
        try{
            $current=Read-GamingRegistryValue $definition.Path $definition.Name
            $wanted=if($Operation -eq 'Apply'){[int]$definition.Value}else{$entry.Before.Value}
            $wantedExists=$Operation -eq 'Apply' -or $entry.Before.Exists
            $wantedKind=if($Operation -eq 'Apply'){'DWord'}else{[string]$entry.Before.Kind}
            $matchesWanted=$current.Exists -eq $wantedExists -and (-not $wantedExists -or ($current.Value -eq $wanted -and $current.Kind -eq $wantedKind))
            if($Operation -eq 'Restore' -and (-not $current.Exists -or $current.Value -ne $definition.Value -or $current.Kind -ne 'DWord') -and -not $matchesWanted){
                $results+=[pscustomobject]@{Name=$definition.Label;Status='KeptUserChange';Success=$true;Message='A later change was kept.'};continue
            }
            if($matchesWanted){
                $results+=[pscustomobject]@{Name=$definition.Label;Status='AlreadySet';Success=$true;Message='Already at the selected value.'};continue
            }
            $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($definition.Path)
            try{
                if($wantedExists){$key.SetValue($definition.Name,$wanted,[Microsoft.Win32.RegistryValueKind]::$wantedKind)}
                else{$key.DeleteValue($definition.Name,$false)}
            }finally{$key.Dispose()}
            $readback=Read-GamingRegistryValue $definition.Path $definition.Name
            if($readback.Exists -ne $wantedExists -or ($wantedExists -and ($readback.Value -ne $wanted -or $readback.Kind -ne $wantedKind))){throw 'Setting did not verify.'}
            $results+=[pscustomobject]@{Name=$definition.Label;Status=$Operation;Success=$true;Message='Saved and verified. Some desktop/browser effects apply when the app reopens.'}
        }catch{
            $permissionDenied=$false;$exception=$_.Exception
            while($exception){if($exception -is [UnauthorizedAccessException] -or $exception -is [System.Security.SecurityException]){$permissionDenied=$true};$exception=$exception.InnerException}
            $results+=[pscustomobject]@{Id=$definition.Id;Name=$definition.Label;Status='Failed';Success=$false;CanElevate=$permissionDenied;Message=$_.Exception.Message}
        }
    }
    if($null -ne $Snapshot.AnimationBefore){
        try{
            Initialize-GamingNative
            $wanted=if($Operation -eq 'Apply'){$false}else{[bool]$Snapshot.AnimationBefore}
            if($Operation -eq 'Restore' -and [GamingNativeMetrics]::Animations() -and -not $wanted){
                $results+=[pscustomobject]@{Name='Desktop animations';Status='KeptUserChange';Success=$true;Message='A later animation preference was kept.'}
            }else{
                [GamingNativeMetrics]::SetAnimations($wanted)
                if([GamingNativeMetrics]::Animations() -ne $wanted){throw 'Animation setting did not verify.'}
                $results+=[pscustomobject]@{Name='Desktop animations';Status=$Operation;Success=$true;Message='Applied with the Windows settings API.'}
            }
        }catch{$results+=[pscustomobject]@{Name='Desktop animations';Status='Failed';Success=$false;Message=$_.Exception.Message}}
    }
    if($Snapshot.PowerMode -in @('HighPerformance','Balanced')){
        try{
            $high=if($Snapshot.PowerMode -eq 'Balanced'){'381b4222-f694-41f0-9685-ff5bb260df2e'}else{'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'}
            $current=Get-GamingPowerPlan
            $wanted=if($Operation -eq 'Apply'){$high}else{[string]$Snapshot.PowerBefore.Guid}
            if($wanted -notmatch '^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$'){throw 'Invalid saved power plan.'}
            if($Operation -eq 'Restore' -and $current.Guid -notin @($high,$wanted)){
                $results+=[pscustomobject]@{Name='Power plan';Status='KeptUserChange';Success=$true;Message='A later power-plan selection was kept.'}
            }else{
                & "$env:WINDIR\System32\powercfg.exe" /setactive $wanted | Out-Null
                if($LASTEXITCODE -ne 0 -or (Get-GamingPowerPlan).Guid -ne $wanted){throw 'Power plan could not be selected.'}
                $results+=[pscustomobject]@{Name='Power plan';Status=$Operation;Success=$true;Message='Selected and verified.'}
            }
        }catch{$results+=[pscustomobject]@{Name='Power plan';Status='Failed';Success=$false;Message=$_.Exception.Message}}
    }
    $retryIds=@($results | Where-Object {$_.CanElevate -and -not $_.Success} | ForEach-Object Id)
    if(-not $NoElevation -and $retryIds.Count){
        Write-GamingStatus 'Windows may request permission for the selected browser background policies...'
        $retry=[pscustomobject]@{Version=1;PowerMode='Current';AnimationBefore=$null;Registry=@($Snapshot.Registry | Where-Object {$_.Id -in $retryIds})}
        $elevated=Invoke-ElevatedGamingTuning -Snapshot $retry -Operation $Operation
        $retryNames=@(Get-GamingRegistryDefinitions | Where-Object {$_.Id -in $retryIds} | ForEach-Object Label)
        $results=@($results | Where-Object {$_.Name -notin $retryNames})+@($elevated.Results)
    }
    if($Snapshot.PSObject.Properties['Extra'] -and $Snapshot.Extra){
        $extraResult=Invoke-GamingExtras -Snapshot $Snapshot.Extra -Operation $Operation
        $results+=@($extraResult.Results)
    }
    [pscustomobject]@{Success=(@($results | Where-Object {-not $_.Success}).Count -eq 0);Results=$results}
}
function Get-PerformanceDashboard {
    $os=Get-CimInstance Win32_OperatingSystem
    if(-not $script:GamingHardwareCache){
        $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
        $gpus=@(Get-CimInstance Win32_VideoController)
        $gpu=$gpus | Where-Object Name -match 'NVIDIA' | Select-Object -First 1
        if(-not $gpu){$gpu=$gpus | Select-Object -First 1}
        $script:GamingHardwareCache=[pscustomobject]@{Cpu=$cpu.Name.Trim();Gpu=$gpu.Name;Refresh=$gpu.CurrentRefreshRate}
    }
    $gm=Read-GamingRegistryValue 'Software\Microsoft\GameBar' 'AutoGameModeEnabled'
    $gameMode=if($gm.Exists){[bool]$gm.Value}else{'Windows default'}
    $hags=(Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
    $hagsState=if($hags -eq 2){'Enabled'}elseif($hags -eq 1){'Disabled'}else{'Windows default'}
    # DxDiag confirms the active driver state when no registry override exists.
    $diagnostic=Join-Path $env:USERPROFILE 'AppData\Local\Temp\GamingMode-readonly-dxdiag.txt'
    if(Test-Path -LiteralPath $diagnostic){
        $diagText=Get-Content -LiteralPath $diagnostic -Raw
        if($diagText -match 'Hardware Scheduling:\s*[^\r\n]*Enabled:True'){$hagsState='Enabled (driver verified)'}
        if($diagText -match 'Current Mode:\s*\d+ x \d+[^\r\n]*\((\d+)Hz\)'){$script:GamingHardwareCache.Refresh=[int]$Matches[1]}
    }
    Initialize-GamingNative
    [uint32]$maximum=0;[uint32]$minimum=0;[uint32]$current=0
    $timerStatus=[GamingNativeMetrics]::NtQueryTimerResolution([ref]$maximum,[ref]$minimum,[ref]$current)
    $wifiText=(& "$env:WINDIR\System32\netsh.exe" wlan show interfaces | Out-String)
    $band=[regex]::Match($wifiText,'(?im)^\s*Band\s*:\s*(.+)$').Groups[1].Value.Trim()
    $speed=[regex]::Match($wifiText,'(?im)^\s*Receive rate \(Mbps\)\s*:\s*(.+)$').Groups[1].Value.Trim()
    $signal=[regex]::Match($wifiText,'(?im)^\s*Signal\s*:\s*(.+)$').Groups[1].Value.Trim()
    $wifi=if($speed){"Wi-Fi $band | $speed Mbps link | $signal signal"}else{'Ethernet / Windows network details'}
    $capture=Read-GamingRegistryValue 'Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled'
    $mouse=Read-GamingRegistryValue 'Control Panel\Mouse' 'MouseSpeed'
    [pscustomobject]@{
        CpuName=$script:GamingHardwareCache.Cpu;GpuName=$script:GamingHardwareCache.Gpu
        RamGiB=[math]::Round($os.TotalVisibleMemorySize/1MB,1);UsedRamGiB=[math]::Round(($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB,1)
        ProcessCount=@(Get-Process).Count;GameMode=$gameMode;HAGS=$hagsState
        BackgroundRecording=$(if($capture.Exists){[bool]$capture.Value}else{'Windows default'})
        RefreshHz=$script:GamingHardwareCache.Refresh;PowerPlan=(Get-GamingPowerPlan).Name
        TimerCurrentMs=$(if($timerStatus -eq 0){[math]::Round($current/10000,3)}else{$null})
        TimerMinimumMs=$(if($timerStatus -eq 0){[math]::Round($minimum/10000,3)}else{$null})
        ISLCRunning=[bool](Get-Process -Name 'Intelligent standby list cleaner ISLC' -ErrorAction SilentlyContinue)
        WifiSummary=$wifi;MouseAcceleration=$(if($mouse.Exists){[string]$mouse.Value -ne '0'}else{$null})
    }
}
function Open-GamingSetting {
    param([Parameter(Mandatory=$true)][string]$Name)
    $settings=@{Gaming='ms-settings:gaming-gamemode';Graphics='ms-settings:display-advancedgraphics-default';PerGameGraphics='ms-settings:display-advancedgraphics';Captures='ms-settings:gaming-gamedvr';Display='ms-settings:display';Power='ms-settings:powersleep';Network='ms-settings:network-status';Mouse='ms-settings:mousetouchpad';Storage='ms-settings:storagesense';Startup='ms-settings:startupapps'}
    if($Name -eq 'Nvidia'){
        $entry=Get-StartApps | Where-Object {$_.Name -match 'NVIDIA Control Panel'} | Select-Object -First 1
        if($entry){Start-Process "$env:WINDIR\explorer.exe" -ArgumentList ('shell:AppsFolder\'+$entry.AppID) -WindowStyle Normal;return}
        $exe='C:\Program Files\NVIDIA Corporation\Control Panel Client\nvcplui.exe'
        if(Test-Path -LiteralPath $exe){Start-Process $exe -WindowStyle Normal;return}
        throw 'NVIDIA Control Panel is not registered. Open NVIDIA App from Start.'
    }
    if(-not $settings.ContainsKey($Name)){throw 'Unknown settings page.'}
    Start-Process $settings[$Name] -WindowStyle Normal
}
function Open-GamingISLC {
    $exe=[string]$script:OptionalHelpersISLCPath
    if(-not(Test-Path -LiteralPath $exe)){throw 'ISLC was not found at its configured location.'}
    Start-Process -FilePath $exe -Verb RunAs -WindowStyle Normal
}
