$ErrorActionPreference='Stop'
$moduleRoot=Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $moduleRoot 'GameLibrary.ps1')
$testRoot=Join-Path (Split-Path $PSCommandPath -Parent) ('discovery-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:GamingGameLibraryRoot=$testRoot
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Discovery([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$checks.Add($Name)}
function New-TestGameDirectory([string]$Name){$path=Join-Path $testRoot $Name;New-Item -ItemType Directory -Path $path -Force | Out-Null;return $path}
function New-TestExe([string]$Directory,[string]$Name){$path=Join-Path $Directory $Name;Copy-Item -LiteralPath (Join-Path $moduleRoot 'GamingMode.exe') -Destination $path;return $path}
$steamLibrary=New-TestGameDirectory 'steam'
$steamGame=New-TestGameDirectory 'steam\steamapps\common\Fixture Game'
$steamExe=New-TestExe $steamGame 'FixtureGame.exe'
$steamLauncher=New-TestExe $steamGame 'FixtureLauncher.exe'
$crash=New-TestExe $steamGame 'CrashReportClient.exe'
'"AppState" { "appid" "123456" "name" "Fixture Steam Game" "installdir" "Fixture Game" }' | Set-Content -LiteralPath (Join-Path $steamLibrary 'steamapps\appmanifest_123456.acf')
function Get-GamingSteamLibraries {return @($steamLibrary)}
$manualDirectory=New-TestGameDirectory 'manual'
$manualLauncher=New-TestExe $manualDirectory 'FixtureLauncher.exe'
$manualExe=New-TestExe $manualDirectory 'RealGame.exe'
$manual=Add-GamingGame -ExecutablePath $manualLauncher
$epicDirectory=New-TestGameDirectory 'epic';$epicExe=New-TestExe $epicDirectory 'EpicFixture.exe'
$gogDirectory=New-TestGameDirectory 'gog';$gogExe=New-TestExe $gogDirectory 'GogFixture.exe'
$ubiDirectory=New-TestGameDirectory 'ubi';$ubiExe=New-TestExe $ubiDirectory 'UbisoftFixture.exe'
$xboxDirectory=New-TestGameDirectory 'xbox';$xboxExe=New-TestExe $xboxDirectory 'XboxFixture.exe'
$folderDirectory=New-TestGameDirectory 'folder';$folderLauncher=New-TestExe $folderDirectory 'ReSkateLauncher.exe';$folderExe=New-TestExe $folderDirectory 'Skate.exe'
function Get-GamingEpicInstalledGames {New-GamingDiscoveredGame -Id 'epic-123abc' -Name 'Epic fixture' -Source Epic -InstallDirectory $epicDirectory -LaunchUri 'com.epicgames.launcher://apps/ns%3Acatalog%3Aapp?action=launch&silent=true' -LaunchExecutablePath $epicExe -ExecutablePath $epicExe}
function Get-GamingRegistryInstalledGames {
    New-GamingDiscoveredGame -Id 'gog-123abc' -Name 'GOG fixture' -Source GOG -InstallDirectory $gogDirectory -LaunchExecutablePath $gogExe -ExecutablePath $gogExe
    New-GamingDiscoveredGame -Id 'ubisoft-77' -Name 'Ubisoft fixture' -Source Ubisoft -InstallDirectory $ubiDirectory -LaunchUri 'uplay://launch/77/0'
}
function Get-GamingXboxInstalledGames {New-GamingDiscoveredGame -Id 'xbox-123abc' -Name 'Xbox fixture' -Source Xbox -InstallDirectory $xboxDirectory -ExecutablePath $xboxExe -AppUserModelId 'Example.Game_abc!Game'}
function Get-GamingScanFolders {return @($folderDirectory,$manualDirectory)}
$scan=Invoke-GamingGameScan
Assert-Discovery ($scan.Success -and $scan.Count -eq 7 -and $scan.AddedCount -eq 5) 'Multiple stores discovered and manual folder deduplicated'
$library=@(Get-GameLibrary)
$steam=@($library | Where-Object Source -eq Steam)[0]
$binding=Set-GamingGameExecutable -GameId $steam.Id -ExecutablePath $steamExe
$updated=Get-GameLibrary | Where-Object Id -eq $steam.Id
Assert-Discovery ($binding.Success -and $updated.ExecutablePath -eq $steamExe -and $updated.IsExecutableBound -and $updated.LaunchUri -eq $steam.LaunchUri) 'Steam EXE overlay preserves store launch URI'
$candidates=@(Get-GamingGameExecutableCandidates -GameId $steam.Id)
Assert-Discovery (@($candidates | Where-Object Path -eq $crash).Count -eq 0 -and @($candidates | Where-Object {$_.Path -eq $steamLauncher -and $_.IsLauncher}).Count -eq 1 -and @($candidates | Where-Object {$_.Path -eq $steamExe -and $_.Suggested}).Count -eq 1) 'Executable candidates exclude crash helpers and distinguish launcher'
Set-GamingGameExecutable -GameId $manual.Id -ExecutablePath $manualExe | Out-Null
$updatedManual=Get-GameLibrary | Where-Object Id -eq $manual.Id
Assert-Discovery ($updatedManual.ExecutablePath -eq $manualExe -and $updatedManual.LaunchExecutablePath -eq $manualLauncher) 'Manual game binding preserves original launcher'
$folder=Get-GameLibrary | Where-Object Source -eq Folder
Assert-Discovery ($folder.LaunchExecutablePath -eq $folderLauncher -and -not $folder.ExecutablePath -and $folder.NeedsExecutableSelection) 'Folder discovery leaves driver EXE selection explicit'
$script:LaunchCalls=New-Object 'System.Collections.Generic.List[object]'
function Start-Process {param($FilePath,$ArgumentList,$WorkingDirectory,$WindowStyle) $script:LaunchCalls.Add([pscustomobject]@{FilePath=$FilePath;Arguments=$ArgumentList})}
function Invoke-GamingAction {param($Action) $script:LaunchCalls.Add([pscustomobject]@{FilePath=('mode:'+ $Action);Arguments=''});[pscustomobject]@{Success=$true}}
$result=Start-GamingGame -GameId $manual.Id -EnterMode:$true
Assert-Discovery ($result.Success -and $script:LaunchCalls[0].FilePath -eq 'mode:Enter' -and $script:LaunchCalls[1].FilePath -eq $manualLauncher) 'Gaming Mode order and original manual launcher dispatch (mock only)'
foreach($game in $library | Where-Object Source -in @('Steam','Epic','Ubisoft','Xbox','GOG','Folder')){$result=Start-GamingGame -GameId $game.Id;Assert-Discovery $result.Success ('Safe '+$game.Source+' launch dispatch (mock only)')}
$cached=@(Read-GamingDiscoveryState 'game-discovery' 'Games');($cached | Where-Object Source -eq Epic).LaunchUri='https://example.invalid/untrusted'
Write-GamingDiscoveryState 'game-discovery' ([pscustomobject]@{Version=1;Games=$cached})
$before=$LaunchCalls.Count;$blocked=Start-GamingGame -GameId 'epic-123abc'
Assert-Discovery (-not $blocked.Success -and $LaunchCalls.Count -eq $before) 'Unrecognized launch URI rejected'
$rejected=$false;try {Add-GamingScanFolder -Path ([IO.Path]::GetPathRoot($testRoot)) | Out-Null}catch{$rejected=$true}
Assert-Discovery $rejected 'Whole-drive scan rejected'
$rejected=$false;try {Set-GamingGameExecutable -GameId $steam.Id -ExecutablePath 'https://example.invalid/game.exe' | Out-Null}catch{$rejected=$true}
Assert-Discovery $rejected 'Nonlocal executable rejected'
$rejected=$false;try {Set-GamingGameExecutable -GameId 'unknown' -ExecutablePath $steamExe | Out-Null}catch{$rejected=$true}
Assert-Discovery $rejected 'Unknown game binding rejected'
$nested=New-TestGameDirectory 'folder\nested';$nestedExe=New-TestExe $nested 'NestedGame.exe'
$bounded=@(Get-GamingBoundedExecutables -Directory $folderDirectory -MaxDepth 0)
Assert-Discovery (@($bounded | Where-Object FullName -eq $nestedExe).Count -eq 0) 'Executable search honors depth bound'
$saved=Read-GamingManualGames
Assert-Discovery ($saved[0].ExecutablePath -eq $manualLauncher) 'Existing manual library format preserved'
[pscustomobject]@{Passed=$true;Checks=@($checks.ToArray());LiveGameLaunches=0;Root=$testRoot} | ConvertTo-Json -Depth 4
