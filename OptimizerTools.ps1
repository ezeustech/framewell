# The Optimizer tools are compiled into a same-process WinForms library.
# Catalog lookup never constructs the UI or applies Windows settings.
$script:GamingOptimizerRoot=$PSScriptRoot
function Get-GamingOptimizerView {
    $path=Join-Path $script:GamingOptimizerRoot 'state\optimizer-view.json'
    if(Test-Path -LiteralPath $path){try{$value=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;if($value.Version -eq 1 -and ([string]$value.Search).Length -le 200){return $value}}catch{}}
    [pscustomobject]@{Version=1;Search=''}
}
function Save-GamingOptimizerView {
    param([AllowEmptyString()][string]$Search='')
    if($Search.Length -gt 200 -or $Search -match '[\x00-\x1F]'){throw 'Search text must be 200 characters or less.'}
    $folder=Join-Path $script:GamingOptimizerRoot 'state';[void][IO.Directory]::CreateDirectory($folder)
    $value=[pscustomobject]@{Version=1;Search=$Search}
    $pending=Join-Path $folder ('optimizer-view.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    $value|ConvertTo-Json|Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination (Join-Path $folder 'optimizer-view.json') -Force
    return $value
}
function Get-GamingOptimizerInfo {
    $path=Join-Path $script:GamingOptimizerRoot 'vendor\optimizer\GamingMode.Optimizer.dll'
    $dependency=Join-Path $script:GamingOptimizerRoot 'vendor\optimizer\Newtonsoft.Json.dll'
    [pscustomobject]@{Installed=((Test-Path -LiteralPath $path -PathType Leaf) -and (Test-Path -LiteralPath $dependency -PathType Leaf));Version='17.0';Path=$path;Execution='Embedded';Message='Windows tools run inside Gaming Mode. Changes are explicit; Windows version and administrator access determine availability. These tools have their own restore behavior.';Source='https://github.com/hellzerg/optimizer';License='GPL-3.0'}
}
function Get-GamingOptimizerFeatures {
    $path=Join-Path $script:GamingOptimizerRoot 'vendor\optimizer\features.json'
    if(Test-Path -LiteralPath $path){$rows=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json;return @($rows)}
    return @()
}
function Start-GamingOptimizer {
    $info=Get-GamingOptimizerInfo
    if(-not $info.Installed){return [pscustomobject]@{Success=$false;Message='The bundled Optimizer is missing. Reinstall the complete package.'}}
    # Compatibility route for callers of the previous command. The WPF window owns creation.
    [pscustomobject]@{Success=$true;Execution='Embedded';NavigateTo='WindowsTools';Message='Open the Windows tools workspace in Gaming Mode. No separate program is launched.'}
}
