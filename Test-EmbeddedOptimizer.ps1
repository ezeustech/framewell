[CmdletBinding()]
param([string]$AssemblyDirectory)
$ErrorActionPreference='Stop'
if(-not $AssemblyDirectory){$AssemblyDirectory=Join-Path $PSScriptRoot 'vendor\optimizer'}
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run with Windows PowerShell -STA.'}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[void][Reflection.Assembly]::LoadFrom((Join-Path $AssemblyDirectory 'Newtonsoft.Json.dll'))
[void][Reflection.Assembly]::LoadFrom((Join-Path $AssemblyDirectory 'GamingMode.Optimizer.dll'))
$state=Join-Path $env:TEMP ('gamingmode-embedded-smoke-'+[guid]::NewGuid().ToString('N'))
$oldCulture=[Globalization.CultureInfo]::DefaultThreadCurrentCulture
$oldUICulture=[Globalization.CultureInfo]::DefaultThreadCurrentUICulture
$oldTls=[Net.ServicePointManager]::SecurityProtocol
$oldCrossThread=[Windows.Forms.Control]::CheckForIllegalCrossThreadCalls
$view=$null
try {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    $view=[Optimizer.EmbeddedHost]::CreateView($state,$false)
    $timer.Stop()
    if($view.TopLevel -or $view.ShowInTaskbar -or $view.FormBorderStyle -ne 'None'){throw 'The embedded view has independent window chrome.'}
    $sections=[Optimizer.EmbeddedHost]::GetSections($view)
    if($sections.Count -lt 16 -or 'advancedExtrasTab' -notin $sections.Id){throw "Expected complete toolset; found $($sections.Count) sections."}
    [Optimizer.EmbeddedHost]::ApplyTheme($view,'#D5AE55',$false,'#000000','#101010','#F5F5F5')
    if($view.BackColor.ToArgb() -ne [Drawing.Color]::Black.ToArgb()){throw 'OLED surface palette was not applied.'}
    foreach($section in $sections){
        # Hardware/Cleaner scans are user-triggered read operations; skip expensive scans in smoke.
        if($section.Id -notin @('indiciumTab','cleanerTab')){[Optimizer.EmbeddedHost]::SelectSection($view,$section.Id)}
    }
    if([Globalization.CultureInfo]::DefaultThreadCurrentCulture -ne $oldCulture -or [Globalization.CultureInfo]::DefaultThreadCurrentUICulture -ne $oldUICulture){throw 'Embedded startup changed host culture.'}
    if([Net.ServicePointManager]::SecurityProtocol -ne $oldTls){throw 'Embedded startup changed host TLS policy.'}
    if([Windows.Forms.Control]::CheckForIllegalCrossThreadCalls -ne $oldCrossThread){throw 'Embedded startup changed host cross-thread checking.'}
    $settings=Get-Content -LiteralPath (Join-Path $state 'Optimizer.json') -Raw | ConvertFrom-Json
    if($settings.EnableTray -or $settings.AutoStart -or $settings.UpdateOnLaunch){throw 'Standalone lifetime/update settings were enabled.'}
    [pscustomobject]@{Result='PASS';SectionCount=$sections.Count;Sections=@($sections.Name);StartupMilliseconds=$timer.ElapsedMilliseconds;InProcess=$true;StateDirectory=$state;Administrator=[Optimizer.EmbeddedHost]::IsAdministrator;WindowsActionsExecuted=$false}|ConvertTo-Json -Depth 4
} finally {
    if($view){[Optimizer.EmbeddedHost]::DisposeView($view);if(-not$view.IsDisposed){throw 'Embedded view did not dispose.'}}
}
