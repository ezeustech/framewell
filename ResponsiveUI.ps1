# Read-only UI work runs in a reusable background runspace. Controls stay on the UI thread.
function Start-FramewellRead {
    param($UI,[string]$Key,[string]$Code,[scriptblock]$Apply,[object]$Argument=$null)
    if($UI.ReadJobs.ContainsKey($Key)){return}
    if(-not $UI.ReadPool){
        $UI.ReadPool=[RunspaceFactory]::CreateRunspacePool(1,1)
        $UI.ReadPool.ApartmentState='STA';$UI.ReadPool.ThreadOptions='ReuseThread';$UI.ReadPool.Open()
    }
    $shell=[PowerShell]::Create();$shell.RunspacePool=$UI.ReadPool
    [void]$shell.AddScript('param($root,$code,$argument) . (Join-Path $root "GamingMode.ps1") -LibraryOnly -NoUI; & ([scriptblock]::Create($code)) $argument').AddArgument($script:GamingRoot).AddArgument($Code).AddArgument($Argument)
    $UI.ReadJobs[$Key]=@{Shell=$shell;Handle=$shell.BeginInvoke();Apply=$Apply;Started=[datetime]::UtcNow}
    $UI.ReadTimer.Start()
}

function Initialize-FramewellReads {
    param($UI)
    $UI.ReadJobs=@{};$UI.ReadPool=$null
    $timer=New-Object Windows.Threading.DispatcherTimer
    $timer.Interval=[timespan]::FromMilliseconds(80)
    $timer.Add_Tick({
        foreach($key in @($UI.ReadJobs.Keys)){
            $job=$UI.ReadJobs[$key];if(-not $job.Handle.IsCompleted){continue}
            $UI.ReadJobs.Remove($key)
            try{
                $rows=@($job.Shell.EndInvoke($job.Handle))
                if($job.Shell.HadErrors){throw $job.Shell.Streams.Error[0]}
                $value=if($rows.Count -eq 1){$rows[0]}else{,$rows}
                & $job.Apply $value
            }catch{$UI.Controls.StatusText.Text='Could not refresh '+$key+': '+$_.Exception.Message}
            finally{$job.Shell.Dispose()}
        }
        if($UI.ReadJobs.Count -eq 0){$UI.ReadTimer.Stop()}
    }.GetNewClosure())
    $UI.ReadTimer=$timer
}

function Stop-FramewellReads {
    param($UI)
    if($UI.ReadTimer){$UI.ReadTimer.Stop()}
    foreach($job in @($UI.ReadJobs.Values)){try{$job.Shell.Stop()}finally{$job.Shell.Dispose()}}
    $UI.ReadJobs.Clear()
    if($UI.ReadPool){$UI.ReadPool.Close();$UI.ReadPool.Dispose();$UI.ReadPool=$null}
}

function Request-FramewellDashboard {
    param($UI)
    $UI.Controls.StatusText.Text='Refreshing system overview...'
    Start-FramewellRead $UI 'Overview' '[pscustomobject]@{Dashboard=Get-PerformanceDashboard;Preview=Get-GamingPreview;Preferences=Get-GamingPreferences}' {
        param($data) Update-MacGamingDashboard $UI -Snapshot $data
        $UI.Controls.StatusText.Text='System overview updated.'
    }.GetNewClosure()
}

function Request-FramewellGames {
    param($UI)
    if(-not $UI.Games.Count){$UI.Controls.GameEmpty.Text='Loading your game library...'}
    Start-FramewellRead $UI 'Games' '@(Get-GameLibrary)' {
        param($data) $UI.Games=@($data);$UI.Controls.GameEmpty.Text="No games found. Add any game's .exe file to get started.";Update-MacGamingGameList $UI
    }.GetNewClosure()
}

function Request-FramewellProfiles {
    param($UI)
    Start-FramewellRead $UI 'Profiles' '[pscustomobject]@{Components=Get-GamingProfileComponents;Profiles=@(Get-GamingProfiles)}' {
        param($data) Update-MacGamingProfiles $UI -Snapshot $data
    }.GetNewClosure()
}

function Request-FramewellWindowsSettings {
    param($UI,[switch]$Force)
    if($UI.WindowsSettingsLoaded -and -not $Force){return}
    Start-FramewellRead $UI 'Windows preferences' '[pscustomobject]@{State=Get-GamingWindowsSettings;Modes=@(Get-GamingDisplayModes)}' {
        param($data) Update-MacGamingWindowsSettings $UI -IncludeDisplay -Snapshot $data;$UI.WindowsSettingsLoaded=$true
    }.GetNewClosure()
}

function Request-FramewellNetwork {
    param($UI)
    if($UI.NetworkLoaded){return}
    Start-FramewellRead $UI 'Network games' '@(Get-GameLibrary)' {
        param($data) Update-MacGamingServers $UI -ReloadGames -CachedGames @($data)
    }.GetNewClosure()
}
