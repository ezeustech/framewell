$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'GamingMode.ps1') -LibraryOnly
$testRoot=Join-Path $PSScriptRoot ('test-results\v2-core-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$script:GamingProfilesRoot=$testRoot;$script:GamingPerformanceRoot=$testRoot
$script:CheckCount=0
function Assert-V2($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:CheckCount++}
function Start-Process {throw 'Unexpected process launch in core test.'}
function Stop-Process {throw 'Unexpected process termination in core test.'}
function Stop-MediaStack {throw 'Unexpected media stop in core test.'}
function Start-MediaStack {throw 'Unexpected media start in core test.'}
function Get-OptionalAppSnapshot {return @()}
function Get-GMMediaDefinitions { @([pscustomobject]@{Key='JellyfinTray'},[pscustomobject]@{Key='Jellyfin'}) }
function Get-MediaStackSnapshot {[pscustomobject]@{SchemaVersion=1;Components=@();JellyfinTranscoders=@()}}

$defaults=@(Get-GamingProfiles)
Assert-V2 ('ChatGPT' -in ($defaults|Where-Object Id -eq 'media-stack').AppIds) 'ChatGPT must belong to Media stack.'
Assert-V2 ('ChatGPT' -notin ($defaults|Where-Object Id -eq 'super-performance').AppIds) 'ChatGPT must not be a separate performance toggle.'
$custom=Save-GamingProfile ([pscustomobject]@{Name='Empty test group';Description='Test';MediaKeys=@();AppIds=@();CustomExecutables=@()})
Assert-V2 ($custom.Id -match '^profile-[a-f0-9]{32}$') 'New profile ID should be generated safely.'
Assert-V2 (@(Get-GamingProfiles).Count -eq 3) 'Saved custom profile should preserve both built-ins.'
$result=Invoke-GamingProfile -ProfileId $custom.Id -Operation Start
Assert-V2 ($result.Success -and @($result.Results).Count -eq 0) 'Empty profile must not launch anything.'
$custom.MediaKeys=@('JellyfinTray');$custom=Save-GamingProfile $custom
Assert-V2 ('Jellyfin' -in $custom.MediaKeys) 'Tray/server dependency must be explicit.'
$bad=$false;try{Save-GamingProfile ([pscustomobject]@{Id='../../bad';Name='Bad';MediaKeys=@();AppIds=@();CustomExecutables=@()})|Out-Null}catch{$bad=$true}
Assert-V2 $bad 'Profile traversal must be rejected.'
Assert-V2 (-not(Test-GamingProfileExecutable 'C:\Windows\System32\notepad.exe' -AllowMissing)) 'Windows applications must be protected from custom close profiles.'
Assert-V2 (-not(Test-GamingProfileExecutable 'D:\Games\Steam.exe' -AllowMissing)) 'Steam must remain protected.'
Assert-V2 (-not(Test-GamingProfileExecutable 'D:\Games\Discord.exe' -AllowMissing)) 'Discord must remain protected.'
$dummy=Join-Path $testRoot 'ExampleGame.exe';[IO.File]::WriteAllText($dummy,'test-only marker; never launched')
$custom.CustomExecutables=@($dummy);$custom=Save-GamingProfile $custom
Remove-Item -LiteralPath $dummy
Assert-V2 (@((Get-GamingProfiles|Where-Object Id -eq $custom.Id).CustomExecutables).Count -eq 1) 'An app moving/uninstalling must not break profile loading.'
$preferences=Get-GamingPreferences;$preferences.Theme='OLED';$preferences.CloseBrowsers=$false;$preferences.PauseSearch=$false
$null=Set-GamingPreferences $preferences
Assert-V2 ((Get-GamingPreferences).Theme -eq 'OLED') 'OLED must persist.'
$selection=Get-GamingSessionTargets -Preferences $preferences -Apps @([pscustomobject]@{Id='Firefox'},[pscustomobject]@{Id='ChatGPT'},[pscustomobject]@{Id='Epic'}) -Media ([pscustomobject]@{Components=@([pscustomobject]@{Key='Jellyfin'})}) -Helpers ([pscustomobject]@{Services=@([pscustomobject]@{Name='WSearch'},[pscustomobject]@{Name='Spooler'});ISLC=@()})
Assert-V2 ('Firefox' -notin $selection.Apps.Id -and 'ChatGPT' -in $selection.Apps.Id -and 'Epic' -in $selection.Apps.Id) 'Category exclusions and Media stack app membership must both apply.'
Assert-V2 ('WSearch' -notin $selection.Helpers.Services.Name -and 'Spooler' -in $selection.Helpers.Services.Name) 'Service selection must preserve independent controls.'

# Mock the native API in this isolated test process; no Windows setting is written.
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class GamingExtraNative {
 public static Dictionary<uint,bool> Values=new Dictionary<uint,bool>();
 public static int[] Mouse=new int[]{6,10,1};
 public static bool Read(uint id){return Values.ContainsKey(id)?Values[id]:true;}
 public static void Write(uint id,bool value){Values[id-1]=value;}
 public static int[] ReadMouse(){return (int[])Mouse.Clone();}
 public static void WriteMouse(int[] value){Mouse=(int[])value.Clone();}
}
'@
$extra=[pscustomobject]@{Version=1;Settings=@([pscustomobject]@{Id='Menu';Before=$true});Mouse=@(6,10,1);Sleep=$null}
$apply=Invoke-GamingExtras $extra Apply
Assert-V2 ($apply.Success -and -not [GamingExtraNative]::Read(0x1002) -and ([GamingExtraNative]::ReadMouse() -join ',') -eq '0,0,0') 'Extra settings must apply only selected API values.'
$restore=Invoke-GamingExtras $extra Restore
Assert-V2 ($restore.Success -and [GamingExtraNative]::Read(0x1002) -and ([GamingExtraNative]::ReadMouse() -join ',') -eq '6,10,1') 'Extra settings must restore exact pointer thresholds and animations.'
$extra.Settings=@([pscustomobject]@{Id='Cursor';Before=$false})
[GamingExtraNative]::Values[0x101A]=$true;[GamingExtraNative]::Mouse=@(2,4,1)
$restore=Invoke-GamingExtras $extra Restore
Assert-V2 (@($restore.Results|Where-Object Status -eq 'KeptUserChange').Count -eq 2) 'Later manual pointer and shadow changes must be retained.'
$bad=$false;try{Invoke-GamingExtras ([pscustomobject]@{Version=1;Settings=@([pscustomobject]@{Id='Unknown';Before=$true});Mouse=$null;Sleep=$null}) Apply|Out-Null}catch{$bad=$true}
Assert-V2 $bad 'Unknown native action IDs must be rejected.'

$now=[datetime]::UtcNow
$epic='C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe'
$overlay='C:\Program Files (x86)\Epic Games\Epic Online Services\managedArtifacts\123abc\EOSOverlayRenderer-Win64-Shipping.exe'
$processes=@(
 [pscustomobject]@{Name='EpicGamesLauncher.exe';ExecutablePath=$epic;ProcessId=100;ParentProcessId=1;CreationDate=$now},
 [pscustomobject]@{Name='EOSOverlayRenderer-Win64-Shipping.exe';ExecutablePath=$overlay;ProcessId=101;ParentProcessId=100;CreationDate=$now.AddSeconds(1)},
 [pscustomobject]@{Name='EOSOverlayRenderer-Win64-Shipping.exe';ExecutablePath=$overlay;ProcessId=102;ParentProcessId=101;CreationDate=$now.AddSeconds(2)},
 [pscustomobject]@{Name='Game.exe';ExecutablePath='D:\Games\Game.exe';ProcessId=200;ParentProcessId=1;CreationDate=$now},
 [pscustomobject]@{Name='EOSOverlayRenderer-Win64-Shipping.exe';ExecutablePath=$overlay;ProcessId=201;ParentProcessId=200;CreationDate=$now.AddSeconds(1)},
 [pscustomobject]@{Name='EOSOverlayRenderer-Win64-Shipping.exe';ExecutablePath=$overlay;ProcessId=301;ParentProcessId=100;CreationDate=$now.AddSeconds(-5)}
)
$owned=@(Get-OmEpicLauncherOverlays $processes|ForEach-Object ProcessId)
Assert-V2 (($owned -join ',') -eq '101,102') 'Only verified launcher-descended overlays may close; game-owned and reused-parent processes must survive.'
$receipt=[pscustomobject]@{Passed=$true;Checks=$script:CheckCount;LiveSettingsChanged=$false;LiveApplicationsStopped=$false;Directory=$testRoot}
$receipt|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $testRoot 'receipt.json') -Encoding UTF8
$receipt|ConvertTo-Json
