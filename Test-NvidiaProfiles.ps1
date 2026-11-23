# Pure transaction tests. This process installs a FAKE GamingNvidia.Session before
# importing the backend. It never loads nvapi64.dll, starts UAC or writes settings.
$ErrorActionPreference='Stop'
if('GamingNvidia.Session' -as [type]){throw 'Run these tests in a fresh PowerShell process; a driver type is already loaded.'}
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
namespace GamingNvidia {
 public class SettingState {public uint Id,Value,Type,Location,IsCurrentPredefined,IsPredefinedValid;public bool Found=true; public SettingState Copy(){return (SettingState)MemberwiseClone();}}
 public class App {public string Name="game.exe",CommandLine="";public uint Flags;}
 public class Profile {public bool Found=true,IsBase=false;public string Name="Test game";public App[] Applications;}
 public class Session : IDisposable {
  public static Dictionary<uint,SettingState> Saved=new Dictionary<uint,SettingState>();
  public static bool Shared,FailSave,Exists=true,JournalReady;public static int Saves,Reads;public static string ProfileName="Test game";public static uint? GlobalPower;
  public static List<string> Trace=new List<string>();
  Dictionary<uint,SettingState> local=new Dictionary<uint,SettingState>();bool exists;string name;
  public Session(){foreach(var x in Saved)local[x.Key]=x.Value.Copy();exists=Exists;name=ProfileName;}
  public string Driver {get{return "FAKE - NO HARDWARE";}}
  public uint[] AvailableIds(){return new uint[]{0x1057EB71,0x00CE2691,0x00E73211,0x002ECAF2,0x0019BB68,0x00A879CF,0x0064B541,0x10835002,0x0005F543,0x10835000,0x007BA09E};}
  public Profile Inspect(string p){return new Profile {Found=exists,Name=name,Applications=exists?(Shared?new[]{new App(),new App()}:new[]{new App()}):new App[0]};}
  public SettingState Read(string p,uint id){Reads++;return local.ContainsKey(id)?local[id].Copy():new SettingState{Id=id,Value=(id==0x1057EB71&&GlobalPower.HasValue)?GlobalPower.Value:0,Location=(id==0x1057EB71&&GlobalPower.HasValue)?(exists?1u:0u):3};}
  public void Write(string p,string n,uint id,uint value){if(!JournalReady)throw new Exception("Write before journal");Trace.Add("Write");local[id]=new SettingState{Id=id,Value=value,Location=0};}
  public void RemoveOverride(string p,string n,uint id){local.Remove(id);}
  public string CreateForExecutable(string p,string n){exists=true;name=n;return n;}
  public void DeleteOwned(string p,string n){if(local.Count!=0)throw new Exception("contains other settings");exists=false;name="";}
  public void Save(){if(FailSave)throw new Exception("Simulated save failure");Saved=new Dictionary<uint,SettingState>();foreach(var x in local)Saved[x.Key]=x.Value.Copy();Exists=exists;ProfileName=name;Saves++;}
  public void Dispose(){}
  public static void Reset(){Saved.Clear();Shared=false;FailSave=false;Exists=true;ProfileName="Test game";Saves=0;Reads=0;GlobalPower=null;JournalReady=false;Trace.Clear();Saved[0x1057EB71]=new SettingState{Id=0x1057EB71,Value=2,Location=0};}
 }
}
'@
. (Join-Path $PSScriptRoot 'NvidiaProfiles.ps1')
# Replace persistence and file existence checks with in-memory values.
$script:FakeJournal=$null
function Get-GamingNvidiaExecutable {param([string]$ExecutablePath,[switch]$AllowMissing) return 'D:\Fake\game.exe'}
function Read-GamingNvidiaJournal {param([string]$ExecutablePath) if($script:FakeJournal){return $script:FakeJournal | ConvertTo-Json -Depth 15 | ConvertFrom-Json};return $null}
function Save-GamingNvidiaJournal {param($Journal) $script:FakeJournal=$Journal | ConvertTo-Json -Depth 15 | ConvertFrom-Json;[GamingNvidia.Session]::JournalReady=$true;[GamingNvidia.Session]::Trace.Add('Journal')}
$script:Assertions=0
function Assert-True($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:Assertions++}
function Assert-Throws([scriptblock]$Code,[string]$Message){$thrown=$false;try{& $Code | Out-Null}catch{$thrown=$true};Assert-True $thrown $Message}
function Reset-Fake { [GamingNvidia.Session]::Reset();$script:FakeJournal=$null }
function Read-Fake([uint32]$Id){$s=New-Object GamingNvidia.Session;try{return $s.Read('D:\Fake\game.exe',$Id)}finally{$s.Dispose()}}

Assert-True (@(Get-GamingNvidiaSettingsCatalog).Count -eq 9) 'Catalog missing settings'
Assert-True (@(ConvertTo-GamingNvidiaPlan Quality | Where-Object {$_.Value -eq [uint32]4294967286}).Count -eq 1) 'High quality DWORD lost unsigned bits'
Assert-True (@(ConvertTo-GamingNvidiaPlan Performance).Count -eq 8 -and @(ConvertTo-GamingNvidiaPlan Quality).Count -eq 8) 'Preset does not set all supported controls'
Assert-True (@(ConvertTo-GamingNvidiaPlan Performance | Where-Object {$_.Key -eq 'TextureQuality'})[0].Value -eq 20) 'Performance preset does not use high performance texture filtering'
Assert-True (@(ConvertTo-GamingNvidiaPlan Performance | Where-Object {$_.Key -eq 'LowLatency'}).Count -eq 0) 'Preset changed unsupported low latency mode'
foreach($cap in @(0,20,277,1000)){Assert-True (@(ConvertTo-GamingNvidiaPlan Custom @{MaxFrameRate=$cap})[0].Value -eq $cap) 'Valid cap rejected'}
foreach($cap in @(-1,19,1001,'NaN','0; whoami')){Assert-Throws {ConvertTo-GamingNvidiaPlan Custom @{MaxFrameRate=$cap}} 'Invalid cap accepted'}
Assert-Throws {ConvertTo-GamingNvidiaPlan Custom @{GlobalProfile='Anything'}} 'Unknown setting accepted'
Assert-Throws {ConvertTo-GamingNvidiaPlan Custom @{PowerMode='Overclock'}} 'Unknown choice accepted'
Assert-Throws {ConvertTo-GamingNvidiaPlan Custom @{}} 'Empty custom plan accepted'

Reset-Fake
$first=Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Performance
Assert-True $first.Success 'Initial performance apply failed'
Assert-True ([GamingNvidia.Session]::Trace[0] -eq 'Journal') 'Journal was not saved before driver mutation'
Assert-True ((Read-Fake 0x1057EB71).Value -eq 1) 'Power value not applied in fake driver'
Assert-True (($script:FakeJournal.Original | Where-Object Id -eq 0x1057EB71).Before.Value -eq 2) 'Original local value not retained'
$second=Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Quality
Assert-True $second.Success 'Repeated preset failed'
Assert-True (@($script:FakeJournal.Original).Count -eq 8) 'Repeated preset replaced or duplicated original snapshot'
$restore=Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Restore
Assert-True $restore.Success 'Restore failed'
Assert-True ((Read-Fake 0x1057EB71).Value -eq 2 -and (Read-Fake 0x1057EB71).Location -eq 0) 'Original explicit value was not restored'
Assert-True ((Read-Fake 0x00CE2691).Location -eq 3) 'Inherited setting became a permanent override'
Assert-True (-not $script:FakeJournal.Active) 'Restore journal remained active'

Reset-Fake;[GamingNvidia.Session]::Shared=$true
Assert-Throws {Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Performance} 'Shared profile accepted'
Assert-True ([GamingNvidia.Session]::Saves -eq 0 -and -not $script:FakeJournal) 'Shared profile was touched'

Reset-Fake;[void](Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Performance)
$manual=New-Object GamingNvidia.Session;$manual.Write('D:\Fake\game.exe','Test game',0x1057EB71,5);$manual.Save();$manual.Dispose()
$restore=Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Restore
Assert-True ($restore.Success -and (Read-Fake 0x1057EB71).Value -eq 5) 'Later manual change was overwritten'

Reset-Fake;[void](Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Performance)
[GamingNvidia.Session]::FailSave=$true
Assert-Throws {Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Quality} 'Save failure was hidden'
Assert-True ($script:FakeJournal.Active -and $script:FakeJournal.Phase -eq 'Prepared') 'Interrupted transaction lost restore state'
[GamingNvidia.Session]::FailSave=$false
$restore=Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Restore
Assert-True ($restore.Success -and (Read-Fake 0x00CE2691).Location -eq 3) 'Failed reapply prevented original restoration'

Reset-Fake;[GamingNvidia.Session]::Saved.Clear();[GamingNvidia.Session]::GlobalPower=1
[void](Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Performance)
[GamingNvidia.Session]::GlobalPower=2
$restore=Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Restore
Assert-True ($restore.Success -and (Read-Fake 0x1057EB71).Location -eq 1 -and (Read-Fake 0x1057EB71).Value -eq 2) 'Later global preference was overwritten or mistaken for failed restoration'

Reset-Fake;[GamingNvidia.Session]::Exists=$false;[GamingNvidia.Session]::Saved.Clear()
[GamingNvidia.Session]::GlobalPower=1
[void](Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Performance)
Assert-True ($script:FakeJournal.CreatedProfile -and [GamingNvidia.Session]::Exists) 'New executable profile not created'
$restore=Invoke-GamingNvidiaTransaction 'D:\Fake\game.exe' Restore
Assert-True ($restore.Success -and -not [GamingNvidia.Session]::Exists) 'Owned profile association not removed on restore'
Assert-True ((Read-Fake 0x1057EB71).Value -eq 1 -and (Read-Fake 0x1057EB71).Location -eq 0) 'Created-profile restore accidentally changed a global original value'

Reset-Fake
function Get-GamingNvidiaStatePath {param([string]$Name,[switch]$Create) return ('D:\Fake\'+$Name)}
function Set-Content {param($LiteralPath,$Encoding,[Parameter(ValueFromPipeline=$true)]$Value) process {}}
function Start-Process {[CmdletBinding()]param($FilePath,$ArgumentList,$Verb,$WindowStyle,[switch]$PassThru) throw (New-Object ComponentModel.Win32Exception(1223))}
$cancel=Invoke-GamingNvidiaProfile -ExecutablePath 'D:\Fake\game.exe' -Preset Performance
Assert-True (-not $cancel.Success -and $cancel.Status -eq 'Skipped') 'UAC cancellation reported success'
Assert-True ([GamingNvidia.Session]::Saves -eq 0 -and -not $script:FakeJournal) 'Cancellation changed the fake driver'
[pscustomobject]@{Success=$true;Assertions=$script:Assertions;Driver='FAKE';LiveDriverWrites=0;UACPrompts=0} | ConvertTo-Json
