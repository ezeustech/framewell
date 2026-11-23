$ErrorActionPreference='Stop'
$compiler=New-Object Microsoft.CSharp.CSharpCodeProvider
$options=New-Object CodeDom.Compiler.CompilerParameters
$options.GenerateExecutable=$true;$options.GenerateInMemory=$false
$options.OutputAssembly=Join-Path $PSScriptRoot 'Framewell.Updater.exe'
$options.CompilerOptions='/target:winexe /platform:x64 /optimize+'
$options.ReferencedAssemblies.AddRange(@('System.dll','System.Core.dll','System.Windows.Forms.dll','System.Net.Http.dll','System.Web.Extensions.dll','System.IO.Compression.dll','System.IO.Compression.FileSystem.dll'))
try{
    $result=$compiler.CompileAssemblyFromSource($options,[string[]]@((Get-Content (Join-Path $PSScriptRoot 'FramewellUpdates.cs') -Raw),(Get-Content (Join-Path $PSScriptRoot 'UpdateHelper.cs') -Raw)))
    if($result.Errors.HasErrors){throw (($result.Errors|ForEach-Object ToString)-join "`n")}
}finally{$compiler.Dispose()}
