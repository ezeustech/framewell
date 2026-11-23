[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string]$CompilerCache = (Join-Path $env:TEMP 'gamingmode-build-compiler')
)
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Build with Windows PowerShell 5.1 (powershell.exe), targeting .NET Framework 4.8.' }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'vendor\optimizer' }
$source = Join-Path $PSScriptRoot 'vendor\optimizer\embedded-source\optimizer-17.0\Optimizer'
if (-not (Test-Path -LiteralPath $source -PathType Container)) { throw 'The complete embedded Optimizer source is required.' }
$package = Join-Path $CompilerCache 'microsoft.net.compilers.toolset.4.8.0.nupkg'
$expected = '37333F4F1E2CE55E621355D6DA651DC23D4CB5F94A8F76B9478816E87F110AD9'
New-Item -ItemType Directory -Path $CompilerCache -Force | Out-Null
if (-not (Test-Path -LiteralPath $package)) {
    Invoke-WebRequest -UseBasicParsing -Uri 'https://api.nuget.org/v3-flatcontainer/microsoft.net.compilers.toolset/4.8.0/microsoft.net.compilers.toolset.4.8.0.nupkg' -OutFile $package
}
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ne $expected) { throw 'Pinned Roslyn compiler package checksum mismatch.' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$compilerDirectory = Join-Path $CompilerCache 'roslyn-4.8.0'
$compiler = Join-Path $compilerDirectory 'tasks\net472\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { [IO.Compression.ZipFile]::ExtractToDirectory($package,$compilerDirectory) }
$build = Join-Path $CompilerCache 'embedded-resources'
New-Item -ItemType Directory -Path $build -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$output = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) 'GamingMode.Optimizer.dll'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[xml]$project = Get-Content -LiteralPath (Join-Path $source 'Optimizer.csproj') -Raw
$arguments = [Collections.Generic.List[string]]::new()
@('/nologo','/target:library','/platform:anycpu','/langversion:latest','/optimize+','/deterministic+','/warn:4',('/out:"'+$output+'"')) | ForEach-Object { $arguments.Add($_) }
$framework = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
foreach($name in @('System','System.Core','System.Drawing','System.Windows.Forms','System.Management','System.ServiceProcess','System.Net.Http','System.IO.Compression','System.IO.Compression.FileSystem','System.Xml','System.Xml.Linq','System.Data','System.Data.DataSetExtensions','System.Deployment','Microsoft.CSharp','Microsoft.VisualBasic')) {
    $reference = Join-Path $framework ($name+'.dll')
    if (-not (Test-Path -LiteralPath $reference)) { throw "Missing .NET Framework reference: $reference" }
    $arguments.Add('/reference:"'+$reference+'"')
}
$automation = [psobject].Assembly.Location
$arguments.Add('/reference:"'+$automation+'"')
$arguments.Add('/reference:"'+(Join-Path $source 'Newtonsoft.Json.dll')+'"')
foreach($item in $project.Project.ItemGroup.EmbeddedResource) {
    if (-not $item.Include) { continue }
    $inputFile = [IO.Path]::GetFullPath((Join-Path $source $item.Include))
    if ($inputFile.EndsWith('.resx')) {
        $stem = [IO.Path]::GetFileNameWithoutExtension($inputFile)
        $logical = if($item.Include.StartsWith('Properties\')) { 'Optimizer.Properties.'+$stem+'.resources' } else { 'Optimizer.'+$stem+'.resources' }
        $resourceFile = Join-Path $build $logical
        $reader = New-Object System.Resources.ResXResourceReader($inputFile)
        $reader.BasePath = [IO.Path]::GetDirectoryName($inputFile)
        $writer = New-Object System.Resources.ResourceWriter($resourceFile)
        try { foreach($entry in $reader.GetEnumerator()) { $writer.AddResource([string]$entry.Key,$entry.Value) }; $writer.Generate() }
        finally { $writer.Dispose(); $reader.Dispose() }
    } else {
        $resourceFile=$inputFile
        $logical=if($item.LogicalName){[string]$item.LogicalName}else{'Optimizer.'+[IO.Path]::GetFileName($inputFile)}
    }
    $arguments.Add('/resource:"'+$resourceFile+'",'+$logical)
}
$sources = @($project.Project.ItemGroup.Compile | Where-Object Include | ForEach-Object { Join-Path $source $_.Include })
$sources += @(Join-Path $source 'EmbeddedHost.cs'; Join-Path $source 'EmbeddedTemplatePanel.cs'; Join-Path $source 'Forms\MainForm.Embedded.cs')
foreach($file in $sources | Sort-Object -Unique) { $arguments.Add('"'+[IO.Path]::GetFullPath($file)+'"') }
$response = Join-Path $build 'compile.rsp'
[IO.File]::WriteAllLines($response,$arguments,[Text.UTF8Encoding]::new($false))
& $compiler ('@'+$response)
if ($LASTEXITCODE -ne 0) { throw "Embedded Optimizer compilation failed ($LASTEXITCODE)." }
Copy-Item -LiteralPath (Join-Path $source 'Newtonsoft.Json.dll') -Destination (Join-Path $OutputDirectory 'Newtonsoft.Json.dll') -Force
Get-Item -LiteralPath $output | Select-Object FullName,Length
Get-FileHash -LiteralPath $output -Algorithm SHA256
