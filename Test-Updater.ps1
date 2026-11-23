[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
[void][Reflection.Assembly]::LoadFrom((Join-Path $PSScriptRoot 'GamingMode.exe'))
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$fixture=Join-Path $env:TEMP ('framewell-update-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Update([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name)}
function Reject-Update([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert-Update $failed $Name}
function Write-Fixture([string]$Root,[string]$Name,[string]$Text){$p=Join-Path $Root $Name;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($p));[IO.File]::WriteAllText($p,$Text)}
Assert-Update ([Framewell.Updates]::ParseVersion('v3.2.0') -gt [Framewell.Updates]::ParseVersion('3.1.1-rc1')) 'Release versions compare numerically'
foreach($p in @('../escape','C:\escape','file:stream','state/preferences.json','app/STATE/p.json','app/backups/a','folder./x','folder /x','/absolute')){
 Reject-Update {[Framewell.Updates]::SafePath($fixture,$p)} ('Unsafe path rejected: '+$p)
}
$package=Join-Path $fixture 'source'
foreach($pair in @(@('app/GamingMode.exe','new-exe'),@('app/GamingMode.ps1','new-script'),@('app/nested/new.txt','new-file'),@('Framewell.exe','new-bootstrap'),@('Framewell.exe.config','new-config'),@('START HERE.txt','instructions'))){Write-Fixture $package $pair[0] $pair[1]}
$manifest=@{Version='3.2.0';Files=@('GamingMode.exe','GamingMode.ps1','nested/new.txt','runtime-files.json')}|ConvertTo-Json
Write-Fixture $package 'app/runtime-files.json' $manifest
$archive=Join-Path $fixture 'package.zip';[IO.Compression.ZipFile]::CreateFromDirectory($package,$archive)
$stage=Join-Path $fixture 'stage';[Framewell.Updates]::ExtractPackage($archive,$stage)
[Framewell.Updates]::ValidateManifest($stage,'3.2.0');Assert-Update $true 'Complete portable package accepted'
Reject-Update {[Framewell.Updates]::ValidateManifest($stage,'3.3.0')} 'Release and manifest version mismatch rejected'
Reject-Update {[Framewell.Updates]::VerifyHash($archive,('0'*64))} 'Checksum mismatch rejected'
$checksum=[Framewell.Updates]::Hash($archive);[Framewell.Updates]::VerifyHash($archive,$checksum)
Assert-Update $true 'Matching checksum accepted'
foreach($case in @('traversal','duplicate','protected','incomplete')){
 $bad=Join-Path $fixture ($case+'.zip');$zip=[IO.Compression.ZipFile]::Open($bad,'Create')
 try{
  $names=switch($case){'traversal'{@('../escape.txt')};'duplicate'{@('same.txt','SAME.txt')};'protected'{@('app/state/preferences.json')};'incomplete'{@('Framewell.exe')}}
  foreach($name in $names){$entry=$zip.CreateEntry($name);$writer=New-Object IO.StreamWriter($entry.Open());try{$writer.Write('fixture')}finally{$writer.Dispose()}}
 }finally{$zip.Dispose()}
 Reject-Update {[Framewell.Updates]::ExtractPackage($bad,(Join-Path $fixture ('bad-'+$case)))} ($case+' ZIP rejected')
}
$files=[ordered]@{};foreach($name in @('GamingMode.exe','GamingMode.ps1','nested/new.txt','runtime-files.json')){$files[$name]=[Framewell.Updates]::Hash((Join-Path $stage ('app/'+$name)))}
function New-TestPlan([string]$Name,[switch]$Portable){
 $base=Join-Path $fixture $Name;$runtime=if($Portable){Join-Path $base 'app'}else{$base}
 Write-Fixture $runtime 'GamingMode.exe' 'old-exe';Write-Fixture $runtime 'GamingMode.ps1' 'old-script';Write-Fixture $runtime 'runtime-files.json' 'old-manifest'
 Write-Fixture $runtime 'state/preferences.json' 'personal-profile';Write-Fixture $runtime 'backups/prior.txt' 'restore-data'
 if($Portable){Write-Fixture $base 'Framewell.exe' 'old-bootstrap'}
 $plan=@{RuntimeRoot=$runtime;StageRoot=$stage;Version='3.2.0';Archive=$archive;PackageHash=$checksum;Files=$files}
 $planPath=Join-Path $fixture ($Name+'-plan.json');$plan|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $planPath -Encoding UTF8
 [pscustomobject]@{Root=$runtime;Base=$base;Plan=$planPath}
}
# A changed staging directory must not replace data from the verified archive.
Write-Fixture $stage 'app/GamingMode.ps1' 'tampered';Write-Fixture $stage 'Framewell.exe' 'tampered-bootstrap'
foreach($portable in @($false,$true)){
 $test=New-TestPlan ('install-'+$portable) -Portable:$portable
 [Framewell.Updates]::Apply($test.Plan)
 Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Root 'GamingMode.ps1')) -eq 'new-script') ('Verified archive used for installation: portable='+$portable)
 Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Root 'nested/new.txt')) -eq 'new-file') 'New subdirectories install successfully'
 Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Root 'state/preferences.json')) -eq 'personal-profile') 'Personal preferences preserved'
 Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Root 'backups/prior.txt')) -eq 'restore-data') 'Restore data preserved'
 if($portable){Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Base 'Framewell.exe')) -eq 'new-bootstrap') 'Portable bootstrap comes from verified archive'}
}
# Force failure after the first replacement; the updater must restore that replacement.
$test=New-TestPlan 'rollback'
$locked=[IO.File]::Open((Join-Path $test.Root 'GamingMode.ps1'),'Open','ReadWrite','None')
try{Reject-Update {[Framewell.Updates]::Apply($test.Plan)} 'Locked target prevents incomplete update'}finally{$locked.Dispose()}
Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Root 'GamingMode.exe')) -eq 'old-exe') 'Earlier replacement rolled back after a later failure'
Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Root 'GamingMode.ps1')) -eq 'old-script') 'Locked target preserved'
Assert-Update ([IO.File]::ReadAllText((Join-Path $test.Root 'state/preferences.json')) -eq 'personal-profile') 'Personal state preserved after rollback'
[pscustomobject]@{Passed=$checks.Count;Checks=$checks;Fixture=$fixture;MachineSettingsChanged=$false}|ConvertTo-Json -Depth 4
