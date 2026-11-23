# Same-process host for the GPL Optimizer component. No process is launched here.
# Loading this module does not load the component, inspect the system, or change settings.
$script:GamingEmbeddedOptimizerRoot=$PSScriptRoot
function Initialize-GamingEmbeddedOptimizer {
    if('Optimizer.EmbeddedHost' -as [type]){return}
    $path=Join-Path $script:GamingEmbeddedOptimizerRoot 'vendor\optimizer\GamingMode.Optimizer.dll'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw 'The integrated Windows tools component is missing. Reinstall the complete Gaming Mode package.'}
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    [void][Reflection.Assembly]::LoadFrom($path)
    if(-not('Optimizer.EmbeddedHost' -as [type])){throw 'The Windows tools component does not expose the supported embedded interface.'}
}
function Get-GamingEmbeddedOptimizerInfo {
    $path=Join-Path $script:GamingEmbeddedOptimizerRoot 'vendor\optimizer\GamingMode.Optimizer.dll'
    $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    [pscustomobject]@{Installed=(Test-Path -LiteralPath $path -PathType Leaf);Path=$path;IsAdministrator=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);Message='Windows tools run inside this app. Their system changes are separate from Gaming Mode session restore.'}
}
function Get-GamingEmbeddedOptimizerSections {
    param($View)
    Initialize-GamingEmbeddedOptimizer
    if($View){return @([Optimizer.EmbeddedHost]::GetSections($View))}
    return @([Optimizer.EmbeddedHost]::GetSections())
}
function New-GamingEmbeddedOptimizerView {
    param([IntPtr]$OwnerWindow=[IntPtr]::Zero)
    Initialize-GamingEmbeddedOptimizer
    [Optimizer.EmbeddedHost]::SetOwnerWindow($OwnerWindow)
    $stateDirectory=Join-Path $script:GamingEmbeddedOptimizerRoot 'state\optimizer'
    $allowActions=[bool][Optimizer.EmbeddedHost]::IsAdministrator
    return [Optimizer.EmbeddedHost]::CreateView($stateDirectory,$allowActions)
}
function Set-GamingEmbeddedOptimizerSection {
    param([Parameter(Mandatory=$true)]$View,[Parameter(Mandatory=$true)][string]$Section)
    Initialize-GamingEmbeddedOptimizer
    $sections=@(Get-GamingEmbeddedOptimizerSections)
    if($Section -notin @($sections.Id)){throw 'Unknown Windows tools section.'}
    [Optimizer.EmbeddedHost]::SelectSection($View,$Section)
}
function Set-GamingEmbeddedOptimizerTheme {
    param([Parameter(Mandatory=$true)]$View,[string]$Theme='Dark')
    Initialize-GamingEmbeddedOptimizer
    $palette=Get-GamingThemes|Where-Object Id -eq $Theme|Select-Object -First 1
    if(-not $palette){$palette=Get-GamingThemes|Where-Object Id -eq 'Dark'|Select-Object -First 1}
    $textColor=if($palette.Id -eq 'Light'){'#202634'}else{'#F0F3F8'}
    [Optimizer.EmbeddedHost]::ApplyTheme($View,[string]$palette.Accent,($palette.Id -eq 'Light'),[string]$palette.Background,[string]$palette.Surface,$textColor)
}
function Remove-GamingEmbeddedOptimizerView {
    param($View)
    if(-not $View){return}
    if('Optimizer.EmbeddedHost' -as [type]){[Optimizer.EmbeddedHost]::DisposeView($View)}else{$View.Dispose()}
}
