# Game discovery uses installed metadata and bounded, explicitly selected folders.
# This module defines functions only; scanning and file pickers run on user actions.
function Read-GamingDiscoveryState {
    param([string]$Name,[string]$Collection)
    $path=Join-Path $script:GamingGameLibraryRoot ('state\'+$Name+'.json')
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    try {$value=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json;if([int]$value.Version -eq 1){return @($value.$Collection)}} catch { }
    return @()
}

function Write-GamingDiscoveryState {
    param([string]$Name,[object]$Value)
    if($Name -notin @('game-discovery','game-bindings','game-scan-folders','game-scan-report')){throw 'Unknown game state file.'}
    $folder=Join-Path $script:GamingGameLibraryRoot 'state'
    if(-not(Test-Path -LiteralPath $folder)){New-Item -ItemType Directory -Path $folder -Force | Out-Null}
    $pending=Join-Path $folder ($Name+'.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination (Join-Path $folder ($Name+'.json')) -Force
}

function Get-GamingStableId {
    param([string]$Prefix,[string]$Value)
    $hash=[Security.Cryptography.SHA256]::Create()
    try {$bytes=$hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Value.ToLowerInvariant()));return $Prefix+'-'+([BitConverter]::ToString($bytes).Replace('-','').Substring(0,20).ToLowerInvariant())} finally {$hash.Dispose()}
}

function Get-GamingLocalDirectory {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]'){return ''}
    try {$full=[IO.Path]::GetFullPath($Path).TrimEnd('\');if($full.Length -lt 4 -or -not(Test-Path -LiteralPath $full -PathType Container)){return ''};return $full} catch {return ''}
}

function Test-GamingPathWithin {
    param([string]$Path,[string]$Directory)
    try {return [IO.Path]::GetFullPath($Path).StartsWith(([IO.Path]::GetFullPath($Directory).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)} catch {return $false}
}

function Test-GamingHelperExecutable {
    param([string]$Path)
    $name=[IO.Path]::GetFileNameWithoutExtension($Path)
    return ($name -match '(?i)(crash|reporter|unins|^setup|installer|redist|vc_red|vcredist|dxsetup|anticheat|anti.cheat|eac_launcher|webhelper|cefprocess|^UnityCrash|^GameLaunchHelper$|^notification_helper$|^QtWebEngineProcess$|^dotnet$|^jre|^javaw?$|updater$|tests?$|^steamcmd$|^steamservice$|^parsec|^AutoClicker$|^AutoKeyboard|^Key Presser$|^nvidiaProfileInspector$|^Intelligent standby|^PS3Dec$|^PS3 Quick Disc|^DolphinTool$|^eden-cli$|^Modmanager$|^Stand Mod Menu$|^Roblox Account Manager$|^cr3(tool|view)$|^shaderaot$|^.*-cli$|^RiotClient|^Riot Client$|^Server$)' -or $Path -match '(?i)[\\/](redist|_CommonRedist|__Installer|Installer|Support|DirectX|EasyAntiCheat|BattlEye|\.DepotDownloader|\.tools|tools|tests|mod-work)[\\/]')
}

function Test-GamingLauncherExecutable {
    param([string]$Path)
    return [IO.Path]::GetFileNameWithoutExtension($Path) -match '(?i)(launcher|bootstrap|updater|^startgame$|^launchgame$|^EADesktop$|^UbisoftConnect$|^GalaxyClient$|^steam$)'
}

function Get-GamingExecutableName {
    param([string]$Path)
    $name=[IO.Path]::GetFileNameWithoutExtension($Path)
    try {$product=[Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductName;if(-not [string]::IsNullOrWhiteSpace($product)){$name=$product}} catch { }
    $name=($name -replace '[\x00-\x1F]',' ').Trim()
    if($name.Length -gt 120){$name=$name.Substring(0,120)}
    return $name
}

function Get-GamingBoundedExecutables {
    param([string]$Directory,[ValidateRange(0,6)][int]$MaxDepth=4,[ValidateRange(1,3000)][int]$MaxDirectories=350,[ValidateRange(1,3000)][int]$MaxFiles=350,[ValidateRange(1,20)][int]$Seconds=5)
    $root=Get-GamingLocalDirectory $Directory
    if(-not $root){return @()}
    $queue=New-Object 'System.Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{Path=$root;Depth=0})
    $files=New-Object 'System.Collections.Generic.List[object]'
    $clock=[Diagnostics.Stopwatch]::StartNew();$visited=0
    while($queue.Count -and $visited -lt $MaxDirectories -and $files.Count -lt $MaxFiles -and $clock.Elapsed.TotalSeconds -lt $Seconds){
        $entry=$queue.Dequeue();$visited++
        try {
            $info=Get-Item -LiteralPath $entry.Path -ErrorAction Stop
            if($info.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            foreach($file in @(Get-ChildItem -LiteralPath $entry.Path -Filter '*.exe' -File -ErrorAction SilentlyContinue)){
                if($files.Count -ge $MaxFiles){break}
                if(-not($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -and -not(Test-GamingHelperExecutable $file.FullName)){$files.Add($file)}
            }
            if($entry.Depth -lt $MaxDepth){
                foreach($child in @(Get-ChildItem -LiteralPath $entry.Path -Directory -ErrorAction SilentlyContinue)){
                    if($queue.Count+$visited -ge $MaxDirectories){break}
                    if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
                    if($child.Name -match '(?i)^(\..*|.*_Data|node_modules|logs|cache|shader_cache|redist|_CommonRedist|__Installer|support|screenshots|videos|EasyAntiCheat|BattlEye|tools|tests|mod-work|Riot Client)$'){continue}
                    $queue.Enqueue([pscustomobject]@{Path=$child.FullName;Depth=($entry.Depth+1)})
                }
            }
        } catch { }
    }
    $script:GamingLastBoundedScan=[pscustomobject]@{Path=$root;DirectoriesVisited=$visited;Candidates=$files.Count;ElapsedSeconds=[math]::Round($clock.Elapsed.TotalSeconds,2);LimitReached=([bool]($queue.Count -or $files.Count -ge $MaxFiles));MaxDepth=$MaxDepth}
    return @($files.ToArray())
}

function Read-GamingXml {
    param([string]$Path)
    $settings=New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing=[Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
    $reader=[Xml.XmlReader]::Create($Path,$settings)
    try {$document=New-Object Xml.XmlDocument;$document.XmlResolver=$null;$document.Load($reader);return ,$document} finally {$reader.Dispose()}
}

function New-GamingDiscoveredGame {
    param([string]$Id,[string]$Name,[string]$Source,[string]$InstallDirectory,[string]$LaunchUri='',[string]$LaunchExecutablePath='',[string]$ExecutablePath='',[string]$AppUserModelId='')
    $directory=Get-GamingLocalDirectory $InstallDirectory
    if(-not $directory -or [string]::IsNullOrWhiteSpace($Name)){return $null}
    if($LaunchExecutablePath -and -not(Test-GamingLocalExecutable $LaunchExecutablePath)){$LaunchExecutablePath=''}
    if($ExecutablePath -and -not(Test-GamingLocalExecutable $ExecutablePath)){$ExecutablePath=''}
    return [pscustomobject]@{Id=$Id;Name=($Name -replace '[\x00-\x1F]',' ').Trim();Source=$Source;LaunchUri=$LaunchUri;LaunchExecutablePath=$LaunchExecutablePath;ExecutablePath=$ExecutablePath;InstallDirectory=$directory;AppUserModelId=$AppUserModelId}
}

function Get-GamingEpicInstalledGames {
    $folder=Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    foreach($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.item' -File -ErrorAction SilentlyContinue | Select-Object -First 500)){
        try {
            $item=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            $app=[string]$item.AppName;$ns=[string]$item.CatalogNamespace;$catalog=[string]$item.CatalogItemId
            if($app -notmatch '^[A-Za-z0-9_.-]+$' -or $ns -notmatch '^[A-Za-z0-9_.-]+$' -or $catalog -notmatch '^[A-Za-z0-9_.-]+$'){continue}
            if($item.MainGameAppName -and [string]$item.MainGameAppName -ne $app){continue}
            if(-not $item.LaunchExecutable){continue}
            $directory=Get-GamingLocalDirectory ([string]$item.InstallLocation);if(-not $directory){continue}
            $exe=[IO.Path]::GetFullPath((Join-Path $directory ([string]$item.LaunchExecutable).Replace('/','\')))
            if(-not(Test-GamingPathWithin $exe $directory) -or -not(Test-GamingLocalExecutable $exe)){continue}
            $uri='com.epicgames.launcher://apps/'+$ns+'%3A'+$catalog+'%3A'+$app+'?action=launch&silent=true'
            $actual=if(Test-GamingLauncherExecutable $exe){''}else{$exe}
            New-GamingDiscoveredGame -Id (Get-GamingStableId 'epic' ($ns+':'+$catalog+':'+$app)) -Name $item.DisplayName -Source 'Epic' -InstallDirectory $directory -LaunchUri $uri -LaunchExecutablePath $exe -ExecutablePath $actual
        } catch { }
    }
}

function Get-GamingRegistryInstalledGames {
    # Local installed-game keys only. Registry command strings are never executed.
    foreach($base in @('HKLM:\SOFTWARE\GOG.com\Games','HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games')){
        foreach($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Select-Object -First 500)){
            try {
                $item=Get-ItemProperty -LiteralPath $key.PSPath
                $directory=Get-GamingLocalDirectory ([string]$item.path);if(-not $directory){continue}
                $name=[string]$item.gameName;if(-not $name){$name=[IO.Path]::GetFileName($directory)}
                $exe=[string]$item.exe;if(-not $exe){$exe=[string]$item.exeFile}
                if($exe -and -not [IO.Path]::IsPathRooted($exe)){$exe=Join-Path $directory $exe}
                if(-not(Test-GamingPathWithin $exe $directory)){$exe=''}
                New-GamingDiscoveredGame -Id (Get-GamingStableId 'gog' $key.PSChildName) -Name $name -Source 'GOG' -InstallDirectory $directory -LaunchExecutablePath $exe -ExecutablePath $exe
            } catch { }
        }
    }
    foreach($base in @('HKLM:\SOFTWARE\Ubisoft\Launcher\Installs','HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs')){
        foreach($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Select-Object -First 500)){
            try {
                if($key.PSChildName -notmatch '^\d+$'){continue}
                $item=Get-ItemProperty -LiteralPath $key.PSPath
                $directory=Get-GamingLocalDirectory ([string]$item.InstallDir);if(-not $directory){$directory=Get-GamingLocalDirectory ([string]$item.InstallLocation)}
                if(-not $directory){continue}
                $name=[string]$item.DisplayName;if(-not $name){$name=[IO.Path]::GetFileName($directory)}
                New-GamingDiscoveredGame -Id ('ubisoft-'+$key.PSChildName) -Name $name -Source 'Ubisoft' -InstallDirectory $directory -LaunchUri ('uplay://launch/'+$key.PSChildName+'/0')
            } catch { }
        }
    }
    $eaRoots=@('HKLM:\SOFTWARE\Electronic Arts\EA Games','HKLM:\SOFTWARE\WOW6432Node\Electronic Arts\EA Games','HKLM:\SOFTWARE\EA Games','HKLM:\SOFTWARE\WOW6432Node\EA Games')
    foreach($base in $eaRoots){
        foreach($key in @(Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Select-Object -First 500)){
            try {
                $item=Get-ItemProperty -LiteralPath $key.PSPath
                $directory=Get-GamingLocalDirectory ([string]$item.'Install Dir');if(-not $directory){$directory=Get-GamingLocalDirectory ([string]$item.InstallDir)};if(-not $directory){$directory=Get-GamingLocalDirectory ([string]$item.InstallLocation)}
                if(-not $directory){continue}
                $name=[string]$item.DisplayName;if(-not $name){$name=$key.PSChildName}
                if($name -match '(?i)(EA Desktop|EA App|Anti.?Cheat|Origin$)'){continue}
                New-GamingDiscoveredGame -Id (Get-GamingStableId 'ea' $directory) -Name $name -Source 'EA' -InstallDirectory $directory
            } catch { }
        }
    }
}

function Get-GamingXboxInstalledGames {
    $seen=@{}
    if(Get-Command Get-AppxPackage -ErrorAction SilentlyContinue){
        foreach($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)){
            try {
                if(-not $package.InstallLocation){continue}
                $directory=[string]$package.InstallLocation;$config=Join-Path $directory 'MicrosoftGame.config'
                if(-not(Test-Path -LiteralPath $config -PathType Leaf)){continue}
                $xml=Read-GamingXml $config;$name=[string]$xml.Game.ShellVisuals.DefaultDisplayName
                if(-not $name){$name=[string]$package.Name}
                $appx=Read-GamingXml (Join-Path $directory 'AppxManifest.xml')
                $application=@($appx.Package.Applications.Application | Where-Object {$_.Id -and $_.Executable}) | Select-Object -First 1
                if(-not $application -or [string]$application.Id -notmatch '^[A-Za-z0-9_.-]+$' -or [string]$package.PackageFamilyName -notmatch '^[A-Za-z0-9_.-]+$'){continue}
                $executables=@($xml.Game.ExecutableList.Executable | Where-Object {$_.TargetDeviceFamily -eq 'PC' -and $_.IsDevOnly -ne 'true'})
                $exe='';if($executables.Count){$exe=[IO.Path]::GetFullPath((Join-Path $directory ([string]$executables[0].Name)))}
                if(-not(Test-GamingPathWithin $exe $directory)){$exe=''}
                $actual=if($name -match '(?i)launcher' -or (Test-GamingLauncherExecutable $exe)){''}else{$exe}
                $seen[$directory]=$true
                if($xml.Game.Identity.Name){$seen['identity:'+([string]$xml.Game.Identity.Name)]=$true}
                New-GamingDiscoveredGame -Id (Get-GamingStableId 'xbox' ([string]$package.PackageFamilyName)) -Name $name -Source 'Xbox' -InstallDirectory $directory -ExecutablePath $actual -AppUserModelId ($package.PackageFamilyName+'!'+$application.Id)
            } catch { }
        }
    }
    # Xbox app's configurable installation location: inspect only known roots plus configured scan roots.
    $roots=@(Get-GamingFixedDriveRoots | ForEach-Object {Join-Path $_ 'XboxGames'})+@(Read-GamingDiscoveryState 'game-scan-folders' 'Folders' | ForEach-Object Path | Where-Object {$_ -match '(?i)[\\/]XboxGames$'})
    foreach($root in @($roots | Select-Object -Unique)){
        foreach($folder in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Select-Object -First 150)){
            try {
                $directory=Join-Path $folder.FullName 'Content';$config=Join-Path $directory 'MicrosoftGame.config'
                if($seen.ContainsKey($directory) -or -not(Test-Path -LiteralPath $config -PathType Leaf)){continue}
                $xml=Read-GamingXml $config;$name=[string]$xml.Game.ShellVisuals.DefaultDisplayName
                if($xml.Game.Identity.Name -and $seen.ContainsKey('identity:'+([string]$xml.Game.Identity.Name))){continue}
                $entry=@($xml.Game.ExecutableList.Executable | Where-Object {$_.TargetDeviceFamily -eq 'PC' -and $_.IsDevOnly -ne 'true'}) | Select-Object -First 1
                if(-not $entry){continue};$exe=[IO.Path]::GetFullPath((Join-Path $directory ([string]$entry.Name)))
                if(-not(Test-GamingPathWithin $exe $directory)){continue}
                $actual=if($name -match '(?i)launcher' -or (Test-GamingLauncherExecutable $exe)){''}else{$exe}
                New-GamingDiscoveredGame -Id (Get-GamingStableId 'xbox-local' $directory) -Name $name -Source 'Xbox' -InstallDirectory $directory -LaunchExecutablePath $exe -ExecutablePath $actual
            } catch { }
        }
    }
}

function Get-GamingFixedDriveRoots {
    return @([IO.DriveInfo]::GetDrives() | Where-Object {$_.DriveType -eq [IO.DriveType]::Fixed -and $_.IsReady} | ForEach-Object {$_.RootDirectory.FullName})
}

function Get-GamingScanFolders {
    $paths=New-Object 'System.Collections.Generic.List[string]'
    foreach($path in @(Read-GamingDiscoveryState 'game-scan-folders' 'Folders' | ForEach-Object Path)){if($path){$paths.Add([string]$path)}}
    # Keep previously found portable game roots without embedding a user's drive layout in defaults.
    foreach($path in @(Read-GamingDiscoveryState 'game-discovery' 'Games' | Where-Object Source -eq 'Folder' | ForEach-Object InstallDirectory)){if($path){$paths.Add([string]$path)}}
    foreach($drive in @(Get-GamingFixedDriveRoots)){
        foreach($name in @('Games','GOG Games','Epic Games','Riot Games','Emulators')){$paths.Add((Join-Path $drive $name))}
        # Shallow discovery is restricted to top-level folders on fixed local drives.
        # Windows, user profiles, media libraries and tool/source trees are not walked automatically.
        foreach($folder in @(Get-ChildItem -LiteralPath $drive -Directory -ErrorAction SilentlyContinue | Select-Object -First 160)){
            if($folder.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if($folder.Name -match '(?i)^(\$|Windows$|WindowsApps$|WpSystem$|Program Files(?: \(x86\))?$|ProgramData$|Users$|Recovery$|System Volume Information$|PerfLogs$|Config\.Msi$|SteamLibrary$|steamapps$|Steam$|steamcmd$|XboxGames$|PC Tools$|MediaAutomation$|movies$|TV$|shows$|music$|pictures$|photos$|videos$|backups?$|node_modules$|github$|\.git$|_CommonRedist$|exports$|Save files|save_data$|Vortex Mods$|ISLC |nvidiaProfileInspector$|AMD$|NVIDIA$|Intel$|Drivers$|ESD$|Preserved .+copies$)' -or $folder.Name -match '(?i)(backup|original.+copy)'){continue}
            $paths.Add($folder.FullName)
        }
    }
    foreach($folder in @((Join-Path $env:USERPROFILE 'Games'),(Join-Path $env:LOCALAPPDATA 'Programs\itch'))){$paths.Add($folder)}
    return @($paths.ToArray() | ForEach-Object {Get-GamingLocalDirectory ([string]$_)} | Where-Object {$_} | Select-Object -Unique)
}

function Add-GamingScanFolder {
    [CmdletBinding()]
    param([string]$Path)
    if(-not $Path){
        Add-Type -AssemblyName System.Windows.Forms
        $picker=New-Object System.Windows.Forms.FolderBrowserDialog;$picker.Description='Choose a games folder to scan (not an entire drive)';$picker.ShowNewFolderButton=$false
        try {if($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return $null};$Path=$picker.SelectedPath} finally {$picker.Dispose()}
    }
    $directory=Get-GamingLocalDirectory $Path
    if(-not $directory){throw 'Choose an existing folder below a local drive root.'}
    $blocked=@($env:WINDIR,$env:ProgramFiles,${env:ProgramFiles(x86)},$env:USERPROFILE,$env:ProgramData)
    if($directory -in $blocked){throw 'Choose a specific games folder, not a Windows, Program Files, or user-profile root.'}
    $folders=@(Read-GamingDiscoveryState 'game-scan-folders' 'Folders')
    if(-not @($folders | Where-Object Path -eq $directory).Count){$folders+= [pscustomobject]@{Path=$directory;AddedUtc=[datetime]::UtcNow.ToString('o')};Write-GamingDiscoveryState 'game-scan-folders' ([pscustomobject]@{Version=1;Folders=$folders})}
    return [pscustomobject]@{Success=$true;Path=$directory;Message='Scan folder saved. Scan installed games to search this folder and nested game EXEs.'}
}

function Remove-GamingScanFolder {
    param([Parameter(Mandatory=$true)][string]$Path)
    $directory=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    $folders=@(Read-GamingDiscoveryState 'game-scan-folders' 'Folders' | Where-Object Path -ine $directory)
    Write-GamingDiscoveryState 'game-scan-folders' ([pscustomobject]@{Version=1;Folders=$folders})
    return [pscustomobject]@{Success=$true;Message='Custom scan root removed. Standard drive locations may still discover it.'}
}

function Get-GamingScanReport {
    $path=Join-Path $script:GamingGameLibraryRoot 'state\game-scan-report.json'
    if(Test-Path -LiteralPath $path -PathType Leaf){try {return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json}catch{ }}
    return [pscustomobject]@{CheckedUtc='';Folders=@();CandidateCount=0;Warnings=@();Message='No extended game scan has run yet.'}
}

function Get-GamingFolderGroupingDirectory {
    param([string]$ExecutablePath,[string]$Root)
    $directory=[IO.Path]::GetDirectoryName($ExecutablePath)
    $relative=$directory.Substring($Root.TrimEnd('\').Length).Trim('\')
    $parts=@($relative -split '\\' | Where-Object {$_})
    $prefix=$Root
    foreach($part in $parts){
        if($part -match '(?i)^(Binaries|bin|bin64|bin32|x64|x86|Win64|Win32|Engine|WindowsNoEditor|Windows|Plugins|Managed|Mono|Runtime|.*_Data)$'){return $prefix}
        $prefix=Join-Path $prefix $part
    }
    return $directory
}

function Get-GamingFolderInstalledGames {
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $script:GamingFolderScanRows=New-Object 'System.Collections.Generic.List[object]'
    $script:GamingFolderScanWarnings=New-Object 'System.Collections.Generic.List[string]'
    $configured=@(Read-GamingDiscoveryState 'game-scan-folders' 'Folders' | ForEach-Object Path)
    $emitted=@{}
    foreach($root in @(Get-GamingScanFolders)){
        if($clock.Elapsed.TotalSeconds -gt 35){$script:GamingFolderScanWarnings.Add('The 35-second portable-folder scan limit was reached. Add a missed game folder explicitly so it is scanned first.');break}
        if(Get-Command Write-GamingStatus -ErrorAction SilentlyContinue){Write-GamingStatus ('Finding portable game EXEs: '+$root)}
        $explicit=$root -in $configured
        $files=@(Get-GamingBoundedExecutables -Directory $root -MaxDepth $(if($explicit){6}else{4}) -MaxDirectories $(if($explicit){800}else{150}) -MaxFiles $(if($explicit){1000}else{250}) -Seconds $(if($explicit){8}else{2}))
        if($script:GamingLastBoundedScan){$script:GamingFolderScanRows.Add($script:GamingLastBoundedScan);if($script:GamingLastBoundedScan.LimitReached){$script:GamingFolderScanWarnings.Add('Scan bound reached for '+$root+'. Add a narrower game folder for a deeper search.')}}
        $groups=@{}
        foreach($file in $files){$directory=Get-GamingFolderGroupingDirectory $file.FullName $root;if(-not $groups.ContainsKey($directory)){$groups[$directory]=New-Object 'System.Collections.Generic.List[object]'};$groups[$directory].Add($file)}
        foreach($folder in @($groups.Keys | Sort-Object)){
            $group=@($groups[$folder].ToArray());$top=@($group | Where-Object DirectoryName -eq $folder)
            $launch=@($top | Where-Object {(Test-GamingLauncherExecutable $_.FullName)} | Sort-Object Name | Select-Object -First 1)
            if(-not $launch.Count){
                # Keep distinct portable EXEs sharing a directory. Engine copies with the same base name collapse.
                $actual=@($group | Where-Object {-not(Test-GamingLauncherExecutable $_.FullName)} | Sort-Object @{Expression={if($_.DirectoryName -eq $folder){0}else{1}}},@{Expression='Length';Descending=$true})
                $names=@{};$launch=@(foreach($file in $actual){$key=([IO.Path]::GetFileNameWithoutExtension($file.Name) -replace '(?i)([-_](Win64|Win32|Shipping|x64|x86))+$','');if(-not $names.ContainsKey($key)){$names[$key]=$true;$file}})
                if(-not $launch.Count){$launch=@($group | Select-Object -First 1)}
            }
            foreach($file in $launch){
                $path=$file.FullName;if($emitted.ContainsKey($path)){continue};$emitted[$path]=$true
                $name=Get-GamingExecutableName $path
                $idValue=if($launch.Count -eq 1){$folder}else{$path}
                # Unregistered EXEs are suggestions; driver binding remains an explicit user choice.
                New-GamingDiscoveredGame -Id (Get-GamingStableId 'scan' $idValue) -Name $name -Source 'Folder' -InstallDirectory $folder -LaunchExecutablePath $path
            }
        }
    }
}

function Get-GamingDiscoverySources {
    $counts=@{};foreach($game in @(Get-GameLibrary)){$counts[[string]$game.Source]++}
    foreach($source in @(
        @{Name='Steam';Method='Registered Steam libraries';Detail='Installed app manifests; utilities excluded.'},
        @{Name='Epic';Method='Epic install manifests';Detail='Installed base games only; removed installs and DLC excluded.'},
        @{Name='GOG';Method='GOG installed-game registry';Detail='Exact registered executables when available.'},
        @{Name='EA';Method='EA installed-game registry';Detail='Choose the game EXE if metadata has no launch target.'},
        @{Name='Ubisoft';Method='Ubisoft installed-game registry';Detail='Uses the Ubisoft Connect game launch URI.'},
        @{Name='Xbox';Method='MicrosoftGame.config and Appx registration';Detail='Games with readable installation metadata; protected files may need manual selection.'},
        @{Name='Folder';Method='Portable EXEs and configured folders';Detail='Bounded scans of top-level game folders on fixed drives, up to 6 levels in explicitly chosen folders. Helper EXEs and system/media roots are skipped.'},
        @{Name='Manual';Method='Add EXE';Detail='Any existing local game or launcher EXE can be added.'}
    )){[pscustomobject]@{Name=$source.Name;Source=$source.Name;Method=$source.Method;Detail=$source.Detail;Count=[int]$counts[$source.Name];Folders=$(if($source.Name -eq 'Folder'){@(Get-GamingScanFolders)}else{@()})}}
}

function Invoke-GamingGameScan {
    [CmdletBinding()]
    param()
    try {
        $before=@(Get-GameLibrary);$items=New-Object 'System.Collections.Generic.List[object]'
        $seenIds=@{};$seenPaths=@{};$seenExecutables=@{}
        foreach($game in $before | Where-Object {$_.Source -in @('Steam','Manual')}){if($game.InstallDirectory){$seenPaths[[string]$game.InstallDirectory]=$true}}
        foreach($getter in @('Get-GamingEpicInstalledGames','Get-GamingRegistryInstalledGames','Get-GamingXboxInstalledGames','Get-GamingFolderInstalledGames')){
            if(Get-Command Write-GamingStatus -ErrorAction SilentlyContinue){Write-GamingStatus ('Scanning installed games: '+$getter.Replace('Get-Gaming','').Replace('InstalledGames',''))}
            foreach($item in @(& $getter)){
                if(-not $item -or $seenIds.ContainsKey([string]$item.Id) -or $seenPaths.ContainsKey([string]$item.InstallDirectory) -or ($item.LaunchExecutablePath -and $seenExecutables.ContainsKey([string]$item.LaunchExecutablePath))){continue}
                $seenIds[[string]$item.Id]=$true;if($item.Source -ne 'Folder'){$seenPaths[[string]$item.InstallDirectory]=$true};if($item.LaunchExecutablePath){$seenExecutables[[string]$item.LaunchExecutablePath]=$true};$items.Add($item)
            }
        }
        Write-GamingDiscoveryState 'game-discovery' ([pscustomobject]@{Version=1;ScannedUtc=[datetime]::UtcNow.ToString('o');Games=@($items.ToArray())})
        $after=@(Get-GameLibrary);$new=@($after | Where-Object {$_.Id -notin @($before.Id)})
        $warnings=@();$rows=@();if($script:GamingFolderScanRows){$rows=@($script:GamingFolderScanRows.ToArray())};if($script:GamingFolderScanWarnings){$warnings=@($script:GamingFolderScanWarnings.ToArray())}
        $message='Found '+$after.Count+' installed games, portable EXEs and launchers ('+$new.Count+' newly discovered). Folder results are candidates; choose the actual game EXE for CPU and GPU controls.'
        Write-GamingDiscoveryState 'game-scan-report' ([pscustomobject]@{Version=1;CheckedUtc=[datetime]::UtcNow.ToString('o');Folders=$rows;CandidateCount=$after.Count;Warnings=$warnings;Message=$message})
        return [pscustomobject]@{Success=$true;Count=$after.Count;AddedCount=$new.Count;Warnings=$warnings;Message=$message}
    } catch {return [pscustomobject]@{Success=$false;Count=0;AddedCount=0;Message=$_.Exception.Message}}
}

function Get-GamingGameExecutableCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId)
    $game=Get-GameLibrary | Where-Object Id -eq $GameId | Select-Object -First 1
    if(-not $game){return @()}
    $files=@(Get-GamingBoundedExecutables -Directory $game.InstallDirectory)
    foreach($path in @($game.ExecutablePath,$game.LaunchExecutablePath)){
        if((Test-GamingLocalExecutable $path) -and $path -notin @($files.FullName)){$files+=Get-Item -LiteralPath $path}
    }
    $ordered=@($files | Sort-Object @{Expression={if(Test-GamingLauncherExecutable $_.FullName){1}else{0}}},@{Expression={if($_.FullName -ieq $game.ExecutablePath){0}else{1}}},@{Expression='Length';Descending=$true})
    $firstActual=@($ordered | Where-Object {-not(Test-GamingLauncherExecutable $_.FullName) -and -not(Test-GamingHelperExecutable $_.FullName)} | Select-Object -First 1)
    foreach($file in $ordered){
        [pscustomobject]@{Path=$file.FullName;Name=$file.Name;IsLauncher=(Test-GamingLauncherExecutable $file.FullName);Suggested=($firstActual.Count -and $file.FullName -eq $firstActual[0].FullName);Source=$(if($file.FullName -eq $game.ExecutablePath){'Current selection'}else{'Installed file'})}
    }
}

function Set-GamingGameExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId,[string]$ExecutablePath)
    $game=Get-GameLibrary | Where-Object Id -eq $GameId | Select-Object -First 1
    if(-not $game){throw 'That game is no longer installed. Refresh the library.'}
    if(-not $ExecutablePath){
        Add-Type -AssemblyName System.Windows.Forms
        $picker=New-Object Windows.Forms.OpenFileDialog;$picker.Title='Choose the actual game EXE for driver settings';$picker.Filter='Executable (*.exe)|*.exe';$picker.CheckFileExists=$true;$picker.Multiselect=$false
        if(Test-Path -LiteralPath $game.InstallDirectory -PathType Container){$picker.InitialDirectory=$game.InstallDirectory}
        try {if($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK){return $null};$ExecutablePath=$picker.FileName} finally {$picker.Dispose()}
    }
    if(-not(Test-GamingLocalExecutable $ExecutablePath)){throw 'Choose an existing .exe file on a local drive.'}
    $path=[IO.Path]::GetFullPath($ExecutablePath)
    $bindings=@(Read-GamingDiscoveryState 'game-bindings' 'Bindings' | Where-Object GameId -ne $GameId)
    $bindings+=[pscustomobject]@{GameId=$GameId;ExecutablePath=$path;UpdatedUtc=[datetime]::UtcNow.ToString('o')}
    Write-GamingDiscoveryState 'game-bindings' ([pscustomobject]@{Version=1;Bindings=$bindings})
    return [pscustomobject]@{Success=$true;GameId=$GameId;ExecutablePath=$path;IsLauncher=(Test-GamingLauncherExecutable $path);Message='Game EXE saved. Its original store or launcher action is preserved.'}
}
