[CmdletBinding()]
param([string]$DistributionDirectory)
$ErrorActionPreference='Stop'
$root=$PSScriptRoot
if(-not $DistributionDirectory){$DistributionDirectory=Join-Path $root 'dist'}
$manifest=Get-Content -LiteralPath (Join-Path $root 'runtime-files.json') -Raw|ConvertFrom-Json
$version=[string]$manifest.Version
if($version -notmatch '^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$'){throw 'The runtime manifest must specify a valid release version.'}
$runtimeName='Framewell-'+$version+'-win-x64.zip'
$sourceName='Framewell-'+$version+'-source.zip'
$distribution=[IO.Path]::GetFullPath($DistributionDirectory)
$fixture=Join-Path $root ('test-results\publication-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$runtime=Join-Path $fixture 'runtime';$source=Join-Path $fixture 'source';$installed=Join-Path $fixture 'installed'
$payload=Join-Path $runtime 'app'
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Package($Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name)}
foreach($archiveName in @($runtimeName,$sourceName)){
    $archivePath=Join-Path $distribution $archiveName
    Assert-Package (Test-Path -LiteralPath $archivePath -PathType Leaf) ('Manifest version archive exists: '+$archiveName)
    $checksum=[string](Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    $sumLines=@(Get-Content -LiteralPath (Join-Path $distribution 'SHA256SUMS.txt'))
    Assert-Package (@($sumLines|Where-Object{$_ -match ('(?i)^'+$checksum+'\s+\*?'+[regex]::Escape($archiveName)+'$')}).Count -eq 1) ('Published checksum matches '+$archiveName)
}
Expand-Archive -LiteralPath (Join-Path $distribution $runtimeName) -DestinationPath $runtime
Expand-Archive -LiteralPath (Join-Path $distribution $sourceName) -DestinationPath $source
$portableExecutable=Join-Path $runtime 'Framewell.exe'
Assert-Package (Test-Path -LiteralPath $portableExecutable -PathType Leaf) 'Portable ZIP exposes Framewell.exe at its root'
Assert-Package (Test-Path -LiteralPath $payload -PathType Container) 'Portable ZIP keeps its complete application payload in app'
Assert-Package (Test-Path -LiteralPath (Join-Path $runtime 'START HERE.txt') -PathType Leaf) 'Portable ZIP includes concise start instructions'
$startHere=Get-Content -LiteralPath (Join-Path $runtime 'START HERE.txt') -Raw
Assert-Package ($startHere -match 'Framewell\.exe' -and $startHere -match '(?i)extract') 'Start instructions name the extract-and-run executable'
$rootEntries=@(Get-ChildItem -LiteralPath $runtime -Force|ForEach-Object Name)
Assert-Package (@($rootEntries|Where-Object {$_ -notin @('Framewell.exe','Framewell.exe.config','START HERE.txt','app')}).Count -eq 0) 'Portable ZIP root contains only the launcher, optional configuration, instructions and app folder'
Assert-Package ([Reflection.AssemblyName]::GetAssemblyName($portableExecutable).Name -eq 'Framewell') 'Public portable executable has the Framewell assembly name'
[void][Reflection.Assembly]::LoadFrom($portableExecutable)
Assert-Package ([PortableLayout]::ResolvePayloadPath($runtime) -eq (Join-Path $payload 'GamingMode.exe')) 'Portable bootstrap resolves only the fixed app payload'
Assert-Package ([PortableLayout]::NormalizeAction([string[]]@()) -eq 'Panel') 'Double-clicking the portable entry point selects the dashboard'
foreach($actionName in @('Panel','Enter','Restore','Media','WindowsTools','Performance','Games')){
    Assert-Package ([PortableLayout]::NormalizeAction([string[]]@($actionName.ToLowerInvariant())) -eq $actionName) ('Portable action is explicitly supported: '+$actionName)
}
$invalidActionRejected=$false;try{[void][PortableLayout]::NormalizeAction([string[]]@('Panel','arbitrary.exe'))}catch{$invalidActionRejected=$true}
Assert-Package $invalidActionRejected 'Portable bootstrap rejects extra command arguments'
foreach($required in [PortableLayout]::GetRequiredFiles()){
    Assert-Package (Test-Path -LiteralPath (Join-Path $payload $required) -PathType Leaf) ('Portable first-launch dependency is packaged: '+$required)
}
Assert-Package (-not(Test-Path -LiteralPath (Join-Path $runtime 'Install-GamingMode.ps1'))) 'An installer is not required at the portable ZIP entry point'
if(Test-Path -LiteralPath (Join-Path $runtime 'Framewell.exe.config')){
    $portableConfig=[xml](Get-Content -LiteralPath (Join-Path $runtime 'Framewell.exe.config') -Raw)
    Assert-Package (@($portableConfig.configuration.startup.supportedRuntime|Where-Object version -eq 'v4.0').Count -gt 0) 'Portable configuration targets the supported .NET Framework runtime'
}
$documents=@('README.md','README.txt','AI_TRANSPARENCY.md','CHANGELOG.md','CONTRIBUTING.md','SECURITY.md','PUBLICATION.txt','LICENSE.txt','LICENSE-ORIGINAL-MIT.txt','THIRD-PARTY-NOTICES.txt','docs\ARCHITECTURE.md','docs\LIMITATIONS.md','docs\VALIDATION.md')
$previews=@('docs\images\overview-oled.png','docs\images\windows-gaming-settings.png','docs\images\memory-dio-theme.png')
foreach($package in @([pscustomobject]@{ArchiveRoot=$runtime;ContentRoot=$payload;Label='runtime'},[pscustomobject]@{ArchiveRoot=$source;ContentRoot=$source;Label='source'})){
    $tree=$package.ContentRoot;$label=$package.Label
    Assert-Package ((Get-Content -LiteralPath (Join-Path $tree 'runtime-files.json') -Raw|ConvertFrom-Json).Version -eq $version) ($label+' manifest version matches release')
    $private=@(Get-ChildItem -LiteralPath $package.ArchiveRoot -Recurse -Force|Where-Object{
        $relative=$_.FullName.Substring($package.ArchiveRoot.Length+1)
        $relative -match '(?:^|[\\/])(?:state|backups|\.git|dist)(?:[\\/]|$)' -or $_.Name -match '(?i)^(?:session\.json|media-stack-config\.json|installation\.json|launcher-errors.*|.*results\.json)$'
    })
    Assert-Package ($private.Count -eq 0) ($label+' excludes personal state, backups and development receipts')
    Assert-Package (-not(Test-Path -LiteralPath (Join-Path $tree 'vendor\optimizer\Optimizer-17.0.exe'))) ($label+' contains no standalone Optimizer executable')
    foreach($name in @($documents)+@($previews)+@('vendor\optimizer\optimizer-17.0-source.zip','vendor\optimizer\LICENSE-GPL-3.0.txt','vendor\optimizer\LICENSE-Newtonsoft.txt','vendor\optimizer\Newtonsoft.Json.dll','vendor\optimizer\provenance.json','vendor\optimizer\features.json')){
        Assert-Package (Test-Path -LiteralPath (Join-Path $tree $name) -PathType Leaf) ($label+' includes '+$name)
    }
    Assert-Package ((Get-Content -LiteralPath (Join-Path $tree 'LICENSE.txt') -Raw) -match 'GNU GENERAL PUBLIC LICENSE') ($label+' carries combined GPL license')
    Assert-Package ((Get-Content -LiteralPath (Join-Path $tree 'AI_TRANSPARENCY.md') -Raw) -match 'Codex/ChatGPT') ($label+' documents AI assistance')
    $readme=Get-Content -LiteralPath (Join-Path $tree 'README.md') -Raw
    Assert-Package ($readme -match '(?i)demo|preview|sample') ($label+' identifies documentation previews')
    foreach($name in $previews){
        $bytes=[IO.File]::ReadAllBytes((Join-Path $tree $name))
        Assert-Package ($bytes.Length -gt 1024 -and ([BitConverter]::ToString($bytes[0..7])) -eq '89-50-4E-47-0D-0A-1A-0A') ($label+' has a valid screenshot: '+$name)
    }
    $provenance=Get-Content -LiteralPath (Join-Path $tree 'vendor\optimizer\provenance.json') -Raw|ConvertFrom-Json
    Assert-Package ((Get-FileHash -LiteralPath (Join-Path $tree ('vendor\optimizer\'+$provenance.UpstreamSourceArchive)) -Algorithm SHA256).Hash -eq $provenance.UpstreamSourceSha256) ($label+' upstream source matches provenance')
    foreach($dependency in $provenance.Dependencies){
        Assert-Package ((Get-FileHash -LiteralPath (Join-Path $tree ('vendor\optimizer\'+$dependency.File)) -Algorithm SHA256).Hash -eq $dependency.Sha256) ($label+' dependency matches provenance: '+$dependency.Name)
    }
    $catalog=Get-Content -LiteralPath (Join-Path $tree 'vendor\optimizer\features.json') -Raw|ConvertFrom-Json
    Assert-Package ($catalog.Count -eq [int]$provenance.CatalogEntries) ($label+' complete feature catalog matches provenance')
    Assert-Package (@($catalog|Where-Object{-not $_.SectionId -or -not $_.Availability}).Count -eq 0) ($label+' features declare their embedded section and availability')
    foreach($retiredId in @($provenance.RetiredEntries)){
        Assert-Package (@($catalog|Where-Object{$_.Id -eq $retiredId -and $_.Availability -eq 'Retired'}).Count -eq 1) ($label+' marks retired upstream feature '+$retiredId)
    }
}
foreach($name in @($manifest.Files)){Assert-Package (Test-Path -LiteralPath (Join-Path $payload $name) -PathType Leaf) ('Runtime manifest file present in app: '+$name)}
$sharedFilesCompared=0
foreach($name in @($manifest.Files)){
    $sourceFile=Join-Path $source $name
    if(Test-Path -LiteralPath $sourceFile -PathType Leaf){
        Assert-Package ((Get-FileHash -LiteralPath (Join-Path $payload $name) -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash) ('Runtime and source payloads agree: '+$name)
        $sharedFilesCompared++
    }
}
Assert-Package ($sharedFilesCompared -gt 40) 'Source archive preserves the runtime scripts, documentation and data exactly'
$runtimeProvenance=Get-Content -LiteralPath (Join-Path $payload 'vendor\optimizer\provenance.json') -Raw|ConvertFrom-Json
$embeddedDll=Join-Path $payload 'vendor\optimizer\GamingMode.Optimizer.dll'
Assert-Package ((Get-FileHash -LiteralPath $embeddedDll -Algorithm SHA256).Hash -eq $runtimeProvenance.EmbeddedAssemblySha256) 'Embedded runtime DLL matches final provenance'
Assert-Package ([Reflection.AssemblyName]::GetAssemblyName($embeddedDll).Name -eq 'GamingMode.Optimizer') 'Embedded Windows tools are a library assembly'
$hostConfigPath=Join-Path $payload 'GamingMode.exe.config'
Assert-Package (Test-Path -LiteralPath $hostConfigPath -PathType Leaf) 'Portable app includes its scoped .NET host configuration'
$hostConfig=[xml](Get-Content -LiteralPath $hostConfigPath -Raw)
Assert-Package (@($hostConfig.configuration.startup.supportedRuntime|Where-Object {$_.version -eq 'v4.0' -and $_.sku -match 'Version=v4\.8'}).Count -gt 0) 'App host configuration declares .NET Framework 4.8'
Assert-Package ([string]$hostConfig.configuration.runtime.loadFromRemoteSources.enabled -eq 'true') 'App-scoped loader configuration supports downloaded local dependencies'
# Simulate downloaded DLLs without running either real GUI executable or changing
# a machine security setting. This fixture loader only reads assembly metadata.
$motwFixture=Join-Path $fixture 'downloaded-dll-probe';[void][IO.Directory]::CreateDirectory($motwFixture)
$motwProbe=Join-Path $motwFixture 'MetadataProbe.exe'
$metadataLoader=@'
using System;
using System.IO;
using System.Reflection;
public static class MetadataProbe {
    public static int Main(string[] args) {
        try {
            string root=AppDomain.CurrentDomain.BaseDirectory;
            Assembly json=Assembly.LoadFrom(Path.Combine(root,"Newtonsoft.Json.dll"));
            Assembly embedded=Assembly.LoadFrom(Path.Combine(root,"GamingMode.Optimizer.dll"));
            if(json.GetType("Newtonsoft.Json.JsonConvert",true)==null || embedded.GetType("Optimizer.EmbeddedHost",true)==null)return 2;
            Console.WriteLine("MOTW_LOADER_PASS");return 0;
        }catch(Exception error){Console.Error.WriteLine(error.GetType().FullName+": "+error.Message);return 1;}
    }
}
'@
Add-Type -TypeDefinition $metadataLoader -OutputAssembly $motwProbe -OutputType ConsoleApplication
Copy-Item -LiteralPath $hostConfigPath -Destination ($motwProbe+'.config')
foreach($dllName in @('Newtonsoft.Json.dll','GamingMode.Optimizer.dll')){
    $target=Join-Path $motwFixture $dllName
    Copy-Item -LiteralPath (Join-Path $payload ('vendor\optimizer\'+$dllName)) -Destination $target
    Set-Content -LiteralPath $target -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3" -Encoding ASCII
    Assert-Package ((Get-Content -LiteralPath $target -Stream Zone.Identifier -Raw) -match 'ZoneId=3') ('Fixture dependency is marked as downloaded: '+$dllName)
}
$motwResult=& $motwProbe 2>&1
Assert-Package ($LASTEXITCODE -eq 0 -and $motwResult -contains 'MOTW_LOADER_PASS') 'App-scoped configuration loads downloaded dependency metadata without a security-policy change or GUI launch'
Assert-Package (-not(Test-Path -LiteralPath (Join-Path $source 'vendor\optimizer\GamingMode.Optimizer.dll'))) 'Source package requires rebuilding its embedded DLL'
foreach($name in @('Build-Release.ps1','Build-Launcher.ps1','Build-PortableLauncher.ps1','Build-EmbeddedOptimizer.ps1','Launcher.cs','PortableLauncher.cs','Test-V3-Publication.ps1','vendor\optimizer\embedded-source\EMBEDDING.md','vendor\optimizer\embedded-source\optimizer-17.0\Optimizer\EmbeddedHost.cs','vendor\optimizer\embedded-source\optimizer-17.0\Optimizer\EmbeddedTemplatePanel.cs','vendor\optimizer\embedded-source\optimizer-17.0\Optimizer\Forms\MainForm.Embedded.cs')){
    Assert-Package (Test-Path -LiteralPath (Join-Path $source $name) -PathType Leaf) ('Source package includes '+$name)
}
# Compare every modified-source archive entry to the editable source package.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$modifiedTree=[IO.Path]::GetFullPath((Join-Path $source 'vendor\optimizer\embedded-source')).TrimEnd('\')+'\'
$sourceZip=[IO.Compression.ZipFile]::OpenRead((Join-Path $payload 'vendor\optimizer\embedded-source.zip'))
$sourceFilesChecked=0
try{
    foreach($entry in $sourceZip.Entries){
        if($entry.FullName -match '[\\/]$'){continue}
        if($entry.FullName -match '(?:^|[\\/])(?:bin|obj|\.git|\.vs)(?:[\\/]|$)'){throw 'Modified-source archive contains build artifacts.'}
        $sourcePath=[IO.Path]::GetFullPath((Join-Path $modifiedTree $entry.FullName))
        if(-not $sourcePath.StartsWith($modifiedTree,[StringComparison]::OrdinalIgnoreCase)){throw 'Modified-source archive has an invalid path.'}
        if(-not(Test-Path -LiteralPath $sourcePath -PathType Leaf)){throw ('Runtime modified source is missing from editable source package: '+$entry.FullName)}
        $stream=$entry.Open();$hasher=[Security.Cryptography.SHA256]::Create()
        try{$entryHash=[BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-','')}finally{$stream.Dispose();$hasher.Dispose()}
        if((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -ne $entryHash){throw ('Modified source differs across packages: '+$entry.FullName)}
        $sourceFilesChecked++
    }
}finally{$sourceZip.Dispose()}
Assert-Package ($sourceFilesChecked -gt 100) 'Runtime includes complete modified corresponding source matching source archive'
$probe=Join-Path $fixture 'Probe.ps1'
$probeContent=@'
param([string]$Root)
$ErrorActionPreference='Stop'
[void][Reflection.Assembly]::LoadFrom((Join-Path $Root 'GamingMode.exe'))
. (Join-Path $Root 'GamingMode.ps1') -LibraryOnly
if(@(Get-GMMediaDefinitions).Count -ne 0 -or @(Get-MediaStackSnapshot).Components.Count -ne 0){throw 'Clean install contains a phantom or personal media component.'}
$profiles=@(Get-GamingProfiles)
if($profiles.Count -ne 2 -or @($profiles|Where-Object Id -in @('media-stack','super-performance')).Count -ne 2){throw 'Clean install must start with the two generic built-in profiles.'}
if(@(($profiles|Where-Object Id -eq 'media-stack').AppIds).Count -ne 0){throw 'Clean install has personal media app membership.'}
if(@($profiles|ForEach-Object{$_.MediaKeys;$_.CustomExecutables}).Count -ne 0){throw 'Personal media keys or executable paths leaked into profiles.'}
if((Get-GamingPreferences).Theme -ne 'Dark'){throw 'Personal theme leaked into release.'}
if('Optimizer.EmbeddedHost' -as [type]){throw 'Library import eagerly loaded Windows tools.'}
$ui=Show-MacGamingPanel -CreateOnly
try{
    Update-MacGamingDashboard $ui
    Update-MacGamingSettings $ui
    Update-MacGamingOptimizer $ui -Reload
    $provenance=Get-Content -LiteralPath (Join-Path $Root 'vendor\optimizer\provenance.json') -Raw|ConvertFrom-Json
    if($ui.OptimizerCatalog.Count -ne [int]$provenance.CatalogEntries){throw 'Integrated Windows tools catalog is incomplete.'}
    if($ui.Controls.AppearanceTheme.Items.Count -ne @(Get-GamingThemes).Count){throw 'Theme catalog is incomplete.'}
    foreach($name in @('NavWindowsTools','WindowsToolsSection','WindowsToolsArea','WindowsSettingsApply','WindowsDisplayPreview','WindowsGpuApply')){if(-not $ui.Controls.ContainsKey($name)){throw ('Integrated UI control is missing: '+$name)}}
    if($ui.EmbeddedOptimizerView -or ('Optimizer.EmbeddedHost' -as [type])){throw 'Dashboard reads eagerly initialized Windows tools.'}
    if($ui.Window.AllowsTransparency){throw 'WPF window cannot host native Windows tools while layered.'}
    $memoryRuntime=Get-GamingMemoryRuntime
    if($memoryRuntime.TimerEnabled -or $memoryRuntime.MonitorRunning){throw 'Memory feature activated during dashboard read.'}
    if(@(Get-GamingSettingsProfiles).Count -ne 0){throw 'Personal settings profiles leaked.'}
    if(Read-GamingState){throw 'Personal session state leaked.'}
}finally{$ui.Window.Close()}
Initialize-GamingEmbeddedOptimizer
if(@(Get-GamingEmbeddedOptimizerSections).Count -lt 16){throw 'Embedded DLL is missing required tool sections.'}
if(Test-Path -LiteralPath (Join-Path $Root 'state\optimizer')){throw 'Static embedded metadata created component state.'}
'CLEAN_INSTALL_PASS'
'@
$probeContent|Set-Content -LiteralPath $probe -Encoding UTF8
$powershell=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$portableProbe=& $powershell -NoProfile -Sta -ExecutionPolicy Bypass -File $probe -Root $payload 2>&1
if($LASTEXITCODE -ne 0){throw ($portableProbe|Out-String)}
Assert-Package ($portableProbe -contains 'CLEAN_INSTALL_PASS') 'Extracted portable payload works without installation and preserves clean profiles, lazy loading and inactive memory tools'
Assert-Package (-not(Test-Path -LiteralPath (Join-Path $runtime 'state'))) 'Portable app state stays with the app payload rather than cluttering the launcher directory'
& (Join-Path $payload 'Install-GamingMode.ps1') -Destination $installed -SkipShortcuts|Out-Null
Assert-Package (Test-Path -LiteralPath (Join-Path $installed 'GamingMode.exe')) 'Optional clean per-user install still succeeds'
Assert-Package (-not(Test-Path -LiteralPath (Join-Path $installed 'state\media-stack-config.json'))) 'Optional clean install contains no private media configuration'
$probeResult=& $powershell -NoProfile -Sta -ExecutionPolicy Bypass -File $probe -Root $installed 2>&1
if($LASTEXITCODE -ne 0){throw ($probeResult|Out-String)}
Assert-Package ($probeResult -contains 'CLEAN_INSTALL_PASS') 'Optional installed dashboard also preserves clean defaults and inactive tools'
& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'Build-Launcher.ps1')
Assert-Package ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $source 'GamingMode.exe') -PathType Leaf)) 'Extracted source builds the complete app host executable'
& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'Build-PortableLauncher.ps1')
Assert-Package ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $source 'Framewell.exe') -PathType Leaf)) 'Extracted source builds the public portable Framewell executable'
$repack=& $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'Build-Release.ps1') 2>&1
if($LASTEXITCODE -ne 0){throw ($repack|Out-String)}
Assert-Package (Test-Path -LiteralPath (Join-Path $source 'vendor\optimizer\GamingMode.Optimizer.dll')) 'Clean extracted source rebuilds embedded Windows tools'
Assert-Package (Test-Path -LiteralPath (Join-Path $source ('dist\'+$runtimeName))) 'Extracted source rebuilds manifest-version runtime package'
Assert-Package (Test-Path -LiteralPath (Join-Path $source ('dist\'+$sourceName))) 'Extracted source rebuilds manifest-version source package'
$result=[pscustomobject]@{Product='Framewell';Version=$version;Passed=$checks.Count;Checks=$checks;SharedPayloadFilesCompared=$sharedFilesCompared;ModifiedSourceFilesCompared=$sourceFilesChecked;Fixture=$fixture;PortableEntryPoint='Framewell.exe';InstallerRequired=$false;MachineSettingsChanged=$false;PersonalDataIncluded=$false}
$result|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $root 'test-results\v3-publication-results.json') -Encoding UTF8
$result|ConvertTo-Json -Depth 6
