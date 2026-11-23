[CmdletBinding()]
param([string]$LauncherPath)
$ErrorActionPreference='Stop'
if(-not $LauncherPath){$LauncherPath=Join-Path $PSScriptRoot 'Framewell.exe'}
$assembly=[Reflection.Assembly]::LoadFrom([IO.Path]::GetFullPath($LauncherPath))
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Portable([bool]$Condition,[string]$Name){if(-not $Condition){throw $Name};$checks.Add($Name)}
function Assert-Rejected([scriptblock]$Operation,[string]$Name){$failed=$false;try{& $Operation|Out-Null}catch{$failed=$true};Assert-Portable $failed $Name}
Assert-Portable ([PortableLayout]::NormalizeAction([string[]]@()) -eq 'Panel') 'Double-click opens the dashboard'
foreach($action in @('Panel','Enter','Restore','Media','WindowsTools','Performance','Games')){
    Assert-Portable ([PortableLayout]::NormalizeAction([string[]]@($action.ToLowerInvariant())) -ceq $action) ('Supported action normalized: '+$action)
}
Assert-Rejected {[PortableLayout]::NormalizeAction([string[]]@('Panel','unexpected'))} 'Multiple arguments are rejected'
Assert-Rejected {[PortableLayout]::NormalizeAction([string[]]@('powershell.exe'))} 'Executable arguments are rejected'
Assert-Rejected {[PortableLayout]::NormalizeAction([string[]]@('Panel; calc'))} 'Command-like arguments are rejected'
Assert-Rejected {[PortableLayout]::NormalizeAction([string[]]@(''))} 'An empty explicit argument is rejected'
foreach($path in @('\\server\share\Framewell','\\?\C:\Framewell','relative','C:relative','')){
    Assert-Rejected {[PortableLayout]::ResolvePayloadPath($path)} ('Nonlocal or relative root is rejected: '+$path)
}
Assert-Portable ([PortableLayout]::ResolvePayloadPath('C:\Portable apps\Framewell') -ceq 'C:\Portable apps\Framewell\app\GamingMode.exe') 'Paths with spaces use the fixed payload'
Assert-Portable ([PortableLayout]::ResolvePayloadPath('C:\Portable\..\Framewell\') -ceq 'C:\Framewell\app\GamingMode.exe') 'Root normalization preserves the fixed app child'
$required=@([PortableLayout]::GetRequiredFiles())
Assert-Portable ('GamingMode.exe' -in $required -and 'GamingMode.exe.config' -in $required -and 'vendor\optimizer\GamingMode.Optimizer.dll' -in $required) 'Payload validation includes host config and embedded library'
Assert-Portable (@($required|Where-Object{[IO.Path]::IsPathRooted($_) -or $_ -match '(^|[\\/])\.\.([\\/]|$)'}).Count -eq 0) 'Required file list contains only package-relative paths'
Assert-Portable (@($assembly.GetReferencedAssemblies()|Where-Object Name -eq 'System.Management.Automation').Count -eq 0) 'Bootstrap can report a missing PowerShell component before loading the payload'
Assert-Portable ($assembly.GetName().Version -eq [version]'3.2.0.0') 'Bootstrap version is 3.2.0'

$launcher=$assembly.GetType('FramewellPortableLauncher',$true)
$flags=[Reflection.BindingFlags]'Static,NonPublic'
$prerequisites=$launcher.GetMethod('CheckWindowsComponents',$flags)
$prerequisites.Invoke($null,@())|Out-Null
Assert-Portable $true 'Read-only Windows component preflight passes on this test PC'

# All writes are confined to this newly created temporary fixture, never app/user state.
$fixture=Join-Path $env:TEMP ('framewell-portable-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$writable=$launcher.GetMethod('CheckWritableState',$flags)
$checkWritable=[Delegate]::CreateDelegate([Action[string]],$writable)
$checkWritable.Invoke([string]$fixture)
Assert-Portable (Test-Path -LiteralPath (Join-Path $fixture 'state') -PathType Container) 'State probe prepares the private settings directory'
Assert-Portable (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'state') -Force).Count -eq 0) 'State probe leaves no temporary files behind'
$blocked=Join-Path $fixture 'blocked'
[void][IO.Directory]::CreateDirectory($blocked)
[IO.File]::WriteAllText((Join-Path $blocked 'state'),'sentinel')
Assert-Rejected {$checkWritable.Invoke([string]$blocked)} 'State write failure is handled'
Assert-Portable ([IO.File]::ReadAllText((Join-Path $blocked 'state')) -ceq 'sentinel') 'Failed preflight preserves an existing file'

. (Join-Path $PSScriptRoot 'AppProfiles.ps1')
. (Join-Path $PSScriptRoot 'GameProcessTuning.ps1')
Assert-Portable (-not(Test-GamingProfileExecutable -Path 'C:\Games\Framewell.exe' -AllowMissing)) 'App profiles cannot close or recursively launch the portable entry point'
function Get-GameLibrary {[pscustomobject]@{Id='portable-test';ExecutablePath='C:\Games\Framewell.exe'}}
Assert-Rejected {Get-GamingProcessExecutable -GameId 'portable-test'} 'The portable entry point cannot be selected as a game process to tune'

[pscustomobject]@{Passed=$checks.Count;Checks=$checks;Fixture=$fixture;PayloadLaunched=$false;SystemSettingsChanged=$false}|ConvertTo-Json -Depth 4
