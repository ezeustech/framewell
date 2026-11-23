param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PSScriptRoot)
$output=[IO.Path]::GetFullPath($OutputDirectory)
if($output -eq [IO.Path]::GetPathRoot($output)){throw 'Choose a dedicated release output directory.'}
[void][IO.Directory]::CreateDirectory($output)
$manifest=Get-Content -LiteralPath (Join-Path $root 'runtime-files.json') -Raw|ConvertFrom-Json
$version=[string]$manifest.Version
$staging=Join-Path $output ('staging-'+[guid]::NewGuid().ToString('N'))
$runtime=Join-Path $staging 'runtime';$source=Join-Path $staging 'source'
[void][IO.Directory]::CreateDirectory($runtime);[void][IO.Directory]::CreateDirectory($source)
$files=@($manifest.Files)
$sourceFiles=@($files|Where-Object {$_ -notin @('GamingMode.exe','vendor\optimizer\GamingMode.Optimizer.dll','vendor\optimizer\embedded-source.zip')})+@('Launcher.cs','Build-Launcher.ps1','Build-EmbeddedOptimizer.ps1','Build-Icon.ps1','Install-GamingMode.ps1','Build-Release.ps1','.gitignore')
$runtimeFiles=@($files)+@('Install-GamingMode.ps1')
$sourceFiles+=@(Get-ChildItem -LiteralPath $root -Filter 'Test-*.ps1' -File|ForEach-Object Name)
$sourceFiles+=@(Get-ChildItem -LiteralPath (Join-Path $root 'test-results') -Filter '*tests.ps1' -File|ForEach-Object{'test-results\'+$_.Name})
$fork=Join-Path $root 'vendor\optimizer\embedded-source'
$sourceFiles+=@(Get-ChildItem -LiteralPath $fork -Recurse -File|Where-Object {$_.FullName -notmatch '[\\/](?:bin|obj|\.git|\.vs)[\\/]'}|ForEach-Object {$_.FullName.Substring($root.Length+1)})
$documentation=@('README.md','AI_TRANSPARENCY.md','CHANGELOG.md','CONTRIBUTING.md','SECURITY.md','LICENSE-ORIGINAL-MIT.txt')
$documentation+=@(Get-ChildItem -LiteralPath (Join-Path $root 'docs') -Recurse -File|ForEach-Object {$_.FullName.Substring($root.Length+1)})
$runtimeFiles+=$documentation
$sourceFiles+=$documentation
function Copy-ReleaseFiles([string[]]$Names,[string]$Target){
    foreach($name in @($Names|Select-Object -Unique)){
        if([IO.Path]::IsPathRooted($name) -or $name -match '(?:^|[\\/])(?:state|backups|\.\.|dist)(?:[\\/]|$)'){throw 'Private or invalid release path.'}
        $sourceName=$name
        $original=Join-Path $root $sourceName
        if(-not(Test-Path -LiteralPath $original -PathType Leaf)){throw ('Missing release file: '+$sourceName)}
        $destination=Join-Path $Target $name
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
        Copy-Item -LiteralPath $original -Destination $destination
    }
}
# Ship the complete modified corresponding source alongside the combined runtime.
# The standalone source archive also includes build scripts and all project sources.
Compress-Archive -Path (Join-Path $fork '*') -DestinationPath (Join-Path $root 'vendor\optimizer\embedded-source.zip') -Force
Copy-ReleaseFiles $runtimeFiles $runtime
Copy-ReleaseFiles $sourceFiles $source
foreach($tree in @($runtime,$source)){
    $private=@(Get-ChildItem -LiteralPath $tree -Recurse -File|Where-Object{$_.FullName -match '[\\/](?:state|backups)[\\/]' -or $_.Name -match '(?i)(session\.json|launcher-errors|installation\.json|verification|results\.json)$'})
    if($private.Count){throw 'Private development data reached staging.'}
}
$runtimeArchive=Join-Path $output ('GamingMode-'+$version+'-win-x64.zip')
$sourceArchive=Join-Path $output ('GamingMode-'+$version+'-source.zip')
Compress-Archive -Path (Join-Path $runtime '*') -DestinationPath $runtimeArchive -Force
Compress-Archive -Path (Join-Path $source '*') -DestinationPath $sourceArchive -Force
$hashes=@($runtimeArchive,$sourceArchive)|ForEach-Object{(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($_)}
$hashes|Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Encoding ASCII
[pscustomobject]@{Version=$version;RuntimeArchive=$runtimeArchive;SourceArchive=$sourceArchive;RuntimeFiles=@(Get-ChildItem -LiteralPath $runtime -Recurse -File).Count;SourceFiles=@(Get-ChildItem -LiteralPath $source -Recurse -File).Count;Staging=$staging;PersonalStateIncluded=$false}|ConvertTo-Json
