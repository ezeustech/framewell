# Documented Windows settings, captured before use and restored without a resident helper.
$script:GamingExtrasRoot=$PSScriptRoot
function Initialize-GamingExtraNative {
    if('GamingExtraNative' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class GamingExtraNative {
 [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)] static extern bool Get(uint action,uint value,out int result,uint flags);
 [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)] static extern bool Set(uint action,uint value,IntPtr result,uint flags);
 [DllImport("user32.dll",EntryPoint="SystemParametersInfoW",SetLastError=true)] static extern bool Mouse(uint action,uint value,[In,Out] int[] result,uint flags);
 public static bool Read(uint action){int value;if(!Get(action,0,out value,0))throw new System.ComponentModel.Win32Exception();return value!=0;}
 public static void Write(uint action,bool value){if(!Set(action,0,new IntPtr(value?1:0),3))throw new System.ComponentModel.Win32Exception();}
 public static int[] ReadMouse(){int[] value=new int[3];if(!Mouse(3,0,value,0))throw new System.ComponentModel.Win32Exception();return value;}
 public static void WriteMouse(int[] value){if(value.Length!=3)throw new ArgumentException();if(!Mouse(4,0,value,3))throw new System.ComponentModel.Win32Exception();}
}
'@
}
function Get-GamingExtraDefinitions {
    @(
        [pscustomobject]@{Id='Menu';Preference='ReduceMenuAnimation';Get=0x1002;Set=0x1003;Name='Menu animations'},
        [pscustomobject]@{Id='Tooltip';Preference='ReduceTooltipAnimation';Get=0x1016;Set=0x1017;Name='Tooltip animations'},
        [pscustomobject]@{Id='Combo';Preference='ReduceComboAnimation';Get=0x1004;Set=0x1005;Name='Dropdown animations'},
        [pscustomobject]@{Id='Cursor';Preference='DisableCursorShadow';Get=0x101A;Set=0x101B;Name='Pointer shadow'}
    )
}
function Get-GamingSleepTimeout {
    param([string]$PlanGuid)
    if($PlanGuid -notmatch '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$'){throw 'Invalid power scheme.'}
    $value=(& "$env:WINDIR\System32\powercfg.exe" /query $PlanGuid '238c9fa8-0aad-41ed-83f4-97be242c8f20' '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' | Out-String)
    if($LASTEXITCODE -ne 0){throw 'Could not inspect the selected power scheme.'}
    $hex=@([regex]::Matches($value,'0x([0-9a-fA-F]{8})')|ForEach-Object{$_.Groups[1].Value})
    if($hex.Count -lt 2){throw 'Power scheme timeout format was not recognized.'}
    return [Convert]::ToUInt32($hex[$hex.Count-2],16)
}
function Get-GamingExtraSnapshot {
    param($Preferences)
    $rows=@()
    foreach($d in Get-GamingExtraDefinitions){if($Preferences.($d.Preference)){Initialize-GamingExtraNative;$rows+=[pscustomobject]@{Id=$d.Id;Before=[GamingExtraNative]::Read($d.Get)}}}
    $mouse=$null
    if($Preferences.DisableMouseAcceleration){Initialize-GamingExtraNative;$mouse=@([GamingExtraNative]::ReadMouse())}
    $sleep=$null
    if($Preferences.PreventSleep){
        $plan=if($Preferences.PowerMode -eq 'HighPerformance'){'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'}elseif($Preferences.PowerMode -eq 'Balanced'){'381b4222-f694-41f0-9685-ff5bb260df2e'}else{(Get-GamingPowerPlan).Guid}
        $sleep=[pscustomobject]@{PlanGuid=$plan;BeforeSeconds=(Get-GamingSleepTimeout $plan)}
    }
    [pscustomobject]@{Version=1;Settings=$rows;Mouse=$mouse;Sleep=$sleep}
}
function Invoke-GamingExtras {
    param($Snapshot,[ValidateSet('Apply','Restore')][string]$Operation)
    if([int]$Snapshot.Version -ne 1){throw 'Unsupported extra-settings snapshot.'}
    $results=@()
    foreach($entry in @($Snapshot.Settings)){
        $d=Get-GamingExtraDefinitions|Where-Object Id -eq $entry.Id|Select-Object -First 1
        if(-not $d -or $entry.Before -isnot [bool]){throw 'Invalid extra-setting record.'}
        try{
            Initialize-GamingExtraNative
            $current=[GamingExtraNative]::Read($d.Get);$wanted=if($Operation -eq 'Apply'){$false}else{[bool]$entry.Before}
            if($Operation -eq 'Restore' -and $current -and -not $wanted){$status='KeptUserChange'}else{
                if($current -ne $wanted){[GamingExtraNative]::Write($d.Set,$wanted)}
                if([GamingExtraNative]::Read($d.Get) -ne $wanted){throw 'Windows did not confirm the selected value.'}
                $status=$Operation
            }
            $results+=[pscustomobject]@{Name=$d.Name;Success=$true;Status=$status;Message='Windows preference verified.'}
        }catch{$results+=[pscustomobject]@{Name=$d.Name;Success=$false;Status='Failed';Message=$_.Exception.Message}}
    }
    if($null -ne $Snapshot.Mouse){
        try{
            Initialize-GamingExtraNative
            $before=@($Snapshot.Mouse);if($before.Count -ne 3 -or @($before|Where-Object{$_ -isnot [int] -or $_ -lt 0 -or $_ -gt 20}).Count){throw 'Invalid mouse settings snapshot.'}
            $current=@([GamingExtraNative]::ReadMouse());$wanted=if($Operation -eq 'Apply'){@(0,0,0)}else{$before}
            if($Operation -eq 'Restore' -and ($current -join ',') -notin @('0,0,0',($wanted -join ','))){$status='KeptUserChange'}else{
                [GamingExtraNative]::WriteMouse([int[]]$wanted)
                if((@([GamingExtraNative]::ReadMouse()) -join ',') -ne ($wanted -join ',')){throw 'Pointer setting did not verify.'};$status=$Operation
            }
            $results+=[pscustomobject]@{Name='Windows pointer acceleration';Success=$true;Status=$status;Message='Pointer speed is unchanged; games using raw input manage this separately.'}
        }catch{$results+=[pscustomobject]@{Name='Windows pointer acceleration';Success=$false;Status='Failed';Message=$_.Exception.Message}}
    }
    if($Snapshot.Sleep){
        try{
            $plan=[string]$Snapshot.Sleep.PlanGuid;$current=Get-GamingSleepTimeout $plan
            $wanted=if($Operation -eq 'Apply'){[uint32]0}else{[uint32]$Snapshot.Sleep.BeforeSeconds}
            if($Operation -eq 'Restore' -and $current -notin @(0,$wanted)){$status='KeptUserChange'}else{
                & "$env:WINDIR\System32\powercfg.exe" /setacvalueindex $plan '238c9fa8-0aad-41ed-83f4-97be242c8f20' '29f6c1db-86da-48c5-9fdb-f2b67b1f44da' $wanted | Out-Null
                if($LASTEXITCODE -ne 0 -or (Get-GamingSleepTimeout $plan) -ne $wanted){throw 'Sleep timeout did not verify.'}
                if((Get-GamingPowerPlan).Guid -eq $plan){& "$env:WINDIR\System32\powercfg.exe" /setactive $plan|Out-Null};$status=$Operation
            }
            $results+=[pscustomobject]@{Name='Prevent AC sleep during session';Success=$true;Status=$status;Message='AC sleep timeout verified. Battery and display timeout are unchanged.'}
        }catch{$results+=[pscustomobject]@{Name='Prevent AC sleep during session';Success=$false;Status='Failed';Message=$_.Exception.Message}}
    }
    [pscustomobject]@{Success=(@($results|Where-Object{-not $_.Success}).Count -eq 0);Results=$results}
}
function Get-GamingStartupConfig {
    $path=Join-Path ([Environment]::GetFolderPath('Startup')) 'Gaming Mode.lnk'
    $enabled=$false
    if(Test-Path -LiteralPath $path){$shell=New-Object -ComObject WScript.Shell;try{$link=$shell.CreateShortcut($path);$enabled=([string]$link.TargetPath -ieq (Join-Path $script:GamingExtrasRoot 'GamingMode.exe'))}finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}}
    [pscustomobject]@{Enabled=$enabled;Path=$path;Mode='Dashboard only'}
}
function Set-GamingStartupConfig {
    param([bool]$Enabled)
    $config=Get-GamingStartupConfig
    if($Enabled){
        $exe=Join-Path $script:GamingExtrasRoot 'GamingMode.exe'
        if(-not(Test-Path -LiteralPath $exe -PathType Leaf)){throw 'Install Gaming Mode before enabling startup.'}
        if((Test-Path -LiteralPath $config.Path) -and -not $config.Enabled){throw 'Another shortcut named Gaming Mode exists in Startup. It was preserved.'}
        $shell=New-Object -ComObject WScript.Shell
        try{$link=$shell.CreateShortcut($config.Path);$link.TargetPath=$exe;$link.Arguments='Panel';$link.WorkingDirectory=$script:GamingExtrasRoot;$link.Description='Open Gaming Mode dashboard at sign-in; does not activate a profile.';$link.IconLocation=(Join-Path $script:GamingExtrasRoot 'GamingMode.ico');$link.WindowStyle=1;$link.Save()}finally{[void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)}
    }elseif($config.Enabled){Remove-Item -LiteralPath $config.Path -ErrorAction Stop}
    Get-GamingStartupConfig
}
