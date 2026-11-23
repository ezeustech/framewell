$ErrorActionPreference='Stop'
$moduleRoot=Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $moduleRoot 'OptionalApps.ps1')
. (Join-Path $moduleRoot 'AppProfiles.ps1')
$testRoot=Join-Path (Split-Path $PSCommandPath -Parent) ('app-launch-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testRoot
$script:GamingProfilesRoot=$testRoot
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-App([bool]$Value,[string]$Label){if(-not $Value){throw ('FAILED: '+$Label)};$checks.Add($Label)}
function New-AppFixture([string]$Path){$null=New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force;[IO.File]::WriteAllBytes($Path,[byte[]]@(0));return $Path}
$old=@{};foreach($name in @('ProgramFiles','ProgramFiles(x86)','LOCALAPPDATA','APPDATA','WINDIR')){$old[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
    $env:ProgramFiles=Join-Path $testRoot 'Programs';${env:ProgramFiles(x86)}=Join-Path $testRoot 'Programs32';$env:LOCALAPPDATA=Join-Path $testRoot 'Local';$env:APPDATA=Join-Path $testRoot 'Roaming';$env:WINDIR=Join-Path $testRoot 'Windows'
    foreach($path in @($env:ProgramFiles,${env:ProgramFiles(x86)},$env:LOCALAPPDATA,$env:APPDATA,$env:WINDIR)){$null=New-Item -ItemType Directory -Path $path -Force}
    $script:RegisteredCandidates=@()
    function Get-OmRegisteredAppCandidates {param($Entry) return $script:RegisteredCandidates}
    function Get-OptionalAppSnapshot {return @()}
    function Get-GamingSteamLibraries {return @()}
    function Get-AppxPackage {param($Name,$ErrorAction) return @()}
    $catalog=@(Get-OmCatalog)
    $created=@{}
    foreach($id in @('Firefox','Chrome','Edge','Epic','OneDrive','Ollama','Brave','Vivaldi','Opera','GOG','EA','Ubisoft','BattleNet','Dropbox','Slack','Telegram','Zoom','Notion','Obsidian','VSCode','OBS','VLC','Plex','AdobeCreativeCloud','Overwolf','Spotify')){
        $entry=$catalog|Where-Object Id -eq $id
        $candidate=@(Get-OmKnownInstallCandidates $entry|Select-Object -First 1)[0]
        Assert-App ([bool]$candidate) ($id+' has a first-launch candidate')
        $created[$id]=New-AppFixture $candidate
        Assert-App ((Resolve-OmLaunchExecutable $entry) -eq $candidate) ($id+' resolves while initially closed')
    }
    $driveEntry=$catalog|Where-Object Id -eq GoogleDrive
    $driveExe=New-AppFixture (Join-Path $env:ProgramFiles 'Google\Drive File Stream\123.4.5\GoogleDriveFS.exe')
    Assert-App ((Resolve-OmLaunchExecutable $driveEntry) -eq $driveExe) 'Versioned Google Drive install resolves with bounded folder search'
    $slackEntry=$catalog|Where-Object Id -eq Slack
    $versionedSlack=New-AppFixture (Join-Path $env:LOCALAPPDATA 'slack\app-8.0.0\slack.exe')
    Assert-App (@(Get-OmKnownInstallCandidates $slackEntry|Where-Object{$_ -eq $versionedSlack}).Count -eq 1) 'Versioned Slack directory is included'
    Assert-App (($catalog|Where-Object Id -eq CrossDeviceResume).ManifestPath.StartsWith($env:WINDIR)) 'Windows app manifest root follows current installation'
    Assert-App ((Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe') -match ($catalog|Where-Object Id -eq Firefox).Pattern) 'Original app regex follows configured Program Files rather than C drive'
    Assert-App ((Join-Path $env:APPDATA 'Spotify\Spotify.exe') -match ($catalog|Where-Object Id -eq Spotify).Pattern) 'Roaming install root follows APPDATA rather than USERPROFILE concatenation'
    $obs=$catalog|Where-Object Id -eq OBS
    $outside=New-AppFixture (Join-Path $testRoot 'Untrusted\obs64.exe')
    $script:RegisteredCandidates=@($outside,($created.OBS+' --unsafe'),('"'+$created.OBS+'" --unsafe'))
    Assert-App ((Resolve-OmLaunchExecutable $obs) -eq $created.OBS) 'Registry candidates outside approved path or containing arguments are ignored'
    Assert-App (-not(Test-OmLaunchExecutable $obs $outside)) 'Same basename outside approved app directory rejected'
    $helper=New-AppFixture (Join-Path $env:ProgramFiles 'Epic Games\Launcher\Engine\Binaries\Win64\EpicWebHelper.exe')
    Assert-App (-not(Test-OmLaunchExecutable ($catalog|Where-Object Id -eq Epic) $helper)) 'Helper executable cannot become application launch target'
    $script:RegisteredCandidates=@()
    $first=@(Get-GamingAppLaunchSnapshot -AppIds @('OBS','VSCode','EA'))
    Assert-App ($first.Count -eq 3 -and @($first|Where-Object{-not $_.Restore.ExecutablePath}).Count -eq 0) 'New profiles can start new-catalog apps without prior running snapshot'
    $stale=[pscustomobject]@{Id='Slack';Name='Slack';Processes=@();Restore=[pscustomobject]@{ExecutablePath=(Join-Path $env:LOCALAPPDATA 'slack\app-0.0.1\slack.exe');Arguments='untrusted-args'}}
    Save-GamingKnownApps @($stale)
    $resolved=Get-GamingAppLaunchSnapshot -AppIds @('Slack')
    Assert-App ($resolved.Restore.ExecutablePath -eq $created.Slack -and $resolved.Restore.Arguments -eq '') 'Stale cached install path repaired and cached arbitrary arguments discarded'
    $packaged=Get-GamingAppLaunchSnapshot -AppIds @('Teams')
    Assert-App ($packaged.Restore.Kind -eq 'Appx' -and -not $packaged.Restore.AppId) 'Packaged app activation is resolved fresh at actual launch'
    Assert-App (@($catalog|Where-Object {$_.Id -in @('OBS','VSCode','Notion','Obsidian','Slack','Zoom','Dropbox','EA') -and $_.Policy -ne 'Graceful'}).Count -eq 0) 'New editor, call, sync and launcher apps retain graceful-only close policy'
    Assert-App ((Test-OmProtectedName 'Steam.exe') -and (Test-OmProtectedName 'Discord.exe')) 'Steam and Discord protections preserved'
    [pscustomobject]@{Passed=$true;Checks=$checks.ToArray();LiveAppLaunches=0;AppClosures=0;Root=$testRoot}|ConvertTo-Json -Depth 4
} finally {foreach($name in $old.Keys){[Environment]::SetEnvironmentVariable($name,$old[$name],'Process')}}
