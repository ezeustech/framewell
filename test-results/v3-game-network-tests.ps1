$ErrorActionPreference='Stop'
$moduleRoot=Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $moduleRoot 'GameLibrary.ps1')
. (Join-Path $moduleRoot 'NetworkDiagnostics.ps1')
$testRoot=Join-Path (Split-Path $PSCommandPath -Parent) ('v3-network-discovery-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$script:GamingGameLibraryRoot=$testRoot;$script:GamingNetworkRoot=$testRoot
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-V3([bool]$Value,[string]$Message){if(-not $Value){throw ('FAILED: '+$Message)};$checks.Add($Message)}
function New-Exe([string]$Relative){$path=Join-Path $testRoot $Relative;$null=New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force;Copy-Item -LiteralPath (Join-Path $moduleRoot 'GamingMode.exe') -Destination $path;return $path}
$root=Join-Path $testRoot 'Portable'
$a=New-Exe 'Portable\Alpha.exe';$b=New-Exe 'Portable\Beta.exe';$nested=New-Exe 'Portable\Nested Game\NestedGame.exe';$engine=New-Exe 'Portable\EngineGame\Binaries\Win64\EngineGame-Win64-Shipping.exe'
$crash=New-Exe 'Portable\CrashReportClient.exe';$uninstall=New-Exe 'Portable\Nested Game\unins000.exe'
function Get-GamingSteamLibraries {return @()}
function Get-GamingEpicInstalledGames {return @()}
function Get-GamingRegistryInstalledGames {return @()}
function Get-GamingXboxInstalledGames {return @()}
function Get-GamingScanFolders {return @($root)}
$scan=Invoke-GamingGameScan;$library=@(Get-GameLibrary)
Assert-V3 ($scan.Success -and $scan.Count -eq 4) 'Multiple direct EXEs and nested games coexist'
Assert-V3 (@($library | Where-Object LaunchExecutablePath -eq $nested).Count -eq 1) 'Root EXE no longer hides a nested game'
Assert-V3 (@($library | Where-Object {$_.LaunchExecutablePath -in @($a,$b)}).Count -eq 2) 'Two distinct EXEs in one folder survive cache deduplication'
Assert-V3 (($library | Where-Object LaunchExecutablePath -eq $engine).InstallDirectory -eq (Join-Path $root 'EngineGame')) 'Engine Binaries folder grouped under game root'
Assert-V3 (@($library | Where-Object {$_.LaunchExecutablePath -in @($crash,$uninstall)}).Count -eq 0) 'Crash and uninstall helpers excluded'
$report=Get-GamingScanReport
Assert-V3 ($report.Folders.Count -eq 1 -and $report.CandidateCount -eq 4) 'Scan report records inspected folders and candidate count'
$blocked=$false;try{Add-GamingScanFolder -Path ([IO.Path]::GetPathRoot($testRoot))}catch{$blocked=$true}
Assert-V3 $blocked 'Whole-drive recursive root cannot be configured'
$deep=New-Exe 'Portable\One\Two\Three\Four\Five\Deep.exe'
$bounded=@(Get-GamingBoundedExecutables $root -MaxDepth 1)
Assert-V3 (@($bounded | Where-Object FullName -eq $deep).Count -eq 0) 'Directory depth bound still enforced'
$script:CpuOn=$false;$script:CpuThrow=$false;$script:CpuCalls=0;$script:LaunchCount=0
function Start-Process {param($FilePath,$WorkingDirectory,$WindowStyle,$ErrorAction) $script:LaunchCount++}
function Get-GamingProcessPreference {param($GameId) return [pscustomobject]@{ApplyOnLaunch=$script:CpuOn}}
function Invoke-GamingLaunchProcessTuning {param($GameId,$WaitSeconds) $script:CpuCalls++;if($script:CpuThrow){throw 'Fixture denied CPU control'};return [pscustomobject]@{Success=$true;Applied=$true;Message='Applied fixture'} }
$launched=Start-GamingGame -GameId $library[0].Id
Assert-V3 ($launched.Success -and $CpuCalls -eq 0 -and $null -eq $launched.CpuResult) 'CPU launch hook does not wait or run when preference is off'
$script:CpuOn=$true;$launched=Start-GamingGame -GameId $library[0].Id
Assert-V3 ($launched.Success -and $CpuCalls -eq 1 -and $launched.CpuResult.Success) 'Opt-in CPU launch hook runs after the game launch request (mock only)'
$script:CpuThrow=$true;$launched=Start-GamingGame -GameId $library[0].Id
Assert-V3 ($launched.Success -and -not $launched.CpuResult.Success -and $launched.Status -eq 'LaunchRequestedWithWarnings') 'CPU access failure preserves successful game launch with a useful warning'

$script:MockGames=@([pscustomobject]@{Id='epic-fortnite';Name='Fortnite';ExecutablePath=$a;IsLauncher=$false},[pscustomobject]@{Id='manual-other';Name='Other Game';ExecutablePath=$b;IsLauncher=$false})
function Get-GameLibrary {return $script:MockGames}
foreach($bad in @('https://example.com','example.com:443','host;whoami','host$(whoami)','host/path','a b','-option')){
    $rejected=$false;try{$null=ConvertTo-GamingNetworkHost $bad}catch{$rejected=$true};Assert-V3 $rejected ('Reject unsafe or malformed host: '+$bad)
}
Assert-V3 ((ConvertTo-GamingNetworkHost 'EXAMPLE.COM.') -eq 'example.com' -and (ConvertTo-GamingNetworkHost '2001:db8::1') -eq '2001:db8::1') 'DNS and IPv6 canonicalized without command execution'
$saved=Save-GamingNetworkServer -Name 'Local match server' -HostName '127.0.0.1' -Protocol TCP -Port 27015 -GameId 'manual-other'
Assert-V3 ((Test-GamingNetworkServerData $saved) -and @(Read-GamingNetworkServers).Count -eq 1) 'Custom game server validates and persists'
$updated=Save-GamingNetworkServer -Id $saved.Id -Name 'Updated server' -HostName 'example.com' -Protocol ICMP -GameId 'manual-other'
Assert-V3 (@(Read-GamingNetworkServers).Count -eq 1 -and $updated.Port -eq 0) 'Updating a saved endpoint retains identity and normalizes ICMP port'
$servers=@(Get-GamingNetworkServers -GameId 'epic-fortnite')
Assert-V3 (@($servers | Where-Object Source -eq 'Epic published endpoint').Count -eq 16) 'Fortnite exposes 16 verified Epic diagnostic endpoints'
Assert-V3 (@($servers | Where-Object Id -eq $saved.Id).Count -eq 0) 'Game-specific endpoint list excludes another game'
$others=@(Get-GamingNetworkServers -GameId 'manual-other')
Assert-V3 (@($others | Where-Object Source -eq 'Epic published endpoint').Count -eq 0 -and -not (Get-GamingNetworkGameGuidance 'manual-other').SupportsPublishedEndpoints) 'Unknown games receive guidance rather than invented server IPs'
Remove-GamingNetworkServer -Id $saved.Id | Out-Null
Assert-V3 (@(Read-GamingNetworkServers).Count -eq 0) 'Remove operates only on saved entry'
$invalid=[pscustomobject]@{InternetAddress='example.com';Protocol='UDP';Port=443;Samples=12;TargetName='';GameId=''}
Assert-V3 (-not(Test-GamingNetworkPreferences $invalid)) 'Unsupported probe protocol rejected'

function Get-GamingNetworkGateway {[pscustomobject]@{Address='192.0.2.1';InterfaceAlias='Fixture adapter'}}
function Resolve-GamingNetworkAddress {param($HostName) return '192.0.2.10'}
$script:ProbeCalls=New-Object 'System.Collections.Generic.List[object]'
function Invoke-GamingPingPair {param($GatewayAddress,$InternetAddress,$Protocol,$Port) $script:ProbeCalls.Add([pscustomobject]@{Address=$InternetAddress;Protocol=$Protocol;Port=$Port});return [pscustomobject]@{Gateway=[pscustomobject]@{Success=$true;RoundtripTime=2};Internet=[pscustomobject]@{Success=$true;RoundtripTime=15}}}
$first=Invoke-GamingNetworkTest -Samples 4 -InternetAddress 'game.example' -Protocol TCP -Port 7777 -TargetName 'My game server' -GameId 'manual-other'
Assert-V3 ($first.Target.AverageMs -eq 15 -and $first.Protocol -eq 'TCP' -and $first.Target.FailureLabel -match 'not packet loss' -and $first.Measurement -match 'not gameplay RTT') 'TCP results identify handshake latency and connection failures honestly'
Assert-V3 ($ProbeCalls.Count -eq 4 -and $ProbeCalls[0].Address -eq '192.0.2.10' -and $ProbeCalls[0].Port -eq 7777) 'Chosen server and port dispatched, DNS resolved once'
$second=Invoke-GamingNetworkTest -Samples 4 -InternetAddress 'game.example' -Protocol TCP -Port 7778
Assert-V3 ($null -eq $second.InternetAverageChangeMs) 'Different TCP ports are not compared'
$third=Invoke-GamingNetworkTest -Samples 4 -InternetAddress 'game.example' -Protocol ICMP
Assert-V3 ($null -eq $third.InternetAverageChangeMs) 'TCP and ICMP measurements are not compared'
$fourth=Invoke-GamingNetworkTest -Samples 4 -InternetAddress 'game.example' -Protocol ICMP
Assert-V3 ($fourth.InternetAverageChangeMs -eq 0) 'Matching endpoint and protocol can be compared'
Assert-V3 ((Get-GamingNetworkPreferences).InternetAddress -eq 'game.example') 'Last test configuration saved for tab profiles'

function Get-CimInstance {param($ClassName,$ErrorAction) return @([pscustomobject]@{ProcessId=101;ExecutablePath=$a},[pscustomobject]@{ProcessId=102;ExecutablePath=$b})}
function Get-NetTCPConnection {param($OwningProcess,$State,$ErrorAction) if($OwningProcess -ne 101){throw 'An unrelated process was inspected.'};return @([pscustomobject]@{RemoteAddress='203.0.113.25';RemotePort=443},[pscustomobject]@{RemoteAddress='127.0.0.1';RemotePort=9000},[pscustomobject]@{RemoteAddress='203.0.113.25';RemotePort=443})}
$active=@(Get-GamingActiveGameEndpoints -GameId 'epic-fortnite')
Assert-V3 ($active.Count -eq 1 -and $active[0].HostName -eq '203.0.113.25' -and $active[0].Notes -match 'not a match server') 'Active endpoint discovery is exact-EXE scoped, deduplicated and excludes loopback'
Initialize-GamingNetworkNative
Assert-V3 ([bool]('GamingNetworkProbe' -as [type])) 'Native async TCP timing helper compiles on Windows PowerShell 5.1'
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
try {
    $listener.Start();$localPort=([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $probe=[GamingNetworkProbe]::Tcp('127.0.0.1',$localPort,500)
    if(-not $probe.Wait(1500)){throw 'Local TCP probe did not complete.'}
    Assert-V3 ($probe.Result.Success -and $probe.Result.RoundtripTime -ge 0 -and $probe.Result.RoundtripTime -lt 500) 'Native TCP timing succeeds against an ephemeral loopback listener'
} finally {$listener.Stop()}
$closedProbe=[GamingNetworkProbe]::Tcp('127.0.0.1',$localPort,500)
if(-not $closedProbe.Wait(1500)){throw 'Closed-port TCP probe did not complete.'}
Assert-V3 (-not $closedProbe.Result.Success) 'Closed TCP port is a failed connection, not zero latency'
[pscustomobject]@{Passed=$true;Checks=$checks.ToArray();ExternalProbes=0;GameLaunches=0;Root=$testRoot} | ConvertTo-Json -Depth 5
