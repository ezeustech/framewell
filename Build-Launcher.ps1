$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'vendor\optimizer\GamingMode.Optimizer.dll'))){
    & (Join-Path $PSScriptRoot 'Build-EmbeddedOptimizer.ps1') | Out-Null
}
$assembly=[System.Management.Automation.PowerShell].Assembly.Location
$parameters=New-Object System.CodeDom.Compiler.CompilerParameters
$parameters.CompilerOptions='/platform:x64 /optimize+ /target:winexe /win32icon:"'+(Join-Path $PSScriptRoot 'GamingMode.ico')+'"'
$parameters.GenerateExecutable=$true
$parameters.GenerateInMemory=$false
$parameters.OutputAssembly=Join-Path $PSScriptRoot 'GamingMode.exe'
$parameters.ReferencedAssemblies.AddRange(@($assembly,'System.Windows.Forms.dll','System.Core.dll','System.dll'))
$provider=[System.CodeDom.Compiler.CodeDomProvider]::CreateProvider('CSharp')
try{
    $sources=@((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Launcher.cs') -Raw))
    # Compile native metric/settings types once, rather than starting csc at each dashboard launch.
    foreach($module in @('Performance.ps1','SessionExtras.ps1','NetworkDiagnostics.ps1')){
        $body=Get-Content -LiteralPath (Join-Path $PSScriptRoot $module) -Raw
        $native=[regex]::Match($body,"(?s)Add-Type[^\r\n]*-TypeDefinition @'\r?\n(.*?)\r?\n'@")
        if(-not $native.Success){throw "Native API source missing: $module"}
        $sources+=@($native.Groups[1].Value)
    }
    $sources+=@((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'NvidiaDrs.cs') -Raw))
    $sources+=@((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'GamingSystemNative.cs') -Raw))
    $sources+=@((Get-Content -LiteralPath (Join-Path $PSScriptRoot 'WindowsDisplayNative.cs') -Raw))
    $build=$provider.CompileAssemblyFromSource($parameters,[string[]]$sources)
    if($build.Errors.HasErrors){throw (($build.Errors | ForEach-Object ToString) -join "`n")}
}finally{$provider.Dispose()}
