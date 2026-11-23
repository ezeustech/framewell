$ErrorActionPreference='Stop'
$moduleRoot=Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $moduleRoot 'GameLibrary.ps1')
. (Join-Path $moduleRoot 'NetworkDiagnostics.ps1')
$testRoot=Join-Path (Split-Path $PSCommandPath -Parent) ('module-'+[guid]::NewGuid().ToString('N'))
$script:GamingGameLibraryRoot=$testRoot
$script:GamingNetworkRoot=$testRoot
New-Item -ItemType Directory -Path (Join-Path $testRoot 'state') -Force | Out-Null
$games=@(Get-GameLibrary)
if($games.Count -lt 1 -or @($games | Where-Object Name -match 'Wallpaper Engine|Lossless Scaling|SteamVR|Steamworks Common').Count){throw 'Steam discovery or utility exclusion failed'}
$exe=Join-Path $moduleRoot 'GamingMode.exe'
$manual=Add-GamingGame -ExecutablePath $exe
$duplicate=Add-GamingGame -ExecutablePath $exe
if($manual.Id -ne $duplicate.Id -or @(Read-GamingManualGames).Count -ne 1){throw 'Manual duplicate detection failed'}
$script:LaunchCalls=New-Object 'System.Collections.Generic.List[string]'
function Start-Process {param($FilePath,$WorkingDirectory,$WindowStyle) $script:LaunchCalls.Add('launch:'+ $FilePath)}
function Invoke-GamingAction {param($Action) $script:LaunchCalls.Add('mode:'+ $Action);[pscustomobject]@{Success=$false;Mode='GamingPartial'}}
$steam=$games | Where-Object Source -eq 'Steam' | Select-Object -First 1
$result=Start-GamingGame -GameId $steam.Id -EnterMode:$true
if(-not $result.Success -or $result.Status -ne 'LaunchRequestedWithWarnings' -or $script:LaunchCalls[0] -ne 'mode:Enter' -or $script:LaunchCalls[1] -ne ('launch:'+$steam.LaunchUri)){throw 'Gaming-before-launch ordering failed'}
$missing=Start-GamingGame -GameId 'steam-1;whoami'
if($missing.Success -or $script:LaunchCalls.Count -ne 2){throw 'Unknown ID was launched'}
$manualResult=Start-GamingGame -GameId $manual.Id
if(-not $manualResult.Success -or $script:LaunchCalls[-1] -ne ('launch:'+$exe)){throw 'Manual launch dispatch failed'}
$summary=Get-GamingPingSummary -Label test -Address 127.0.0.1 -Samples @(2,4,3) -Sent 4
if($summary.AverageMs -ne 3 -or $summary.JitterMs -ne 1.5 -or $summary.LossPercent -ne 25){throw 'Network summary failed'}
$history=@(1..21 | ForEach-Object {[pscustomobject]@{CheckedUtc=('test-'+$_);InterfaceAlias='Mock Wi-Fi';Internet=[pscustomobject]@{Address='1.1.1.1';AverageMs=10}}})
ConvertTo-Json -InputObject $history -Depth 5 | Set-Content -LiteralPath (Get-GamingNetworkHistoryPath)
function Get-GamingNetworkGateway {[pscustomobject]@{Address='192.168.0.1';InterfaceAlias='Mock Wi-Fi'}}
function Invoke-GamingPingPair {[pscustomobject]@{Gateway=[pscustomobject]@{Success=$true;RoundtripTime=3};Internet=[pscustomobject]@{Success=$true;RoundtripTime=20}}}
$network=Invoke-GamingNetworkTest -Samples 4
if(@(Get-GamingNetworkHistory).Count -ne 20 -or $network.InternetAverageChangeMs -ne 10 -or $network.Internet.LossPercent -ne 0){throw 'Network history or comparison failed'}
$other=Invoke-GamingNetworkTest -Samples 4 -InternetAddress '8.8.8.8'
if($null -ne $other.InternetAverageChangeMs -or $other.Internet.Address -ne '8.8.8.8'){throw 'Different probe endpoints must not be compared'}
[pscustomobject]@{Passed=$true;SteamGames=$games.Count;LiveGameLaunches=0;Root=$testRoot;Checks=@('Steam discovery','Utility exclusion','Manual duplicate handling','Mode-before-launch','Partial-mode launch','Unknown-ID rejection','Manual launch dispatch','Ping math','History cap')} | ConvertTo-Json -Depth 4
