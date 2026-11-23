function Add-FramewellUpdateControls {
    param($UI)
    $card=New-MacCard $UI 'Framewell updates'
    [void]$card.Panel.Children.Add((New-MacText $UI 'Version 3.2.0' 13 -Secondary))
    [void]$card.Panel.Children.Add((New-MacToggle $UI 'AutomaticUpdates' 'Automatic updates' 'Checks for stable releases in the background. Verified updates install after you close Framewell. Profiles and settings are preserved.'))
    $status=New-MacText $UI 'Updates come from the official Framewell GitHub releases.' 12 -Secondary
    $status.Margin='0,6,0,12';$null=Register-MacControl $UI 'UpdateStatus' $status;[void]$card.Panel.Children.Add($status)
    $buttons=New-Object Windows.Controls.WrapPanel
    [void]$buttons.Children.Add((New-MacButton $UI 'CheckUpdates' 'Check for updates'))
    [void]$buttons.Children.Add((New-MacButton $UI 'DownloadUpdate' 'Download update'))
    [void]$card.Panel.Children.Add($buttons)
    $UI.Controls.PageSettings.Content.Children.Insert(2,$card.Border)
    $pref=Get-GamingPreferences
    $UI.Controls.AutomaticUpdates.IsChecked=($pref.AutomaticUpdates -ne $false)
    $UI.Controls.AutomaticUpdates.Add_Click({
        $p=Get-GamingPreferences
        $p|Add-Member -NotePropertyName AutomaticUpdates -NotePropertyValue ([bool]$UI.Controls.AutomaticUpdates.IsChecked) -Force
        $null=Set-GamingPreferences -Preferences $p
        if($UI.Controls.AutomaticUpdates.IsChecked){Start-FramewellUpdateCheck $UI -Download -Automatic}
        else{$UI.UpdatePlan=$null;$UI.Controls.UpdateStatus.Text='Automatic updates are off. Manual checks are available.'}
    }.GetNewClosure())
    $UI.Controls.CheckUpdates.Add_Click({Start-FramewellUpdateCheck $UI}.GetNewClosure())
    $UI.Controls.DownloadUpdate.Add_Click({Start-FramewellUpdateCheck $UI -Download}.GetNewClosure())
    $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(500)
    $timer.Add_Tick({
        if(-not $UI.UpdateJob){$UI.UpdateTimer.Stop();return}
        $UI.Controls.UpdateStatus.Text=[string]$UI.UpdateJob.Status
        if($UI.UpdateJob.Complete){
            $UI.UpdateTimer.Stop();$UI.Controls.CheckUpdates.IsEnabled=$true;$UI.Controls.DownloadUpdate.IsEnabled=$true
            if($UI.UpdateJob.PlanPath -and ($UI.UpdateManualDownload -or $UI.Controls.AutomaticUpdates.IsChecked)){$UI.UpdatePlan=[string]$UI.UpdateJob.PlanPath}
            if($UI.UpdatePlan){$UI.Controls.StatusText.Text='An update is ready and will install when Framewell closes.'}
        }
    }.GetNewClosure())
    $UI.UpdateTimer=$timer
    $UI.Window.Add_Closed({
        $UI.UpdateTimer.Stop()
        if($UI.UpdatePlan){
            try{$process=Get-Process -Id $PID;[Framewell.Updates]::InstallAfterExit($UI.UpdatePlan,$PID,$process.StartTime.ToUniversalTime().Ticks)}
            catch{[Windows.MessageBox]::Show('The update could not start. Your current installation is unchanged. '+$_.Exception.Message,'Framewell update')|Out-Null}
        }
    }.GetNewClosure())
}

function Start-FramewellUpdateCheck {
    param($UI,[switch]$Download,[switch]$Automatic)
    if($UI.UpdateJob -and -not $UI.UpdateJob.Complete){return}
    if(-not ('Framewell.Updates' -as [type])){$UI.Controls.UpdateStatus.Text='Open Framewell.exe to use automatic updates.';return}
    $UI.UpdateManualDownload=([bool]$Download -and -not $Automatic)
    $UI.UpdateJob=[Framewell.Updates]::Start($script:GamingRoot,'3.2.0',[bool]$Download)
    $UI.Controls.CheckUpdates.IsEnabled=$false;$UI.Controls.DownloadUpdate.IsEnabled=$false
    $UI.UpdateTimer.Start()
}
