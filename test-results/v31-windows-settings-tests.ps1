$ErrorActionPreference='Stop'
$appRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $appRoot 'WindowsGameSettings.ps1')
$fixture=Join-Path $PSScriptRoot ('windows-settings-fixture-'+[guid]::NewGuid().ToString('N'))
$script:GamingWindowsRoot=$fixture
$script:values=@{};$script:writeCount=0;$script:administrator=$true;$script:failName=''
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw ('FAILED: '+$Name)};$checks.Add($Name)}
function Expect-Failure([scriptblock]$Callback,[string]$Name){$failed=$false;try{& $Callback|Out-Null}catch{$failed=$true};Assert $failed $Name}
function Test-GamingWindowsAdministrator {$script:administrator}
function Value-Key($Definition){$Definition.Hive+'|'+$Definition.Path+'|'+$Definition.Name}
function Read-GamingWindowsValue {
    param($Definition)
    $id=Value-Key $Definition
    if($script:values.ContainsKey($id)){return ConvertTo-GamingWindowsValue $script:values[$id]}
    [pscustomobject]@{Exists=$false;Value=$null;Kind='DWord'}
}
function Write-GamingWindowsValue {
    param($Definition,$Value)
    if($script:failName -and $Definition.Name -eq $script:failName){throw 'Simulated registry access failure'}
    # Verify that the real implementation saved a valid restore receipt before this mock write.
    if($Definition.Name -in @(Get-GamingWindowsDefinitions|ForEach-Object Name)){$null=Read-GamingWindowsJournal}else{$null=Read-GamingGpuPreferenceJournal}
    $script:writeCount++;$script:values[(Value-Key $Definition)]=ConvertTo-GamingWindowsValue $Value
}
function Put-Value([string]$Id,$Value){$definition=Get-GamingWindowsDefinitions|Where-Object Id -eq $Id;$script:values[(Value-Key $definition)]=$Value}
function DWord([int]$Value){[pscustomobject]@{Exists=$true;Value=$Value;Kind='DWord'}}

Put-Value GameModeAuto (DWord 1);Put-Value GameModeAllow (DWord 0)
$result=Set-GamingWindowsSettings -GameMode Enabled
Assert ($result.Success -and $script:writeCount -eq 1 -and (Read-GamingWindowsValue (Get-GamingWindowsDefinitions|Where-Object Id -eq 'GameModeAllow')).Value -eq 1) 'Game Mode fixes its secondary flag even when the primary flag already matches'
$count=$script:writeCount;Set-GamingWindowsSettings -GameMode Enabled|Out-Null
Assert ($script:writeCount -eq $count) 'Already matching settings do not create redundant writes'
$journal=Read-GamingWindowsJournal
Assert ($journal.Entries.Count -eq 1 -and $journal.Entries[0].Before.Value -eq 0) 'Original secondary flag is journaled before applying'
Restore-GamingWindowsSettings|Out-Null
Assert ((Read-GamingWindowsValue (Get-GamingWindowsDefinitions|Where-Object Id -eq 'GameModeAllow')).Value -eq 0) 'Restore returns the original Game Mode secondary flag'
Put-Value GameModeAuto (DWord 99)
$result=Set-GamingWindowsSettings -GameMode Default
Assert ($result.Success -and -not (Read-GamingWindowsValue (Get-GamingWindowsDefinitions|Where-Object Id -eq 'GameModeAuto')).Exists) 'Default removes an unrecognized saved value instead of incorrectly skipping it'
Restore-GamingWindowsSettings|Out-Null
Assert ((Read-GamingWindowsValue (Get-GamingWindowsDefinitions|Where-Object Id -eq 'GameModeAuto')).Value -eq 99) 'Restore retains an original nonstandard DWORD exactly'
$script:administrator=$false;$count=$script:writeCount
$result=Set-GamingWindowsSettings -GameMode Disabled -HardwareScheduling Enabled
Assert (-not $result.Success -and $result.RequiresElevation -and $script:writeCount -eq $count) 'Mixed user/machine request preflights elevation before any write'
$script:administrator=$true
$script:failName='AllowAutoGameMode';$result=Set-GamingWindowsSettings -GameMode Enabled;$script:failName=''
Assert (-not $result.Success -and $result.Message -match 'could not' -and @($result.Results|Where-Object {-not $_.Success}).Count -eq 1) 'Partial Windows write failure is surfaced and retains restore records'
$null=Restore-GamingWindowsSettings

$binary=[pscustomobject]@{Exists=$true;Kind='Binary';Value=[byte[]]@(0,127,255)}
$roundtrip=$binary|ConvertTo-Json -Compress|ConvertFrom-Json
$normalized=ConvertTo-GamingWindowsValue $roundtrip
Assert ($normalized.Value -is [byte[]] -and (Test-GamingWindowsValueEqual $binary $normalized)) 'Binary registry originals survive JSON roundtrip with correct CLR type'
$strings=[pscustomobject]@{Exists=$true;Kind='MultiString';Value=[string[]]@('One','Two')}
Assert (Test-GamingWindowsValueEqual $strings ($strings|ConvertTo-Json -Compress|ConvertFrom-Json)) 'MultiString originals compare structurally after JSON roundtrip'
Expect-Failure {ConvertTo-GamingWindowsValue ([pscustomobject]@{Exists=$true;Kind='DWord';Value=1.5})} 'Fractional DWORD restore data is rejected'
Expect-Failure {ConvertTo-GamingWindowsValue ([pscustomobject]@{Exists=$true;Kind='Binary';Value=@(256)})} 'Out-of-range binary restore data is rejected'
Expect-Failure {ConvertTo-GamingWindowsValue ([pscustomobject]@{Exists=$true;Kind='String';Value='ok';Command='extra'})} 'Unknown snapshot fields are rejected'
foreach($kind in @('DWord','QWord','String','ExpandString','Binary','MultiString','None')){
    $parsed=[Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind],$kind,$false)
    Assert ([string]$parsed -ceq $kind) ('RegistryValueKind parsing supports '+$kind)
}

$exe='C:\Games\Fixture.exe';$definition=Get-GamingGpuPreferenceDefinition $exe
$script:values[(Value-Key $definition)]=[pscustomobject]@{Exists=$true;Kind='String';Value='CustomToken=1;GpuPreference=1;'}
Set-GamingGpuPreference -ExecutablePath $exe -Preference HighPerformance|Out-Null
$gpuJournal=Read-GamingGpuPreferenceJournal
Assert ((Read-GamingWindowsValue $definition).Value -eq 'CustomToken=1;GpuPreference=2;' -and $gpuJournal.Entries[0].Before.Value -eq 'CustomToken=1;GpuPreference=1;') 'GPU setting preserves unrelated tokens and journals the original value'
Set-GamingGpuPreference -ExecutablePath $exe -Preference Default|Out-Null
Assert ((Read-GamingWindowsValue $definition).Value -eq 'CustomToken=1;' -and (Read-GamingGpuPreferenceJournal).Entries[0].Before.Value -eq 'CustomToken=1;GpuPreference=1;') 'Repeated GPU changes keep the first restore baseline'
Restore-GamingGpuPreference $exe|Out-Null
Assert ((Read-GamingWindowsValue $definition).Value -eq 'CustomToken=1;GpuPreference=1;') 'GPU restore returns the original token string'
Set-GamingGpuPreference -ExecutablePath $exe -Preference HighPerformance|Out-Null
$script:values[(Value-Key $definition)]=[pscustomobject]@{Exists=$true;Kind='String';Value='CustomToken=2;GpuPreference=1;'};$count=$script:writeCount
$restored=Restore-GamingGpuPreference $exe
Assert ($script:writeCount -eq $count -and $restored.Message -match 'later') 'GPU restore preserves later changes made by another tool'
Set-GamingGpuPreference -ExecutablePath $exe -Preference HighPerformance|Out-Null
$gpuJournal=Read-GamingGpuPreferenceJournal
$gpuJournal.Entries=@($gpuJournal.Entries)+@($gpuJournal.Entries)
Write-GamingWindowsJson -Path (Join-Path $fixture 'state\gpu-preference-journal.json') -Value $gpuJournal
$count=$script:writeCount
Expect-Failure {Set-GamingGpuPreference -ExecutablePath $exe -Preference Default} 'Duplicate GPU restore records are rejected before changing Windows'
Assert ($script:writeCount -eq $count) 'Corrupt GPU journal causes no write'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'state') -Filter '*.pending').Count -eq 0) 'Atomic journal replacements leave no incomplete final writes'

$token='0123456789abcdef0123456789abcdef';$statusPath=Join-Path $fixture ('state\display-'+$token+'.status.json')
$status=[pscustomobject]@{Token=$token;Success=$true;RequiresConfirmation=$true;State='Preview';DeadlineUtc=[datetime]::UtcNow.AddMinutes(1).ToString('o');Message='Preview'}
Write-GamingWindowsJson $statusPath $status
function Start-Sleep {param($Milliseconds);$script:ackStatus.RequiresConfirmation=$false;$script:ackStatus.State=$script:ackState;$script:ackStatus.Success=($script:ackState -eq 'Kept');$script:ackStatus.Message=$script:ackState;Write-GamingWindowsJson $script:ackPath $script:ackStatus}
$script:ackStatus=$status;$script:ackPath=$statusPath;$script:ackState='Kept'
$confirmation=Confirm-GamingDisplayMode $token
Assert ($confirmation.Success -and $confirmation.Message -eq 'Kept') 'Display Keep succeeds only after worker acknowledgement'
$status.RequiresConfirmation=$true;$status.State='Preview';$status.DeadlineUtc=[datetime]::UtcNow.AddMinutes(1).ToString('o');Write-GamingWindowsJson $statusPath $status;$script:ackState='Failed'
$confirmation=Confirm-GamingDisplayMode $token
Assert (-not $confirmation.Success -and $confirmation.Message -eq 'Failed') 'Worker persistence failure reaches display confirmation UI'
$status.RequiresConfirmation=$true;$status.DeadlineUtc=[datetime]::UtcNow.AddMinutes(-1).ToString('o');Write-GamingWindowsJson $statusPath $status
Assert (-not (Confirm-GamingDisplayMode $token).Success) 'Expired display preview cannot be kept'
$workerSource=Get-Content -LiteralPath (Join-Path $appRoot 'DisplayWorker.ps1') -Raw
Assert ($workerSource -match 'GamingModeDisplayPreview-v1' -and $workerSource -match 'ReleaseMutex\(') 'Independent display workers serialize previews and release their mutex'
$nativeSource=Get-Content -LiteralPath (Join-Path $appRoot 'WindowsDisplayNative.cs') -Raw
Assert ($nativeSource -match 'EnumSettings\(device,-2,ref saved\)' -and $nativeSource -match '0x10000001U') 'Native persistence captures and can restore the previously stored display frequency'
Add-Type -Path (Join-Path $appRoot 'WindowsDisplayNative.cs')
Assert ($null -ne ('GamingWindowsDisplay' -as [type])) 'Display PInvoke implementation compiles on Windows PowerShell'
[pscustomobject]@{Passed=$checks.Count;Checks=@($checks.ToArray());MockRegistryWrites=$script:writeCount;LiveRegistryWrites=$false;LiveDisplayChanges=$false;LiveElevation=$false;VerifiedUtc=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $PSScriptRoot 'v31-windows-settings-results.json') -Encoding UTF8
Write-Output ('PASS: '+$checks.Count+' Windows settings and display safety checks; all writes mocked.')
