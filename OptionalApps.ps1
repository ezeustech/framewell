# Optional application handling for Gaming Mode. Compatible with Windows PowerShell 5.1.
# Dot-source this file. It never closes an application merely by being loaded.

function Get-OmCreationStamp {
    param($Process)
    if (-not $Process.CreationDate) { return '' }
    return ([datetime]$Process.CreationDate).ToUniversalTime().ToString('o')
}

function ConvertTo-OmIdentity {
    param($Process)
    [pscustomobject]@{
        ProcessId = [int]$Process.ProcessId
        ParentProcessId = [int]$Process.ParentProcessId
        CreationDateUtc = Get-OmCreationStamp $Process
        ExecutablePath = [string]$Process.ExecutablePath
        Name = [string]$Process.Name
    }
}

function Get-OmCatalog {
    $localUser = [regex]::Escape($env:LOCALAPPDATA)
    $roamingUser = [regex]::Escape($env:APPDATA)
    $programs='(?:'+[regex]::Escape($env:ProgramFiles)+'|'+[regex]::Escape(${env:ProgramFiles(x86)})+')'
    $windows=[regex]::Escape($env:WINDIR)
    $packages='(?:'+[regex]::Escape((Join-Path $env:ProgramFiles 'WindowsApps'))+'|[A-Z]:\\WindowsApps)'
    $entries=@(
        [pscustomobject]@{Id='Firefox';Name='Firefox';Pattern=('(?i)^'+$programs+'\\Mozilla Firefox\\(?:firefox|crashhelper)\.exe$');Primary='firefox.exe';Policy='Graceful';RestoreArgs=''},
        [pscustomobject]@{Id='Chrome';Name='Google Chrome';Pattern=('(?i)^(?:'+$programs+'|'+$localUser+')\\Google\\Chrome\\Application\\chrome\.exe$');Primary='chrome.exe';Policy='Graceful';RestoreArgs=''},
        [pscustomobject]@{Id='Edge';Name='Microsoft Edge browser';Pattern=('(?i)^'+$programs+'\\Microsoft\\Edge\\Application\\msedge\.exe$');Primary='msedge.exe';Policy='Graceful';RestoreArgs=''},
        [pscustomobject]@{Id='Epic';Name='Epic Games Launcher';Pattern=('(?i)^'+$programs+'\\Epic Games\\Launcher\\(?:Portal\\Binaries\\Win(?:32|64)\\EpicGamesLauncher|Engine\\Binaries\\Win(?:32|64)\\EpicWebHelper)\.exe$');Primary='EpicGamesLauncher.exe';Policy='AppOnly';RestoreArgs='-silent'},
        [pscustomobject]@{Id='Spotify';Name='Spotify';Pattern=('(?i)^(?:'+$roamingUser+'\\Spotify\\Spotify\.exe|'+$packages+'\\SpotifyAB\.SpotifyMusic_[^\\]+\\Spotify\.exe)$');Primary='Spotify.exe';Policy='AppOnly';RestoreArgs=''},
        [pscustomobject]@{Id='OneDrive';Name='OneDrive';Pattern=('(?i)^(?:'+$localUser+'\\Microsoft\\OneDrive|'+$programs+'\\Microsoft OneDrive)(?:\\[\d.]+)?\\OneDrive\.exe$');Primary='OneDrive.exe';Policy='OneDrive';RestoreArgs='/background'},
        [pscustomobject]@{Id='Wallpaper';Name='Wallpaper Engine';Pattern='(?i)^[A-Z]:\\(?:[^\\]+\\)*steamapps\\common\\wallpaper_engine\\(?:wallpaper(?:32|64)|wallpaperui|webwallpaper(?:32|64))\.exe$';Primary='wallpaper64.exe|wallpaper32.exe';Policy='AppOnly';RestoreArgs='-silent'},
        [pscustomobject]@{Id='Ollama';Name='Ollama';Pattern=('(?i)^'+$localUser+'\\Programs\\Ollama\\(?:ollama app|ollama)\.exe$');Primary='ollama app.exe|ollama.exe';Policy='AppOnly';RestoreArgs=''},
        [pscustomobject]@{Id='RobloxTray';Name='Roblox background launcher';Pattern=('(?i)^'+$localUser+'\\Roblox\\Versions\\version-[a-z0-9]+\\(?:RobloxPlayerBeta|RobloxCrashHandler)\.exe$');Primary='RobloxPlayerBeta.exe';Policy='RobloxTray';RestoreArgs='--launch-to-tray'},
        [pscustomobject]@{Id='CrossDeviceResume';Name='Cross-device resume';Pattern=('(?i)^'+$windows+'\\SystemApps\\MicrosoftWindows\.Client\.CBS_cw5n1h2txyewy\\CrossDeviceResume\.exe$');Primary='CrossDeviceResume.exe';Policy='AppOnly';RestoreArgs='';PackageName='MicrosoftWindows.Client.CBS';PackageFamily='MicrosoftWindows.Client.CBS_cw5n1h2txyewy';ApplicationId='CrossDeviceResumeApp';ManifestPath=(Join-Path $env:WINDIR 'SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\AppxManifest.xml')},
        [pscustomobject]@{Id='Teams';Name='Microsoft Teams';Pattern=('(?i)^'+$packages+'\\MSTeams_[^\\]+__8wekyb3d8bbwe\\ms-teams\.exe$');Primary='ms-teams.exe';Policy='Graceful';RestoreArgs='';PackageName='MSTeams';PackageFamily='MSTeams_8wekyb3d8bbwe';ApplicationId='MSTeams'},
        [pscustomobject]@{Id='PhoneLink';Name='Phone Link';Pattern=('(?i)^'+$packages+'\\Microsoft\.YourPhone_[^\\]+__8wekyb3d8bbwe\\(?:PhoneExperienceHost|YourPhone)\.exe$');Primary='PhoneExperienceHost.exe|YourPhone.exe';Policy='Graceful';RestoreArgs='';PackageName='Microsoft.YourPhone';PackageFamily='Microsoft.YourPhone_8wekyb3d8bbwe';ApplicationId='App'},
        [pscustomobject]@{Id='Widgets';Name='Windows Widgets';Pattern=('(?i)^'+$packages+'\\MicrosoftWindows\.Client\.WebExperience_[^\\]+__cw5n1h2txyewy\\Dashboard\\(?:Widgets|WidgetService)\.exe$');Primary='Widgets.exe';Policy='AppOnly';RestoreArgs='';PackageName='MicrosoftWindows.Client.WebExperience';PackageFamily='MicrosoftWindows.Client.WebExperience_cw5n1h2txyewy'},
        [pscustomobject]@{Id='Copilot';Name='Microsoft Copilot';Pattern=('(?i)^'+$packages+'\\Microsoft\.Copilot_[^\\]+__8wekyb3d8bbwe\\(?:Copilot|ms-copilot)\.exe$');Primary='Copilot.exe|ms-copilot.exe';Policy='Graceful';RestoreArgs='';PackageName='Microsoft.Copilot';PackageFamily='Microsoft.Copilot_8wekyb3d8bbwe'},
        [pscustomobject]@{Id='ChatGPT';Name='ChatGPT / Codex';Pattern=('(?i)^'+$packages+'\\OpenAI\.Codex_[^\\]+\\app\\ChatGPT\.exe$');Primary='ChatGPT.exe';Policy='ChatGPT';RestoreArgs=''}
    )
    # Additional applications close normally so editors, calls and recordings can
    # present their own save/quit prompts. Shared runtimes and game processes are excluded.
    $userPrograms=$localUser+'\\Programs'
    $extra=@(
        @('Brave','Brave browser',($programs+'\\BraveSoftware\\Brave-Browser\\Application\\brave\.exe'),'brave.exe','Browsers'),
        @('Vivaldi','Vivaldi',('(?:'+$localUser+'|'+$programs+')\\Vivaldi\\Application\\vivaldi\.exe'),'vivaldi.exe','Browsers'),
        @('Opera','Opera',($localUser+'\\Programs\\Opera(?: GX)?\\(?:[\d.]+\\)?opera\.exe'),'opera.exe','Browsers'),
        @('GOG','GOG Galaxy',($programs+'\\GOG Galaxy\\(?:GalaxyClient|GalaxyClient Helper)\.exe'),'GalaxyClient.exe','Launchers'),
        @('EA','EA app',($programs+'\\Electronic Arts\\EA Desktop\\EA Desktop\\(?:EADesktop|EACefSubProcess)\.exe'),'EADesktop.exe','Launchers'),
        @('Ubisoft','Ubisoft Connect',($programs+'\\Ubisoft\\Ubisoft Game Launcher\\(?:UbisoftConnect|upc|UplayWebCore)\.exe'),'UbisoftConnect.exe|upc.exe','Launchers'),
        @('BattleNet','Battle.net',($programs+'\\Battle\.net\\(?:Battle\.net(?:\.[\d]+)?\\)?Battle\.net\.exe'),'Battle.net.exe','Launchers'),
        @('RiotClient','Riot client',('[A-Z]:\\Riot Games\\Riot Client\\(?:RiotClientServices|RiotClientUx|RiotClientUxRender)\.exe'),'RiotClientServices.exe','Launchers'),
        @('Dropbox','Dropbox',('(?:'+$programs+'|'+$roamingUser+')\\Dropbox\\Client\\Dropbox\.exe'),'Dropbox.exe','CloudSync'),
        @('GoogleDrive','Google Drive',($programs+'\\Google\\Drive File Stream\\[\d.]+\\GoogleDriveFS\.exe'),'GoogleDriveFS.exe','CloudSync'),
        @('Slack','Slack',($localUser+'\\slack\\(?:app-[\d.]+\\)?slack\.exe'),'slack.exe','DesktopExtras'),
        @('Telegram','Telegram Desktop',($roamingUser+'\\Telegram Desktop\\Telegram\.exe'),'Telegram.exe','DesktopExtras'),
        @('Zoom','Zoom',('(?:'+$roamingUser+'|'+$programs+')\\Zoom\\bin\\Zoom\.exe'),'Zoom.exe','DesktopExtras'),
        @('Notion','Notion',($userPrograms+'\\Notion\\Notion\.exe'),'Notion.exe','DesktopExtras'),
        @('Obsidian','Obsidian',($userPrograms+'\\Obsidian\\Obsidian\.exe'),'Obsidian.exe','DesktopExtras'),
        @('VSCode','Visual Studio Code',('(?:'+$userPrograms+'|'+$programs+')\\Microsoft VS Code\\Code\.exe'),'Code.exe','DesktopExtras'),
        @('OBS','OBS Studio',($programs+'\\obs-studio\\bin\\64bit\\obs64\.exe'),'obs64.exe','MediaApps'),
        @('VLC','VLC media player',($programs+'\\VideoLAN\\VLC\\vlc\.exe'),'vlc.exe','MediaApps'),
        @('Plex','Plex desktop',($programs+'\\Plex\\Plex\\Plex\.exe'),'Plex.exe','MediaApps'),
        @('AdobeCreativeCloud','Adobe Creative Cloud',($programs+'\\Adobe\\Adobe Creative Cloud\\ACC\\Creative Cloud\.exe'),'Creative Cloud.exe','DesktopExtras'),
        @('Overwolf','Overwolf',($programs+'\\Overwolf\\(?:Overwolf|OverwolfBrowser)\.exe'),'Overwolf.exe','DesktopExtras')
    )
    foreach($app in $extra){$entries+=[pscustomobject]@{Id=$app[0];Name=$app[1];Pattern=('(?i)^'+$app[2]+'$');Primary=$app[3];Category=$app[4];Policy='Graceful';RestoreArgs=''}}
    foreach($entry in $entries){
        if(-not $entry.PSObject.Properties['Category']){
            $category=switch($entry.Id){ {$_ -in @('Firefox','Chrome','Edge')} {'Browsers';break} {$_ -in @('Epic','RobloxTray')} {'Launchers';break} OneDrive {'CloudSync';break} Spotify {'MediaApps';break} ChatGPT {'MediaProfile';break} default {'DesktopExtras'} }
            $entry|Add-Member -NotePropertyName Category -NotePropertyValue $category
        }
        $entry
    }
}

function Test-OmLaunchExecutable {
    param($Entry,[string]$Path)
    if(-not $Entry -or $Path -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($Path) -ine '.exe' -or $Path -match '[\x00-\x1F]'){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path)
        return ($full -match $Entry.Pattern -and [IO.Path]::GetFileName($full) -in @($Entry.Primary -split '\|') -and (Test-Path -LiteralPath $full -PathType Leaf))
    } catch {return $false}
}

function Get-OmRegisteredAppCandidates {
    param($Entry)
    foreach($name in @($Entry.Primary -split '\|')){
        foreach($base in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths','HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')){
            try {
                $key=Get-Item -LiteralPath (Join-Path $base $name) -ErrorAction SilentlyContinue
                if($key){$value=[string]$key.GetValue('');if($value){$value.Trim().Trim('"')}}
            } catch { }
        }
    }
}

function Get-OmKnownInstallCandidates {
    param($Entry)
    $programRoots=@($env:ProgramFiles,${env:ProgramFiles(x86)} | Where-Object {$_} | Select-Object -Unique)
    $relative=switch($Entry.Id){
        Firefox {'Mozilla Firefox\firefox.exe'}
        Chrome {'Google\Chrome\Application\chrome.exe'}
        Edge {'Microsoft\Edge\Application\msedge.exe'}
        Epic {'Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe';'Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe'}
        OneDrive {'Microsoft OneDrive\OneDrive.exe'}
        Brave {'BraveSoftware\Brave-Browser\Application\brave.exe'}
        Vivaldi {'Vivaldi\Application\vivaldi.exe'}
        GOG {'GOG Galaxy\GalaxyClient.exe'}
        EA {'Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe'}
        Ubisoft {'Ubisoft\Ubisoft Game Launcher\UbisoftConnect.exe';'Ubisoft\Ubisoft Game Launcher\upc.exe'}
        BattleNet {'Battle.net\Battle.net.exe'}
        Dropbox {'Dropbox\Client\Dropbox.exe'}
        Zoom {'Zoom\bin\Zoom.exe'}
        VSCode {'Microsoft VS Code\Code.exe'}
        OBS {'obs-studio\bin\64bit\obs64.exe'}
        VLC {'VideoLAN\VLC\vlc.exe'}
        Plex {'Plex\Plex\Plex.exe'}
        AdobeCreativeCloud {'Adobe\Adobe Creative Cloud\ACC\Creative Cloud.exe'}
        Overwolf {'Overwolf\Overwolf.exe'}
        default {@()}
    }
    foreach($root in $programRoots){foreach($path in @($relative)){Join-Path $root $path}}
    $localRelative=switch($Entry.Id){
        Chrome {'Google\Chrome\Application\chrome.exe'}
        OneDrive {'Microsoft\OneDrive\OneDrive.exe'}
        Ollama {'Programs\Ollama\ollama app.exe';'Programs\Ollama\ollama.exe'}
        Vivaldi {'Vivaldi\Application\vivaldi.exe'}
        Opera {'Programs\Opera\opera.exe';'Programs\Opera GX\opera.exe'}
        Slack {'slack\slack.exe'}
        Notion {'Programs\Notion\Notion.exe'}
        Obsidian {'Programs\Obsidian\Obsidian.exe'}
        VSCode {'Programs\Microsoft VS Code\Code.exe'}
        default {@()}
    }
    foreach($path in @($localRelative)){Join-Path $env:LOCALAPPDATA $path}
    $roamingRelative=switch($Entry.Id){Spotify {'Spotify\Spotify.exe'} Dropbox {'Dropbox\Client\Dropbox.exe'} Telegram {'Telegram Desktop\Telegram.exe'} Zoom {'Zoom\bin\Zoom.exe'} default {@()}}
    foreach($path in @($roamingRelative)){Join-Path $env:APPDATA $path}
    $versionFolders=@()
    switch($Entry.Id){
        Slack {$versionFolders+=@{Path=(Join-Path $env:LOCALAPPDATA 'slack');Filter='app-*';Leaf='slack.exe'}}
        Opera {foreach($name in @('Opera','Opera GX')){$versionFolders+=@{Path=(Join-Path $env:LOCALAPPDATA ('Programs\'+$name));Filter='*';Leaf='opera.exe'}}}
        RobloxTray {$versionFolders+=@{Path=(Join-Path $env:LOCALAPPDATA 'Roblox\Versions');Filter='version-*';Leaf='RobloxPlayerBeta.exe'}}
        GoogleDrive {foreach($root in $programRoots){$versionFolders+=@{Path=(Join-Path $root 'Google\Drive File Stream');Filter='*';Leaf='GoogleDriveFS.exe'}}}
        BattleNet {foreach($root in $programRoots){$versionFolders+=@{Path=(Join-Path $root 'Battle.net');Filter='Battle.net.*';Leaf='Battle.net.exe'}}}
        OneDrive {foreach($root in @((Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'))+@($programRoots|ForEach-Object{Join-Path $_ 'Microsoft OneDrive'})){$versionFolders+=@{Path=$root;Filter='*';Leaf='OneDrive.exe'}}}
        RiotClient {foreach($drive in @([IO.DriveInfo]::GetDrives()|Where-Object{$_.DriveType -eq [IO.DriveType]::Fixed -and $_.IsReady})){Join-Path $drive.RootDirectory.FullName 'Riot Games\Riot Client\RiotClientServices.exe'}}
        Wallpaper {if(Get-Command Get-GamingSteamLibraries -ErrorAction SilentlyContinue){foreach($root in @(Get-GamingSteamLibraries)){Join-Path $root 'steamapps\common\wallpaper_engine\wallpaper64.exe';Join-Path $root 'steamapps\common\wallpaper_engine\wallpaper32.exe'}}}
    }
    foreach($location in $versionFolders){
        foreach($folder in @(Get-ChildItem -LiteralPath $location.Path -Directory -Filter $location.Filter -ErrorAction SilentlyContinue | Where-Object{-not($_.Attributes -band [IO.FileAttributes]::ReparsePoint)} | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 30)){Join-Path $folder.FullName $location.Leaf}
    }
    # Spotify's store package uses an EXE rather than the Appx restore branch.
    if($Entry.Id -eq 'Spotify'){
        foreach($package in @(Get-AppxPackage -Name 'SpotifyAB.SpotifyMusic' -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 2)){if($package.InstallLocation){Join-Path $package.InstallLocation 'Spotify.exe'}}
    }
}

function Resolve-OmLaunchExecutable {
    param($Entry,[string]$PreviousPath='')
    if(Test-OmLaunchExecutable -Entry $Entry -Path $PreviousPath){return [IO.Path]::GetFullPath($PreviousPath)}
    foreach($path in @(@(Get-OmRegisteredAppCandidates $Entry)+@(Get-OmKnownInstallCandidates $Entry) | Select-Object -Unique)){
        if(Test-OmLaunchExecutable -Entry $Entry -Path ([string]$path)){return [IO.Path]::GetFullPath([string]$path)}
    }
    return ''
}

function Get-OmPackagedAppId {
    param($Entry)
    if (-not $Entry.PackageFamily) { return '' }
    $manifestPath = [string]$Entry.ManifestPath
    if (-not $manifestPath) {
        $package = Get-AppxPackage -Name ([string]$Entry.PackageName) -ErrorAction SilentlyContinue |
            Where-Object { $_.PackageFamilyName -eq $Entry.PackageFamily } |
            Sort-Object Version -Descending | Select-Object -First 1
        if (-not $package) { return '' }
        $manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { return '' }
    try {
        [xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
        $primaryNames = @($Entry.Primary -split '\|')
        $applications = @($manifest.Package.Applications.Application | Where-Object {
            $primaryNames -contains [IO.Path]::GetFileName([string]$_.Executable)
        })
        if ($Entry.ApplicationId) { $applications = @($applications | Where-Object Id -eq $Entry.ApplicationId) }
        $application = $applications | Select-Object -First 1
        if (-not $application -or [string]$application.Id -notmatch '^[a-zA-Z0-9._-]+$') { return '' }
        return ([string]$Entry.PackageFamily+'!'+[string]$application.Id)
    } catch { return '' }
}

function Test-OmProtectedName {
    param([string]$Name)
    return $Name -match '(?i)^(?:steam(?:webhelper|service)?|Discord(?:SystemHelper)?|codex-windows-sandbox-service)\.exe$'
}

function Test-OmChatGptToolPath {
    param([string]$Path, [string]$Name)
    if (Test-OmProtectedName $Name) { return $false }
    $packages='(?:'+[regex]::Escape((Join-Path $env:ProgramFiles 'WindowsApps'))+'|[A-Z]:\\WindowsApps)'
    $windows=[regex]::Escape($env:WINDIR)
    if ($Path -match ('(?i)^'+$packages+'\\OpenAI\.Codex(?:_|PrimaryRuntime\.)[^\\]+\\')) { return $true }
    if ($Path -match ('(?i)^'+$windows+'\\(?:System32|SysWOW64)\\(?:cmd|conhost)\.exe$')) { return $true }
    if ($Path -match ('(?i)^'+$windows+'\\(?:System32|SysWOW64)\\WindowsPowerShell\\v1\.0\\powershell\.exe$')) { return $true }
    if ($Path -match ('(?i)^'+[regex]::Escape($env:ProgramFiles)+'\\PowerShell\\\d+\\pwsh\.exe$')) { return $true }
    $localUser = [regex]::Escape($env:LOCALAPPDATA)
    if ($Path -match ('(?i)^'+$localUser+'\\Roblox\\Versions\\version-[a-z0-9]+\\StudioMCP\.exe$')) { return $true }
    return $false
}

function Get-OmVerifiedProcess {
    param($Identity)
    if (-not $Identity -or -not $Identity.ExecutablePath -or -not $Identity.CreationDateUtc) { return $null }
    if (Test-OmProtectedName ([string]$Identity.Name)) { return $null }
    $live = Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$Identity.ProcessId) -ErrorAction SilentlyContinue
    if (-not $live) { return $null }
    if ([string]$live.ExecutablePath -ine [string]$Identity.ExecutablePath) { return $null }
    if ((Get-OmCreationStamp $live) -ne [string]$Identity.CreationDateUtc) { return $null }
    return $live
}

function Test-OmRobloxTray {
    param($Process)
    if (-not $Process -or $Process.CommandLine -notmatch '(?i)(?:^|\s)--launch-to-tray(?:\s|$)') { return $false }
    if ($Process.CommandLine -match '(?i)placeid|gameid|join|--app\b|--play\b|ticket|launchmode:play') { return $false }
    $native = Get-Process -Id ([int]$Process.ProcessId) -ErrorAction SilentlyContinue
    return ($native -and $native.MainWindowHandle -eq [intptr]::Zero)
}

function Test-OmCurrentProcessInTree {
    param($Identities)
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $targets = @($Identities | ForEach-Object { [int]$_.ProcessId })
    $current = [int]$PID
    $visited = @{}
    while ($current -gt 0 -and -not $visited.ContainsKey($current)) {
        if ($targets -contains $current) { return $true }
        $visited[$current] = $true
        $parent = $all | Where-Object { [int]$_.ProcessId -eq $current } | Select-Object -First 1
        if (-not $parent) { break }
        $current = [int]$parent.ParentProcessId
    }
    return $false
}

function Get-OmEpicLauncherOverlays {
    param([object[]]$Processes)
    $launcher=Get-OmCatalog|Where-Object Id -eq 'Epic'|Select-Object -First 1
    $owners=@($Processes|Where-Object{$_.Name -eq 'EpicGamesLauncher.exe' -and $_.ExecutablePath -match $launcher.Pattern})
    $owned=New-Object 'System.Collections.Generic.HashSet[int]'
    foreach($owner in $owners){[void]$owned.Add([int]$owner.ProcessId)}
    $overlayRows=New-Object 'System.Collections.Generic.List[object]'
    $programs='(?:'+[regex]::Escape($env:ProgramFiles)+'|'+[regex]::Escape(${env:ProgramFiles(x86)})+')'
    do{
        $changed=$false
        foreach($p in $Processes){
            if($owned.Contains([int]$p.ProcessId) -or -not $owned.Contains([int]$p.ParentProcessId)){continue}
            if($p.ExecutablePath -notmatch ('(?i)^'+$programs+'\\Epic Games\\Epic Online Services\\managedArtifacts\\[a-z0-9]+\\EOSOverlayRenderer-Win(?:32|64)-Shipping\.exe$')){continue}
            $parent=$Processes|Where-Object ProcessId -eq $p.ParentProcessId|Select-Object -First 1
            if(-not $parent -or $parent.CreationDate -gt $p.CreationDate){continue}
            [void]$owned.Add([int]$p.ProcessId);$overlayRows.Add($p);$changed=$true
        }
    }while($changed)
    return @($overlayRows.ToArray())
}

function Get-OptionalAppSnapshot {
    [CmdletBinding()]
    param()
    $all = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $catalog = @(Get-OmCatalog)
    foreach ($entry in $catalog) {
        $matches = @($all | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -match $entry.Pattern -and -not (Test-OmProtectedName $_.Name) })
        if ($matches.Count -eq 0) { continue }
        $primaryNames = @($entry.Primary -split '\|')
        $primary = $matches | Where-Object { $primaryNames -contains $_.Name } | Sort-Object CreationDate | Select-Object -First 1
        if (-not $primary) { continue }
        if ($entry.Id -eq 'RobloxTray') {
            if (-not (Test-OmRobloxTray $primary)) { continue }
            $matches = @($matches | Where-Object { $_.ProcessId -eq $primary.ProcessId -or $_.ParentProcessId -eq $primary.ProcessId })
        }
        if($entry.Id -eq 'Epic'){$matches+=@(Get-OmEpicLauncherOverlays -Processes $all)}
        if ($entry.Id -eq 'ChatGPT') {
            $treeIds = New-Object 'System.Collections.Generic.HashSet[int]'
            foreach ($item in $matches) { [void]$treeIds.Add([int]$item.ProcessId) }
            do {
                $changed = $false
                foreach ($item in $all) {
                    if ($treeIds.Contains([int]$item.ParentProcessId) -and -not $treeIds.Contains([int]$item.ProcessId)) {
                        [void]$treeIds.Add([int]$item.ProcessId)
                        $changed = $true
                    }
                }
            } while ($changed)
            $matches = @($all | Where-Object { $treeIds.Contains([int]$_.ProcessId) -and (Test-OmChatGptToolPath $_.ExecutablePath $_.Name) })
        }
        $restoreKind = 'Exe'
        $restoreArgs = [string]$entry.RestoreArgs
        $appId = ''
        if ($entry.Id -eq 'Ollama' -and $primary.Name -eq 'ollama.exe') { $restoreArgs = 'serve' }
        if ($entry.Id -eq 'ChatGPT') {
            $restoreKind = 'Appx'
            $startApp = Get-StartApps -ErrorAction SilentlyContinue | Where-Object { $_.AppID -like 'OpenAI.Codex_2p2nqsd0c76g0!*' } | Select-Object -First 1
            if ($startApp) { $appId = [string]$startApp.AppID }
        } elseif ($entry.PackageFamily) {
            $restoreKind = 'Appx'
            $appId = Get-OmPackagedAppId -Entry $entry
            # Only include a packaged app if its installed manifest supplies a
            # recognized activation entry point for a later Restore.
            if (-not $appId) { continue }
        }
        [pscustomobject]@{
            Id = [string]$entry.Id
            Name = [string]$entry.Name
            Policy = [string]$entry.Policy
            CapturedUtc = [datetime]::UtcNow.ToString('o')
            Processes = @($matches | ForEach-Object { ConvertTo-OmIdentity $_ })
            Restore = [pscustomobject]@{Kind=$restoreKind;ExecutablePath=[string]$primary.ExecutablePath;Arguments=$restoreArgs;AppId=$appId}
        }
    }
}

function Get-OmRemainingIdentities {
    param($App)
    foreach ($identity in @($App.Processes)) {
        if (Get-OmVerifiedProcess $identity) { $identity }
    }
}

function Stop-OptionalApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Snapshot,
        [bool]$IncludeChatGPT = $false,
        [switch]$ChatGPTOnly
    )
    $catalog = @(Get-OmCatalog)
    foreach ($app in @($Snapshot)) {
        if ($ChatGPTOnly -and $app.Id -ne 'ChatGPT') { continue }
        if ($app.Id -eq 'ChatGPT' -and -not $IncludeChatGPT) { continue }
        $entry = $catalog | Where-Object Id -eq $app.Id | Select-Object -First 1
        if (-not $entry) { continue }
        $result = [pscustomobject]@{Id=[string]$app.Id;Name=[string]$app.Name;Closed=$false;Status='Skipped';Detail='';StoppedProcessIds=@();RemainingProcessIds=@();CompletedUtc=''}
        $liveBefore = @(Get-OmRemainingIdentities $app)
        # Only launcher-owned overlays are eligible. Game-owned EOS processes stay running.
        $epicOverlayIds=if($app.Id -eq 'Epic'){@(Get-OmEpicLauncherOverlays -Processes @(Get-CimInstance Win32_Process)|ForEach-Object ProcessId)}else{@()}
        if ($liveBefore.Count -eq 0) {
            $result.Status = 'AlreadyClosed'
            $result.Detail = 'The captured application was no longer running; it will not be reopened automatically.'
            $result.CompletedUtc = [datetime]::UtcNow.ToString('o')
            $result
            continue
        }
        if ($app.Id -eq 'ChatGPT' -and (Test-OmCurrentProcessInTree $app.Processes)) {
            $result.Detail = 'Kept open because this Gaming Mode process was launched from ChatGPT/Codex. Use the desktop shortcut to close it safely.'
            $result.RemainingProcessIds = @($liveBefore | ForEach-Object ProcessId)
            $result.CompletedUtc = [datetime]::UtcNow.ToString('o')
            $result
            continue
        }
        if ($app.Id -eq 'RobloxTray') {
            $roblox = $liveBefore | Where-Object Name -eq 'RobloxPlayerBeta.exe' | Select-Object -First 1
            $robloxLive = Get-OmVerifiedProcess $roblox
            if (-not (Test-OmRobloxTray $robloxLive)) {
                $result.Detail = 'Roblox is no longer an idle tray launcher; it was kept running.'
                $result.RemainingProcessIds = @($liveBefore | ForEach-Object ProcessId)
                $result.CompletedUtc = [datetime]::UtcNow.ToString('o')
                $result
                continue
            }
        }
        $errors = New-Object 'System.Collections.Generic.List[string]'
        if ($entry.Policy -eq 'OneDrive') {
            try {
                if ($app.Restore.ExecutablePath -match $entry.Pattern) {
                    Start-Process -FilePath $app.Restore.ExecutablePath -ArgumentList '/shutdown' -WindowStyle Hidden -ErrorAction Stop | Out-Null
                }
            } catch { $errors.Add($_.Exception.Message) }
        } else {
            foreach ($identity in $liveBefore) {
                $verified = Get-OmVerifiedProcess $identity
                if (-not $verified) { continue }
                if ($app.Id -eq 'ChatGPT') {
                    if ($identity.Name -ne 'ChatGPT.exe') { continue }
                } elseif ($identity.ExecutablePath -notmatch $entry.Pattern -and $identity.ProcessId -notin $epicOverlayIds) { continue }
                try {
                    $native = Get-Process -Id ([int]$identity.ProcessId) -ErrorAction Stop
                    if ($native.MainWindowHandle -ne [intptr]::Zero) { [void]$native.CloseMainWindow() }
                } catch { }
            }
        }
        $deadline = [datetime]::UtcNow.AddSeconds(5)
        do {
            Start-Sleep -Milliseconds 200
            $remaining = @(Get-OmRemainingIdentities $app)
        } while ($remaining.Count -gt 0 -and [datetime]::UtcNow -lt $deadline)
        if ($entry.Policy -in @('AppOnly','RobloxTray','ChatGPT')) {
            foreach ($identity in @($remaining | Sort-Object CreationDateUtc -Descending)) {
                if ($app.Id -eq 'ChatGPT') {
                    if (-not (Test-OmChatGptToolPath $identity.ExecutablePath $identity.Name)) { continue }
                } elseif ($identity.ExecutablePath -notmatch $entry.Pattern -and $identity.ProcessId -notin $epicOverlayIds) { continue }
                if (-not (Get-OmVerifiedProcess $identity)) { continue }
                try { Stop-Process -Id ([int]$identity.ProcessId) -ErrorAction Stop } catch { $errors.Add($_.Exception.Message) }
            }
            Start-Sleep -Milliseconds 250
        }
        $remaining = @(Get-OmRemainingIdentities $app)
        $remainingIds = @($remaining | ForEach-Object ProcessId)
        $result.StoppedProcessIds = @($liveBefore | Where-Object { $remainingIds -notcontains $_.ProcessId } | ForEach-Object ProcessId)
        $result.RemainingProcessIds = $remainingIds
        $result.Closed = ($remaining.Count -eq 0)
        if ($result.Closed) {
            $result.Status = 'Closed'
            $result.Detail = 'Closed; Restore will reopen this application.'
        } elseif ($entry.Policy -eq 'Graceful') {
            $result.Status = 'KeptOpen'
            $result.Detail = 'The application is still open, possibly awaiting a save/quit prompt or remaining in its tray. It was not force-closed.'
        } else {
            $result.Status = 'Partial'
            $result.Detail = 'Some captured processes remain running.'
        }
        if ($errors.Count -gt 0) { $result.Detail += ' ' + ($errors.ToArray() -join ' ') }
        $result.CompletedUtc = [datetime]::UtcNow.ToString('o')
        $result
    }
}

function Start-OptionalApps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]$Snapshot,
        [AllowNull()]$Results = $null
    )
    $catalog = @(Get-OmCatalog)
    foreach ($app in @($Snapshot)) {
        if ($null -ne $Results) {
            # A graceful close can finish after the stop result was recorded.
            # Restore partially closed groups too; the primary-process check
            # below still prevents duplicating an application that stayed open.
            $closedRecord = @($Results | Where-Object {
                $_.Id -eq $app.Id -and ($_.Closed -eq $true -or @($_.StoppedProcessIds | Where-Object { $_ -gt 0 }).Count -gt 0)
            })
            if ($closedRecord.Count -eq 0) { continue }
        }
        $entry = $catalog | Where-Object Id -eq $app.Id | Select-Object -First 1
        if (-not $entry) { continue }
        $result = [pscustomobject]@{Id=[string]$app.Id;Name=[string]$app.Name;Restored=$false;Status='Skipped';Detail=''}
        $primaryNames = @($entry.Primary -split '\|')
        $current = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ExecutablePath -and $_.ExecutablePath -match $entry.Pattern -and $primaryNames -contains $_.Name })
        if ($current.Count -gt 0) {
            $result.Restored = $true
            $result.Status = 'AlreadyRunning'
            $result.Detail = 'Already running; no duplicate instance launched.'
            $result
            continue
        }
        try {
            if ($app.Id -eq 'ChatGPT') {
                $startApp = Get-StartApps -ErrorAction SilentlyContinue | Where-Object { $_.AppID -like 'OpenAI.Codex_2p2nqsd0c76g0!*' } | Select-Object -First 1
                if (-not $startApp) { throw 'ChatGPT/Codex is not registered in the Start menu.' }
                Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('shell:AppsFolder\'+[string]$startApp.AppID) -WindowStyle Hidden -ErrorAction Stop | Out-Null
            } elseif ($entry.PackageFamily) {
                # Resolve from the approved installed package, never replay an
                # AppID or arbitrary launch arguments from the saved state file.
                $appId = Get-OmPackagedAppId -Entry $entry
                if (-not $appId) { throw 'The approved packaged application is no longer registered. Open it normally from Start.' }
                Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('shell:AppsFolder\'+$appId) -WindowStyle Hidden -ErrorAction Stop | Out-Null
            } else {
                $launchPath = Resolve-OmLaunchExecutable -Entry $entry -PreviousPath ([string]$app.Restore.ExecutablePath)
                $launchArgs = [string]$entry.RestoreArgs
                if(-not $launchPath){throw 'The application was not found in its approved installation locations. Add its EXE to a custom profile if it uses another location.'}
                if ($app.Id -eq 'Discord' -or $launchPath -notmatch $entry.Pattern) { throw 'The saved executable is not in the optional-app allowlist.' }
                if ($primaryNames -notcontains [IO.Path]::GetFileName($launchPath)) { throw 'The saved executable is not the application entry point.' }
                if ($app.Id -eq 'Ollama' -and [IO.Path]::GetFileName($launchPath) -eq 'ollama.exe') { $launchArgs = 'serve' }
                if (-not (Test-Path -LiteralPath $launchPath -PathType Leaf)) { throw 'The application was not found in its approved installation locations. Add its EXE to a custom profile if it uses another location.' }
                $launchStyle = if ($entry.Policy -eq 'Graceful' -or $entry.Id -eq 'Spotify') { 'Normal' } else { 'Hidden' }
                $launch = @{FilePath=$launchPath;WindowStyle=$launchStyle;ErrorAction='Stop'}
                if ($launchArgs) { $launch.ArgumentList = $launchArgs }
                Start-Process @launch | Out-Null
            }
            $deadline = [datetime]::UtcNow.AddSeconds(10)
            $observed = @()
            do {
                Start-Sleep -Milliseconds 300
                $observed = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
                    $_.ExecutablePath -and $_.ExecutablePath -match $entry.Pattern -and $primaryNames -contains $_.Name
                })
                if ($observed.Count -gt 0) { break }
            } while ([datetime]::UtcNow -lt $deadline)
            if ($observed.Count -gt 0) {
                $result.Restored = $true
                $result.Status = 'Started'
                $result.Detail = 'The application is running again. Browser tabs and unsaved work depend on its session settings.'
            } else {
                $result.Status = 'NotReady'
                $result.Detail = 'Launch was requested, but the application was not observed within ten seconds. Retry Restore or open it from Start.'
            }
        } catch {
            $result.Status = 'Failed'
            $result.Detail = $_.Exception.Message
        }
        $result
    }
}
