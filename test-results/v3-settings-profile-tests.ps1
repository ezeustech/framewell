$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'GamingMode.ps1') -LibraryOnly
$fixture=Join-Path $PSScriptRoot ('v3-settings-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'state'))
$script:GamingSettingsProfilesRoot=$fixture;$script:GamingPerformanceRoot=$fixture;$script:GamingProfilesRoot=$fixture;$script:GamingSystemRoot=$fixture;$script:GamingNetworkRoot=$fixture
function Get-GMMediaDefinitions {return @()}
function Start-Process {throw 'No process launches permitted in profile tests.'}
function Stop-Process {throw 'No process stops permitted in profile tests.'}
function Invoke-GamingAction {throw 'No mode activation permitted in profile tests.'}
function Get-GamingCpuTopology {[pscustomobject]@{SupportsAffinity=$true;LogicalProcessorCount=16}}
$checks=New-Object 'System.Collections.Generic.List[string]'
function Check($Condition,[string]$Message){if(-not $Condition){throw $Message};$checks.Add($Message)}
function Reject([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Check $rejected $Message}
Check (@((Get-GamingDefaultProfiles|Where-Object Id -eq 'media-stack').AppIds).Count -eq 0) 'New users receive no personal media app selection'
Check (@(Get-OmCatalog).Count -eq 36) 'Expanded optional application catalog'
Check (@(Get-GamingOptimizerFeatures).Count -eq 129) 'Full companion catalog is flattened for UI'
$prefs=Get-GamingPreferences;$prefs.Theme='DIO';$null=Set-GamingPreferences $prefs
$appearance=Save-GamingSettingsProfile -Name 'Golden hour' -Scope Appearance
Check ($appearance.Id -match '^settings-[a-f0-9]{32}$') 'Settings profile gets safe independent ID'
$prefs.Theme='OLED';$null=Set-GamingPreferences $prefs
$applied=Apply-GamingSettingsProfile $appearance.Id
Check ($applied.Success -and (Get-GamingPreferences).Theme -eq 'DIO') 'Theme profile applies without hardware actions'
$null=Save-GamingProcessPreference -GameId 'manual-demo' -Priority AboveNormal -LogicalProcessors @(0,2) -ApplyOnLaunch $true
$null=Save-GamingMemoryPreferences -StandbyThresholdMB 2048 -AvailableThresholdMB 1024 -IntervalSeconds 45 -TimerMilliseconds 1
$null=Save-GamingNetworkServer -Name 'Local test only' -HostName '127.0.0.1' -Protocol TCP -Port 443
$null=Save-GamingNetworkPreferences -Preferences ([pscustomobject]@{Version=1;InternetAddress='127.0.0.1';Protocol='TCP';Port=443;Samples=4;TargetName='Fixture';GameId=''})
$null=Save-GamingProfile ([pscustomobject]@{Name='Quiet work';Description='';AppIds=@('Brave','OBS');MediaKeys=@();CustomExecutables=@()})
$all=Save-GamingSettingsProfile -Name 'Whole app' -Scope All
Check (@($all.Files.PSObject.Properties).Count -eq 5) 'Whole-app scope captures configured CPU memory network and app profiles'
$export=Join-Path $fixture 'profile.json';$null=Export-GamingSettingsProfile $all.Id $export
$import=Import-GamingSettingsProfile $export
Check ($import.Id -ne $all.Id -and $import.Name -eq $all.Name) 'Import is separate and does not overwrite original profile'
Check ((Apply-GamingSettingsProfile $import.Id).Success) 'Imported whole-app profile applies validated data only'
Check ((Get-GamingProcessPreference 'manual-demo').Priority -eq 'AboveNormal') 'CPU settings survive export/import'
Check ((Get-GamingMemoryPreferences).IntervalSeconds -eq 45) 'Memory settings survive export/import'
Check (@(Read-GamingNetworkServers).Count -eq 1) 'Server settings survive export/import'
$bad=$all|ConvertTo-Json -Depth 30|ConvertFrom-Json
$bad.Files|Add-Member -NotePropertyName '..\malicious.json' -NotePropertyValue ([pscustomobject]@{Version=1})
Reject {ConvertTo-GamingSettingsProfile $bad} 'File traversal rejected before writes'
$bad=$all|ConvertTo-Json -Depth 30|ConvertFrom-Json;$bad.Files.'game-process-preferences.json'.Games[0].Priority='RealTime'
Reject {ConvertTo-GamingSettingsProfile $bad} 'Invalid CPU payload rejected before writes'
$bad=$all|ConvertTo-Json -Depth 30|ConvertFrom-Json;$bad.Files.'memory-preferences.json'.IntervalSeconds=1
Reject {ConvertTo-GamingSettingsProfile $bad} 'Unbounded memory monitor interval rejected'
$bad=$all|ConvertTo-Json -Depth 30|ConvertFrom-Json;$bad.Files.'network-servers.json'.Servers[0].HostName='example.com;calc.exe'
Reject {ConvertTo-GamingSettingsProfile $bad} 'Command-shaped network address rejected'
Reject {Test-GamingPortableConfiguration 'games.json' ([pscustomobject]@{Version=1;Games=@([pscustomobject]@{Id=('manual-'+[guid]::NewGuid().ToString('N'));Name='Bad';Source='Manual';ExecutablePath='C:\Windows\System32\cmd.exe';LaunchUri=''})})} 'Executable profiles reject system script hosts'
$null=Remove-GamingSettingsProfile $appearance.Id
Check (-not @(Get-GamingSettingsProfiles|Where-Object Id -eq $appearance.Id).Count) 'Delete removes only selected saved profile'
Check ((Get-GamingPreferences).Theme -eq 'DIO') 'Deleting profile does not alter active preferences'
$report=[pscustomobject]@{Passed=$checks.Count;Checks=$checks;MachineMutations=$false;Fixture=$fixture}
$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'v3-settings-profile-results.json') -Encoding UTF8
$report|ConvertTo-Json -Depth 5
