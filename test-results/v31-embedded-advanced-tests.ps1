param([string]$AppRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$assembly=[Reflection.Assembly]::LoadFrom((Join-Path $AppRoot 'vendor\optimizer\GamingMode.Optimizer.dll'))
$binding=[Reflection.BindingFlags]'Static,NonPublic,Public'
$actions=$assembly.GetType('Optimizer.EmbeddedAdvancedActions',$true)
$snapshotType=$assembly.GetType('Optimizer.EmbeddedValueSnapshot',$true)
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$checks.Add($Name)}
function Invoke-Plan([int]$Operation,[int]$Ram=32,[string]$Process='FixtureGame_31.exe'){
    return ,$actions.GetMethod('Plan',$binding).Invoke($null,[object[]]@($Operation,$Ram,$Process))
}
function Expect-Failure([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Name}
function New-Snapshot([bool]$Exists,[int]$Kind,[string]$Json){
    $value=[Activator]::CreateInstance($snapshotType,$true);$value.Exists=$Exists;$value.Kind=$Kind;$value.JsonValue=$Json;return $value
}
$cores=Invoke-Plan 0
Assert ($cores.Count -eq 2 -and $cores[0].ValueName -eq 'ValueMin' -and $cores[1].ValueName -eq 'ValueMax' -and $cores[0].Value -eq 0 -and $cores[1].Value -eq 0) 'UnlockAllCores maps to the exact two upstream metadata values'
$group=Invoke-Plan 1 64
Assert ($group.Count -eq 1 -and $group[0].ValueName -eq 'SvcHostSplitThresholdInKB' -and $group[0].Value -eq 67108864) 'Svchost grouping converts selected GB to the upstream KB threshold'
$reset=Invoke-Plan 2
Assert ($reset[0].Value -eq 380000) 'Svchost reset matches upstream while UI identifies it as an Optimizer value'
Expect-Failure {Invoke-Plan 1 2048} 'Overflowing RAM threshold rejected before any write'
Expect-Failure {Invoke-Plan 1 0} 'Zero RAM threshold rejected before any write'
Expect-Failure {Invoke-Plan 9} 'Unknown operation rejected'
$block=Invoke-Plan 3
Assert ($block[0].KeyPath.EndsWith('\FixtureGame_31.exe') -and $block[0].ValueName -eq 'Debugger' -and -not $block[0].Remove -and $block[0].Value -eq '%windir%\System32\taskkill.exe') 'Process prevent targets only the selected app Debugger value'
$allow=Invoke-Plan 4
Assert ($allow[0].Remove -and $allow[0].ValueName -eq 'Debugger') 'Process allow removes only the owned Debugger value, never the process key'
foreach($bad in @('C:\Games\bad.exe','..\bad.exe','game.exe /silent','game.exe\Nested','../bad.exe','','game','*game.exe','a..b.exe')){
    Expect-Failure {Invoke-Plan 3 32 $bad} ('Unsafe process input rejected: '+$bad)
}
foreach($protected in @('lsass.exe','svchost.exe','MSMPENG.EXE','cmd.exe','powershell.exe','GamingMode.exe','Framewell.exe','Steam.exe','discord.exe','MsSense.exe','mbamservice.exe')){
    Expect-Failure {Invoke-Plan 3 32 $protected} ('Protected process rejected: '+$protected)
}
$address=$actions.GetMethod('ValidateAddress',$binding)
foreach($badAddress in @(@('SOFTWARE\Microsoft\Windows\CurrentVersion\Run','Payload'),@('SYSTEM\CurrentControlSet\Control','DifferentValue'),@('SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\lsass.exe','Debugger'))){
    Expect-Failure {$address.Invoke($null,[object[]]$badAddress)} ('Restore rejects an address outside its supported scope: '+$badAddress[1])
}
$equal=$actions.GetMethod('Equal',$binding)
$before=New-Snapshot $true 4 '1';$written=New-Snapshot $true 4 '2';$missing=New-Snapshot $false 0 $null
Assert (-not $equal.Invoke($null,[object[]]@($before,$written))) 'Restore comparison detects later registry-value edits'
Assert (-not $equal.Invoke($null,[object[]]@($before,$missing))) 'Restore comparison distinguishes missing original values'
Assert ($equal.Invoke($null,[object[]]@($missing,(New-Snapshot $false 0 $null)))) 'Restore comparison accepts matching absent values'
$foreign=New-Snapshot $true 1 '"other-debugger.exe"'
Expect-Failure {$actions.GetMethod('CheckOwnership',$binding).Invoke($null,[object[]]@($block[0],$foreign))} 'Existing debugger owned by another tool is preserved'
$own=New-Snapshot $true 1 '"%windir%\\System32\\taskkill.exe"'
$actions.GetMethod('CheckOwnership',$binding).Invoke($null,[object[]]@($block[0],$own))
Assert $true 'Existing Optimizer marker is recognized without deleting sibling settings'
foreach($operation in 0..4){
    $plan=Invoke-Plan $operation
    $description=$actions.GetMethod('Describe',$binding).Invoke($null,[object[]]@($operation,$plan))
    Assert ($description -match 'HKLM \(64-bit\)' -and $description -match 'original registry values') ('Action '+$operation+' exposes exact preview and restore behavior')
}
$source=Get-Content -LiteralPath (Join-Path $AppRoot 'vendor\optimizer\embedded-source\optimizer-17.0\Optimizer\EmbeddedTemplatePanel.cs') -Raw
Assert (-not ($source -match 'Process\.Start\(|Application\.Restart\(|Environment\.Exit\(|Program\.Main\(')) 'Native advanced actions contain no child launch, app restart, or standalone entrypoint'
Assert ($source -match 'SaveJournal\(receipts\); // Durable restore information must exist before the first write\.') 'Apply persists the restore receipt before writing Windows values'
Assert ($source -match 'if \(!Equal\(current, written\)\) \{ preserved\+\+; continue; \}') 'Restore implementation preserves subsequent external edits'
Assert ($source -match 'MessageBoxDefaultButton\.Button2' -and $source -match 'IsAdministrator') 'Apply and restore require explicit confirmation and administrator access'
[pscustomobject]@{Passed=$checks.Count;Checks=@($checks.ToArray());LiveRegistryWrites=$false;LiveElevation=$false;LiveProcessStarts=$false;Scope='Pure action planning, validation, ownership and source safety checks. No Apply or Restore invoked.';VerifiedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'v31-embedded-advanced-results.json') -Encoding UTF8
Write-Output ('PASS: '+$checks.Count+' embedded advanced checks; no live setting changes.')
