# Windows PowerShell 5.1. Dot-sourcing defines functions only.
$script:GamingGameLibraryRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'GameDiscovery.ps1')

function ConvertFrom-GamingVdf {
    param([Parameter(Mandatory=$true)][string]$Text)
    $tokens=@([regex]::Matches($Text,'"(?:\\.|[^"\\])*"|[{}]') | ForEach-Object Value)
    $cursor=@{Index=0}
    function Read-GamingVdfToken([string]$Token) {
        if($Token.Length -lt 2 -or $Token[0] -ne '"'){throw 'Invalid VDF string.'}
        return $Token.Substring(1,$Token.Length-2).Replace('\"','"').Replace('\\','\')
    }
    function Read-GamingVdfObject($List,$Position,[bool]$Nested) {
        $map=@{}
        while($Position.Index -lt $List.Count) {
            $keyToken=$List[$Position.Index];$Position.Index++
            if($keyToken -eq '}') {
                if(-not $Nested){throw 'Unexpected VDF closing brace.'}
                return ,$map
            }
            if($keyToken -eq '{'){throw 'Unexpected VDF opening brace.'}
            $key=Read-GamingVdfToken $keyToken
            if($Position.Index -ge $List.Count){throw 'Incomplete VDF property.'}
            $valueToken=$List[$Position.Index];$Position.Index++
            if($valueToken -eq '{') {$value=Read-GamingVdfObject $List $Position $true}
            else {$value=Read-GamingVdfToken $valueToken}
            $map[$key]=$value
        }
        if($Nested){throw 'Unclosed VDF object.'}
        return ,$map
    }
    return Read-GamingVdfObject $tokens $cursor $false
}

function Get-GamingSteamLibraries {
    $roots=New-Object 'System.Collections.Generic.List[string]'
    $steam=Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if($steam.SteamPath){$roots.Add(([string]$steam.SteamPath).Replace('/','\'))}
    if(-not $roots.Count){
        $fallback=Join-Path ${env:ProgramFiles(x86)} 'Steam'
        if(Test-Path -LiteralPath $fallback -PathType Container){$roots.Add($fallback)}
    }
    $libraries=New-Object 'System.Collections.Generic.List[string]'
    foreach($root in $roots){
        if(-not [IO.Path]::IsPathRooted($root)){continue}
        $full=[IO.Path]::GetFullPath($root)
        if(-not $libraries.Contains($full)){$libraries.Add($full)}
        $vdf=Join-Path $full 'steamapps\libraryfolders.vdf'
        if(-not(Test-Path -LiteralPath $vdf -PathType Leaf)){$vdf=Join-Path $full 'config\libraryfolders.vdf'}
        if(-not(Test-Path -LiteralPath $vdf -PathType Leaf)){continue}
        try {
            $parsed=ConvertFrom-GamingVdf (Get-Content -LiteralPath $vdf -Raw)
            foreach($key in @($parsed.libraryfolders.Keys)){
                if([string]$key -notmatch '^\d+$'){continue}
                $entry=$parsed.libraryfolders[$key]
                $path=if($entry -is [System.Collections.IDictionary]){[string]$entry.path}else{[string]$entry}
                if($path -and [IO.Path]::IsPathRooted($path)){
                    $path=[IO.Path]::GetFullPath($path)
                    if(-not $libraries.Contains($path)){$libraries.Add($path)}
                }
            }
        } catch {
            # A malformed or concurrently updated manifest must not break the rest of the library.
        }
    }
    return @($libraries.ToArray())
}

function Get-GamingManualGamesPath {
    Join-Path $script:GamingGameLibraryRoot 'state\games.json'
}

function Read-GamingManualGames {
    $path=Get-GamingManualGamesPath
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    $saved=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if([int]$saved.Version -ne 1){throw 'Unrecognized manual game library format; the file has been preserved.'}
    return @($saved.Games)
}

function Test-GamingLocalExecutable {
    param([string]$Path)
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\' -or [IO.Path]::GetExtension($Path) -ine '.exe'){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path)
        return (Test-Path -LiteralPath $full -PathType Leaf)
    } catch {return $false}
}

function Get-GameLibrary {
    [CmdletBinding()]
    param()
    $games=New-Object 'System.Collections.Generic.List[object]'
    $seen=@{}
    $utilityIds=@('228980','250820','431960','993090','1070560','1391110','1628350')
    foreach($library in @(Get-GamingSteamLibraries)) {
        $apps=Join-Path $library 'steamapps'
        if(-not(Test-Path -LiteralPath $apps -PathType Container)){continue}
        foreach($manifest in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try {
                $parsed=ConvertFrom-GamingVdf (Get-Content -LiteralPath $manifest.FullName -Raw)
                $app=$parsed.AppState
                $id=[string]$app.appid;$name=[string]$app.name
                if($id -notmatch '^\d+$' -or [string]::IsNullOrWhiteSpace($name) -or $seen.ContainsKey($id)){continue}
                if($id -in $utilityIds -or $name -match '(?i)^(Steamworks Common Redistributables|SteamVR|Wallpaper Engine|Lossless Scaling|Steam Linux Runtime|Proton)(\s|$)'){continue}
                $installDir=[string]$app.installdir
                if([string]::IsNullOrWhiteSpace($installDir) -or $installDir -match '[\\/]' -or $installDir -in @('.','..')){continue}
                $gameDirectory=Join-Path (Join-Path $apps 'common') $installDir
                if(-not(Test-Path -LiteralPath $gameDirectory -PathType Container)){continue}
                $seen[$id]=$true
                $games.Add([pscustomobject]@{Id=('steam-'+$id);Name=$name;Source='Steam';LaunchUri=('steam://rungameid/'+$id);ExecutablePath='';LaunchExecutablePath='';AppUserModelId='';InstallDirectory=$gameDirectory})
            } catch { }
        }
    }
    foreach($manual in @(Read-GamingManualGames)) {
        if(-not $manual -or [string]$manual.Id -notmatch '^manual-[a-f0-9]{32}$'){continue}
        $path=[string]$manual.ExecutablePath
        if(-not(Test-GamingLocalExecutable $path)){continue}
        $games.Add([pscustomobject]@{Id=[string]$manual.Id;Name=[string]$manual.Name;Source='Manual';LaunchUri='';ExecutablePath=[IO.Path]::GetFullPath($path);LaunchExecutablePath=[IO.Path]::GetFullPath($path);AppUserModelId='';InstallDirectory=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))})
    }
    $knownIds=@{};$knownDirectories=@{};$knownExecutables=@{}
    foreach($game in $games){$knownIds[[string]$game.Id]=$true;$knownDirectories[[string]$game.InstallDirectory]=$true;if($game.LaunchExecutablePath){$knownExecutables[[string]$game.LaunchExecutablePath]=$true}}
    foreach($cached in @(Read-GamingDiscoveryState 'game-discovery' 'Games')){
        if(-not $cached -or [string]$cached.Id -notmatch '^(epic|gog|ea|ubisoft|xbox|xbox-local|scan)-[A-Za-z0-9]+$' -or $cached.Source -notin @('Epic','GOG','EA','Ubisoft','Xbox','Folder')){continue}
        if($knownIds.ContainsKey([string]$cached.Id) -or $knownDirectories.ContainsKey([string]$cached.InstallDirectory) -or ($cached.LaunchExecutablePath -and $knownExecutables.ContainsKey([string]$cached.LaunchExecutablePath))){continue}
        $game=New-GamingDiscoveredGame -Id $cached.Id -Name $cached.Name -Source $cached.Source -InstallDirectory $cached.InstallDirectory -LaunchUri $cached.LaunchUri -LaunchExecutablePath $cached.LaunchExecutablePath -ExecutablePath $cached.ExecutablePath -AppUserModelId $cached.AppUserModelId
        if($game){$games.Add($game);$knownIds[[string]$game.Id]=$true;if($game.Source -ne 'Folder'){$knownDirectories[[string]$game.InstallDirectory]=$true};if($game.LaunchExecutablePath){$knownExecutables[[string]$game.LaunchExecutablePath]=$true}}
    }
    $bindings=@{};foreach($binding in @(Read-GamingDiscoveryState 'game-bindings' 'Bindings')){if($binding.GameId){$bindings[[string]$binding.GameId]=$binding}}
    foreach($game in $games){
        $bound=$false
        if($bindings.ContainsKey([string]$game.Id)){
            $selected=[string]$bindings[[string]$game.Id].ExecutablePath
            if(Test-GamingLocalExecutable $selected){$game.ExecutablePath=[IO.Path]::GetFullPath($selected);$bound=$true}
        }
        $isLauncher=($game.ExecutablePath -and (Test-GamingLauncherExecutable $game.ExecutablePath))
        $game | Add-Member -NotePropertyName IsExecutableBound -NotePropertyValue $bound -Force
        $game | Add-Member -NotePropertyName IsLauncher -NotePropertyValue ([bool]$isLauncher) -Force
        $game | Add-Member -NotePropertyName NeedsExecutableSelection -NotePropertyValue ([bool](-not $game.ExecutablePath -or $isLauncher)) -Force
    }
    return @($games.ToArray() | Sort-Object Name,Source)
}

function Add-GamingGame {
    [CmdletBinding()]
    param([string]$ExecutablePath)
    if(-not $ExecutablePath) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker=New-Object System.Windows.Forms.OpenFileDialog
        $picker.Title='Choose a game executable'
        $picker.Filter='Game executable (*.exe)|*.exe'
        $picker.CheckFileExists=$true;$picker.CheckPathExists=$true;$picker.Multiselect=$false
        try {
            if($picker.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK){return $null}
            $ExecutablePath=$picker.FileName
        } finally {$picker.Dispose()}
    }
    if(-not(Test-GamingLocalExecutable $ExecutablePath)){throw 'Choose an existing .exe file on a local drive.'}
    $path=[IO.Path]::GetFullPath($ExecutablePath)
    $games=@(Read-GamingManualGames)
    $existing=$games | Where-Object {[string]$_.ExecutablePath -ieq $path} | Select-Object -First 1
    if($existing){return $existing}
    $name=[IO.Path]::GetFileNameWithoutExtension($path)
    try {$product=[Diagnostics.FileVersionInfo]::GetVersionInfo($path).ProductName;if(-not [string]::IsNullOrWhiteSpace($product)){$name=$product}}catch{ }
    $name=($name -replace '[\x00-\x1F]',' ').Trim()
    if($name.Length -gt 120){$name=$name.Substring(0,120)}
    $game=[pscustomobject]@{Id=('manual-'+[Guid]::NewGuid().ToString('N'));Name=$name;Source='Manual';LaunchUri='';ExecutablePath=$path}
    $save=Get-GamingManualGamesPath
    $directory=Split-Path $save -Parent
    if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force | Out-Null}
    $pending=Join-Path $directory ('games.'+[Guid]::NewGuid().ToString('N')+'.pending.json')
    [pscustomobject]@{Version=1;Games=@($games)+@($game)} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination $save -Force
    return $game
}

function Start-GamingGame {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId,[bool]$EnterMode=$false)
    $game=@(Get-GameLibrary | Where-Object Id -eq $GameId)
    if($game.Count -ne 1){return [pscustomobject]@{Success=$false;Status='Unavailable';Game=$null;ModeResult=$null;Message='That installed game is no longer available. Refresh the library.'}}
    $game=$game[0]
    $modeResult=$null
    try {
        if($EnterMode){
            if(-not(Get-Command Invoke-GamingAction -ErrorAction SilentlyContinue)){throw 'Gaming Mode workflow is unavailable.'}
            $modeResult=Invoke-GamingAction 'Enter'
        }
        if($game.Source -eq 'Steam') {
            if($game.Id -notmatch '^steam-(\d+)$' -or $game.LaunchUri -ne ('steam://rungameid/'+$Matches[1])){throw 'Invalid Steam game identifier.'}
            Start-Process -FilePath $game.LaunchUri -WindowStyle Normal -ErrorAction Stop | Out-Null
        } elseif($game.Source -eq 'Epic') {
            if($game.LaunchUri -notmatch '^com\.epicgames\.launcher://apps/[A-Za-z0-9_.-]+%3A[A-Za-z0-9_.-]+%3A[A-Za-z0-9_.-]+\?action=launch&silent=true$'){throw 'Invalid Epic game launch URI.'}
            Start-Process -FilePath $game.LaunchUri -WindowStyle Normal -ErrorAction Stop | Out-Null
        } elseif($game.Source -eq 'Ubisoft') {
            if($game.Id -notmatch '^ubisoft-(\d+)$' -or $game.LaunchUri -ne ('uplay://launch/'+$Matches[1]+'/0')){throw 'Invalid Ubisoft game launch URI.'}
            Start-Process -FilePath $game.LaunchUri -WindowStyle Normal -ErrorAction Stop | Out-Null
        } elseif($game.Source -eq 'Xbox' -and $game.AppUserModelId) {
            if($game.AppUserModelId -notmatch '^[A-Za-z0-9_.-]+![A-Za-z0-9_.-]+$'){throw 'Invalid Xbox application identifier.'}
            Start-Process -FilePath (Join-Path $env:WINDIR 'explorer.exe') -ArgumentList ('shell:AppsFolder\'+$game.AppUserModelId) -WindowStyle Normal -ErrorAction Stop | Out-Null
        } elseif($game.Source -in @('Manual','Folder','GOG','EA','Xbox')) {
            $launchPath=[string]$game.LaunchExecutablePath
            if(-not $launchPath -and $game.Source -ne 'Manual'){$launchPath=[string]$game.ExecutablePath}
            if(-not(Test-GamingLocalExecutable $launchPath)){throw 'Choose this game''s executable before launching it.'}
            Start-Process -FilePath $launchPath -WorkingDirectory ([IO.Path]::GetDirectoryName($launchPath)) -WindowStyle Normal -ErrorAction Stop | Out-Null
        } else {throw 'Unsupported game source.'}
        $cpuResult=$null
        if((Get-Command Get-GamingProcessPreference -ErrorAction SilentlyContinue) -and (Get-Command Invoke-GamingLaunchProcessTuning -ErrorAction SilentlyContinue)){
            try {
                $cpuPreference=Get-GamingProcessPreference -GameId $game.Id
                if($cpuPreference.ApplyOnLaunch){$cpuResult=Invoke-GamingLaunchProcessTuning -GameId $game.Id -WaitSeconds 15}
            } catch {$cpuResult=[pscustomobject]@{Success=$false;Applied=$false;Message=$_.Exception.Message}}
        }
        $partial=($EnterMode -and -not $modeResult.Success) -or ($cpuResult -and -not $cpuResult.Success)
        $message='Game launch requested.'
        if($EnterMode -and -not $modeResult.Success){$message+=' Some background apps stayed open; review the Gaming Mode results.'}
        if($cpuResult){$message+=' CPU controls: '+$cpuResult.Message}
        return [pscustomobject]@{Success=$true;Status=$(if($partial){'LaunchRequestedWithWarnings'}else{'LaunchRequested'});Game=$game;ModeResult=$modeResult;CpuResult=$cpuResult;Message=$message}
    } catch {
        return [pscustomobject]@{Success=$false;Status='Failed';Game=$game;ModeResult=$modeResult;Message=$_.Exception.Message}
    }
}
