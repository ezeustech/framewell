[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference='Stop'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'Build this launcher with Windows PowerShell 5.1.'}
if(-not $OutputDirectory){$OutputDirectory=$PSScriptRoot}
$output=[IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($output)
$parameters=New-Object System.CodeDom.Compiler.CompilerParameters
# AnyCPU lets the bootstrap explain an unsupported architecture; the payload is x64.
$parameters.CompilerOptions='/platform:anycpu /optimize+ /target:winexe /win32icon:"'+(Join-Path $PSScriptRoot 'GamingMode.ico')+'"'
$parameters.GenerateExecutable=$true
$parameters.GenerateInMemory=$false
$parameters.OutputAssembly=Join-Path $output 'Framewell.exe'
$parameters.ReferencedAssemblies.AddRange(@('System.dll','System.Core.dll','System.Windows.Forms.dll'))
$provider=[System.CodeDom.Compiler.CodeDomProvider]::CreateProvider('CSharp')
try {
    $source=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'PortableLauncher.cs') -Raw
    $build=$provider.CompileAssemblyFromSource($parameters,[string[]]@($source))
    if($build.Errors.HasErrors){throw (($build.Errors|ForEach-Object ToString)-join "`n")}
} finally {$provider.Dispose()}
$configuration=Join-Path $PSScriptRoot 'Framewell.exe.config'
$destination=Join-Path $output 'Framewell.exe.config'
if([IO.Path]::GetFullPath($configuration) -ine [IO.Path]::GetFullPath($destination)){
    Copy-Item -LiteralPath $configuration -Destination $destination -Force
}
Get-Item -LiteralPath $parameters.OutputAssembly|Select-Object FullName,Length
