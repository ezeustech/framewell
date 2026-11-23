$ErrorActionPreference='Stop'
$moduleRoot=Split-Path (Split-Path $PSCommandPath -Parent) -Parent
. (Join-Path $moduleRoot 'FrameBenchmark.ps1')
$testRoot=Join-Path (Split-Path $PSCommandPath -Parent) ('frames-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $testRoot 'state') -Force | Out-Null
$script:GamingFrameRoot=$testRoot
$rows=New-Object 'System.Collections.Generic.List[object]'
foreach($v in @((1..99 | ForEach-Object {10}),50,100)) {
    foreach($interval in @($v)){$rows.Add([pscustomobject]@{Application='game.exe';ProcessID=4242;SwapChainAddress='0xAAA';msBetweenPresents=$interval})}
}
foreach($v in @(0,-1,'NaN','Infinity','bad')){$rows.Add([pscustomobject]@{Application='game.exe';ProcessID=4242;SwapChainAddress='0xAAA';msBetweenPresents=$v})}
1..10 | ForEach-Object {$rows.Add([pscustomobject]@{Application='game.exe';ProcessID=4242;SwapChainAddress='0xBBB';msBetweenPresents=1})}
1..150 | ForEach-Object {$rows.Add([pscustomobject]@{Application='other.exe';ProcessID=9999;SwapChainAddress='0xCCC';msBetweenPresents=0.1})}
$csv=Join-Path $testRoot 'sample.csv'
$rows.ToArray() | Export-Csv -LiteralPath $csv -NoTypeInformation
$r=ConvertFrom-GamingFrameCsv -Path $csv -ProcessId 4242 -ProcessName game.exe
if(-not $r.Success -or $r.Samples -ne 101 -or $r.AverageFPS -ne 88.6 -or $r.OnePercentLowFPS -ne 13.33 -or $r.P95FrameTimeMs -ne 10 -or $r.SwapChain -ne '0xAAA'){throw 'Frame summary calculation or process/swapchain filtering failed'}
$none=ConvertFrom-GamingFrameCsv -Path $csv -ProcessId 12345
if($none.Success){throw 'Unrelated process rows were accepted'}
$short=Join-Path $testRoot 'short.csv'
$rows.ToArray() | Select-Object -First 5 | Export-Csv -LiteralPath $short -NoTypeInformation
if((ConvertFrom-GamingFrameCsv -Path $short -ProcessId 4242).Success){throw 'Insufficient data was accepted'}
$game=[pscustomobject]@{Source='Steam';InstallDirectory='D:\SteamLibrary\steamapps\common\Test'}
if(-not(Test-GamingFramePathForGame 'D:\SteamLibrary\steamapps\common\Test\bin\game.exe' $game)){throw 'Valid scoped game path rejected'}
if(Test-GamingFramePathForGame 'D:\SteamLibrary\steamapps\common\TestOther\game.exe' $game){throw 'Prefix collision accepted'}
$blocked=$false
try{$null=Get-GamingFrameStatePath (Join-Path $testRoot '..\outside.json')}catch{$blocked=$true}
if(-not $blocked){throw 'Escaping report path accepted'}
$script:LaunchCalled=$false
function Start-Process {$script:LaunchCalled=$true;throw 'Unexpected capture launch'}
function Get-GamingPresentMonInfo {[pscustomobject]@{Path='C:\Program Files\NVIDIA Corporation\FrameViewSDK\bin\PresentMon_x64.exe';Version='test'}}
function Get-RunningGamingProcesses {[pscustomobject]@{Pid=4242;Name='game.exe';Path='D:\Games\game.exe';CreationDateUtc='different';WorkingSetMB=100}}
$request=Join-Path $testRoot ('state\benchmark-'+[guid]::NewGuid().ToString('N')+'.request.json')
[pscustomobject]@{Version=1;GameId='steam-123';ProcessId=4242;CreationDateUtc='original';ExecutablePath='D:\Games\game.exe';Seconds=20}|ConvertTo-Json|Set-Content -LiteralPath $request
$blocked=$false
try{$null=Invoke-GamingFrameWorker -RequestFile $request}catch{$blocked=$true}
if(-not $blocked -or $script:LaunchCalled){throw 'Changed process identity was accepted'}
[pscustomobject]@{Passed=$true;Checks=@('Mean FPS','Ceiling 1% low','Nearest-rank P95','PID filter','Dominant swapchain','Invalid intervals','Insufficient samples','Game path boundary','Report path boundary','Process identity guard');ActualCaptures=0;Report=$r;TestRoot=$testRoot}|ConvertTo-Json -Depth 5
