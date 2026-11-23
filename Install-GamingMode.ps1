param([string]$Destination=(Join-Path $env:LOCALAPPDATA 'Programs\Gaming Mode'),[switch]$SkipShortcuts)
$ErrorActionPreference='Stop'
$source=[IO.Path]::GetFullPath($PSScriptRoot)
$destinationPath=[IO.Path]::GetFullPath($Destination)
if($destinationPath -eq [IO.Path]::GetPathRoot($destinationPath)){throw 'Installation cannot target a drive root.'}
if($destinationPath.TrimEnd('\') -ieq $source.TrimEnd('\')){throw 'Choose a destination different from the extracted installer folder, or run GamingMode.exe portably.'}
$running=@(Get-CimInstance Win32_Process -Filter "Name = 'GamingMode.exe'" -ErrorAction SilentlyContinue|Where-Object {$_.ExecutablePath -ieq (Join-Path $destinationPath 'GamingMode.exe')})
if($running.Count){throw 'Close Gaming Mode before updating this installation. Your active session journal is preserved.'}
if(-not(Test-Path -LiteralPath $destinationPath)){New-Item -ItemType Directory -Path $destinationPath -Force | Out-Null}
$files=@((Get-Content -LiteralPath (Join-Path $source 'runtime-files.json') -Raw|ConvertFrom-Json).Files)
foreach($file in $files){
    if([IO.Path]::IsPathRooted($file) -or $file -match '(?:^|[\\/])\.\.(?:[\\/]|$)'){throw 'Invalid runtime manifest path.'}
    $origin=Join-Path $source $file
    if(-not(Test-Path -LiteralPath $origin -PathType Leaf)){throw "Missing source file: $file"}
    if($file -like '*.ps1'){
        $parseErrors=$null;$tokens=$null
        [System.Management.Automation.Language.Parser]::ParseFile($origin,[ref]$tokens,[ref]$parseErrors) | Out-Null
        if($parseErrors.Count){throw "Syntax validation failed: $file"}
    }
}
$backup=Join-Path $destinationPath ('backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss'))
foreach($file in $files){
    $target=Join-Path $destinationPath $file
    if(Test-Path -LiteralPath $target){
        $backupFile=Join-Path $backup $file
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($backupFile))
        Copy-Item -LiteralPath $target -Destination $backupFile -Force
    }
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    Copy-Item -LiteralPath (Join-Path $source $file) -Destination $target -Force
}
# Archive the exact legacy companion during a 3.0 upgrade; the new UI uses a DLL.
$legacy=Join-Path $destinationPath 'vendor\optimizer\Optimizer-17.0.exe'
if(Test-Path -LiteralPath $legacy -PathType Leaf){
    $legacyBackup=Join-Path $backup 'vendor\optimizer\Optimizer-17.0.exe'
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($legacyBackup))
    Move-Item -LiteralPath $legacy -Destination $legacyBackup -Force
}
$desktop=[Environment]::GetFolderPath('Desktop')
$shell=New-Object -ComObject WScript.Shell
$launcher=Join-Path $destinationPath 'GamingMode.exe'
$definitions=if($SkipShortcuts){@()}else{@(
    @{Name='Gaming Mode';Action='Panel';Description='Gaming dashboard, game launcher and reversible optimizations. Keeps Steam and Discord.';Icon=(Join-Path $destinationPath 'GamingMode.ico')},
    @{Name='Restore Normal Mode';Action='Restore';Description='Restore apps and media services closed by Gaming Mode.';Icon="$env:WINDIR\System32\imageres.dll,84"},
    @{Name='Start Media Stack';Action='Media';Description='Start your saved Media stack profile.';Icon=(Join-Path $destinationPath 'GamingMode.ico')}
)}
$shortcuts=@(foreach($definition in $definitions){
    $linkPath=Join-Path $desktop ($definition.Name+'.lnk')
    $shortcut=$shell.CreateShortcut($linkPath)
    $shortcut.TargetPath=$launcher
    $shortcut.Arguments=$definition.Action
    $shortcut.WorkingDirectory=$destinationPath
    $shortcut.Description=$definition.Description
    $shortcut.IconLocation=$definition.Icon
    $shortcut.WindowStyle=1
    $shortcut.Save()
    [pscustomobject]@{Name=$definition.Name;Path=$linkPath;Action=$definition.Action}
})
[Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) | Out-Null
$receipt=[pscustomobject]@{InstalledUtc=[datetime]::UtcNow.ToString('o');Destination=$destinationPath;Shortcuts=@($shortcuts);Activated=$false}
$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destinationPath 'installation.json') -Encoding UTF8
$receipt | ConvertTo-Json -Depth 5
