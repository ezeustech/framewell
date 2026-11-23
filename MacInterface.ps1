# WPF interface for Framewell. Dot-sourcing defines functions only.
# Windows PowerShell 5.1 compatible; workflow changes remain in the backend.
if (-not (Get-Command Get-GamingThemes -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'ThemeCatalog.ps1') }
if (-not (Get-Command Get-GamingEmbeddedOptimizerInfo -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'EmbeddedOptimizer.ps1') }
if (-not (Get-Command Initialize-FramewellReads -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'ResponsiveUI.ps1') }
if (-not (Get-Command Add-FramewellUpdateControls -ErrorAction SilentlyContinue)) { . (Join-Path $PSScriptRoot 'FramewellUpdateUI.ps1') }

function ConvertTo-MacGamingThemedXaml {
    param([xml]$Document)
    $tokens = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($node in $Document.SelectNodes('//*')) {
        foreach ($attribute in @($node.Attributes)) {
            if ($attribute.LocalName -notin @('Background','Foreground','BorderBrush','Fill','Stroke','Color','CaretBrush','Value')) { continue }
            $value = [string]$attribute.Value
            $whiteCard = ($value -eq 'White' -and ($attribute.LocalName -eq 'Background' -or ($node.LocalName -eq 'Setter' -and $node.GetAttribute('Property') -eq 'Background')))
            if ($value -notmatch '^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$' -and -not $whiteCard) { continue }
            $token = if ($whiteCard) { 'FFFFFF' } else { $value.Substring(1).ToUpperInvariant() }
            [void]$tokens.Add($token)
            $kind = if ($attribute.LocalName -eq 'Color') { 'Color' } else { 'Brush' }
            $attribute.Value = '{DynamicResource Mac' + $kind + $token + '}'
        }
    }
    foreach ($token in @('DDE8F7','1164C8','485267','202634','E9F2FF','F0F4FA','E1E5EC','F6F7FA')) { [void]$tokens.Add($token) }
    [pscustomobject]@{Document=$Document;Tokens=@($tokens)}
}

function Apply-MacGamingTheme {
    param($UI, [string]$Theme='Dark')
    $palette=Get-GamingThemes | Where-Object Id -eq $Theme | Select-Object -First 1
    if(-not $palette){$Theme='Dark';$palette=Get-GamingThemes|Where-Object Id -eq 'Dark'}
    if($UI.ThemeInitialized -and $UI.Theme -eq $Theme){return}
    $dark = @{
        'FFFFFF'='#282F3A'; '202634'='#EBEFF6'; '344056'='#E0E7F2'; '485267'='#B8C2D2'
        '536F93'='#AEC7E8'; '617087'='#B4C0D3'; '657185'='#B1BED2'; '667184'='#A9B5C8'
        '697B93'='#B2C3DA'; '718097'='#B4C1D5'; '778095'='#ADB8CC'; '788497'='#AAB8CF'
        '7C8597'='#AAB7CB'; '7C899D'='#AEBCD0'; '7C8FA9'='#A7BDD8'; '7D899B'='#ADBDD3'
        '8994A6'='#A7B5CC'; '8A94A5'='#ABB7C9'; '8A95A8'='#AAB8D0'; '8B93A3'='#A7B3C7'
        '8B96A8'='#A9B8CE'; '9098A7'='#A4B2C7'; '919BAD'='#A5B4CC'; '929BAA'='#ABB8CD'
        '929CAD'='#A5B4CB'; '939BAA'='#A6B3C7'; '939CAD'='#A7B4CC'; '959EAD'='#ADB9CE'
        '969EAC'='#A3B1C8'; '969EAD'='#ADB9CE'; '98A1B0'='#ADB9CF'; '9AA3B2'='#AAB8CF'
        '9CA4B2'='#A9B6CB'; 'C7CDD8'='#454F60'; 'CFD5DF'='#536074'; 'D9E5F5'='#344D70'
        'DDE2E9'='#435066'; 'DDE2EA'='#343E4E'; 'DDE8F7'='#263E5D'; 'DDEBFC'='#244567'
        'DEE8F6'='#354962'; 'E0EAF7'='#354963'; 'E1E5EC'='#3B475B'; 'E2E5EC'='#354050'
        'E4E7ED'='#343F50'; 'E5E8EE'='#3B4657'; 'E9F2FF'='#23476E'; 'ECF5FF'='#25374D'
        'EDF0F4'='#3C485B'; 'EDF2F9'='#3D4A60'; 'EDF3FB'='#283B53'; 'EEF1F6'='#364154'
        'F0F2F6'='#202630'; 'F0F4FA'='#34445B'; 'F5F6F9'='#2A313D'; 'F6F7FA'='#242C38'
        'F6F8FF'='#293248'; 'F7F8FB'='#252D38'; 'FAFBFD'='#232A35'; '106CCF'='#8FC5FF'
        '1164C8'='#92C5FF'; '3679C4'='#97C9FF'; '273142'='#000000'; '16000000'='#55000000'
    }
    if ($Theme -eq 'OLED') {
        foreach ($key in @('FFFFFF','F0F2F6','FAFBFD','F5F6F9','F7F8FB','F6F7FA','ECF5FF','F6F8FF')) { $dark[$key]='#000000' }
        foreach ($key in @('C7CDD8','E1E5EC','E2E5EC','E4E7ED','E5E8EE','EDF0F4','DDE2EA','DDE2E9')) { $dark[$key]='#303030' }
        $dark['EEF1F6']='#1B1B1B';$dark['EDF3FB']='#101820'
    } elseif ($Theme -eq 'Midnight') {
        $dark['FFFFFF']='#17253E';$dark['FAFBFD']='#111D32';$dark['F0F2F6']='#0B1629'
        $dark['F5F6F9']='#15223A';$dark['F7F8FB']='#101D33';$dark['F6F7FA']='#101B30'
        $dark['ECF5FF']='#1A3154';$dark['F6F8FF']='#202F50';$dark['DDE8F7']='#2C4570'
        $dark['DDEBFC']='#2B4975';$dark['EEF1F6']='#2A3C5D';$dark['EDF3FB']='#223655'
        $dark['087CFA']='#4379DC';$dark['1164C8']='#BDD5FF';$dark['E9F2FF']='#304D7A'
    }
    if($Theme -notin @('Dark','Light','OLED','Midnight')){
        foreach($key in @('FFFFFF','F5F6F9','F7F8FB','F6F7FA')){$dark[$key]=$palette.Surface}
        $dark['FAFBFD']=$palette.Background;$dark['F0F2F6']=$palette.Sidebar
        foreach($key in @('ECF5FF','F6F8FF','DDE8F7','DDEBFC','EEF1F6','EDF3FB','E9F2FF','F0F4FA')){$dark[$key]=$palette.Selection}
        foreach($key in @('C7CDD8','DDE2EA','DDE2E9','E1E5EC','E2E5EC','E4E7ED','E5E8EE','EDF0F4','EDF2F9','D9E5F5')){$dark[$key]=$palette.Border}
        foreach($key in @('485267','617087','7C8597','697B93','718097','7C8FA9','9098A7','969EAC','969EAD','919BAD')){$dark[$key]=$palette.Secondary}
        foreach($key in @('087CFA','63A7FF','6CAEFF')){$dark[$key]=$palette.Accent}
        foreach($key in @('1164C8','106CCF','3679C4')){$dark[$key]=$palette.Metric}
    }
    $UI.ApplyingTheme = $true
    try {
        foreach ($token in @($UI.ThemeTokens)) {
            $value = if ($Theme -ne 'Light' -and $dark.ContainsKey($token)) { $dark[$token] } else { '#' + $token }
            $color = [System.Windows.Media.ColorConverter]::ConvertFromString($value)
            $brush = New-Object System.Windows.Media.SolidColorBrush $color
            $brush.Freeze()
            # WPF dynamic resources need the CLR value, not PowerShell's wrapper.
            $UI.Window.Resources[('MacColor' + $token)] = $color.PSObject.BaseObject
            $UI.Window.Resources[('MacBrush' + $token)] = $brush.PSObject.BaseObject
        }
        $metricColor = [System.Windows.Media.ColorConverter]::ConvertFromString([string]$palette.Metric)
        $metricBrush = New-Object System.Windows.Media.SolidColorBrush $metricColor
        $metricBrush.Freeze()
        $UI.Window.Resources['MacMetricAccent'] = $metricBrush.PSObject.BaseObject
        $UI.Theme = $Theme; $UI.ThemeInitialized = $true
        $UI.Controls.AppearanceTheme.SelectedIndex = [array]::IndexOf(@((Get-GamingThemes).Id),$Theme)
        if($UI.Controls.ContainsKey('ThemeDescription')){$UI.Controls.ThemeDescription.Text=$palette.Description+' Original character-inspired colors; no artwork included.'}
        if($UI.Controls.ContainsKey('ThemeSwatches')){foreach($pair in @(@(0,$palette.Accent),@(1,$palette.Metric),@(2,$palette.Surface),@(3,$palette.Background))){$UI.Controls.ThemeSwatches.Children[[int]$pair[0]].Background=New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString([string]$pair[1]))}}
        Set-MacGamingPage $UI $UI.CurrentPage
        if($UI.EmbeddedOptimizerView){try{Set-GamingEmbeddedOptimizerTheme -View $UI.EmbeddedOptimizerView -Theme $Theme}catch{if($UI.Controls.ContainsKey('WindowsToolsStatus')){$UI.Controls.WindowsToolsStatus.Text=$_.Exception.Message}}}
    } finally { $UI.ApplyingTheme = $false }
}

function Save-MacGamingTheme {
    param($UI, [string]$Theme)
    $preferences = Get-GamingPreferences
    if (-not $preferences.PSObject.Properties['Theme']) { $preferences | Add-Member -NotePropertyName Theme -NotePropertyValue $Theme }
    else { $preferences.Theme = $Theme }
    $null = Set-GamingPreferences -Preferences $preferences
    Apply-MacGamingTheme $UI $Theme
    Set-MacGamingStatus $UI ($Theme + ' appearance saved.')
}

function Sync-MacGamingUi {
    param($UI)
    if (-not $UI -or -not $UI.Window -or $UI.Window.Dispatcher.HasShutdownStarted) { return }
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    $callback = [System.Windows.Threading.DispatcherOperationCallback]{ param($frameObject) $frameObject.Continue = $false; return $null }
    [void]$UI.Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $callback, $frame)
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Set-MacGamingStatus {
    param($UI, [string]$Message)
    $UI.Controls.StatusText.Text = $Message
    Sync-MacGamingUi $UI
}

function Get-MacGamingStateText {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 'Check in Settings' }
    if ($Value -is [bool]) { if ($Value) { return 'On' } else { return 'Off' } }
    return [string]$Value
}

function Format-MacGamingNumber {
    param($Value, [int]$Decimals = 0)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return '--' }
    $number = 0.0
    if (-not [double]::TryParse([string]$Value, [ref]$number)) { return [string]$Value }
    return $number.ToString(('N' + $Decimals), [Globalization.CultureInfo]::CurrentCulture)
}

function Set-MacGamingPage {
    param($UI, [ValidateSet('Overview','Games','Profiles','Performance','Network','Tools','WindowsTools','Settings')][string]$Page)
    foreach ($name in @('Overview','Games','Profiles','Performance','Network','Tools','WindowsTools','Settings')) {
        if (-not $UI.Controls.ContainsKey(('Page'+$name))) { continue }
        $UI.Controls[('Page' + $name)].Visibility = if ($name -eq $Page) { 'Visible' } else { 'Collapsed' }
        $UI.Controls[('Nav' + $name)].Background = if ($name -eq $Page) { $UI.Window.Resources['MacBrushDDE8F7'] } else { [System.Windows.Media.Brushes]::Transparent }
        $UI.Controls[('Nav' + $name)].Foreground = if ($name -eq $Page) { $UI.Window.Resources['MacBrush1164C8'] } else { $UI.Window.Resources['MacBrush485267'] }
    }
    $UI.CurrentPage = $Page
}

function Update-MacGamingGameList {
    param($UI, [switch]$Reload)
    $selectedId = [string]$UI.Controls.GameList.SelectedItem.Id
    if ($Reload) { $UI.Games = @(Get-GameLibrary) }
    $search = [string]$UI.Controls.GameSearch.Text
    $filtered = @($UI.Games | Where-Object { [string]::IsNullOrWhiteSpace($search) -or $_.Name.IndexOf($search, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Sort-Object Name)
    $UI.Controls.GameList.ItemsSource = $null
    $UI.Controls.GameList.ItemsSource = $filtered
    $UI.Controls.GameCount.Text = [string]$filtered.Count + ' games'
    $UI.Controls.GameList.Height = [math]::Min(180,[math]::Max(84,($filtered.Count*42)))
    $UI.Controls.GameEmpty.Visibility = if ($filtered.Count) { 'Collapsed' } else { 'Visible' }
    if ($filtered.Count) {
        $restoreSelection = $filtered | Where-Object Id -eq $selectedId | Select-Object -First 1
        if ($restoreSelection) { $UI.Controls.GameList.SelectedItem = $restoreSelection } else { $UI.Controls.GameList.SelectedIndex = 0 }
    }
    $UI.Controls.LaunchGame.IsEnabled = [bool]$filtered.Count
}

function Save-MacGamingPreferences {
    param($UI)
    $preferences = Get-GamingPreferences
    foreach ($property in @('KeepISLC','DeepTrim','PowerMode','ReduceAnimations','ReduceTransparency','DisableBackgroundCapture','DisableBrowserBackground') + @(Get-MacGamingExtraPreferenceNames)) {
        if (-not $preferences.PSObject.Properties[$property]) { $preferences | Add-Member -NotePropertyName $property -NotePropertyValue $null }
    }
    $preferences.KeepISLC = [bool]$UI.Controls.KeepISLC.IsChecked
    $preferences.DeepTrim = [bool]$UI.Controls.DeepTrim.IsChecked
    $preferences.PowerMode = @('Current','HighPerformance','Balanced')[[math]::Max(0,$UI.Controls.PowerMode.SelectedIndex)]
    $preferences.ReduceAnimations = [bool]$UI.Controls.ReduceAnimations.IsChecked
    $preferences.ReduceTransparency = [bool]$UI.Controls.ReduceTransparency.IsChecked
    $preferences.DisableBackgroundCapture = [bool]$UI.Controls.DisableBackgroundCapture.IsChecked
    $preferences.DisableBrowserBackground = [bool]$UI.Controls.DisableBrowserBackground.IsChecked
    foreach ($property in @(Get-MacGamingExtraPreferenceNames)) { $preferences.$property = [bool]$UI.Controls[$property].IsChecked }
    $null = Set-GamingPreferences -Preferences $preferences
    Set-MacGamingStatus $UI 'Preferences saved for your next Gaming Mode session.'
}

function Set-MacGamingPreset {
    param($UI, [ValidateSet('Lowest background','Balanced','ISLC comparison')][string]$Name)
    $UI.Controls.DeepTrim.IsChecked = ($Name -ne 'Balanced')
    $UI.Controls.KeepISLC.IsChecked = ($Name -eq 'ISLC comparison')
    $UI.Controls.PowerMode.SelectedIndex = 0
    Save-MacGamingPreferences $UI
    Set-MacGamingStatus $UI ($Name + ' preset saved. Individual visual, capture and browser choices were kept.')
}

function Update-MacGamingDashboard {
    param($UI,$Snapshot=$null)
    $dashboard = if($Snapshot){$Snapshot.Dashboard}else{Get-PerformanceDashboard}
    $preview = if($Snapshot){$Snapshot.Preview}else{Get-GamingPreview}
    $preferences = if($Snapshot){$Snapshot.Preferences}else{Get-GamingPreferences}
    $state = $preview.State
    $UI.Dashboard = $dashboard
    $UI.Active = [bool]($state -and $state.Active)
    $UI.Controls.ProcessCount.Text = Format-MacGamingNumber $dashboard.ProcessCount
    $UI.Controls.MemoryCount.Text = (Format-MacGamingNumber $dashboard.UsedRamGiB 1) + ' GB'
    $UI.Controls.MemoryTotal.Text = 'of ' + (Format-MacGamingNumber $dashboard.RamGiB 1) + ' GB in use'
    if ($dashboard.RamGiB -and [double]$dashboard.RamGiB -gt 0) {
        $UI.Controls.MemoryMeter.Value = [math]::Min(100, [math]::Max(0, ([double]$dashboard.UsedRamGiB / [double]$dashboard.RamGiB * 100)))
    }
    $UI.Controls.RefreshCount.Text = (Format-MacGamingNumber $dashboard.RefreshHz) + ' Hz'
    $UI.Controls.CpuName.Text = [string]$dashboard.CpuName
    $UI.Controls.GpuName.Text = [string]$dashboard.GpuName
    $UI.Controls.PowerPlanName.Text = [string]$dashboard.PowerPlan
    $UI.Controls.TimerValue.Text = (Format-MacGamingNumber $dashboard.TimerCurrentMs 2) + ' ms'
    $UI.Controls.ISLCState.Text = if ($dashboard.ISLCRunning) { 'ISLC is running' } else { 'ISLC is not running' }
    $UI.Controls.WifiSummary.Text = if ($dashboard.WifiSummary) { [string]$dashboard.WifiSummary } else { 'Connection details are available in Windows network settings.' }
    $UI.Controls.GameModeState.Text = Get-MacGamingStateText $dashboard.GameMode
    $UI.Controls.HagsState.Text = Get-MacGamingStateText $dashboard.HAGS
    $UI.Controls.CaptureState.Text = Get-MacGamingStateText $dashboard.BackgroundRecording
    $UI.Controls.DisplayState.Text = (Format-MacGamingNumber $dashboard.RefreshHz) + ' Hz selected'
    $UI.Controls.KeepISLC.IsChecked = [bool]$preferences.KeepISLC
    $UI.Controls.DeepTrim.IsChecked = if ($null -eq $preferences.DeepTrim) { $true } else { [bool]$preferences.DeepTrim }
    $UI.Controls.PowerMode.SelectedIndex = if ($preferences.PowerMode -eq 'HighPerformance') { 1 } elseif ($preferences.PowerMode -eq 'Balanced') { 2 } else { 0 }
    $UI.Controls.ReduceAnimations.IsChecked = [bool]$preferences.ReduceAnimations
    $UI.Controls.ReduceTransparency.IsChecked = [bool]$preferences.ReduceTransparency
    $UI.Controls.DisableBackgroundCapture.IsChecked = if ($null -eq $preferences.DisableBackgroundCapture) { $true } else { [bool]$preferences.DisableBackgroundCapture }
    $UI.Controls.DisableBrowserBackground.IsChecked = if ($null -eq $preferences.DisableBrowserBackground) { $true } else { [bool]$preferences.DisableBrowserBackground }
    foreach ($property in @(Get-MacGamingExtraPreferenceNames)) {
        $UI.Controls[$property].IsChecked = if ($null -ne $preferences.$property) { [bool]$preferences.$property } else { $property -match '^(Close|Pause)' }
    }
    $UI.CloseAfterActivation = if ($null -eq $preferences.CloseAfterActivation) { $true } else { [bool]$preferences.CloseAfterActivation }
    $UI.Controls.CloseAfterActivation.IsChecked = $UI.CloseAfterActivation
    Apply-MacGamingTheme $UI ([string]$preferences.Theme)
    $UI.Controls.ModeBadge.Text = if ($UI.Active) { if ($state.Mode -eq 'GamingWithMedia') { 'GAMING + MEDIA' } elseif ($state.Mode -match 'Partial') { 'NEEDS ATTENTION' } else { 'GAMING MODE ON' } } else { 'NORMAL MODE' }
    $UI.Controls.HeroTitle.Text = if ($UI.Active) { 'Your gaming session.' } else { 'Ready when you are.' }
    $UI.Controls.HeroSubtitle.Text = if ($UI.Active) { 'Restore your apps when you are finished, or bring the media stack back on its own.' } else { 'Clear optional background work and give your game room to run. Steam and Discord stay open.' }
    $UI.Controls.ToggleMode.Content = if ($UI.Active) { 'Turn Gaming Mode Off' } else { 'Turn Gaming Mode On' }
    $UI.Controls.RestoreNormal.IsEnabled = $UI.Active
    $UI.Controls.ReapplyMode.Visibility = if ($UI.Active) { 'Visible' } else { 'Collapsed' }
    $appNames = @($preview.Apps | ForEach-Object Name)
    $UI.Controls.AppsSummary.Text = if ($appNames.Count) { $appNames -join ', ' } else { 'No optional apps are currently targeted.' }
    $media = @($preview.Media.Components | Where-Object Running)
    $UI.Controls.MediaSummary.Text = [string]$media.Count + ' media components currently running'
    $UI.Controls.LastChange.Text = if ($state -and $null -ne $state.AfterCount) { 'Last session: ' + $state.BeforeCount + ' to ' + $state.AfterCount + ' processes after activation.' } else { 'Your measured before-and-after count will appear after activation.' }
    $UI.Controls.SidebarComputer.Text = [string]$env:COMPUTERNAME
    if($UI.Controls.ContainsKey('QuickMemoryAvailable')){try{Update-MacGamingMemory $UI}catch{$UI.Controls.QuickMemoryStandby.Text='Memory readings unavailable'}}
}

function Show-MacGamingResult {
    param($UI, $Result)
    $rows = @($Result.Results)
    $lines = @($rows | ForEach-Object {
        $name = if ($_.Name) { $_.Name } elseif ($_.Component) { $_.Component } else { $_.Key }
        $message = if ($_.Message) { $_.Message } else { $_.Detail }
        (@($name, $_.Status, $message) | Where-Object { $_ }) -join ' - '
    })
    if (-not $lines.Count -and $Result.Message) { $lines = @([string]$Result.Message) }
    $UI.Controls.ResultText.Text = $lines -join "`r`n"
    $UI.Controls.ResultPanel.Visibility = if ($lines.Count) { 'Visible' } else { 'Collapsed' }
    if ($Result.PSObject.Properties['Success'] -and -not $Result.Success) {
        $UI.Controls.ResultPanel.IsExpanded = $true
        Set-MacGamingPage $UI 'Overview'
    }
}

function Invoke-MacGamingBusy {
    param($UI, [scriptblock]$Operation, [string]$Message, [string]$SuccessMessage='Done.', [switch]$CloseOnSuccess, [switch]$RefreshDashboard, [switch]$InlineResult)
    if ($UI.Busy) { return }
    # Do not apply an older read snapshot after a user starts a state-changing action.
    if($UI.ReadJobs.Count){Stop-FramewellReads $UI}
    $UI.Busy = $true
    $UI.Controls.MainWorkspace.IsEnabled = $false
    $UI.Controls.CloseWindow.IsEnabled = $false
    $UI.Window.Cursor = [System.Windows.Input.Cursors]::Wait
    Set-MacGamingStatus $UI $Message
    try {
        $result = & $Operation
        $success = $true
        if ($null -ne $result -and $result.PSObject.Properties['Success']) { $success = [bool]$result.Success }
        if ($RefreshDashboard) { Update-MacGamingDashboard $UI }
        if (-not $InlineResult -and $result -and ($result.PSObject.Properties['Results'] -or $result.PSObject.Properties['Message'])) { Show-MacGamingResult $UI $result }
        if ($success) {
            Set-MacGamingStatus $UI $SuccessMessage
            if ($CloseOnSuccess -and $UI.CloseAfterActivation -ne $false) {
                $UI.Busy = $false
                $keepMemoryTools=$false
                if(Get-Command Get-GamingMemoryRuntime -ErrorAction SilentlyContinue){$keepMemoryTools=[bool](Get-GamingMemoryRuntime).RequiresOpenApp}
                if($keepMemoryTools){$UI.Window.WindowState='Minimized'}else{$UI.Window.Close()}
            }
        } else {
            if ($InlineResult -and $result.Message) { Set-MacGamingStatus $UI ([string]$result.Message) }
            else { Set-MacGamingStatus $UI 'Some items need attention. Your restore information is saved below.' }
        }
        return $result
    } catch {
        if (-not $InlineResult) {
            $UI.Controls.ResultText.Text = $_.Exception.Message
            $UI.Controls.ResultPanel.Visibility = 'Visible'
            $UI.Controls.ResultPanel.IsExpanded = $true
            Set-MacGamingPage $UI 'Overview'
        }
        Set-MacGamingStatus $UI ('Could not finish: ' + $_.Exception.Message)
    } finally {
        $UI.Busy = $false
        $UI.Controls.MainWorkspace.IsEnabled = $true
        $UI.Controls.CloseWindow.IsEnabled = $true
        $UI.Window.Cursor = [System.Windows.Input.Cursors]::Arrow
    }
}

function Get-MacGamingExtraPreferenceNames {
    @('CloseBrowsers','CloseLaunchers','CloseCloudSync','CloseMediaApps','CloseDesktopExtras','PauseSearch','PausePrinting','PauseVR','PausePeripheralHelpers','ReduceMenuAnimation','ReduceTooltipAnimation','ReduceComboAnimation','DisableCursorShadow','DisableMouseAcceleration','PreventSleep')
}

function Register-MacControl {
    param($UI,[string]$Name,$Control)
    $Control.Name=$Name
    $UI.Controls[$Name]=$Control
    $UI.Window.RegisterName($Name,$Control)
    return $Control
}
function New-MacText {
    param($UI,[string]$Text,[int]$Size=13,[switch]$Secondary)
    $label=New-Object System.Windows.Controls.TextBlock
    $label.Text=$Text;$label.FontSize=$Size;$label.TextWrapping='Wrap'
    $label.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty,$(if($Secondary){'MacBrush7C8597'}else{'MacBrush202634'}))
    return $label
}
function New-MacButton {
    param($UI,[string]$Name,[string]$Text,[string]$Style='')
    $button=New-Object System.Windows.Controls.Button
    $button.Content=$Text
    if($Style){$button.Style=$UI.Window.Resources[$Style]}
    $button.Margin='0,0,8,8'
    Register-MacControl $UI $Name $button
}
function New-MacCard {
    param($UI,[string]$Title)
    $border=New-Object System.Windows.Controls.Border
    $border.Style=$UI.Window.Resources['Card'];$border.Margin='0,0,0,14'
    $panel=New-Object System.Windows.Controls.StackPanel
    $border.Child=$panel
    if($Title){$label=New-MacText $UI $Title 16;$label.FontWeight='SemiBold';$label.Margin='0,0,0,12';[void]$panel.Children.Add($label)}
    [pscustomobject]@{Border=$border;Panel=$panel}
}
function New-MacToggle {
    param($UI,[string]$Name,[string]$Text,[string]$Description='')
    $panel=New-Object System.Windows.Controls.StackPanel
    $check=New-Object System.Windows.Controls.CheckBox
    $check.Style=$UI.Window.Resources['Toggle'];$check.Content=$Text;$check.Margin='0,3,0,0'
    $null=Register-MacControl $UI $Name $check
    [void]$panel.Children.Add($check)
    if($Description){$hint=New-MacText $UI $Description 11 -Secondary;$hint.Margin='0,5,48,12';[void]$panel.Children.Add($hint)}else{$check.Margin='0,5,0,13'}
    return $panel
}
function New-MacPage {
    param($UI,[string]$Name,[string]$Title,[string]$Subtitle)
    $scroll=New-Object System.Windows.Controls.ScrollViewer
    $scroll.VerticalScrollBarVisibility='Auto';$scroll.HorizontalScrollBarVisibility='Disabled';$scroll.Visibility='Collapsed'
    $panel=New-Object System.Windows.Controls.StackPanel;$panel.Margin='0,0,7,5';$scroll.Content=$panel
    $heading=New-MacText $UI $Title 25;$heading.FontWeight='SemiBold';$heading.Margin='0,0,0,7'
    $hint=New-MacText $UI $Subtitle 13 -Secondary;$hint.Margin='0,0,0,20'
    [void]$panel.Children.Add($heading);[void]$panel.Children.Add($hint)
    $null=Register-MacControl $UI ('Page'+$Name) $scroll
    [void]$UI.Controls.PageOverview.Parent.Children.Add($scroll)
    return $panel
}

function Add-MacGamingV2Controls {
    param($UI)
    if($UI.V2Built){return};$UI.V2Built=$true
    $nav=$UI.Controls.NavOverview.Parent
    $profilesNav=New-MacButton $UI 'NavProfiles' 'Profiles' 'Nav'
    $settingsNav=New-MacButton $UI 'NavSettings' 'Settings' 'Nav'
    foreach($entry in @(@($profilesNav,[char]0xE8B7,'Profiles'),@($settingsNav,[char]0xE713,'Settings'))){
        $navContent=New-Object System.Windows.Controls.StackPanel;$navContent.Orientation='Horizontal'
        $navIcon=New-Object System.Windows.Controls.TextBlock;$navIcon.FontFamily='Segoe MDL2 Assets';$navIcon.Text=[string]$entry[1];$navIcon.Width=27
        $navText=New-Object System.Windows.Controls.TextBlock;$navText.Text=[string]$entry[2]
        [void]$navContent.Children.Add($navIcon);[void]$navContent.Children.Add($navText);$entry[0].Content=$navContent
    }
    $profilesNav.Margin='0,3';$settingsNav.Margin='0,3'
    $nav.Children.Insert(3,$profilesNav);[void]$nav.Children.Add($settingsNav)
    $UI.Controls.StartMedia.Content='Open profiles'
    $UI.Controls.StartMedia.ToolTip='Start or stop the media stack and your own app collections.'
    # ChatGPT is a profile component, not a separate session toggle.
    $extraPower=New-Object System.Windows.Controls.ComboBoxItem;$extraPower.Content='Use Balanced temporarily';[void]$UI.Controls.PowerMode.Items.Add($extraPower)

    $performance=$UI.Controls.PagePerformance.Content
    $categories=New-MacCard $UI 'Optional apps to close'
    foreach($entry in @(@('CloseBrowsers','Browsers'),@('CloseLaunchers','Unused launchers'),@('CloseCloudSync','Cloud sync apps'),@('CloseMediaApps','Media and music apps'),@('CloseDesktopExtras','Wallpaper and desktop extras'))){[void]$categories.Panel.Children.Add((New-MacToggle $UI $entry[0] $entry[1]))}
    $categoryHint=New-MacText $UI 'Steam, Discord, active games and protected Windows components stay available. ChatGPT is managed through Profiles.' 11 -Secondary;[void]$categories.Panel.Children.Add($categoryHint)
    $performance.Children.Insert(4,$categories.Border)
    $services=New-MacCard $UI 'Deeper trim selections'
    [void]$services.Panel.Children.Add((New-MacText $UI 'These apply when Deeper trim is enabled. Original states are restored afterward.' 11 -Secondary))
    foreach($entry in @(@('PauseSearch','Pause search indexing'),@('PausePrinting','Pause printing when the queue is empty'),@('PauseVR','Pause optional VR background services'),@('PausePeripheralHelpers','Pause optional peripheral helpers'))){[void]$services.Panel.Children.Add((New-MacToggle $UI $entry[0] $entry[1]))}
    $performance.Children.Insert(5,$services.Border)
    $extras=New-MacCard $UI 'Desktop, pointer and sleep preferences'
    foreach($entry in @(
        @('ReduceMenuAnimation','Reduce menu animations','A desktop visual preference; not a guaranteed game FPS improvement.'),
        @('ReduceTooltipAnimation','Reduce tooltip animations','Temporarily simplifies Windows tooltip effects.'),
        @('ReduceComboAnimation','Reduce dropdown animations','Temporarily simplifies Windows dropdown effects.'),
        @('DisableCursorShadow','Disable pointer shadow','Changes the desktop pointer appearance.'),
        @('DisableMouseAcceleration','Use unaccelerated Windows pointer motion','Raw-input games usually control mouse motion independently.'),
        @('PreventSleep','Prevent AC sleep during the session','Temporarily sets the plugged-in sleep timeout to Never, then restores it.')
    )){[void]$extras.Panel.Children.Add((New-MacToggle $UI $entry[0] $entry[1] $entry[2]))}
    $saveIndex=$performance.Children.IndexOf($UI.Controls.SavePreferences);$performance.Children.Insert($saveIndex,$extras.Border)

    # Games: wider discovery, explicit executable binding, and per-game NVIDIA settings.
    $games=$UI.Controls.PageGames.Content
    $discovery=New-Object System.Windows.Controls.WrapPanel;$discovery.Margin='0,0,0,12'
    [void]$discovery.Children.Add((New-MacButton $UI 'ScanGames' 'Scan installed games'))
    [void]$discovery.Children.Add((New-MacButton $UI 'AddScanFolder' '+ Scan folder'))
    $UI.Controls.AddGame.Content='+ Add EXE'
    $games.Children.Insert(1,$discovery)
    $binding=New-MacCard $UI 'Actual game executable'
    $exeHint=New-MacText $UI 'Bind the game process itself, not its launcher. NVIDIA settings and FPS measurement use this executable.' 11 -Secondary;$exeHint.Margin='0,0,0,11';[void]$binding.Panel.Children.Add($exeHint)
    $exeChoice=New-Object System.Windows.Controls.ComboBox;$exeChoice.DisplayMemberPath='Name';$exeChoice.Margin='0,0,0,10';$null=Register-MacControl $UI 'GameExecutableChoice' $exeChoice;[void]$binding.Panel.Children.Add($exeChoice)
    $exeActions=New-Object System.Windows.Controls.WrapPanel
    [void]$exeActions.Children.Add((New-MacButton $UI 'UseGameExecutable' 'Use selected EXE'))
    [void]$exeActions.Children.Add((New-MacButton $UI 'BrowseGameExecutable' 'Browse EXE...'))
    [void]$binding.Panel.Children.Add($exeActions)
    $exePath=New-MacText $UI 'Select a game to inspect its executable.' 10 -Secondary;$null=Register-MacControl $UI 'GameExecutablePath' $exePath;[void]$binding.Panel.Children.Add($exePath)
    [void]$games.Children.Add($binding.Border)
    $nvidia=New-MacCard $UI 'NVIDIA profile for this game'
    $gpuHint=New-MacText $UI 'Per-game presets: Performance favors speed with filtering shortcuts and possible tearing; Quality favors filtering with VSync, which may add latency. Restart the game. Changes persist until Restore GPU profile.' 11 -Secondary;$gpuHint.Margin='0,0,0,12';[void]$nvidia.Panel.Children.Add($gpuHint)
    $gpuButtons=New-Object System.Windows.Controls.WrapPanel
    [void]$gpuButtons.Children.Add((New-MacButton $UI 'NvidiaPerformance' 'Performance' 'Primary'))
    [void]$gpuButtons.Children.Add((New-MacButton $UI 'NvidiaQuality' 'Quality'))
    [void]$gpuButtons.Children.Add((New-MacButton $UI 'NvidiaRestore' 'Restore GPU profile'))
    [void]$nvidia.Panel.Children.Add($gpuButtons)
    $gpuStatus=New-MacText $UI 'Choose and bind an executable to load its driver profile.' 11 -Secondary;$gpuStatus.Margin='0,7,0,12';$null=Register-MacControl $UI 'NvidiaStatus' $gpuStatus;[void]$nvidia.Panel.Children.Add($gpuStatus)
    $custom=New-Object System.Windows.Controls.Expander;$custom.Header='Custom NVIDIA controls'
    $customPanel=New-Object System.Windows.Controls.StackPanel;$customPanel.Margin='0,10,0,0';$null=Register-MacControl $UI 'NvidiaCustomFields' $customPanel;$custom.Content=$customPanel
    [void]$nvidia.Panel.Children.Add($custom)
    $customApply=New-MacButton $UI 'NvidiaApplyCustom' 'Apply changed GPU controls';$customApply.IsEnabled=$false;$customApply.Margin='0,13,0,0';$customApply.HorizontalAlignment='Left';[void]$nvidia.Panel.Children.Add($customApply)
    $null=Register-MacControl $UI 'NvidiaCard' $nvidia.Border
    $gpuShortcut=New-MacButton $UI 'GoToNvidia' 'GPU controls';$gpuShortcut.HorizontalAlignment='Left';$gpuShortcut.Margin='0,12,0,0'
    $UI.Controls.LaunchGame.Parent.Children.Insert(3,$gpuShortcut)
    [void]$games.Children.Add($nvidia.Border)

    # Profiles: named collections with component checkboxes and custom executables.
    $profiles=New-MacPage $UI 'Profiles' 'Profiles' 'Start or stop a collection of apps, or apply a performance session.'
    $profileToolbar=New-Object System.Windows.Controls.WrapPanel
    [void]$profileToolbar.Children.Add((New-MacButton $UI 'NewProfile' '+ New profile'))
    [void]$profileToolbar.Children.Add((New-MacButton $UI 'RefreshProfiles' 'Refresh profiles'))
    [void]$profiles.Children.Add($profileToolbar)
    $profileList=New-Object System.Windows.Controls.ListBox;$profileList.DisplayMemberPath='Name';$profileList.ItemContainerStyle=$UI.Controls.GameList.ItemContainerStyle;$profileList.Height=110;$profileList.Margin='0,6,0,16';$profileList.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty,'MacBrushF6F7FA');$profileList.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty,'MacBrushE1E5EC');$null=Register-MacControl $UI 'ProfileList' $profileList;[void]$profiles.Children.Add($profileList)
    $profileCard=New-MacCard $UI ''
    $profileName=New-Object System.Windows.Controls.TextBox;$profileName.FontSize=17;$profileName.FontWeight='SemiBold';$profileName.Margin='0,0,0,9';$null=Register-MacControl $UI 'ProfileName' $profileName;[void]$profileCard.Panel.Children.Add($profileName)
    $profileDescription=New-Object System.Windows.Controls.TextBox;$profileDescription.TextWrapping='Wrap';$profileDescription.MinHeight=48;$profileDescription.Margin='0,0,0,13';$null=Register-MacControl $UI 'ProfileDescription' $profileDescription;[void]$profileCard.Panel.Children.Add($profileDescription)
    $profileActions=New-Object System.Windows.Controls.WrapPanel
    foreach($entry in @(@('ProfileStart','Start profile'),@('ProfileStop','Close profile'),@('ProfileApply','Apply Super Performance'),@('ProfileRestore','Restore session'))){[void]$profileActions.Children.Add((New-MacButton $UI $entry[0] $entry[1]))}
    [void]$profileCard.Panel.Children.Add($profileActions)
    $profileStatus=New-MacText $UI '' 11 -Secondary;$profileStatus.Margin='0,8,0,13';$null=Register-MacControl $UI 'ProfileStatus' $profileStatus;[void]$profileCard.Panel.Children.Add($profileStatus)
    $profileEditor=New-Object System.Windows.Controls.StackPanel;$null=Register-MacControl $UI 'ProfileEditor' $profileEditor
    [void]$profileEditor.Children.Add((New-MacText $UI 'Media services' 14))
    $mediaOptions=New-Object System.Windows.Controls.WrapPanel;$mediaOptions.Margin='0,8,0,16';$null=Register-MacControl $UI 'ProfileMediaOptions' $mediaOptions;[void]$profileEditor.Children.Add($mediaOptions)
    [void]$profileEditor.Children.Add((New-MacText $UI 'Optional apps' 14))
    $appOptions=New-Object System.Windows.Controls.WrapPanel;$appOptions.Margin='0,8,0,16';$null=Register-MacControl $UI 'ProfileAppOptions' $appOptions;[void]$profileEditor.Children.Add($appOptions)
    [void]$profileEditor.Children.Add((New-MacText $UI 'Your own executables' 14))
    $customList=New-Object System.Windows.Controls.ListBox;$customList.Height=85;$customList.Margin='0,8,0,10';$customList.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty,'MacBrushF6F7FA');$customList.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty,'MacBrushE1E5EC');$null=Register-MacControl $UI 'ProfileCustomExecutables' $customList;[void]$profileEditor.Children.Add($customList)
    $exeTools=New-Object System.Windows.Controls.WrapPanel
    [void]$exeTools.Children.Add((New-MacButton $UI 'ProfileAddExe' '+ Add EXE'))
    [void]$exeTools.Children.Add((New-MacButton $UI 'ProfileRemoveExe' 'Remove selected entry'))
    [void]$profileEditor.Children.Add($exeTools)
    [void]$profileEditor.Children.Add((New-MacText $UI 'Closing a custom app uses a normal close request. Unsaved-work prompts are left open.' 11 -Secondary))
    $saveProfile=New-MacButton $UI 'SaveProfile' 'Save profile' 'Primary';$saveProfile.HorizontalAlignment='Left';$saveProfile.Margin='0,15,0,0';[void]$profileEditor.Children.Add($saveProfile)
    [void]$profileCard.Panel.Children.Add($profileEditor);[void]$profiles.Children.Add($profileCard.Border)

    # Settings: appearance and startup live here, not in the sidebar.
    $settings=New-MacPage $UI 'Settings' 'Settings' 'Make the dashboard yours. Choose your appearance and startup behavior.'
    $appearanceParent=$UI.Controls.AppearanceTheme.Parent
    $appearanceParent.Children.Remove($UI.Controls.AppearanceTheme)
    if($appearanceParent.Children.Count -and $appearanceParent.Children[0] -is [System.Windows.Controls.TextBlock]){$appearanceParent.Children.RemoveAt(0)}
    foreach($theme in @('OLED','Midnight')){$item=New-Object System.Windows.Controls.ComboBoxItem;$item.Content=$theme;[void]$UI.Controls.AppearanceTheme.Items.Add($item)}
    $appearance=New-MacCard $UI 'Appearance'
    [void]$appearance.Panel.Children.Add($UI.Controls.AppearanceTheme)
    [void]$appearance.Panel.Children.Add((New-MacText $UI 'Dark, Light, OLED pure black, or Midnight. Appearance is saved immediately.' 11 -Secondary))
    [void]$settings.Children.Add($appearance.Border)
    $startup=New-MacCard $UI 'Startup and resource use'
    [void]$startup.Panel.Children.Add((New-MacToggle $UI 'OpenAtSignIn' 'Open the dashboard at sign-in' 'Starts the dashboard only. It does not close apps or activate a performance profile.'))
    [void]$startup.Panel.Children.Add((New-MacToggle $UI 'CloseAfterActivation' 'Close this window after activation' 'Closes after activation, or minimizes while an opt-in memory monitor or timer request needs it.'))
    [void]$startup.Panel.Children.Add((New-MacText $UI 'Readings refresh on demand. The optional memory monitor runs only when enabled and ends when the app closes.' 11 -Secondary))
    $saveSettings=New-MacButton $UI 'SaveSettings' 'Save settings' 'Primary';$saveSettings.HorizontalAlignment='Left';$saveSettings.Margin='0,15,0,0';[void]$startup.Panel.Children.Add($saveSettings)
    [void]$settings.Children.Add($startup.Border)

    $network=$UI.Controls.PageNetwork.Content
    $probeOptions=New-MacCard $UI 'Probe options'
    [void]$probeOptions.Panel.Children.Add((New-MacText $UI 'Reference endpoint only. This does not change your DNS server and does not measure game-server ping.' 11 -Secondary))
    $probeRow=New-Object System.Windows.Controls.Grid;$probeRow.Margin='0,12,0,0'
    foreach($width in @('*','16','*')){$column=New-Object System.Windows.Controls.ColumnDefinition;$column.Width=$width;[void]$probeRow.ColumnDefinitions.Add($column)}
    $samplePanel=New-Object System.Windows.Controls.StackPanel;[void]$samplePanel.Children.Add((New-MacText $UI 'Samples per endpoint' 11 -Secondary))
    $samples=New-Object System.Windows.Controls.ComboBox;$samples.Margin='0,6,0,0';$samples.ItemsSource=@(4,12,20);$samples.SelectedItem=12;$null=Register-MacControl $UI 'NetworkSamples' $samples;[void]$samplePanel.Children.Add($samples);[void]$probeRow.Children.Add($samplePanel)
    $endpointPanel=New-Object System.Windows.Controls.StackPanel;[System.Windows.Controls.Grid]::SetColumn($endpointPanel,2);[void]$endpointPanel.Children.Add((New-MacText $UI 'Internet reference' 11 -Secondary))
    $endpoint=New-Object System.Windows.Controls.ComboBox;$endpoint.Margin='0,6,0,0';$endpoint.ItemsSource=@('1.1.1.1','8.8.8.8','9.9.9.9');$endpoint.SelectedIndex=0;$null=Register-MacControl $UI 'NetworkEndpoint' $endpoint;[void]$endpointPanel.Children.Add($endpoint);[void]$probeRow.Children.Add($endpointPanel)
    [void]$probeOptions.Panel.Children.Add($probeRow);$network.Children.Insert(2,$probeOptions.Border)
}

function Update-MacGamingSelectedGame {
    param($UI)
    $game=$UI.Controls.GameList.SelectedItem
    if($UI.Controls.ContainsKey('CpuPriority')){Update-MacGamingCpu $UI}
    if($UI.Controls.ContainsKey('WindowsGpuPreference')){Update-MacGamingGpuPreference $UI}
    $UI.Controls.SelectedGameName.Text=if($game){[string]$game.Name}else{'Choose a game'}
    $UI.Controls.LaunchGame.IsEnabled=[bool]$game
    $UI.Controls.BenchmarkGame.IsEnabled=[bool]$game
    foreach($key in @('UseGameExecutable','BrowseGameExecutable')){$UI.Controls[$key].IsEnabled=[bool]$game}
    $UI.Controls.GameExecutableChoice.ItemsSource=$null
    $UI.Controls.NvidiaCustomFields.Children.Clear()
    $UI.Controls.NvidiaStatus.ToolTip=$null
    $UI.NvidiaProfile=$null;$UI.NvidiaExecutable='';$UI.NvidiaTouched=@{}
    foreach($key in @('NvidiaPerformance','NvidiaQuality','NvidiaRestore','NvidiaApplyCustom')){$UI.Controls[$key].IsEnabled=$false}
    if(-not $game){$UI.Controls.GameExecutablePath.Text='Select a game to inspect its executable.';$UI.Controls.NvidiaStatus.Text='Select a game to load its driver profile.';return}
    try{
        $candidates=@(Get-GamingGameExecutableCandidates -GameId $game.Id)
        $UI.Controls.GameExecutableChoice.ItemsSource=$candidates
        $bound=$candidates|Where-Object Path -eq $game.ExecutablePath|Select-Object -First 1
        if($bound){$UI.Controls.GameExecutableChoice.SelectedItem=$bound}elseif($candidates.Count){$UI.Controls.GameExecutableChoice.SelectedIndex=0}
        $UI.Controls.UseGameExecutable.IsEnabled=[bool]$candidates.Count
        $UI.Controls.GameExecutablePath.Text=if($game.ExecutablePath){[string]$game.ExecutablePath}else{'No executable bound. Choose the actual game EXE above.'}
        if(-not $game.ExecutablePath -or $game.NeedsExecutableSelection){$UI.Controls.NvidiaStatus.Text='Choose the actual game executable before changing its driver profile.';return}
        Update-MacGamingNvidia $UI ([string]$game.ExecutablePath)
    }catch{$UI.Controls.NvidiaStatus.Text=$_.Exception.Message;Set-MacGamingStatus $UI $_.Exception.Message}
}

function Update-MacGamingNvidia {
    param($UI,[string]$ExecutablePath)
    $UI.LoadingNvidia=$true
    try{
        $profile=Get-GamingNvidiaGameProfile -ExecutablePath $ExecutablePath
        $catalog=@(Get-GamingNvidiaSettingsCatalog)
        $UI.NvidiaProfile=$profile;$UI.NvidiaExecutable=$ExecutablePath;$UI.NvidiaTouched=@{}
        $UI.Controls.NvidiaCustomFields.Children.Clear()
        $UI.Controls.NvidiaPerformance.IsEnabled=[bool]$profile.CanApply
        $UI.Controls.NvidiaQuality.IsEnabled=[bool]$profile.CanApply
        $UI.Controls.NvidiaRestore.IsEnabled=[bool]$profile.CanRestore
        $UI.Controls.NvidiaApplyCustom.IsEnabled=$false
        $messages=@([string]$profile.ProfileName,[string]$profile.Message)
        if(-not $profile.CanApply -and -not $profile.Message){$messages+=@('This driver profile cannot be changed for this executable.')}
        $UI.Controls.NvidiaStatus.Text=(@($messages|Where-Object{$_}) -join "`r`n")
        $UI.Controls.NvidiaStatus.ToolTip=(@($profile.Notes|Where-Object{$_}|ForEach-Object{[string]$_}) -join "`r`n`r`n")
        foreach($setting in $catalog){
            $current=@($profile.Settings|Where-Object Id -eq $setting.Id)|Select-Object -First 1
            $row=New-Object System.Windows.Controls.StackPanel;$row.Margin='0,0,0,16'
            $label=New-MacText $UI ([string]$setting.Name) 13;$label.FontWeight='SemiBold';[void]$row.Children.Add($label)
            $description=[string]$setting.Description
            if($current -and -not $current.Supported){$description+=' Unavailable on this driver.'}
            $hint=New-MacText $UI $description 11 -Secondary;$hint.Margin='0,4,0,7';[void]$row.Children.Add($hint)
            $value=if($current -and $null -ne $current.Value){[string]$current.Value}else{[string]$setting.Default}
            if($setting.Kind -eq 'Integer'){
                $control=New-Object System.Windows.Controls.TextBox;$control.Text=$value
                $currentUI=$UI
                $control.Add_TextChanged({param($sender,$eventArgs) if($currentUI.LoadingNvidia){return};$currentUI.NvidiaTouched[[string]$sender.Tag]=[string]$sender.Text;$currentUI.Controls.NvidiaApplyCustom.IsEnabled=[bool]$currentUI.NvidiaProfile.CanApply}.GetNewClosure())
            }else{
                $control=New-Object System.Windows.Controls.ComboBox;$control.DisplayMemberPath='Name';$control.ItemsSource=@($setting.Options)
                $match=$setting.Options|Where-Object Value -eq $value|Select-Object -First 1
                if($match){$control.SelectedItem=$match}else{$control.SelectedIndex=-1}
                $currentUI=$UI
                $control.Add_SelectionChanged({param($sender,$eventArgs) if($currentUI.LoadingNvidia -or -not $sender.SelectedItem){return};$currentUI.NvidiaTouched[[string]$sender.Tag]=[string]$sender.SelectedItem.Value;$currentUI.Controls.NvidiaApplyCustom.IsEnabled=[bool]$currentUI.NvidiaProfile.CanApply}.GetNewClosure())
            }
            $control.Tag=[string]$setting.Id;$control.IsEnabled=([bool]$profile.CanApply -and $current -and [bool]$current.Supported)
            [void]$row.Children.Add($control);[void]$UI.Controls.NvidiaCustomFields.Children.Add($row)
        }
    }finally{$UI.LoadingNvidia=$false}
}

function Invoke-MacGamingNvidiaPreset {
    param($UI,[ValidateSet('Performance','Quality','Custom','Restore')][string]$Preset)
    if(-not $UI.NvidiaExecutable){return}
    if($Preset -eq 'Custom' -and -not $UI.NvidiaTouched.Count){Set-MacGamingStatus $UI 'Change a GPU control first.';return}
    $path=[string]$UI.NvidiaExecutable;$settings=@{};foreach($key in @($UI.NvidiaTouched.Keys)){$settings[$key]=$UI.NvidiaTouched[$key]}
    $operation={Invoke-GamingNvidiaProfile -ExecutablePath $path -Preset $Preset -Settings $settings}.GetNewClosure()
    $result=Invoke-MacGamingBusy $UI $operation 'Updating the selected game driver profile...' 'GPU profile updated. Restart the game to use it.' -InlineResult
    if($result){$message=[string]$result.Message;if($result.Success){Update-MacGamingNvidia $UI $path};if($message){$UI.Controls.NvidiaStatus.Text=$message}}
}

function Update-MacGamingProfiles {
    param($UI,[string]$SelectId='',$Snapshot=$null)
    if(-not $SelectId -and $UI.CurrentProfile){$SelectId=[string]$UI.CurrentProfile.Id}
    $UI.ProfileComponents=if($Snapshot){$Snapshot.Components}else{Get-GamingProfileComponents}
    $UI.Profiles=if($Snapshot){@($Snapshot.Profiles)}else{@(Get-GamingProfiles)}
    $UI.Controls.ProfileList.ItemsSource=$null;$UI.Controls.ProfileList.ItemsSource=$UI.Profiles
    $selected=$UI.Profiles|Where-Object Id -eq $SelectId|Select-Object -First 1
    if($selected){$UI.Controls.ProfileList.SelectedItem=$selected}elseif($UI.Profiles.Count){$UI.Controls.ProfileList.SelectedIndex=0}
    Update-MacGamingProfileEditor $UI $UI.Controls.ProfileList.SelectedItem
    if($UI.Controls.ContainsKey('SettingsProfileChoice')){Update-MacGamingSettingsProfiles $UI}
}

function Update-MacGamingProfileEditor {
    param($UI,$Profile)
    $UI.CurrentProfile=$Profile
    if(-not $Profile){return}
    $UI.Controls.ProfileName.Text=[string]$Profile.Name;$UI.Controls.ProfileDescription.Text=[string]$Profile.Description
    $performance=$Profile.Kind -eq 'Performance'
    foreach($name in @('ProfileStart','ProfileStop')){$UI.Controls[$name].Visibility=if($performance){'Collapsed'}else{'Visible'};$UI.Controls[$name].IsEnabled=[bool]$Profile.Id}
    foreach($name in @('ProfileApply','ProfileRestore')){$UI.Controls[$name].Visibility=if($performance){'Visible'}else{'Collapsed'}}
    $UI.Controls.ProfileStatus.Text=if($performance){'Selected apps and services close when you apply this profile. Session preferences are configured in Performance. Steam and Discord are preserved.'}else{'Save edits before starting or closing this collection. Running indicators update when you refresh profiles.'}
    foreach($group in @(@('Media','MediaKeys','ProfileMediaOptions'),@('Apps','AppIds','ProfileAppOptions'))){
        $panel=$UI.Controls[$group[2]];$panel.Children.Clear()
        foreach($item in @($UI.ProfileComponents.($group[0]))){
            $check=New-Object System.Windows.Controls.CheckBox;$check.Tag=[string]$item.Id;$check.Content=[string]$item.Name;$check.Margin='0,5,18,9';$check.MinWidth=155
            $check.IsChecked=([string]$item.Id -in @($Profile.($group[1])))
            $check.ToolTip=if($item.Running){'Currently running'}else{'Currently stopped'}
            [void]$panel.Children.Add($check)
        }
    }
    $UI.Controls.ProfileCustomExecutables.ItemsSource=@($Profile.CustomExecutables)
}

function Save-MacGamingProfile {
    param($UI)
    if(-not $UI.CurrentProfile){return}
    $profile=$UI.CurrentProfile|ConvertTo-Json -Depth 12|ConvertFrom-Json
    $profile.Name=[string]$UI.Controls.ProfileName.Text;$profile.Description=[string]$UI.Controls.ProfileDescription.Text
    $profile.MediaKeys=@($UI.Controls.ProfileMediaOptions.Children|Where-Object IsChecked|ForEach-Object{[string]$_.Tag})
    $profile.AppIds=@($UI.Controls.ProfileAppOptions.Children|Where-Object IsChecked|ForEach-Object{[string]$_.Tag})
    $profile.CustomExecutables=@($UI.Controls.ProfileCustomExecutables.ItemsSource)
    $saved=Save-GamingProfile -Profile $profile
    Update-MacGamingProfiles $UI ([string]$saved.Id)
    Set-MacGamingStatus $UI 'Profile saved. It will use these selections the next time you start or close it.'
}

function Invoke-MacGamingProfileAction {
    param($UI,[ValidateSet('Start','Stop','Apply','Restore')][string]$Operation)
    if(-not $UI.CurrentProfile.Id){return}
    $id=[string]$UI.CurrentProfile.Id;$close=($Operation -eq 'Apply' -and $UI.CurrentProfile.Kind -eq 'Performance')
    $action={Invoke-GamingProfile -ProfileId $id -Operation $Operation}.GetNewClosure()
    $result=Invoke-MacGamingBusy $UI $action ($Operation+' profile...') 'Profile action completed.' -InlineResult -RefreshDashboard -CloseOnSuccess:$close
    if($result){
        $lines=@($result.Results|ForEach-Object{(@($_.Name,$_.Status,$_.Message)|Where-Object{$_}) -join ' - '})
        $UI.Controls.ProfileStatus.Text=if($lines.Count){$lines -join "`r`n"}else{[string]$result.Message}
    }
}

function Update-MacGamingSettings {
    param($UI)
    $startup=Get-GamingStartupConfig;$UI.Controls.OpenAtSignIn.IsChecked=[bool]$startup.Enabled
    $preferences=Get-GamingPreferences;$UI.Controls.CloseAfterActivation.IsChecked=($preferences.CloseAfterActivation -ne $false)
}

function Save-MacGamingSettings {
    param($UI)
    $null=Set-GamingStartupConfig -Enabled ([bool]$UI.Controls.OpenAtSignIn.IsChecked)
    $preferences=Get-GamingPreferences
    $value=[bool]$UI.Controls.CloseAfterActivation.IsChecked
    if(-not $preferences.PSObject.Properties['CloseAfterActivation']){$preferences|Add-Member -NotePropertyName CloseAfterActivation -NotePropertyValue $value}else{$preferences.CloseAfterActivation=$value}
    $null=Set-GamingPreferences -Preferences $preferences;$UI.CloseAfterActivation=$value
    Set-MacGamingStatus $UI 'Settings saved. Sign-in startup opens only the dashboard.'
}

function New-MacInput {
    param($UI,[string]$Name,[string]$Label,[string]$Value='',[object[]]$Options=@())
    $panel=New-Object Windows.Controls.StackPanel;$panel.Margin='0,0,0,12'
    $hint=New-MacText $UI $Label 11 -Secondary;$hint.Margin='0,0,0,6';[void]$panel.Children.Add($hint)
    if($Options.Count){$input=New-Object Windows.Controls.ComboBox;$input.ItemsSource=$Options;$input.SelectedIndex=0}else{$input=New-Object Windows.Controls.TextBox;$input.Text=$Value}
    $null=Register-MacControl $UI $Name $input;[void]$panel.Children.Add($input)
    return $panel
}

function Add-MacGamingV3Controls {
    param($UI)
    if($UI.V3Built){return};$UI.V3Built=$true
    $nav=$UI.Controls.NavOverview.Parent
    $toolsNav=New-MacButton $UI 'NavTools' 'Tools' 'Nav';$toolsNav.Margin='0,3'
    $navContent=New-Object Windows.Controls.StackPanel;$navContent.Orientation='Horizontal'
    $icon=New-Object Windows.Controls.TextBlock;$icon.FontFamily='Segoe MDL2 Assets';$icon.Text=[char]0xE90F;$icon.Width=27
    $label=New-Object Windows.Controls.TextBlock;$label.Text='Tools';[void]$navContent.Children.Add($icon);[void]$navContent.Children.Add($label);$toolsNav.Content=$navContent
    $nav.Children.Insert($nav.Children.IndexOf($UI.Controls.NavSettings),$toolsNav)

    # Compact dashboard: session controls, current readings, then useful actions.
    $overview=$UI.Controls.PageOverview.Content
    $UI.Controls.HeroTitle.FontSize=25;$UI.Controls.HeroTitle.Margin='0,8,0,5'
    $UI.Controls.HeroSubtitle.FontSize=12;$UI.Controls.ToggleMode.Parent.Margin='0,15,0,0'
    $UI.Controls.HeroTitle.Parent.Parent.Padding='20'
    $widgets=New-Object Windows.Controls.Primitives.UniformGrid;$widgets.Columns=2;$widgets.Margin='0,0,0,14'
    $memory=New-MacCard $UI 'Memory toolkit';$memory.Border.Margin='0,0,12,0'
    $free=New-MacText $UI '-- GB available' 23;$free.FontWeight='SemiBold';$null=Register-MacControl $UI 'QuickMemoryAvailable' $free;[void]$memory.Panel.Children.Add($free)
    $standby=New-MacText $UI 'Standby cache: --' 11 -Secondary;$standby.Margin='0,5,0,14';$null=Register-MacControl $UI 'QuickMemoryStandby' $standby;[void]$memory.Panel.Children.Add($standby)
    $memoryButtons=New-Object Windows.Controls.WrapPanel
    [void]$memoryButtons.Children.Add((New-MacButton $UI 'QuickMemoryPurge' 'Clear standby'))
    [void]$memoryButtons.Children.Add((New-MacButton $UI 'QuickMemoryTools' 'Memory tools'))
    [void]$memory.Panel.Children.Add($memoryButtons)
    $memoryState=New-MacText $UI 'Monitor off · timer request off' 10 -Secondary;$null=Register-MacControl $UI 'QuickMemoryState' $memoryState;[void]$memory.Panel.Children.Add($memoryState)
    [void]$widgets.Children.Add($memory.Border)
    $quick=New-MacCard $UI 'Quick access';$quick.Border.Margin='0'
    foreach($entry in @(@('QuickGames','Game library & GPU profiles'),@('QuickNetwork','Test a game server'),@('QuickProfiles','Start or close an app profile'))){$b=New-MacButton $UI $entry[0] $entry[1];$b.HorizontalContentAlignment='Left';$b.Margin='0,0,0,8';[void]$quick.Panel.Children.Add($b)}
    [void]$widgets.Children.Add($quick.Border);$overview.Children.Insert(3,$widgets)

    # Replace the fixed four-item theme picker with the complete palette catalog.
    $UI.Controls.AppearanceTheme.Items.Clear();$UI.Controls.AppearanceTheme.DisplayMemberPath='Name';$UI.Controls.AppearanceTheme.ItemsSource=@(Get-GamingThemes);$UI.Controls.AppearanceTheme.MaxDropDownHeight=360
    $appearance=$UI.Controls.AppearanceTheme.Parent
    foreach($child in @($appearance.Children)){if($child -is [Windows.Controls.TextBlock] -and $child.Text -like 'Dark, Light*'){$appearance.Children.Remove($child)}}
    $swatches=New-Object Windows.Controls.WrapPanel;$swatches.Margin='0,0,0,11';$null=Register-MacControl $UI 'ThemeSwatches' $swatches
    foreach($n in 0..3){$swatch=New-Object Windows.Controls.Border;$swatch.Width=52;$swatch.Height=22;$swatch.CornerRadius=7;$swatch.Margin='0,0,8,0';[void]$swatches.Children.Add($swatch)}
    [void]$appearance.Children.Add($swatches)
    $themeDescription=New-MacText $UI '' 11 -Secondary;$null=Register-MacControl $UI 'ThemeDescription' $themeDescription;[void]$appearance.Children.Add($themeDescription)

    # Explicit per-game process controls; no global priority or core changes.
    $games=$UI.Controls.PageGames.Content
    $searchLabel=New-MacText $UI 'Search games' 11 -Secondary;$searchLabel.Margin='0,0,0,6'
    $searchParent=$UI.Controls.GameSearch.Parent;$searchParent.Children.Insert($searchParent.Children.IndexOf($UI.Controls.GameSearch),$searchLabel)
    $cpu=New-MacCard $UI 'CPU scheduling for this game';$null=Register-MacControl $UI 'CpuCard' $cpu.Border
    [void]$cpu.Panel.Children.Add((New-MacText $UI 'Choose a priority and logical processors for the selected executable. Start with all processors; restricting cores can reduce performance.' 11 -Secondary))
    $cpuFields=New-Object Windows.Controls.Grid;$cpuFields.Margin='0,12,0,0'
    foreach($width in @('*','14','*')){$column=New-Object Windows.Controls.ColumnDefinition;$column.Width=$width;[void]$cpuFields.ColumnDefinitions.Add($column)}
    $priority=New-MacInput $UI 'CpuPriority' 'Priority' -Options @('Unchanged','Idle','BelowNormal','Normal','AboveNormal','High');[void]$cpuFields.Children.Add($priority)
    $coreText=New-MacInput $UI 'CpuCoreSelection' 'Logical processors (blank = all)' '' ;[Windows.Controls.Grid]::SetColumn($coreText,2);[void]$cpuFields.Children.Add($coreText);[void]$cpu.Panel.Children.Add($cpuFields)
    [void]$cpu.Panel.Children.Add((New-MacText $UI 'Use numbers or ranges, for example 0-7, 10, 12. These are logical processors, not physical cores.' 11 -Secondary))
    $topology=New-MacText $UI '' 11 -Secondary;$topology.Margin='0,7,0,12';$null=Register-MacControl $UI 'CpuTopology' $topology;[void]$cpu.Panel.Children.Add($topology)
    [void]$cpu.Panel.Children.Add((New-MacToggle $UI 'CpuApplyOnLaunch' 'Apply saved CPU settings when launching here'))
    $cpuButtons=New-Object Windows.Controls.WrapPanel
    foreach($entry in @(@('CpuSave','Save for this game'),@('CpuApply','Apply to running game'),@('CpuRestore','Restore process settings'),@('CpuRefresh','Refresh processes'))){[void]$cpuButtons.Children.Add((New-MacButton $UI $entry[0] $entry[1]))}
    [void]$cpu.Panel.Children.Add($cpuButtons)
    $cpuStatus=New-MacText $UI 'Select and bind a game executable.' 11 -Secondary;$null=Register-MacControl $UI 'CpuStatus' $cpuStatus;[void]$cpu.Panel.Children.Add($cpuStatus)
    $games.Children.Insert($games.Children.IndexOf($UI.Controls.NvidiaCard),$cpu.Border)
    $cpuShortcut=New-MacButton $UI 'GoToCpu' 'CPU controls';$cpuShortcut.HorizontalAlignment='Left';[void]$UI.Controls.LaunchGame.Parent.Children.Add($cpuShortcut)
    $networkShortcut=New-MacButton $UI 'GoToGameNetwork' 'Test this game connection';$networkShortcut.HorizontalAlignment='Left';[void]$UI.Controls.LaunchGame.Parent.Children.Add($networkShortcut)
    $scanInfo=New-MacText $UI 'Missing a portable game? Add its EXE or a specific games folder. Scans are bounded and skip Windows and helper executables.' 11 -Secondary;$scanInfo.Margin='0,0,0,14';$null=Register-MacControl $UI 'ScanInfo' $scanInfo;$games.Children.Insert(2,$scanInfo)

    # Saved endpoint selector and custom targets, keeping the existing result cards.
    $network=$UI.Controls.PageNetwork.Content
    $oldProbe=$UI.Controls.NetworkSamples.Parent.Parent.Parent.Parent
    if($oldProbe -and $network.Children.Contains($oldProbe)){$network.Children.Remove($oldProbe)}
    $servers=New-MacCard $UI 'Game servers & custom targets'
    [void]$servers.Panel.Children.Add((New-MacInput $UI 'NetworkGame' 'Game' -Options @('All games')))
    $UI.Controls.NetworkGame.DisplayMemberPath='Name'
    [void]$servers.Panel.Children.Add((New-MacInput $UI 'NetworkServer' 'Saved or published endpoint' -Options @('Choose a target')))
    $UI.Controls.NetworkServer.DisplayMemberPath='Name'
    $serverButtons=New-Object Windows.Controls.WrapPanel
    foreach($entry in @(@('NetworkRefreshServers','Refresh servers'),@('NetworkActiveEndpoints','Inspect running game connections'),@('NetworkRemoveServer','Remove saved endpoint'))){[void]$serverButtons.Children.Add((New-MacButton $UI $entry[0] $entry[1]))}
    [void]$servers.Panel.Children.Add($serverButtons)
    $guidance=New-MacText $UI 'Published region probes approximate the route. Use the game network overlay for the actual match RTT.' 11 -Secondary;$guidance.Margin='0,4,0,12';$null=Register-MacControl $UI 'NetworkGuidance' $guidance;[void]$servers.Panel.Children.Add($guidance)
    [void]$servers.Panel.Children.Add((New-MacInput $UI 'NetworkHost' 'Server hostname or IP address' '1.1.1.1'))
    $probeGrid=New-Object Windows.Controls.Primitives.UniformGrid;$probeGrid.Columns=3
    foreach($entry in @(@('NetworkProtocol','Probe type',@('ICMP','TCP')),@('NetworkPort','TCP port',@()),@('NetworkSampleChoice','Samples',@(4,12,20)))){
        $field=New-MacInput $UI $entry[0] $entry[1] '443' -Options $entry[2];$field.Margin='0,0,10,12';[void]$probeGrid.Children.Add($field)
    }
    $UI.Controls.NetworkSampleChoice.SelectedItem=12;$UI.Controls.NetworkPort.IsEnabled=$false;[void]$servers.Panel.Children.Add($probeGrid)
    [void]$servers.Panel.Children.Add((New-MacInput $UI 'NetworkServerName' 'Name for a saved endpoint' 'My server'))
    $serverActions=New-Object Windows.Controls.WrapPanel
    $UI.Controls.RunNetworkTest.Parent.Children.Remove($UI.Controls.RunNetworkTest)
    $UI.Controls.RunNetworkTest.Margin='0,0,8,8';$UI.Controls.RunNetworkTest.Content='Measure connection'
    [void]$serverActions.Children.Add($UI.Controls.RunNetworkTest)
    [void]$serverActions.Children.Add((New-MacButton $UI 'NetworkSaveServer' 'Save endpoint'))
    [void]$servers.Panel.Children.Add($serverActions)
    $network.Children.Insert(2,$servers.Border)

    # Settings snapshots are independent of app launch / close profiles.
    $profiles=$UI.Controls.PageProfiles.Content
    $snapshots=New-MacCard $UI 'Settings profiles';$null=Register-MacControl $UI 'SettingsProfilesCard' $snapshots.Border
    [void]$snapshots.Panel.Children.Add((New-MacText $UI 'Save the whole app or one area. Applying a profile changes saved preferences; it does not close apps or immediately apply driver tweaks.' 11 -Secondary))
    $saved=New-Object Windows.Controls.ComboBox;$saved.DisplayMemberPath='Name';$saved.Margin='0,12,0,12';$null=Register-MacControl $UI 'SettingsProfileChoice' $saved;[void]$snapshots.Panel.Children.Add($saved)
    $scopeGrid=New-Object Windows.Controls.Grid
    foreach($width in @('*','14','*')){$column=New-Object Windows.Controls.ColumnDefinition;$column.Width=$width;[void]$scopeGrid.ColumnDefinitions.Add($column)}
    $nameInput=New-MacInput $UI 'SettingsProfileName' 'New profile name' 'My setup';[void]$scopeGrid.Children.Add($nameInput)
    $scopeInput=New-MacInput $UI 'SettingsProfileScope' 'Scope' -Options @('All','Overview','Performance','Games','Network','Profiles','Appearance','Memory','Tools','Settings');[Windows.Controls.Grid]::SetColumn($scopeInput,2);[void]$scopeGrid.Children.Add($scopeInput);[void]$snapshots.Panel.Children.Add($scopeGrid)
    $snapshotButtons=New-Object Windows.Controls.WrapPanel
    foreach($entry in @(@('SettingsProfileSave','Save current settings'),@('SettingsProfileApply','Apply'),@('SettingsProfileExport','Export'),@('SettingsProfileImport','Import'),@('SettingsProfileRemove','Remove'))){[void]$snapshotButtons.Children.Add((New-MacButton $UI $entry[0] $entry[1]))}
    [void]$snapshots.Panel.Children.Add($snapshotButtons)
    $snapshotStatus=New-MacText $UI '' 11 -Secondary;$null=Register-MacControl $UI 'SettingsProfileStatus' $snapshotStatus;[void]$snapshots.Panel.Children.Add($snapshotStatus)
    $profiles.Children.Insert(2,$snapshots.Border)
    $perApp=New-MacCard $UI 'Individual background apps'
    [void]$perApp.Panel.Children.Add((New-MacText $UI 'Choose individual apps in your Super Performance profile. Each collection can include your own executables as well as detected apps.' 11 -Secondary))
    $editApps=New-MacButton $UI 'EditBackgroundApps' 'Choose apps to close';$editApps.HorizontalAlignment='Left';$editApps.Margin='0,12,0,0';[void]$perApp.Panel.Children.Add($editApps)
    $UI.Controls.PagePerformance.Content.Children.Insert(4,$perApp.Border)

    # Memory toolkit and direct access to the integrated Windows tools.
    $tools=New-MacPage $UI 'Tools' 'Tools' 'Memory controls, diagnostics, and an extended Windows toolbox.'
    $memoryCard=New-MacCard $UI 'Memory & timer toolkit';$null=Register-MacControl $UI 'MemoryToolsCard' $memoryCard.Border
    $readings=New-MacText $UI 'Refresh to read memory and timer information.' 15;$null=Register-MacControl $UI 'MemoryReadings' $readings;[void]$memoryCard.Panel.Children.Add($readings)
    $memoryHint=New-MacText $UI 'Standby memory is reusable cache. Clear it to investigate memory pressure, not as a routine FPS boost.' 11 -Secondary;$memoryHint.Margin='0,8,0,14';[void]$memoryCard.Panel.Children.Add($memoryHint)
    $memoryActions=New-Object Windows.Controls.WrapPanel
    [void]$memoryActions.Children.Add((New-MacButton $UI 'MemoryRefresh' 'Refresh readings'))
    [void]$memoryActions.Children.Add((New-MacButton $UI 'MemoryPurge' 'Clear standby now'))
    [void]$memoryCard.Panel.Children.Add($memoryActions)
    $thresholds=New-Object Windows.Controls.Primitives.UniformGrid;$thresholds.Columns=3
    foreach($entry in @(@('MemoryStandbyThreshold','Standby above (MB)','1024'),@('MemoryAvailableThreshold','Available below (MB)','1024'),@('MemoryInterval','Check every (seconds)','30'))){$field=New-MacInput $UI $entry[0] $entry[1] $entry[2];$field.Margin='0,10,10,8';[void]$thresholds.Children.Add($field)}
    [void]$memoryCard.Panel.Children.Add($thresholds)
    [void]$memoryCard.Panel.Children.Add((New-MacToggle $UI 'MemoryMonitorToggle' 'Enable threshold monitor' 'Only purges when both conditions are met. Stops when this dashboard closes.'))
    [void]$memoryCard.Panel.Children.Add((New-MacInput $UI 'MemoryTimerMilliseconds' 'Timer request (0.5-16 ms, in 0.5 ms steps)' '1'))
    [void]$memoryCard.Panel.Children.Add((New-MacToggle $UI 'MemoryTimerToggle' 'Enable timer request' 'Whole milliseconds use a per-app multimedia request. Fractional values such as 0.5 ms use an experimental native request. Windows may clamp the value; the observed timer does not prove a game uses it or gains lower latency.'))
    $memorySave=New-MacButton $UI 'MemorySave' 'Save memory preferences';$memorySave.HorizontalAlignment='Left';[void]$memoryCard.Panel.Children.Add($memorySave)
    $memoryStatus=New-MacText $UI '' 11 -Secondary;$null=Register-MacControl $UI 'MemoryToolStatus' $memoryStatus;[void]$memoryCard.Panel.Children.Add($memoryStatus)
    [void]$tools.Children.Add($memoryCard.Border)
    $optimizer=New-MacCard $UI 'Windows tools'
    [void]$optimizer.Panel.Children.Add((New-MacText $UI 'Cleanup, startup, DNS, apps and Windows configuration, built into this workspace. System changes use their own controls and are separate from session restore.' 11 -Secondary))
    $optimizerInfo=New-MacText $UI '' 11 -Secondary;$optimizerInfo.Margin='0,8,0,12';$null=Register-MacControl $UI 'OptimizerInfo' $optimizerInfo;[void]$optimizer.Panel.Children.Add($optimizerInfo)
    [void]$optimizer.Panel.Children.Add((New-MacButton $UI 'OptimizerLaunch' 'Open Windows tools' 'Primary'))
    [void]$optimizer.Panel.Children.Add((New-MacInput $UI 'OptimizerSearch' 'Find a feature' ''))
    [void]$optimizer.Panel.Children.Add((New-MacInput $UI 'OptimizerCategory' 'Category' -Options @('All')))
    $featureList=New-Object Windows.Controls.ListBox;$featureList.DisplayMemberPath='Name';$featureList.Height=190;$featureList.ItemContainerStyle=$UI.Controls.GameList.ItemContainerStyle;$featureList.SetResourceReference([Windows.Controls.Control]::BackgroundProperty,'MacBrushF6F7FA');$featureList.SetResourceReference([Windows.Controls.Control]::BorderBrushProperty,'MacBrushE1E5EC');$null=Register-MacControl $UI 'OptimizerFeatures' $featureList;[void]$optimizer.Panel.Children.Add($featureList)
    $featureHint=New-MacText $UI '' 11 -Secondary;$featureHint.Margin='0,10,0,0';$null=Register-MacControl $UI 'OptimizerFeatureInfo' $featureHint;[void]$optimizer.Panel.Children.Add($featureHint)
    [void]$optimizer.Panel.Children.Add((New-MacButton $UI 'OptimizerOpenFeature' 'Open selected feature'))
    $UI.Controls.OptimizerOpenFeature.IsEnabled=$false
    [void]$tools.Children.Add($optimizer.Border)
    Add-MacGamingWindowsToolsControls $UI
    Add-MacGamingWindowsSettingsControls $UI
}

function Add-MacGamingWindowsSettingsControls {
    param($UI)
    $card=New-MacCard $UI 'Windows gaming settings';$null=Register-MacControl $UI 'WindowsSettingsCard' $card.Border
    [void]$card.Panel.Children.Add((New-MacText $UI 'Choose Windows preferences here. Apply saves them until you change or restore them; these controls are separate from a temporary gaming session.' 11 -Secondary))
    $fields=New-Object Windows.Controls.Primitives.UniformGrid;$fields.Columns=3;$fields.Margin='0,12,0,0'
    foreach($entry in @(@('WindowsGameMode','Game Mode'),@('WindowsHardwareScheduling','GPU scheduling'),@('WindowsBackgroundCapture','Background capture'))){$field=New-MacInput $UI $entry[0] $entry[1] -Options @('Default','Enabled','Disabled');$field.Margin='0,0,10,12';[void]$fields.Children.Add($field)}
    [void]$card.Panel.Children.Add($fields)
    [void]$card.Panel.Children.Add((New-MacText $UI 'GPU scheduling depends on your driver and Windows version. Its requested preference needs administrator access and a restart to take effect.' 11 -Secondary))
    $actions=New-Object Windows.Controls.WrapPanel;$actions.Margin='0,12,0,0'
    foreach($entry in @(@('WindowsSettingsApply','Apply preferences'),@('WindowsSettingsRestore','Restore previous preferences'),@('WindowsSettingsRefresh','Refresh'),@('WindowsSettingsAdministrator','Restart as administrator'))){[void]$actions.Children.Add((New-MacButton $UI $entry[0] $entry[1]))}
    [void]$card.Panel.Children.Add($actions)
    $state=New-MacText $UI 'Open this page to load Windows preferences.' 11 -Secondary;$null=Register-MacControl $UI 'WindowsSettingsStatus' $state;[void]$card.Panel.Children.Add($state)
    $display=New-MacInput $UI 'WindowsDisplayMode' 'Primary display refresh rate · current resolution' -Options @('Refresh to load display modes');$display.Margin='0,16,0,8';$UI.Controls.WindowsDisplayMode.DisplayMemberPath='Label';[void]$card.Panel.Children.Add($display)
    $displayActions=New-Object Windows.Controls.WrapPanel
    [void]$displayActions.Children.Add((New-MacButton $UI 'WindowsDisplayPreview' 'Preview refresh rate'))
    [void]$displayActions.Children.Add((New-MacButton $UI 'WindowsDisplayRefresh' 'Refresh display modes'))
    [void]$card.Panel.Children.Add($displayActions)
    [void]$card.Panel.Children.Add((New-MacText $UI 'A preview reverts after 15 seconds unless you choose Keep. Resolution, orientation and color depth stay the same.' 11 -Secondary))
    $UI.Controls.PagePerformance.Content.Children.Insert(3,$card.Border)
    $gpu=New-MacCard $UI 'Windows GPU preference';$null=Register-MacControl $UI 'WindowsGpuCard' $gpu.Border
    [void]$gpu.Panel.Children.Add((New-MacText $UI 'Choose which GPU Windows should prefer for this executable. This is useful on systems with integrated and dedicated graphics; the game or driver can override it.' 11 -Secondary))
    $field=New-MacInput $UI 'WindowsGpuPreference' 'GPU choice for the selected game' -Options @('Default','PowerSaving','HighPerformance');$field.Margin='0,12,0,8';[void]$gpu.Panel.Children.Add($field)
    $gpuActions=New-Object Windows.Controls.WrapPanel
    foreach($entry in @(@('WindowsGpuApply','Apply to this game'),@('WindowsGpuRestore','Restore previous preference'))){$button=New-MacButton $UI $entry[0] $entry[1];$button.IsEnabled=$false;[void]$gpuActions.Children.Add($button)}
    [void]$gpu.Panel.Children.Add($gpuActions)
    $gpuStatus=New-MacText $UI 'Choose and bind a game executable first.' 11 -Secondary;$null=Register-MacControl $UI 'WindowsGpuStatus' $gpuStatus;[void]$gpu.Panel.Children.Add($gpuStatus)
    $games=$UI.Controls.PageGames.Content;$games.Children.Insert($games.Children.IndexOf($UI.Controls.CpuCard),$gpu.Border)
}

function Update-MacGamingWindowsSettings {
    param($UI,[switch]$IncludeDisplay,$Snapshot=$null)
    if(Get-Command Get-GamingWindowsSettings -ErrorAction SilentlyContinue){
        $state=if($Snapshot){$Snapshot.State}else{Get-GamingWindowsSettings}
        foreach($pair in @(@('WindowsGameMode','GameMode'),@('WindowsHardwareScheduling','HardwareScheduling'),@('WindowsBackgroundCapture','BackgroundCapture'))){$UI.Controls[$pair[0]].SelectedItem=[string]$state.($pair[1])}
        $UI.Controls.WindowsSettingsAdministrator.Visibility=if($state.IsAdministrator){'Collapsed'}else{'Visible'}
        $UI.Controls.WindowsSettingsStatus.Text='Current Windows preferences loaded. Default lets Windows decide.'
    }
    if($IncludeDisplay -and (Get-Command Get-GamingDisplayModes -ErrorAction SilentlyContinue)){
        $modes=if($Snapshot){@($Snapshot.Modes)}else{@(Get-GamingDisplayModes)};$UI.Controls.WindowsDisplayMode.ItemsSource=$modes
        $current=$modes|Where-Object IsCurrent|Select-Object -First 1
        if($current){$UI.Controls.WindowsDisplayMode.SelectedItem=$current}elseif($modes.Count){$UI.Controls.WindowsDisplayMode.SelectedIndex=0}
        $UI.Controls.WindowsDisplayPreview.IsEnabled=($modes.Count -gt 0)
    }
}

function Update-MacGamingGpuPreference {
    param($UI)
    $game=$UI.Controls.GameList.SelectedItem
    $ready=[bool]($game -and $game.ExecutablePath -and -not $game.NeedsExecutableSelection)
    foreach($name in @('WindowsGpuPreference','WindowsGpuApply','WindowsGpuRestore')){$UI.Controls[$name].IsEnabled=$ready}
    $UI.Controls.WindowsGpuPreference.SelectedItem='Default'
    $UI.Controls.WindowsGpuStatus.Text='Choose and bind a game executable first.'
    if($ready -and (Get-Command Get-GamingGpuPreference -ErrorAction SilentlyContinue)){
        try{$preference=Get-GamingGpuPreference -ExecutablePath ([string]$game.ExecutablePath);$UI.Controls.WindowsGpuPreference.SelectedItem=[string]$preference.Preference;$UI.Controls.WindowsGpuStatus.Text='Applies only to '+[string]$game.Name+'. Restart the game after changing this preference.'}catch{$UI.Controls.WindowsGpuStatus.Text=$_.Exception.Message}
    }
}

function Show-MacGamingDisplayConfirmation {
    param($UI,$Result)
    $deadline=[datetime]::UtcNow.AddSeconds([int]$Result.TimeoutSeconds)
    if($Result.DeadlineUtc){$deadline=([datetime]::Parse([string]$Result.DeadlineUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime()}
    if($deadline -le [datetime]::UtcNow){$null=Revert-GamingDisplayMode -Token ([string]$Result.ConfirmationToken);Update-MacGamingWindowsSettings $UI -IncludeDisplay;$UI.Controls.WindowsSettingsStatus.Text='Display preview expired and was reverted.';return}
    $dialog=New-Object Windows.Window;$dialog.Owner=$UI.Window;$dialog.Title='Keep this refresh rate?';$dialog.Width=430;$dialog.Height=220;$dialog.ResizeMode='NoResize';$dialog.WindowStartupLocation='CenterOwner';$dialog.ShowInTaskbar=$false
    $dialog.Resources=$UI.Window.Resources
    $dialog.Background=$UI.Window.Resources['MacBrushFFFFFF'];$dialog.Foreground=$UI.Window.Resources['MacBrush202634'];$dialog.FontFamily=$UI.Window.FontFamily
    $panel=New-Object Windows.Controls.StackPanel;$panel.Margin=24;$dialog.Content=$panel
    $heading=New-Object Windows.Controls.TextBlock;$heading.Text='Keep this refresh rate?';$heading.FontSize=20;$heading.FontWeight='SemiBold';[void]$panel.Children.Add($heading)
    $countdown=New-Object Windows.Controls.TextBlock;$countdown.Margin='0,12,0,20';$countdown.TextWrapping='Wrap';[void]$panel.Children.Add($countdown)
    $actions=New-Object Windows.Controls.StackPanel;$actions.Orientation='Horizontal';$actions.HorizontalAlignment='Right';[void]$panel.Children.Add($actions)
    $revert=New-Object Windows.Controls.Button;$revert.Content='Revert';$revert.Padding='18,9';$revert.Margin='0,0,10,0';[void]$actions.Children.Add($revert)
    $keep=New-Object Windows.Controls.Button;$keep.Content='Keep';$keep.Padding='18,9';$keep.Style=$UI.Window.Resources['Primary'];[void]$actions.Children.Add($keep)
    $state=@{Confirmed=$false;Deadline=$deadline;Token=[string]$Result.ConfirmationToken;Message='Display preview reverted.'}
    $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(250)
    $tick={
        $remaining=[math]::Max(0,[math]::Ceiling(($state.Deadline-[datetime]::UtcNow).TotalSeconds))
        $countdown.Text='Your previous refresh rate returns in '+$remaining+' seconds unless you keep this change.'
        if($remaining -le 0){$dialog.Close()}
    }.GetNewClosure()
    $timer.Add_Tick($tick)
    $revert.Add_Click({$dialog.Close()}.GetNewClosure())
    $keep.Add_Click({try{$reply=Confirm-GamingDisplayMode -Token $state.Token;if($reply.Success){$state.Confirmed=$true;$state.Message=[string]$reply.Message;$dialog.Close()}else{$countdown.Text=[string]$reply.Message}}catch{$countdown.Text=$_.Exception.Message}}.GetNewClosure())
    $dialog.Add_Closing({$timer.Stop();if(-not $state.Confirmed){try{$null=Revert-GamingDisplayMode -Token $state.Token}catch{}}}.GetNewClosure())
    $countdown.Text='Keep this refresh rate, or let the preview return to your previous setting.'
    try{$timer.Start();[void]$dialog.ShowDialog()}finally{$timer.Stop()}
    Update-MacGamingWindowsSettings $UI -IncludeDisplay
    $UI.Controls.WindowsSettingsStatus.Text=$state.Message
}

function Update-MacGamingMemory {
    param($UI,[switch]$LoadPreferences)
    if(-not(Get-Command Get-GamingMemorySnapshot -ErrorAction SilentlyContinue)){return}
    $m=Get-GamingMemorySnapshot;$runtime=Get-GamingMemoryRuntime
    $UI.Controls.QuickMemoryAvailable.Text=(Format-MacGamingNumber ($m.AvailableMB/1024) 1)+' GB available'
    $standby=if($m.StandbyAvailable){(Format-MacGamingNumber ($m.StandbyMB/1024) 1)+' GB'}else{'unavailable'}
    $UI.Controls.QuickMemoryStandby.Text='Standby cache: '+$standby
    $UI.Controls.MemoryReadings.Text='Available '+(Format-MacGamingNumber ($m.AvailableMB/1024) 1)+' GB   ·   Standby '+$standby+'   ·   Timer '+(Format-MacGamingNumber $m.CurrentTimerMs 2)+' ms'
    $UI.Controls.QuickMemoryState.Text='Monitor '+$(if($runtime.MonitorRunning){'on'}else{'off'})+' · timer request '+$(if($runtime.TimerEnabled){'on'}else{'off'})
    $UI.LoadingMemory=$true
    try{
        $UI.Controls.MemoryMonitorToggle.IsChecked=[bool]$runtime.MonitorRunning;$UI.Controls.MemoryTimerToggle.IsChecked=[bool]$runtime.TimerEnabled
        if($LoadPreferences){$p=Get-GamingMemoryPreferences;$UI.Controls.MemoryStandbyThreshold.Text=[string]$p.StandbyThresholdMB;$UI.Controls.MemoryAvailableThreshold.Text=[string]$p.AvailableThresholdMB;$UI.Controls.MemoryInterval.Text=[string]$p.IntervalSeconds;$UI.Controls.MemoryTimerMilliseconds.Text=[string]$p.TimerMilliseconds}
    }finally{$UI.LoadingMemory=$false}
    if($runtime.LastMessage){$UI.Controls.MemoryToolStatus.Text=[string]$runtime.LastMessage}
}

function Save-MacGamingMemory {
    param($UI)
    $timer=ConvertFrom-MacTimerValue ([string]$UI.Controls.MemoryTimerMilliseconds.Text)
    $result=Save-GamingMemoryPreferences -StandbyThresholdMB ([int]$UI.Controls.MemoryStandbyThreshold.Text) -AvailableThresholdMB ([int]$UI.Controls.MemoryAvailableThreshold.Text) -IntervalSeconds ([int]$UI.Controls.MemoryInterval.Text) -TimerMilliseconds $timer
    $UI.Controls.MemoryToolStatus.Text=if($result.Message){[string]$result.Message}else{'Memory preferences saved.'}
    return $result
}

function ConvertFrom-MacTimerValue {
    param([string]$Text)
    $value=0.0
    $valid=[double]::TryParse($Text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::CurrentCulture,[ref]$value)
    if(-not $valid){$valid=[double]::TryParse($Text,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$value)}
    if(-not $valid -or [double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0.5 -or $value -gt 16 -or [math]::Abs(($value*2)-[math]::Round($value*2)) -gt 0.00001){throw 'Enter a timer period from 0.5 to 16 ms in 0.5 ms steps.'}
    return $value
}

function Update-MacGamingCpu {
    param($UI)
    if(-not $UI.Controls.ContainsKey('CpuPriority')){return}
    $game=$UI.Controls.GameList.SelectedItem
    foreach($name in @('CpuSave','CpuApply','CpuRestore','CpuRefresh')){$UI.Controls[$name].IsEnabled=[bool]($game -and $game.ExecutablePath)}
    if(-not $game){return}
    try{
        $topology=Get-GamingCpuTopology;$preference=Get-GamingProcessPreference -GameId $game.Id
        $UI.Controls.CpuPriority.SelectedItem=[string]$preference.Priority;$UI.Controls.CpuCoreSelection.Text=@($preference.LogicalProcessors)-join ', ';$UI.Controls.CpuApplyOnLaunch.IsChecked=[bool]$preference.ApplyOnLaunch
        $UI.Controls.CpuTopology.Text=[string]$topology.LogicalProcessorCount+' logical processors. '+[string]$topology.Message
        $UI.Controls.CpuCoreSelection.IsEnabled=[bool]$topology.SupportsAffinity
        $targets=@(Get-GamingProcessTargets -GameId $game.Id)
        $UI.Controls.CpuStatus.Text=if($targets.Count){(@($targets|ForEach-Object{$_.Name+' · PID '+$_.ProcessId+' · '+$_.Priority})-join "`r`n")}elseif($game.ExecutablePath){'Game is not running. Save preferences now, or start it before applying.'}else{'Choose the actual game executable before using CPU controls.'}
    }catch{$UI.Controls.CpuStatus.Text=$_.Exception.Message}
}

function ConvertFrom-MacCpuSelection {
    param([string]$Text)
    if([string]::IsNullOrWhiteSpace($Text)){return @()}
    $values=New-Object 'System.Collections.Generic.HashSet[int]'
    foreach($part in $Text.Split(',')){
        $token=$part.Trim()
        if($token -match '^(\d{1,4})\s*-\s*(\d{1,4})$'){$first=[int]$Matches[1];$last=[int]$Matches[2];if($last -lt $first -or $last -gt 1023){throw 'Use ascending processor ranges within 0-1023.'};foreach($n in $first..$last){[void]$values.Add($n)}}
        elseif($token -match '^\d{1,4}$'){$n=[int]$token;if($n -gt 1023){throw 'Processor numbers must be 0-1023.'};[void]$values.Add($n)}
        else{throw 'Enter processor numbers or ranges, such as 0-7, 10. Leave blank to use all.'}
    }
    return @($values|Sort-Object)
}

function Save-MacGamingCpu {
    param($UI)
    $game=$UI.Controls.GameList.SelectedItem;if(-not $game){return}
    $cores=@(ConvertFrom-MacCpuSelection ([string]$UI.Controls.CpuCoreSelection.Text))
    $result=Save-GamingProcessPreference -GameId $game.Id -Priority ([string]$UI.Controls.CpuPriority.SelectedItem) -LogicalProcessors $cores -ApplyOnLaunch ([bool]$UI.Controls.CpuApplyOnLaunch.IsChecked)
    $UI.Controls.CpuStatus.Text=[string]$result.Message;return $result
}

function Update-MacGamingServers {
    param($UI,[switch]$ReloadGames,[switch]$ActiveConnections,[switch]$LoadPreferences,$CachedGames=$null)
    if($UI.LoadingServers){return};$UI.LoadingServers=$true
    $savedProbe=$null
    try{
        if(($LoadPreferences -or -not $UI.NetworkLoaded) -and (Get-Command Get-GamingNetworkPreferences -ErrorAction SilentlyContinue)){$savedProbe=Get-GamingNetworkPreferences}
        if($ReloadGames -or -not $UI.Controls.NetworkGame.ItemsSource){$selected=if($savedProbe){[string]$savedProbe.GameId}else{[string]$UI.Controls.NetworkGame.SelectedItem.Id};$games=@([pscustomobject]@{Id='';Name='All games'})+$(if($null -ne $CachedGames){@($CachedGames)}else{@(Get-GameLibrary)});$UI.Controls.NetworkGame.ItemsSource=$games;$match=$games|Where-Object Id -eq $selected|Select-Object -First 1;if($match){$UI.Controls.NetworkGame.SelectedItem=$match}else{$UI.Controls.NetworkGame.SelectedIndex=0}}
        $gameId=[string]$UI.Controls.NetworkGame.SelectedItem.Id
        $rows=@(Get-GamingNetworkServers -GameId $gameId)
        if($ActiveConnections){if(-not $gameId){throw 'Choose a game before inspecting its active connections.'};$rows+=@(Get-GamingActiveGameEndpoints -GameId $gameId)}
        $UI.Controls.NetworkServer.ItemsSource=$rows;if($rows.Count){$UI.Controls.NetworkServer.SelectedIndex=0}
        $guidance=Get-GamingNetworkGameGuidance -GameId $gameId
        $UI.Controls.NetworkGuidance.Text=[string]$guidance.Message
        $UI.Controls.NetworkGuidance.ToolTip=[string]$guidance.SourceUrl
        if($ActiveConnections){$UI.Controls.NetworkGuidance.Text+=' Active TCP entries may be login or CDN connections, not the match server.'}
    }finally{$UI.LoadingServers=$false}
    Update-MacGamingServerSelection $UI
    if($savedProbe){$UI.Controls.NetworkHost.Text=[string]$savedProbe.InternetAddress;$UI.Controls.NetworkProtocol.SelectedItem=[string]$savedProbe.Protocol;$UI.Controls.NetworkPort.Text=[string]$savedProbe.Port;$UI.Controls.NetworkSampleChoice.SelectedItem=[int]$savedProbe.Samples;$UI.Controls.NetworkServerName.Text=[string]$savedProbe.TargetName}
    $UI.NetworkLoaded=$true
}

function Update-MacGamingServerSelection {
    param($UI)
    if($UI.LoadingServers){return};$server=$UI.Controls.NetworkServer.SelectedItem;if(-not $server -or -not $server.HostName){return}
    $UI.Controls.NetworkHost.Text=[string]$server.HostName;$UI.Controls.NetworkProtocol.SelectedItem=[string]$server.Protocol;$UI.Controls.NetworkPort.Text=[string]$(if($server.Port){$server.Port}else{443});$UI.Controls.NetworkServerName.Text=[string]$server.Name
    $UI.Controls.NetworkGuidance.Text=[string]$server.Notes;$UI.Controls.NetworkGuidance.ToolTip=[string]$server.SourceUrl
}

function Update-MacGamingSettingsProfiles {
    param($UI)
    $id=[string]$UI.Controls.SettingsProfileChoice.SelectedItem.Id;$rows=@(Get-GamingSettingsProfiles);$UI.Controls.SettingsProfileChoice.ItemsSource=$rows
    $match=$rows|Where-Object Id -eq $id|Select-Object -First 1;if($match){$UI.Controls.SettingsProfileChoice.SelectedItem=$match}elseif($rows.Count){$UI.Controls.SettingsProfileChoice.SelectedIndex=0}
}

function Update-MacGamingOptimizer {
    param($UI,[switch]$Reload)
    if($UI.LoadingOptimizer){return}
    if($Reload -or -not $UI.OptimizerCatalog){
        $UI.LoadingOptimizer=$true
        try{
            $UI.OptimizerCatalog=@(Get-GamingOptimizerFeatures);$UI.Controls.OptimizerCategory.ItemsSource=@('All')+@($UI.OptimizerCatalog.Category|Sort-Object -Unique);$UI.Controls.OptimizerCategory.SelectedIndex=0
            $info=Get-GamingEmbeddedOptimizerInfo;$UI.Controls.OptimizerInfo.Text=[string]$info.Message;$UI.Controls.OptimizerLaunch.IsEnabled=[bool]$info.Installed
            if(Get-Command Get-GamingOptimizerView -ErrorAction SilentlyContinue){$view=Get-GamingOptimizerView;$UI.Controls.OptimizerSearch.Text=[string]$view.Search}
        }finally{$UI.LoadingOptimizer=$false}
    }
    $query=[string]$UI.Controls.OptimizerSearch.Text;$category=[string]$UI.Controls.OptimizerCategory.SelectedItem
    $UI.Controls.OptimizerFeatures.ItemsSource=@($UI.OptimizerCatalog|Where-Object{($category -eq 'All' -or -not $category -or $_.Category -eq $category) -and (-not $query -or ($_.Name+' '+$_.Description).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0)})
}

function Add-MacGamingWindowsToolsControls {
    param($UI)
    $nav=$UI.Controls.NavOverview.Parent
    $button=New-MacButton $UI 'NavWindowsTools' 'Windows tools' 'Nav';$button.Margin='0,3'
    $content=New-Object Windows.Controls.StackPanel;$content.Orientation='Horizontal'
    $icon=New-Object Windows.Controls.TextBlock;$icon.FontFamily='Segoe MDL2 Assets';$icon.Text=[char]0xE90F;$icon.Width=27
    $label=New-Object Windows.Controls.TextBlock;$label.Text='Windows tools';[void]$content.Children.Add($icon);[void]$content.Children.Add($label);$button.Content=$content
    $nav.Children.Insert($nav.Children.IndexOf($UI.Controls.NavSettings),$button)
    $page=New-Object Windows.Controls.Grid;$page.Visibility='Collapsed';$page.Margin='0,0,0,4'
    foreach($height in @('Auto','Auto','*')){$row=New-Object Windows.Controls.RowDefinition;$row.Height=$height;[void]$page.RowDefinitions.Add($row)}
    $heading=New-Object Windows.Controls.StackPanel
    $title=New-MacText $UI 'Windows tools' 25;$title.FontWeight='SemiBold';$title.Margin='0,0,0,5';[void]$heading.Children.Add($title)
    $hint=New-MacText $UI 'A complete Windows toolbox, right here. System changes use their own controls and restore behavior.' 11 -Secondary;$hint.Margin='0,0,0,10';[void]$heading.Children.Add($hint)
    [void]$page.Children.Add($heading)
    $bar=New-Object Windows.Controls.Grid;$bar.Margin='0,0,0,10'
    foreach($width in @('*','Auto','Auto')){$column=New-Object Windows.Controls.ColumnDefinition;$column.Width=$width;[void]$bar.ColumnDefinitions.Add($column)}
    foreach($height in @('Auto','Auto')){$row=New-Object Windows.Controls.RowDefinition;$row.Height=$height;[void]$bar.RowDefinitions.Add($row)}
    $sections=New-Object Windows.Controls.ComboBox;$sections.DisplayMemberPath='Name';$sections.Margin='0,0,10,0';$sections.MinWidth=150;$null=Register-MacControl $UI 'WindowsToolsSection' $sections;[void]$bar.Children.Add($sections)
    $admin=New-MacButton $UI 'WindowsToolsAdministrator' 'Enable administrator tools';$admin.Margin='0,0,8,0';$admin.Padding='12,8';[Windows.Controls.Grid]::SetColumn($admin,1);[void]$bar.Children.Add($admin)
    $release=New-MacButton $UI 'WindowsToolsUnload' 'Unload';$release.Margin='0';$release.Padding='12,8';$release.ToolTip='Close the embedded toolbox and release its active view. Reopen it from the sidebar.';[Windows.Controls.Grid]::SetColumn($release,2);[void]$bar.Children.Add($release)
    $status=New-MacText $UI 'Tools load when you open this page.' 10 -Secondary;$status.Margin='0,7,0,0';$null=Register-MacControl $UI 'WindowsToolsStatus' $status;[Windows.Controls.Grid]::SetRow($status,1);[Windows.Controls.Grid]::SetColumnSpan($status,3);[void]$bar.Children.Add($status)
    [Windows.Controls.Grid]::SetRow($bar,1);[void]$page.Children.Add($bar)
    $surface=New-Object Windows.Controls.Border;$surface.BorderThickness=1;$surface.SetResourceReference([Windows.Controls.Border]::BorderBrushProperty,'MacBrushE1E5EC');$surface.SetResourceReference([Windows.Controls.Border]::BackgroundProperty,'MacBrushFFFFFF');$surface.ClipToBounds=$true
    $area=New-Object Windows.Controls.Grid;$null=Register-MacControl $UI 'WindowsToolsArea' $area;$surface.Child=$area
    $placeholder=New-Object Windows.Controls.StackPanel;$placeholder.VerticalAlignment='Center';$placeholder.HorizontalAlignment='Center';$placeholder.MaxWidth=420
    $message=New-MacText $UI 'Your Windows workspace' 20;$message.FontWeight='SemiBold';$message.TextAlignment='Center';[void]$placeholder.Children.Add($message)
    $note=New-MacText $UI 'Open the toolbox to inspect Windows configuration and use its integrated utilities.' 12 -Secondary;$note.Margin='0,10,0,16';$note.TextAlignment='Center';[void]$placeholder.Children.Add($note)
    $load=New-MacButton $UI 'WindowsToolsLoad' 'Load Windows tools' 'Primary';$load.HorizontalAlignment='Center';[void]$placeholder.Children.Add($load)
    $null=Register-MacControl $UI 'WindowsToolsPlaceholder' $placeholder;[void]$area.Children.Add($placeholder)
    [Windows.Controls.Grid]::SetRow($surface,2);[void]$page.Children.Add($surface)
    $null=Register-MacControl $UI 'PageWindowsTools' $page;[void]$UI.Controls.PageOverview.Parent.Children.Add($page)
}

function Resolve-MacGamingWindowsSection {
    param($UI,[string]$Category)
    $sections=@($UI.Controls.WindowsToolsSection.ItemsSource)
    if(-not $sections.Count){return ''}
    if(-not $Category){return [string]$sections[0].Id}
    $catalogFeature=$UI.OptimizerCatalog|Where-Object Id -eq $Category|Select-Object -First 1
    if($catalogFeature -and $catalogFeature.SectionId -in @($sections.Id)){return [string]$catalogFeature.SectionId}
    $direct=$sections|Where-Object{$_.Id -ieq $Category -or $_.Name -ieq $Category}|Select-Object -First 1
    if($direct){return [string]$direct.Id}
    $featureId=$Category
    if($featureId -match '^ProcessControl\.' -or $featureId -match '^AdvancedTweaks\.(UnlockAllCores|SvchostProcessSplitting)(\.|$)'){return 'advancedExtrasTab'}
    $windowsTweaks=@('EnableLegacyVolumeSlider','DisableGameBar','DisableCortana','DisableEdgeTelemetry','DisableEdgeDiscoverBar','DisableXboxLive','DisableQuickAccessHistory','DisableSensorServices','DisablePrivacyOptions','DisableTelemetryServices','DisableAutomaticUpdates','DisableMyPeople','DisableStartMenuAds','DisableSpellingTyping','DisableWindowsInk','ExcludeDrivers','DisableInsiderService','DisableStoreUpdates','DisableCloudClipboard','EnableLongPaths','RemoveCastToDevice','EnableGamingMode','DisableTPMCheck','RestoreClassicPhotoViewer','DisableModernStandby','HideTaskbarWeather','HideTaskbarSearch','DisableNewsInterests','TaskbarToLeft','DisableSnapAssist','DisableWidgets','DisableChat','DisableStickers','ClassicMenu','CompactMode','DisableVirtualizationBasedTechnology','DisableCoPilotAI','TaskbarSmaller','ClassicRibbon','UninstallOneDrive')
    if($featureId -like 'Tweaks.*' -and $featureId.Substring(7) -in $windowsTweaks -and 'windows10Tab' -in @($sections.Id)){return 'windows10Tab'}
    $Category=($Category -split '\.')[0]
    $known=@{Cleaner='cleanerTab';Pinger='pingerTab';ProcessControl='advancedExtrasTab';HostsEditor='hostsEditorTab';RegistryFix='registryFixerTab';Integrator='integratorTab';AdvancedTweaks='advancedTab';Tweaks='universalTab';Apps='appsTab';UWP='modernAppsTab';Startup='startupTab';Hardware='indiciumTab';Disk='diskActivityTab';Unlocker='fileHandlesTab';Variables='integratorTab';Run='integratorTab';ContextMenu='integratorTab';Language='optionsTab';Shodan='pingerTab'}
    if($known.ContainsKey($Category) -and $known[$Category] -in @($sections.Id)){return [string]$known[$Category]}
    $pattern=switch($Category){
        Cleaner {'clean'} Pinger {'dns|ping'} ProcessControl {'process'} HostsEditor {'host'} RegistryFix {'registry|repair'} Integrator {'integrat|context'}
        AdvancedTweaks {'advanced'} Tweaks {'universal|general|windows'} PostAction {'advanced'} Apps {'download|apps'} UWP {'uwp|modern'} Startup {'startup'} Hardware {'hardware'}
        Disk {'disk'} Unlocker {'handle|unlock'} Variables {'variable'} Run {'integrat|command'} ContextMenu {'integrat|context'} Language {'option|setting'} Shodan {'ping|dns'}
        default {[regex]::Escape($Category)}
    }
    $match=$sections|Where-Object{($_.Id+' '+$_.Name) -match $pattern}|Select-Object -First 1
    if($match){return [string]$match.Id}
    return [string]$sections[0].Id
}

function Remove-MacGamingEmbeddedOptimizer {
    param($UI)
    $view=$UI.EmbeddedOptimizerView;$formsHost=$UI.EmbeddedOptimizerHost
    $UI.EmbeddedOptimizerView=$null;$UI.EmbeddedOptimizerHost=$null
    if($formsHost){$formsHost.Child=$null;$UI.Controls.WindowsToolsArea.Children.Remove($formsHost);$formsHost.Dispose()}
    if($view){Remove-GamingEmbeddedOptimizerView -View $view}
    $UI.Controls.WindowsToolsPlaceholder.Visibility='Visible'
    $UI.Controls.WindowsToolsStatus.Text='Windows tools unloaded. Open this page again to reload.'
}

function Show-MacGamingWindowsTools {
    param($UI,[string]$Section='')
    $catalogFeature=$UI.OptimizerCatalog|Where-Object Id -eq $Section|Select-Object -First 1
    if($catalogFeature -and $catalogFeature.Availability -eq 'Retired'){Set-MacGamingStatus $UI ([string]$catalogFeature.Description);return}
    Set-MacGamingPage $UI 'WindowsTools'
    if($UI.LoadingEmbeddedOptimizer){return}
    $UI.LoadingEmbeddedOptimizer=$true
    try{
        if(-not $UI.EmbeddedOptimizerView){
            $info=Get-GamingEmbeddedOptimizerInfo
            if(-not $info.Installed){throw 'The integrated Windows tools component is missing. Reinstall the complete Framewell package.'}
            $UI.Controls.WindowsToolsStatus.Text='Loading the integrated Windows toolbox...';Sync-MacGamingUi $UI
            Add-Type -AssemblyName WindowsFormsIntegration
            $sections=@(Get-GamingEmbeddedOptimizerSections);$UI.Controls.WindowsToolsSection.ItemsSource=$sections
            $interop=New-Object Windows.Interop.WindowInteropHelper($UI.Window)
            $view=New-GamingEmbeddedOptimizerView -OwnerWindow $interop.Handle
            if(-not $view){throw 'The Windows tools view could not be created.'}
            $UI.EmbeddedOptimizerView=$view
            $UI.Controls.WindowsToolsSection.ItemsSource=@(Get-GamingEmbeddedOptimizerSections -View $view)
            $formsHost=New-Object System.Windows.Forms.Integration.WindowsFormsHost
            $UI.EmbeddedOptimizerHost=$formsHost
            Set-GamingEmbeddedOptimizerTheme -View $view -Theme $UI.Theme
            $formsHost.SetResourceReference([System.Windows.Forms.Integration.WindowsFormsHost]::BackgroundProperty,'MacBrushFAFBFD')
            $formsHost.Child=$view
            [void]$UI.Controls.WindowsToolsArea.Children.Add($formsHost)
            $UI.Controls.WindowsToolsPlaceholder.Visibility='Collapsed'
            $UI.Controls.WindowsToolsAdministrator.Visibility=if($info.IsAdministrator){'Collapsed'}else{'Visible'}
            $UI.Controls.WindowsToolsStatus.Text=if($info.IsAdministrator){'Administrator tools enabled. Apply only the changes you choose; session Restore does not undo these system changes.'}else{'Preview mode. Enable administrator tools to restart this app with Windows approval before making system changes.'}
        }
        $sectionId=if($Section){Resolve-MacGamingWindowsSection $UI $Section}elseif($UI.Controls.WindowsToolsSection.SelectedItem){[string]$UI.Controls.WindowsToolsSection.SelectedItem.Id}else{Resolve-MacGamingWindowsSection $UI ''}
        $match=$UI.Controls.WindowsToolsSection.ItemsSource|Where-Object Id -eq $sectionId|Select-Object -First 1
        if($match){$UI.Controls.WindowsToolsSection.SelectedItem=$match;Set-GamingEmbeddedOptimizerSection -View $UI.EmbeddedOptimizerView -Section $sectionId}
    }catch{
        $failure=$_.Exception.Message
        try{Remove-MacGamingEmbeddedOptimizer $UI}catch{}
        $UI.Controls.WindowsToolsStatus.Text=$failure
        Set-MacGamingStatus $UI $failure
    }finally{$UI.LoadingEmbeddedOptimizer=$false}
}

function Register-MacGamingV3Handlers {
    param($UI)
    $c=$UI.Controls
    $c.WindowsSettingsApply.Add_Click({try{
        $result=Set-GamingWindowsSettings -GameMode ([string]$UI.Controls.WindowsGameMode.SelectedItem) -HardwareScheduling ([string]$UI.Controls.WindowsHardwareScheduling.SelectedItem) -BackgroundCapture ([string]$UI.Controls.WindowsBackgroundCapture.SelectedItem)
        if($result.RequiresElevation){$UI.Controls.WindowsSettingsAdministrator.Visibility='Visible'}
        $UI.Controls.WindowsSettingsStatus.Text=[string]$result.Message
    }catch{$UI.Controls.WindowsSettingsStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $c.WindowsSettingsRestore.Add_Click({try{$result=Restore-GamingWindowsSettings;Update-MacGamingWindowsSettings $UI;$UI.Controls.WindowsSettingsStatus.Text=[string]$result.Message}catch{$UI.Controls.WindowsSettingsStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $c.WindowsSettingsRefresh.Add_Click({try{Update-MacGamingWindowsSettings $UI -IncludeDisplay}catch{$UI.Controls.WindowsSettingsStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $c.WindowsDisplayRefresh.Add_Click({try{Update-MacGamingWindowsSettings $UI -IncludeDisplay}catch{$UI.Controls.WindowsSettingsStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $c.WindowsSettingsAdministrator.Add_Click({try{$result=Restart-GamingModeElevated -InitialPage Performance;Set-MacGamingStatus $UI ([string]$result.Message);if($result.Success){$UI.Window.Close()}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.WindowsDisplayPreview.Add_Click({try{$selected=$UI.Controls.WindowsDisplayMode.SelectedItem;if($selected -and $selected.Key){$result=Set-GamingDisplayMode -Key ([string]$selected.Key);$UI.Controls.WindowsSettingsStatus.Text=[string]$result.Message;if($result.Success -and $result.RequiresConfirmation){Show-MacGamingDisplayConfirmation $UI $result}}}catch{$UI.Controls.WindowsSettingsStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $c.WindowsGpuApply.Add_Click({try{$game=$UI.Controls.GameList.SelectedItem;if($game -and $game.ExecutablePath){$result=Set-GamingGpuPreference -ExecutablePath ([string]$game.ExecutablePath) -Preference ([string]$UI.Controls.WindowsGpuPreference.SelectedItem);$UI.Controls.WindowsGpuStatus.Text=[string]$result.Message}}catch{$UI.Controls.WindowsGpuStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $c.WindowsGpuRestore.Add_Click({try{$game=$UI.Controls.GameList.SelectedItem;if($game -and $game.ExecutablePath){$result=Restore-GamingGpuPreference -ExecutablePath ([string]$game.ExecutablePath);Update-MacGamingGpuPreference $UI;$UI.Controls.WindowsGpuStatus.Text=[string]$result.Message}}catch{$UI.Controls.WindowsGpuStatus.Text=$_.Exception.Message}}.GetNewClosure())
    $c.NavTools.Add_Click({Set-MacGamingPage $UI 'Tools';try{Update-MacGamingMemory $UI -LoadPreferences;Update-MacGamingOptimizer $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    foreach($name in @('QuickMemoryTools','OpenISLC')){$c[$name].Content=$(if($name -eq 'OpenISLC'){'Built-in memory tools'}else{'Memory tools'});$c[$name].Add_Click({Set-MacGamingPage $UI 'Tools';try{Update-MacGamingMemory $UI -LoadPreferences}catch{Set-MacGamingStatus $UI $_.Exception.Message};$UI.Controls.MemoryToolsCard.BringIntoView()}.GetNewClosure())}
    $c.QuickGames.Add_Click({Set-MacGamingPage $UI 'Games';& $UI.Actions.LoadGames}.GetNewClosure())
    $c.QuickNetwork.Add_Click({Set-MacGamingPage $UI 'Network';try{Update-MacGamingServers $UI -ReloadGames}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.QuickProfiles.Add_Click({Set-MacGamingPage $UI 'Profiles';& $UI.Actions.LoadProfiles}.GetNewClosure())
    $c.EditBackgroundApps.Add_Click({Set-MacGamingPage $UI 'Profiles';try{Update-MacGamingProfiles $UI 'super-performance';$UI.Controls.ProfileList.BringIntoView()}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.GoToCpu.Add_Click({$UI.Controls.CpuCard.BringIntoView()}.GetNewClosure())
    $c.GoToGameNetwork.Add_Click({try{Set-MacGamingPage $UI 'Network';Update-MacGamingServers $UI -ReloadGames;$id=[string]$UI.Controls.GameList.SelectedItem.Id;$match=$UI.Controls.NetworkGame.ItemsSource|Where-Object Id -eq $id|Select-Object -First 1;if($match){$UI.Controls.NetworkGame.SelectedItem=$match}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    foreach($name in @('QuickMemoryPurge','MemoryPurge')){$c[$name].Add_Click({$result=Invoke-MacGamingBusy $UI {Invoke-GamingStandbyPurge} 'Clearing standby cache. Windows may request administrator permission...' 'Standby operation finished.' -InlineResult;if($result){$UI.Controls.MemoryToolStatus.Text=[string]$result.Message};Update-MacGamingMemory $UI}.GetNewClosure())}
    $c.MemoryRefresh.Add_Click({try{Update-MacGamingMemory $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.MemorySave.Add_Click({try{$null=Save-MacGamingMemory $UI;Set-MacGamingStatus $UI 'Memory preferences saved.'}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.MemoryMonitorToggle.Add_Click({
        if($UI.LoadingMemory){return}
        try{if($UI.Controls.MemoryMonitorToggle.IsChecked){$null=Save-MacGamingMemory $UI;$result=Start-GamingMemoryMonitor -StandbyThresholdMB ([int]$UI.Controls.MemoryStandbyThreshold.Text) -AvailableThresholdMB ([int]$UI.Controls.MemoryAvailableThreshold.Text) -IntervalSeconds ([int]$UI.Controls.MemoryInterval.Text)}else{$result=Stop-GamingMemoryMonitor};$UI.Controls.MemoryToolStatus.Text=[string]$result.Message;Update-MacGamingMemory $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message;Update-MacGamingMemory $UI}
    }.GetNewClosure())
    $c.MemoryTimerToggle.Add_Click({try{$enabled=[bool]$UI.Controls.MemoryTimerToggle.IsChecked;$timer=if($enabled){ConvertFrom-MacTimerValue ([string]$UI.Controls.MemoryTimerMilliseconds.Text)}else{1.0};$result=Set-GamingTimerResolution -Enabled $enabled -Milliseconds $timer;$UI.Controls.MemoryToolStatus.Text=[string]$result.Message;Update-MacGamingMemory $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message;Update-MacGamingMemory $UI}}.GetNewClosure())
    $c.CpuSave.Add_Click({try{$null=Save-MacGamingCpu $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.CpuRefresh.Add_Click({Update-MacGamingCpu $UI}.GetNewClosure())
    $c.CpuApply.Add_Click({try{$game=$UI.Controls.GameList.SelectedItem;if($game){$saved=Save-MacGamingCpu $UI;if($saved -and $saved.Success -eq $false){return};$id=[string]$game.Id;$result=Invoke-MacGamingBusy $UI {Invoke-GamingProcessTuning -GameId $id}.GetNewClosure() 'Applying settings to the selected running game...' 'Process settings updated.' -InlineResult;$UI.Controls.CpuStatus.Text=[string]$result.Message}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.CpuRestore.Add_Click({try{$id=[string]$UI.Controls.GameList.SelectedItem.Id;if($id){$result=Restore-GamingProcessTuning -GameId $id;$UI.Controls.CpuStatus.Text=[string]$result.Message}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.NetworkGame.Add_SelectionChanged({if(-not $UI.LoadingServers){try{Update-MacGamingServers $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message}}}.GetNewClosure())
    $c.NetworkServer.Add_SelectionChanged({Update-MacGamingServerSelection $UI}.GetNewClosure())
    $c.NetworkProtocol.Add_SelectionChanged({$UI.Controls.NetworkPort.IsEnabled=([string]$UI.Controls.NetworkProtocol.SelectedItem -eq 'TCP')}.GetNewClosure())
    $c.NetworkRefreshServers.Add_Click({try{Update-MacGamingServers $UI -ReloadGames}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.NetworkActiveEndpoints.Add_Click({try{Update-MacGamingServers $UI -ActiveConnections}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.NetworkSaveServer.Add_Click({try{$row=Save-GamingNetworkServer -Name ([string]$UI.Controls.NetworkServerName.Text) -HostName ([string]$UI.Controls.NetworkHost.Text) -Protocol ([string]$UI.Controls.NetworkProtocol.SelectedItem) -Port ([int]$UI.Controls.NetworkPort.Text) -GameId ([string]$UI.Controls.NetworkGame.SelectedItem.Id);Update-MacGamingServers $UI;Set-MacGamingStatus $UI 'Endpoint saved.'}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.NetworkRemoveServer.Add_Click({try{$selected=$UI.Controls.NetworkServer.SelectedItem;if($selected){$r=Remove-GamingNetworkServer -Id $selected.Id;Update-MacGamingServers $UI;Set-MacGamingStatus $UI ([string]$r.Message)}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.SettingsProfileSave.Add_Click({try{$scope=[string]$UI.Controls.SettingsProfileScope.SelectedItem;if($UI.OptimizerCatalog -and $scope -in @('All','Tools') -and (Get-Command Save-GamingOptimizerView -ErrorAction SilentlyContinue)){$null=Save-GamingOptimizerView -Search ([string]$UI.Controls.OptimizerSearch.Text)};$r=Save-GamingSettingsProfile -Name ([string]$UI.Controls.SettingsProfileName.Text) -Scope $scope;Update-MacGamingSettingsProfiles $UI;Set-MacGamingStatus $UI 'Settings profile saved.'}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.SettingsProfileApply.Add_Click({try{$id=[string]$UI.Controls.SettingsProfileChoice.SelectedItem.Id;if($id){$r=Apply-GamingSettingsProfile -Id $id;Update-MacGamingDashboard $UI;Update-MacGamingGameList $UI -Reload;Update-MacGamingProfiles $UI;Update-MacGamingServers $UI -ReloadGames -LoadPreferences;Update-MacGamingMemory $UI -LoadPreferences;Update-MacGamingOptimizer $UI -Reload;$UI.Controls.SettingsProfileStatus.Text=[string]$r.Message;Set-MacGamingPage $UI 'Profiles'}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.SettingsProfileExport.Add_Click({try{$id=[string]$UI.Controls.SettingsProfileChoice.SelectedItem.Id;if($id){$r=Export-GamingSettingsProfile -Id $id;Set-MacGamingStatus $UI 'Profile export finished.'}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.SettingsProfileImport.Add_Click({try{$r=Import-GamingSettingsProfile;Update-MacGamingSettingsProfiles $UI;if($r){Set-MacGamingStatus $UI 'Profile imported. Select it and Apply when ready.'}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.SettingsProfileRemove.Add_Click({try{$id=[string]$UI.Controls.SettingsProfileChoice.SelectedItem.Id;if($id){$r=Remove-GamingSettingsProfile -Id $id;Update-MacGamingSettingsProfiles $UI;Set-MacGamingStatus $UI 'Settings profile removed.'}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.SettingsProfileChoice.Add_SelectionChanged({$p=$UI.Controls.SettingsProfileChoice.SelectedItem;if($p){$UI.Controls.SettingsProfileStatus.Text=[string]$p.Scope+' · '+[string]$p.Summary}}.GetNewClosure())
    $c.OptimizerLaunch.Add_Click({Show-MacGamingWindowsTools $UI}.GetNewClosure())
    $c.NavWindowsTools.Add_Click({Show-MacGamingWindowsTools $UI}.GetNewClosure())
    $c.WindowsToolsLoad.Add_Click({Show-MacGamingWindowsTools $UI}.GetNewClosure())
    $c.WindowsToolsUnload.Add_Click({try{Remove-MacGamingEmbeddedOptimizer $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.WindowsToolsSection.Add_SelectionChanged({if(-not $UI.LoadingEmbeddedOptimizer -and $UI.EmbeddedOptimizerView -and $UI.Controls.WindowsToolsSection.SelectedItem){try{Set-GamingEmbeddedOptimizerSection -View $UI.EmbeddedOptimizerView -Section ([string]$UI.Controls.WindowsToolsSection.SelectedItem.Id)}catch{Set-MacGamingStatus $UI $_.Exception.Message}}}.GetNewClosure())
    $c.WindowsToolsAdministrator.Add_Click({try{$result=Restart-GamingModeElevated -InitialPage WindowsTools;Set-MacGamingStatus $UI ([string]$result.Message);if($result.Success){$UI.Window.Close()}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.OptimizerOpenFeature.Add_Click({$feature=$UI.Controls.OptimizerFeatures.SelectedItem;Show-MacGamingWindowsTools $UI ([string]$feature.Id)}.GetNewClosure())
    $c.OptimizerFeatures.Add_MouseDoubleClick({$feature=$UI.Controls.OptimizerFeatures.SelectedItem;if($feature){Show-MacGamingWindowsTools $UI ([string]$feature.Id)}}.GetNewClosure())
    $c.OptimizerSearch.Add_TextChanged({try{Update-MacGamingOptimizer $UI}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.OptimizerSearch.Add_LostFocus({try{if(Get-Command Save-GamingOptimizerView -ErrorAction SilentlyContinue){$null=Save-GamingOptimizerView -Search ([string]$UI.Controls.OptimizerSearch.Text)}}catch{Set-MacGamingStatus $UI $_.Exception.Message}}.GetNewClosure())
    $c.OptimizerCategory.Add_SelectionChanged({if($UI.OptimizerCatalog){Update-MacGamingOptimizer $UI}}.GetNewClosure())
    $c.OptimizerFeatures.Add_SelectionChanged({$f=$UI.Controls.OptimizerFeatures.SelectedItem;$UI.Controls.OptimizerOpenFeature.IsEnabled=[bool]($f -and $f.Availability -ne 'Retired');if($f){$UI.Controls.OptimizerFeatureInfo.Text=[string]$f.Category+' · '+[string]$f.Description}}.GetNewClosure())
}

function Show-MacGamingPanel {
    param([string]$InitialAction = 'Panel',[switch]$CreateOnly)
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName PresentationCore
    Add-Type -AssemblyName WindowsBase
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Framewell" Width="1050" Height="790" MinWidth="960" MinHeight="700" WindowStartupLocation="CenterScreen" WindowStyle="None" AllowsTransparency="False" Background="#F6F7FA" ResizeMode="CanResizeWithGrip" FontFamily="Segoe UI Variable, Segoe UI" FontSize="13" Foreground="#202634">
  <shell:WindowChrome.WindowChrome><shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="8" CornerRadius="18" GlassFrameThickness="0" UseAeroCaptionButtons="False"/></shell:WindowChrome.WindowChrome>
  <Window.Resources>
    <SolidColorBrush x:Key="Muted" Color="#778095"/>
    <Style TargetType="TextBlock"><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style TargetType="Button">
      <Setter Property="Foreground" Value="#344056"/><Setter Property="Background" Value="#EEF1F6"/><Setter Property="BorderBrush" Value="Transparent"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="15,10"/><Setter Property="Cursor" Value="Hand"/><Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border x:Name="ButtonBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.82"/></Trigger><Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.64"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#63A7FF"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="Background" Value="#087CFA"/><Setter Property="Foreground" Value="White"/><Setter Property="Padding" Value="23,13"/></Style>
    <Style x:Key="Nav" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}"><Setter Property="Background" Value="Transparent"/><Setter Property="HorizontalContentAlignment" Value="Left"/><Setter Property="Margin" Value="0,3"/><Setter Property="Padding" Value="15,12"/><Setter Property="FontWeight" Value="Normal"/></Style>
    <Style x:Key="Traffic" TargetType="Button"><Setter Property="Width" Value="30"/><Setter Property="Height" Value="30"/><Setter Property="Margin" Value="3,0,0,0"/><Setter Property="Padding" Value="0"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Grid><Ellipse Width="18" Height="18" Fill="{TemplateBinding Background}" Stroke="#16000000" StrokeThickness="1"/><TextBlock x:Name="Glyph" Text="{TemplateBinding Content}" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="#202634" HorizontalAlignment="Center" VerticalAlignment="Center" Opacity="0"/></Grid><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="Glyph" Property="Opacity" Value="1"/></Trigger><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="Glyph" Property="Opacity" Value="1"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.35"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="White"/><Setter Property="CornerRadius" Value="16"/><Setter Property="BorderBrush" Value="#E5E8EE"/><Setter Property="BorderThickness" Value="1"/><Setter Property="Padding" Value="20"/></Style>
    <Style x:Key="SectionTitle" TargetType="TextBlock" BasedOn="{StaticResource {x:Type TextBlock}}"><Setter Property="FontSize" Value="25"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,7"/></Style>
    <Style x:Key="SecondaryText" TargetType="TextBlock" BasedOn="{StaticResource {x:Type TextBlock}}"><Setter Property="Foreground" Value="#7C8597"/><Setter Property="LineHeight" Value="20"/></Style>
    <Style TargetType="CheckBox"><Setter Property="Foreground" Value="#202634"/></Style>
    <Style TargetType="RadioButton"><Setter Property="Foreground" Value="#202634"/></Style>
    <Style TargetType="ListBox"><Setter Property="Foreground" Value="#202634"/></Style>
    <Style TargetType="ListView"><Setter Property="Foreground" Value="#202634"/></Style>
    <Style TargetType="ListBoxItem"><Setter Property="Foreground" Value="#202634"/></Style>
    <Style TargetType="ListViewItem"><Setter Property="Foreground" Value="#202634"/></Style>
    <Style TargetType="ScrollViewer"><Setter Property="HorizontalContentAlignment" Value="Stretch"/></Style>
    <Style x:Key="Toggle" TargetType="CheckBox" BasedOn="{StaticResource {x:Type CheckBox}}"><Setter Property="Cursor" Value="Hand"/><Setter Property="VerticalContentAlignment" Value="Center"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="CheckBox"><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="50"/></Grid.ColumnDefinitions><ContentPresenter Grid.Column="0" VerticalAlignment="Center"/><Border x:Name="Track" Grid.Column="1" Width="38" Height="22" CornerRadius="11" Background="#CFD5DF" HorizontalAlignment="Right"><Ellipse x:Name="Thumb" Width="18" Height="18" Margin="2" Fill="White" HorizontalAlignment="Left"></Ellipse></Border></Grid><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Track" Property="Background" Value="#087CFA"/><Setter TargetName="Thumb" Property="HorizontalAlignment" Value="Right"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter TargetName="Track" Property="Opacity" Value="0.4"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="ComboBox"><Setter Property="Padding" Value="10,7"/><Setter Property="MinHeight" Value="35"/><Setter Property="Foreground" Value="#202634"/><Setter Property="Background" Value="#F6F7FA"/><Setter Property="BorderBrush" Value="#DDE2E9"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBox"><Grid><ToggleButton Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8"><Path Data="M0,0 L4,4 L8,0" Stroke="#7C8597" StrokeThickness="1.4" Width="8" Height="4" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,12,0"/></Border></ControlTemplate></ToggleButton.Template></ToggleButton><ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" ContentTemplateSelector="{TemplateBinding ItemTemplateSelector}" Margin="11,7,31,7" VerticalAlignment="Center" IsHitTestVisible="False"/><Popup x:Name="PART_Popup" Placement="Bottom" IsOpen="{TemplateBinding IsDropDownOpen}" AllowsTransparency="True" Focusable="False" PopupAnimation="None"><Border Background="#F6F7FA" BorderBrush="#DDE2E9" BorderThickness="1" CornerRadius="9" Padding="4" MinWidth="{TemplateBinding ActualWidth}" MaxHeight="{TemplateBinding MaxDropDownHeight}" Margin="0,3,0,0"><ScrollViewer CanContentScroll="True" VerticalScrollBarVisibility="Auto"><StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border></Popup></Grid><ControlTemplate.Triggers><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="ComboBoxItem"><Setter Property="Foreground" Value="#202634"/><Setter Property="Padding" Value="10,8"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem"><Border x:Name="ComboItemBorder" CornerRadius="6" Background="Transparent" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ComboItemBorder" Property="Background" Value="#F0F4FA"/></Trigger><Trigger Property="IsSelected" Value="True"><Setter TargetName="ComboItemBorder" Property="Background" Value="#E9F2FF"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="TextBox"><Setter Property="Padding" Value="11,9"/><Setter Property="Foreground" Value="#202634"/><Setter Property="Background" Value="#F6F7FA"/><Setter Property="BorderBrush" Value="#E1E5EC"/><Setter Property="BorderThickness" Value="1"/><Setter Property="CaretBrush" Value="#202634"/></Style>
    <Style TargetType="ScrollBar"><Setter Property="Width" Value="9"/><Setter Property="Background" Value="Transparent"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ScrollBar"><Grid Background="Transparent"><Track x:Name="PART_Track" Orientation="{TemplateBinding Orientation}" IsDirectionReversed="True"><Track.DecreaseRepeatButton><RepeatButton Command="ScrollBar.PageUpCommand" Focusable="False"><RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.DecreaseRepeatButton><Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType="Thumb"><Border Background="#CFD5DF" CornerRadius="4" Margin="2,0"/></ControlTemplate></Thumb.Template></Thumb></Track.Thumb><Track.IncreaseRepeatButton><RepeatButton Command="ScrollBar.PageDownCommand" Focusable="False"><RepeatButton.Template><ControlTemplate TargetType="RepeatButton"><Border Background="Transparent"/></ControlTemplate></RepeatButton.Template></RepeatButton></Track.IncreaseRepeatButton></Track></Grid></ControlTemplate></Setter.Value></Setter></Style>
    <Style TargetType="Expander"><Setter Property="Foreground" Value="#202634"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Expander"><StackPanel><ToggleButton IsChecked="{Binding IsExpanded, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}" Foreground="{TemplateBinding Foreground}" HorizontalContentAlignment="Left"><ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="Transparent" Padding="0,5"><StackPanel Orientation="Horizontal"><Path x:Name="Chevron" Data="M0,0 L4,4 L0,8" Stroke="#7C8597" StrokeThickness="1.3" Width="4" Height="8" Margin="1,0,9,0" VerticalAlignment="Center" RenderTransformOrigin="0.5,0.5"/><ContentPresenter/></StackPanel></Border><ControlTemplate.Triggers><Trigger Property="IsChecked" Value="True"><Setter TargetName="Chevron" Property="RenderTransform"><Setter.Value><RotateTransform Angle="90"/></Setter.Value></Setter></Trigger></ControlTemplate.Triggers></ControlTemplate></ToggleButton.Template><ContentPresenter ContentSource="Header"/></ToggleButton><ContentPresenter x:Name="ExpandContent" ContentSource="Content" Visibility="Collapsed"/></StackPanel><ControlTemplate.Triggers><Trigger Property="IsExpanded" Value="True"><Setter TargetName="ExpandContent" Property="Visibility" Value="Visible"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
  </Window.Resources>
  <Border Margin="12" CornerRadius="18" Background="#FAFBFD" BorderBrush="#C7CDD8" BorderThickness="1">

    <Grid>
      <Grid.RowDefinitions><RowDefinition Height="51"/><RowDefinition Height="*"/><RowDefinition Height="34"/></Grid.RowDefinitions>
      <Border x:Name="TitleBar" Grid.Row="0" Background="#F5F6F9" CornerRadius="18,18,0,0" BorderBrush="#E2E5EC" BorderThickness="0,0,0,1">
        <Grid Margin="20,0"><TextBlock Text="Framewell" HorizontalAlignment="Left" VerticalAlignment="Center" FontWeight="SemiBold" FontSize="13" Foreground="#667184"/><StackPanel Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Right"><Button x:Name="MinimizeWindow" Content="&#xE921;" Style="{StaticResource Traffic}" Background="#FFBD2E" ToolTip="Minimize" AutomationProperties.Name="Minimize"/><Button x:Name="MaximizeWindow" Content="&#xE922;" Style="{StaticResource Traffic}" Background="#28C840" ToolTip="Maximize or restore" AutomationProperties.Name="Maximize or restore"/><Button x:Name="CloseWindow" Content="&#xE8BB;" Style="{StaticResource Traffic}" Background="#FF6059" ToolTip="Close" AutomationProperties.Name="Close"/></StackPanel></Grid>
      </Border>
      <Grid x:Name="MainWorkspace" Grid.Row="1">
        <Grid.ColumnDefinitions><ColumnDefinition Width="190"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
        <Border Grid.Column="0" Background="#F0F2F6" BorderBrush="#E1E5EC" BorderThickness="0,0,1,0">
          <Grid Margin="14,24,14,18"><Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
            <StackPanel Margin="9,0,0,28"><Border Width="44" Height="44" CornerRadius="13" Background="#087CFA" HorizontalAlignment="Left"><Viewbox Margin="9"><Canvas Width="32" Height="24"><Path Fill="White" Data="M8,3 L24,3 C28,3 30,7 31,17 C32,23 27,25 22,18 L10,18 C5,25 0,23 1,17 C2,7 4,3 8,3 Z"/><Path Stroke="#087CFA" StrokeThickness="2.4" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Data="M9,8 L9,14 M6,11 L12,11"/><Ellipse Canvas.Left="21" Canvas.Top="8" Width="3" Height="3" Fill="#087CFA"/><Ellipse Canvas.Left="25" Canvas.Top="12" Width="3" Height="3" Fill="#087CFA"/></Canvas></Viewbox></Border><TextBlock Text="Framewell" FontSize="18" FontWeight="SemiBold" Margin="0,14,0,4"/><TextBlock Text="Gaming workspace" FontSize="11" Foreground="#8B93A3"/></StackPanel>
            <StackPanel Grid.Row="1"><TextBlock Text="WORKSPACE" FontSize="9" FontWeight="SemiBold" Foreground="#969EAC" Margin="13,0,0,8"/><Button x:Name="NavOverview" Style="{StaticResource Nav}"><StackPanel Orientation="Horizontal"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE80F;" Width="27"/><TextBlock Text="Overview"/></StackPanel></Button><Button x:Name="NavGames" Style="{StaticResource Nav}"><StackPanel Orientation="Horizontal"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE7FC;" Width="27"/><TextBlock Text="Games"/></StackPanel></Button><Button x:Name="NavPerformance" Style="{StaticResource Nav}"><StackPanel Orientation="Horizontal"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE9D9;" Width="27"/><TextBlock Text="Performance"/></StackPanel></Button><Button x:Name="NavNetwork" Style="{StaticResource Nav}"><StackPanel Orientation="Horizontal"><TextBlock FontFamily="Segoe MDL2 Assets" Text="&#xE701;" Width="27"/><TextBlock Text="Network"/></StackPanel></Button></StackPanel>
            <StackPanel Grid.Row="3" Margin="10,0"><TextBlock Text="APPEARANCE" FontSize="9" FontWeight="SemiBold" Foreground="#969EAC" Margin="0,0,0,8"/><ComboBox x:Name="AppearanceTheme" Margin="0,0,0,18"><ComboBoxItem Content="Dark"/><ComboBoxItem Content="Light"/></ComboBox><Border Height="1" Background="#DDE2EA" Margin="0,0,0,17"/><TextBlock x:Name="SidebarComputer" Text="THIS PC" FontSize="11" FontWeight="SemiBold"/><TextBlock Text="Changes you can undo." FontSize="11" Foreground="#9098A7" Margin="0,5,0,0"/></StackPanel>
          </Grid>
        </Border>
        <Grid Grid.Column="1" Margin="30,25,30,18">
          <ScrollViewer x:Name="PageOverview" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel Margin="0,0,7,5">
              <DockPanel Margin="0,0,0,18"><Button x:Name="RefreshDashboard" DockPanel.Dock="Right" Content="Refresh" Padding="14,8" VerticalAlignment="Top"/><StackPanel><TextBlock Text="Overview" Style="{StaticResource SectionTitle}"/><TextBlock Text="Your games, your settings, one workspace." Style="{StaticResource SecondaryText}"/></StackPanel></DockPanel>
              <Border CornerRadius="19" Padding="23" BorderBrush="#D9E5F5" BorderThickness="1"><Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#ECF5FF" Offset="0"/><GradientStop Color="#F6F8FF" Offset="1"/></LinearGradientBrush></Border.Background><StackPanel><Border Background="#DDEBFC" CornerRadius="6" Padding="8,4" HorizontalAlignment="Left"><TextBlock x:Name="ModeBadge" Text="NORMAL MODE" Foreground="#3679C4" FontSize="9" FontWeight="Bold"/></Border><TextBlock x:Name="HeroTitle" Text="Ready when you are." FontSize="29" FontWeight="SemiBold" Margin="0,14,0,8"/><TextBlock x:Name="HeroSubtitle" Text="Clear optional background work and give your game room to run. Steam and Discord stay open." Foreground="#697B93" MaxWidth="575" HorizontalAlignment="Left" LineHeight="20"/><StackPanel Orientation="Horizontal" Margin="0,21,0,0"><Button x:Name="ToggleMode" Content="Turn Gaming Mode On" Style="{StaticResource Primary}"/><Button x:Name="ReapplyMode" Content="Apply again" Margin="10,0,0,0" Visibility="Collapsed" Background="#E0EAF7"/></StackPanel></StackPanel></Border>
              <UniformGrid Columns="3" Margin="0,15,0,17"><Border Style="{StaticResource Card}" Margin="0,0,10,0"><StackPanel><TextBlock Text="PROCESSES" FontSize="9" FontWeight="SemiBold" Foreground="#919BAD"/><TextBlock x:Name="ProcessCount" Text="--" FontSize="30" FontWeight="SemiBold" Margin="0,7,0,3"/><TextBlock Text="Current snapshot" FontSize="11" Foreground="#969EAD"/></StackPanel></Border><Border Style="{StaticResource Card}" Margin="0,0,10,0"><StackPanel><TextBlock Text="MEMORY" FontSize="9" FontWeight="SemiBold" Foreground="#919BAD"/><TextBlock x:Name="MemoryCount" Text="-- GB" FontSize="27" FontWeight="SemiBold" Margin="0,8,0,4"/><TextBlock x:Name="MemoryTotal" Text="Checking usage" FontSize="10" Foreground="#969EAD"/><ProgressBar x:Name="MemoryMeter" Minimum="0" Maximum="100" Height="3" Foreground="#6CAEFF" Background="#EDF2F9" BorderThickness="0" Margin="0,9,0,0"/></StackPanel></Border><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="DISPLAY" FontSize="9" FontWeight="SemiBold" Foreground="#919BAD"/><TextBlock x:Name="RefreshCount" Text="-- Hz" FontSize="27" FontWeight="SemiBold" Margin="0,8,0,4"/><TextBlock Text="Selected refresh rate" FontSize="10" Foreground="#969EAD"/></StackPanel></Border></UniformGrid>
              <Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="Restore your session" FontSize="16" FontWeight="SemiBold"/><TextBlock Text="Restore supported apps from your last session, or open an app profile." Style="{StaticResource SecondaryText}" Margin="0,7,0,14"/><UniformGrid Columns="2"><Button x:Name="RestoreNormal" Content="Restore Normal Mode" Margin="0,0,10,0"/><Button x:Name="StartMedia" Content="Start Media Stack"/></UniformGrid><TextBlock x:Name="MediaSummary" Foreground="#959EAD" FontSize="11" Margin="0,12,0,0"/></StackPanel></Border>
              <Expander x:Name="ResultPanel" Header="Session report" Visibility="Collapsed" Margin="1,14,0,0" Foreground="#657185"><TextBox x:Name="ResultText" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" MaxHeight="150" Margin="0,10,0,0" FontSize="11"/></Expander>
              <TextBlock x:Name="LastChange" Text="Your measured before-and-after count will appear after activation." Foreground="#939CAD" FontSize="10" Margin="2,16,0,0"/>
              <Expander Header="What Framewell closes" Margin="1,13,0,0" Foreground="#788497" FontSize="11"><StackPanel Margin="0,10,0,0"><TextBlock x:Name="AppsSummary" Text="Checking open apps..." Foreground="#7D899B"/><TextBlock Text="Media streaming and downloads stop. Save work first. Browsers waiting for a save prompt stay open. Windows, security, drivers, networking, active games, Steam and Discord are preserved." Foreground="#929CAD" Margin="0,8,0,0" LineHeight="18"/></StackPanel></Expander>
            </StackPanel>
          </ScrollViewer>
          <ScrollViewer x:Name="PageGames" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel Margin="0,0,7,5"><DockPanel Margin="0,0,0,22"><Button x:Name="AddGame" DockPanel.Dock="Right" Content="+ Add a game" VerticalAlignment="Top"/><StackPanel><TextBlock Text="Your games" Style="{StaticResource SectionTitle}"/><TextBlock Text="Pick a game. Start with a quieter PC." Style="{StaticResource SecondaryText}"/></StackPanel></DockPanel>
              <Border Style="{StaticResource Card}" Padding="18"><StackPanel><TextBox x:Name="GameSearch" ToolTip="Search your games" Margin="0,0,0,12"/><DockPanel Margin="2,0,2,10"><TextBlock x:Name="GameCount" DockPanel.Dock="Right" Text="0 games" Foreground="#8994A6" FontSize="11"/><TextBlock Text="LIBRARY" FontSize="9" FontWeight="SemiBold" Foreground="#919BAD"/></DockPanel><Grid><ListBox x:Name="GameList" Height="275" BorderThickness="0" Background="Transparent" ScrollViewer.HorizontalScrollBarVisibility="Disabled"><ListBox.ItemContainerStyle><Style TargetType="ListBoxItem" BasedOn="{StaticResource {x:Type ListBoxItem}}"><Setter Property="Padding" Value="12,10"/><Setter Property="Margin" Value="0,2"/><Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBoxItem"><Border x:Name="GameItem" CornerRadius="9" Background="Transparent" Padding="{TemplateBinding Padding}"><ContentPresenter/></Border><ControlTemplate.Triggers><Trigger Property="IsSelected" Value="True"><Setter TargetName="GameItem" Property="Background" Value="#E9F2FF"/><Setter Property="Foreground" Value="#106CCF"/></Trigger><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="GameItem" Property="Background" Value="#F0F4FA"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style></ListBox.ItemContainerStyle><ListBox.ItemTemplate><DataTemplate><Grid><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions><TextBlock Text="{Binding Name}" FontWeight="SemiBold" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/><TextBlock Grid.Column="1" Text="{Binding Source}" FontSize="10" Foreground="#929BAA" Margin="10,2,0,0"/></Grid></DataTemplate></ListBox.ItemTemplate></ListBox><TextBlock x:Name="GameEmpty" Text="No games found. Add any game's .exe file to get started." Foreground="#9AA3B2" HorizontalAlignment="Center" VerticalAlignment="Center" MaxWidth="320" TextAlignment="Center"/></Grid></StackPanel></Border>
              <Border Style="{StaticResource Card}" Margin="0,15,0,0"><StackPanel><TextBlock x:Name="SelectedGameName" Text="Choose a game" FontSize="17" FontWeight="SemiBold"/><CheckBox x:Name="EnterBeforeLaunch" Content="Turn on Gaming Mode before launching" IsChecked="True" Style="{StaticResource Toggle}" Margin="0,16,0,15"/><Button x:Name="LaunchGame" Content="Launch game" Style="{StaticResource Primary}" HorizontalAlignment="Left" IsEnabled="False"/><TextBlock Text="Steam stays running. Other launchers may reopen if the selected game needs them." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,13,0,0"/><Border Height="1" Background="#EDF0F4" Margin="0,18"/><Button x:Name="BenchmarkGame" Content="Measure FPS (20 sec)" HorizontalAlignment="Left" IsEnabled="False"/><TextBlock x:Name="BenchmarkResult" Text="Run the selected game first. This measures rendering, not mouse-to-screen latency." Foreground="#8994A6" FontSize="11" LineHeight="19" Margin="0,10,0,0"/></StackPanel></Border>
            </StackPanel>
          </ScrollViewer>
          <ScrollViewer x:Name="PagePerformance" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel Margin="0,0,7,5"><TextBlock Text="Performance" Style="{StaticResource SectionTitle}"/><TextBlock Text="Useful controls. Clear tradeoffs. Easy to restore." Style="{StaticResource SecondaryText}" Margin="0,0,0,20"/>
              <Border Style="{StaticResource Card}" Margin="0,0,0,14"><StackPanel><TextBlock Text="Session presets" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="Choose a starting point, then customize below. Presets adjust background trimming and ISLC; your other switches keep their settings." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,7,0,13"/><UniformGrid Columns="3"><Button x:Name="PresetLowest" Content="Lowest background" Margin="0,0,8,0" Padding="9,10" FontSize="11"/><Button x:Name="PresetBalanced" Content="Balanced" Margin="0,0,8,0" Padding="9,10" FontSize="11"/><Button x:Name="PresetISLC" Content="ISLC comparison" Padding="9,10" FontSize="11"/></UniformGrid></StackPanel></Border>
              <Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="This PC" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="CpuName" Text="Checking processor..." Margin="0,10,0,4" Foreground="#617087"/><TextBlock x:Name="GpuName" Text="Checking graphics..." Foreground="#617087"/><Border Height="1" Background="#EDF0F4" Margin="0,16"/><CheckBox x:Name="DeepTrim" Style="{StaticResource Toggle}" IsChecked="True"><TextBlock Text="Deeper trim" FontWeight="SemiBold"/></CheckBox><TextBlock Text="Temporarily pauses search indexing and printing. Restore brings them back." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,6,55,16"/></StackPanel></Border>
              <Border Style="{StaticResource Card}" Margin="0,14,0,0"><StackPanel><TextBlock Text="Desktop and background activity" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="Temporary changes for a gaming session. Restore puts the original settings back." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,7,0,16"/><CheckBox x:Name="ReduceAnimations" Style="{StaticResource Toggle}"><TextBlock Text="Reduce Windows animations" FontWeight="SemiBold"/></CheckBox><TextBlock Text="Simplifies desktop transitions. This is a visual preference, not a guaranteed in-game FPS gain." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,6,55,16"/><CheckBox x:Name="ReduceTransparency" Style="{StaticResource Toggle}"><TextBlock Text="Reduce Windows transparency" FontWeight="SemiBold"/></CheckBox><TextBlock Text="Uses solid Windows surfaces during the session. Your game still controls its own graphics." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,6,55,16"/><CheckBox x:Name="DisableBackgroundCapture" Style="{StaticResource Toggle}" IsChecked="True"><TextBlock Text="Pause Windows background recording" FontWeight="SemiBold"/></CheckBox><TextBlock Text="Turns off automatic background game capture for the session. Manual OBS recording is separate." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,6,55,16"/><CheckBox x:Name="DisableBrowserBackground" Style="{StaticResource Toggle}" IsChecked="True"><TextBlock Text="Limit browser background activity" FontWeight="SemiBold"/></CheckBox><TextBlock Text="Temporarily limits Chrome and Edge background apps and Edge startup boost. Previous settings are restored." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,6,55,0"/></StackPanel></Border>
              <Border Style="{StaticResource Card}" Margin="0,14,0,0"><StackPanel><TextBlock Text="Power profile" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="PowerPlanName" Text="Checking current plan..." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,6,0,12"/><ComboBox x:Name="PowerMode"><ComboBoxItem Content="Keep my current power plan"/><ComboBoxItem Content="Use High performance temporarily"/></ComboBox><TextBlock Text="High performance can increase heat and power use. Framewell restores your original plan when you turn it off." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,10,0,0"/></StackPanel></Border>
              <Border Style="{StaticResource Card}" Margin="0,14,0,0"><StackPanel><DockPanel><Button x:Name="OpenISLC" Content="Open ISLC" DockPanel.Dock="Right" Padding="12,7"/><StackPanel><TextBlock Text="Memory and timers" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="ISLCState" Text="Checking ISLC..." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,4,0,0"/></StackPanel></DockPanel><CheckBox x:Name="KeepISLC" Style="{StaticResource Toggle}" Margin="0,16,0,8"><TextBlock Text="Keep existing ISLC running" FontWeight="SemiBold"/></CheckBox><TextBlock Text="An optional comparison, not a guaranteed FPS boost. Standby memory is reusable cache; clearing it is not automatically faster." Style="{StaticResource SecondaryText}" FontSize="11"/><StackPanel Orientation="Horizontal" Margin="0,13,0,0"><TextBlock x:Name="TimerValue" Text="-- ms" FontSize="18" FontWeight="SemiBold"/><TextBlock Text="  current timer resolution" Foreground="#8B96A8" VerticalAlignment="Center" FontSize="11"/></StackPanel><TextBlock Text="This reading is not measured input latency or network ping." Foreground="#9CA4B2" FontSize="10" Margin="0,5,0,0"/></StackPanel></Border>
              <Button x:Name="SavePreferences" Content="Save session preferences" Style="{StaticResource Primary}" HorizontalAlignment="Left" Margin="0,15,0,22"/>
              <TextBlock Text="Windows gaming settings" FontSize="16" FontWeight="SemiBold" Margin="1,0,0,12"/>
              <UniformGrid Columns="2"><Button x:Name="OpenGameMode" HorizontalContentAlignment="Left" Margin="0,0,10,10" Padding="16,14"><StackPanel><TextBlock Text="Game Mode" FontWeight="SemiBold"/><TextBlock x:Name="GameModeState" Text="Check in Settings" Foreground="#8A95A8" FontSize="11" Margin="0,5,0,0"/></StackPanel></Button><Button x:Name="OpenGraphics" HorizontalContentAlignment="Left" Margin="0,0,0,10" Padding="16,14"><StackPanel><TextBlock Text="Graphics and HAGS" FontWeight="SemiBold"/><TextBlock x:Name="HagsState" Text="Check in Settings" Foreground="#8A95A8" FontSize="11" Margin="0,5,0,0"/></StackPanel></Button><Button x:Name="OpenCaptures" HorizontalContentAlignment="Left" Margin="0,0,10,0" Padding="16,14"><StackPanel><TextBlock Text="Background recording" FontWeight="SemiBold"/><TextBlock x:Name="CaptureState" Text="Check in Settings" Foreground="#8A95A8" FontSize="11" Margin="0,5,0,0"/></StackPanel></Button><Button x:Name="OpenDisplay" HorizontalContentAlignment="Left" Padding="16,14"><StackPanel><TextBlock Text="Display refresh rate" FontWeight="SemiBold"/><TextBlock x:Name="DisplayState" Text="Check in Settings" Foreground="#8A95A8" FontSize="11" Margin="0,5,0,0"/></StackPanel></Button></UniformGrid>
              <Border Background="#EDF3FB" CornerRadius="12" Padding="16" Margin="0,16,0,0"><StackPanel><TextBlock Text="Inside your game" FontWeight="SemiBold" Foreground="#536F93"/><TextBlock Text="Use NVIDIA Reflex where supported and raw mouse input if you prefer consistent pointer motion. Select the highest supported display refresh rate. Compare frame caps, VRR and VSync for your game and display; these have no universal all-games switch." Foreground="#7C8FA9" FontSize="11" LineHeight="18" Margin="0,6,0,14"/><UniformGrid Columns="2"><Button x:Name="OpenPerGameGraphics" Content="Per-game graphics" Margin="0,0,9,0" Background="#DEE8F6" Padding="10,9" FontSize="11"/><Button x:Name="OpenNvidia" Content="NVIDIA Control Panel" Background="#DEE8F6" Padding="10,9" FontSize="11"/></UniformGrid></StackPanel></Border><TextBlock Text="Experimental and per-game settings vary by game and hardware. Compare before and after to decide what works on this PC." Foreground="#9AA3B2" FontSize="10" LineHeight="17" Margin="2,14,0,0"/>
            </StackPanel>
          </ScrollViewer>
          <ScrollViewer x:Name="PageNetwork" Visibility="Collapsed" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel Margin="0,0,7,5"><TextBlock Text="Network" Style="{StaticResource SectionTitle}"/><TextBlock Text="Measure the connection before changing it." Style="{StaticResource SecondaryText}" Margin="0,0,0,21"/>
              <Border Style="{StaticResource Card}"><StackPanel><DockPanel><Button x:Name="OpenNetwork" Content="Network settings" DockPanel.Dock="Right" Padding="12,8"/><TextBlock Text="Your connection" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/></DockPanel><TextBlock x:Name="WifiSummary" Text="Checking connection..." Foreground="#718097" LineHeight="21" Margin="0,14,0,0"/></StackPanel></Border>
              <UniformGrid Columns="2" Margin="0,15,0,0"><Border Style="{StaticResource Card}" Margin="0,0,12,0"><StackPanel><TextBlock Text="ROUTER" Foreground="#919BAD" FontWeight="SemiBold" FontSize="9"/><TextBlock x:Name="GatewayPing" Text="-- ms" FontWeight="SemiBold" FontSize="32" Margin="0,12,0,3"/><TextBlock Text="Average round-trip time" Foreground="#959EAD" FontSize="11"/><Border Height="1" Background="#EDF0F4" Margin="0,18,0,14"/><TextBlock x:Name="GatewayJitter" Text="Jitter  --" Foreground="#7C899D" FontSize="12"/><TextBlock x:Name="GatewayLoss" Text="Loss  --" Foreground="#7C899D" FontSize="12" Margin="0,7,0,0"/></StackPanel></Border><Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="SELECTED ENDPOINT" Foreground="#919BAD" FontWeight="SemiBold" FontSize="9"/><TextBlock x:Name="InternetPing" Text="-- ms" Foreground="{DynamicResource MacMetricAccent}" FontWeight="SemiBold" FontSize="32" Margin="0,12,0,3"/><TextBlock Text="Average round-trip time" Foreground="#959EAD" FontSize="11"/><Border Height="1" Background="#EDF0F4" Margin="0,18,0,14"/><TextBlock x:Name="InternetJitter" Text="Jitter  --" Foreground="#7C899D" FontSize="12"/><TextBlock x:Name="InternetLoss" Text="Loss  --" Foreground="#7C899D" FontSize="12" Margin="0,7,0,0"/></StackPanel></Border></UniformGrid>
              <StackPanel Orientation="Horizontal" Margin="0,19,0,0"><Button x:Name="RunNetworkTest" Content="Measure connection" Style="{StaticResource Primary}"/><TextBlock x:Name="NetworkChecked" Text="No test yet" Foreground="#98A1B0" FontSize="11" VerticalAlignment="Center" Margin="17,0,0,0"/></StackPanel>
              <TextBlock Text="ICMP measures round-trip response; TCP measures connection setup. Region probes and active connections are estimates. Use your game's own network overlay for actual match ping." Style="{StaticResource SecondaryText}" FontSize="11" Margin="0,13,0,22"/>
              <Border Style="{StaticResource Card}"><StackPanel><TextBlock Text="The useful first step" FontWeight="SemiBold" FontSize="16"/><TextBlock Text="Gaming Mode stops the media server and downloads to reduce local network load. Compare results before and after, and test Ethernet if Wi-Fi jitter or packet loss persists." Style="{StaticResource SecondaryText}" Margin="0,10,0,0"/><TextBlock Text="A DNS change cannot shorten the distance to a game server." Foreground="#9AA3B2" FontSize="11" Margin="0,12,0,0"/></StackPanel></Border>
            </StackPanel>
          </ScrollViewer>
        </Grid>
      </Grid>
      <Border Grid.Row="2" BorderBrush="#E4E7ED" BorderThickness="0,1,0,0" Background="#F7F8FB" CornerRadius="0,0,18,18"><Grid Margin="18,0"><Ellipse Fill="#56B789" Width="6" Height="6" HorizontalAlignment="Left"/><TextBlock x:Name="StatusText" Text="Ready. No background watcher stays behind when you close this window." FontSize="10" Foreground="#8A94A5" VerticalAlignment="Center" Margin="15,0,20,0" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/><ResizeGrip HorizontalAlignment="Right" VerticalAlignment="Bottom"/></Grid></Border>
    </Grid>
  </Border>
</Window>
'@
    $themedXaml = ConvertTo-MacGamingThemedXaml $xaml
    $xaml = $themedXaml.Document
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $reader.Close()
    $controls = @{}
    foreach ($match in [regex]::Matches($xaml.OuterXml, 'x:Name="([^"]+)"')) { $name = $match.Groups[1].Value; $controls[$name] = $window.FindName($name) }
    $ui = @{Window=$window;Controls=$controls;Busy=$false;Active=$false;CurrentPage='Overview';Games=@();Actions=@{};Dashboard=$null;ThemeTokens=$themedXaml.Tokens;Theme='Dark';ApplyingTheme=$false;Profiles=@();CurrentProfile=$null;ProfileComponents=$null;LoadingNvidia=$false;NvidiaTouched=@{};NvidiaProfile=$null;NvidiaExecutable='';CloseAfterActivation=$true}
    Initialize-FramewellReads $ui
    Add-MacGamingV2Controls $ui
    Add-MacGamingV3Controls $ui
    Add-FramewellUpdateControls $ui
    $initialPreferences = Get-GamingPreferences
    Apply-MacGamingTheme $ui ([string]$initialPreferences.Theme)
    $previousStatusCallback = $script:GamingStatusCallback
    $script:GamingStatusCallback = { param($message) Set-MacGamingStatus $ui ([string]$message) }.GetNewClosure()

    $ui.Actions.Refresh = { Request-FramewellDashboard $ui }.GetNewClosure()
    $ui.Actions.Enter = {
        $operation = { Invoke-GamingAction 'Enter' }
        $null = Invoke-MacGamingBusy $ui $operation 'Saving your session and clearing optional background work...' 'Gaming Mode is on.' -CloseOnSuccess -RefreshDashboard
    }.GetNewClosure()
    $ui.Actions.Restore = {
        $operation = { Invoke-GamingAction 'Restore' }
        $null = Invoke-MacGamingBusy $ui $operation 'Restoring your normal session...' 'Normal mode restored.' -RefreshDashboard
    }.GetNewClosure()
    $ui.Actions.Media = {
        $operation = { Invoke-GamingProfile -ProfileId 'media-stack' -Operation Start }
        $null = Invoke-MacGamingBusy $ui $operation 'Starting streaming, requests and downloads...' 'Your media stack is ready.' -RefreshDashboard
    }.GetNewClosure()
    $ui.Actions.Toggle = { if ($ui.Active) { & $ui.Actions.Restore } else { & $ui.Actions.Enter } }.GetNewClosure()
    $ui.Actions.LoadGames = { Request-FramewellGames $ui }.GetNewClosure()
    $ui.Actions.AddGame = {
        try { $null = Add-GamingGame; Update-MacGamingGameList $ui -Reload; Set-MacGamingStatus $ui 'Game library updated.' }
        catch { Set-MacGamingStatus $ui $_.Exception.Message }
    }.GetNewClosure()
    $ui.Actions.ScanGames = {
        $result=Invoke-MacGamingBusy $ui {Invoke-GamingGameScan} 'Scanning installed games and your selected folders...' 'Game scan complete.' -InlineResult
        if($result -and $result.Success){Update-MacGamingGameList $ui -Reload;if($result.Message){Set-MacGamingStatus $ui ([string]$result.Message)}}
        try{$scan=Get-GamingScanReport;$ui.Controls.ScanInfo.Text=[string]$scan.Message;if($scan.Warnings){$ui.Controls.ScanInfo.Text+=' '+(@($scan.Warnings)-join ' ')}}catch{}
    }.GetNewClosure()
    $ui.Actions.LoadProfiles = { Request-FramewellProfiles $ui }.GetNewClosure()
    $ui.Actions.Launch = {
        $selected = $ui.Controls.GameList.SelectedItem
        if (-not $selected) { return }
        $gameId = [string]$selected.Id
        $enterMode = [bool]$ui.Controls.EnterBeforeLaunch.IsChecked
        $operation = { Start-GamingGame -GameId $gameId -EnterMode:$enterMode }.GetNewClosure()
        $null = Invoke-MacGamingBusy $ui $operation ('Preparing ' + [string]$selected.Name + '...') 'Game launch requested.' -CloseOnSuccess:$enterMode -RefreshDashboard
    }.GetNewClosure()
    $ui.Actions.Network = {
        $sampleCount=[int]$ui.Controls.NetworkSampleChoice.SelectedItem;$address=[string]$ui.Controls.NetworkHost.Text
        $protocol=[string]$ui.Controls.NetworkProtocol.SelectedItem;$port=443
        if($protocol -eq 'TCP' -and -not [int]::TryParse([string]$ui.Controls.NetworkPort.Text,[ref]$port)){Set-MacGamingStatus $ui 'Enter a TCP port from 1 to 65535.';return}
        $targetName=[string]$ui.Controls.NetworkServerName.Text;$gameId=[string]$ui.Controls.NetworkGame.SelectedItem.Id
        $operation = { Invoke-GamingNetworkTest -Samples $sampleCount -InternetAddress $address -Protocol $protocol -Port $port -TargetName $targetName -GameId $gameId }.GetNewClosure()
        $result = Invoke-MacGamingBusy $ui $operation 'Measuring router and selected endpoint...' 'Endpoint test complete.' -InlineResult
        if ($null -eq $result -or -not $result.PSObject.Properties['Gateway']) { return }
        $ui.Controls.GatewayPing.Text = (Format-MacGamingNumber $result.Gateway.AverageMs 1) + ' ms'
        $ui.Controls.GatewayJitter.Text = 'Jitter  ' + (Format-MacGamingNumber $result.Gateway.JitterMs 1) + ' ms'
        $ui.Controls.GatewayLoss.Text = 'Loss  ' + (Format-MacGamingNumber $result.Gateway.LossPercent 1) + '%'
        $ui.Controls.InternetPing.Text = (Format-MacGamingNumber $result.Internet.AverageMs 1) + ' ms'
        $ui.Controls.InternetJitter.Text = 'Jitter  ' + (Format-MacGamingNumber $result.Internet.JitterMs 1) + ' ms'
        $ui.Controls.InternetLoss.Text = $(if($protocol -eq 'TCP'){'Probe failures  '}else{'Loss  '}) + (Format-MacGamingNumber $result.Internet.LossPercent 1) + '%'
        $ui.Controls.NetworkChecked.Text = 'Updated ' + [datetime]::Now.ToString('t')
        $ui.Controls.NetworkGuidance.Text=[string]$result.Measurement
    }.GetNewClosure()
    $ui.Actions.Benchmark = {
        $selected = $ui.Controls.GameList.SelectedItem
        if (-not $selected) { return }
        $gameId = [string]$selected.Id
        $ui.Controls.BenchmarkResult.Text = 'Collecting 20 seconds of frames from the selected running game...'
        $operation = { Invoke-GamingFrameBenchmark -GameId $gameId -Seconds 20 }.GetNewClosure()
        $result = Invoke-MacGamingBusy $ui $operation 'Measuring the selected game. Windows may ask for administrator permission...' 'Rendering measurement complete.' -InlineResult
        if ($null -eq $result) { $ui.Controls.BenchmarkResult.Text = 'Measurement did not complete. See the status message below.'; return }
        if (-not $result.Success) { $ui.Controls.BenchmarkResult.Text = [string]$result.Message; return }
        $ui.Controls.BenchmarkResult.Text = 'Average ' + (Format-MacGamingNumber $result.AverageFPS 1) + ' FPS   |   1% low ' + (Format-MacGamingNumber $result.OnePercentLowFPS 1) + ' FPS   |   P95 frame time ' + (Format-MacGamingNumber $result.P95FrameTimeMs 2) + ' ms' + "`r`n" + 'Rendering measurement, not mouse-to-screen latency.'
    }.GetNewClosure()

    $controls.CloseWindow.Add_Click({ if (-not $ui.Busy) { $ui.Window.Close() } }.GetNewClosure())
    $controls.MinimizeWindow.Add_Click({ $ui.Window.WindowState = 'Minimized' }.GetNewClosure())
    $controls.MaximizeWindow.Add_Click({ $ui.Window.WindowState = if ($ui.Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } }.GetNewClosure())
    $controls.TitleBar.Add_MouseLeftButtonDown({ param($sender,$eventArgs) if ($eventArgs.ClickCount -eq 2) { $ui.Window.WindowState = if ($ui.Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' } } else { $ui.Window.DragMove() } }.GetNewClosure())
    $window.Add_Closing({ param($sender,$eventArgs) if ($ui.Busy) { $eventArgs.Cancel = $true } }.GetNewClosure())
    $window.Add_Closed({Stop-FramewellReads $ui;try{Remove-MacGamingEmbeddedOptimizer $ui}catch{}}.GetNewClosure())
    $controls.NavOverview.Add_Click({ Set-MacGamingPage $ui 'Overview' }.GetNewClosure())
    $controls.NavGames.Add_Click({ Set-MacGamingPage $ui 'Games'; if (-not $ui.Games.Count) { & $ui.Actions.LoadGames } }.GetNewClosure())
    $controls.NavProfiles.Add_Click({ Set-MacGamingPage $ui 'Profiles';if(-not $ui.Profiles.Count){& $ui.Actions.LoadProfiles} }.GetNewClosure())
    $controls.NavPerformance.Add_Click({ Set-MacGamingPage $ui 'Performance';try{Request-FramewellWindowsSettings $ui}catch{Set-MacGamingStatus $ui $_.Exception.Message} }.GetNewClosure())
    $controls.NavNetwork.Add_Click({ Set-MacGamingPage $ui 'Network';try{Request-FramewellNetwork $ui}catch{Set-MacGamingStatus $ui $_.Exception.Message} }.GetNewClosure())
    $controls.NavSettings.Add_Click({ Set-MacGamingPage $ui 'Settings';try{Update-MacGamingSettings $ui}catch{Set-MacGamingStatus $ui $_.Exception.Message} }.GetNewClosure())
    $controls.ToggleMode.Add_Click({ & $ui.Actions.Toggle }.GetNewClosure())
    $controls.ReapplyMode.Add_Click({ & $ui.Actions.Enter }.GetNewClosure())
    $controls.RestoreNormal.Add_Click({ & $ui.Actions.Restore }.GetNewClosure())
    $controls.StartMedia.Add_Click({ Set-MacGamingPage $ui 'Profiles';& $ui.Actions.LoadProfiles }.GetNewClosure())
    $controls.RefreshDashboard.Add_Click({ & $ui.Actions.Refresh }.GetNewClosure())
    $controls.AddGame.Add_Click({ & $ui.Actions.AddGame }.GetNewClosure())
    $controls.ScanGames.Add_Click({ & $ui.Actions.ScanGames }.GetNewClosure())
    $controls.AddScanFolder.Add_Click({try{$path=Add-GamingScanFolder;if($path){& $ui.Actions.ScanGames}}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    $controls.LaunchGame.Add_Click({ & $ui.Actions.Launch }.GetNewClosure())
    $controls.BenchmarkGame.Add_Click({ & $ui.Actions.Benchmark }.GetNewClosure())
    $controls.GoToNvidia.Add_Click({$ui.Controls.NvidiaCard.BringIntoView()}.GetNewClosure())
    $controls.GameSearch.Add_TextChanged({ if (-not $ui.Busy) { Update-MacGamingGameList $ui } }.GetNewClosure())
    $controls.GameList.Add_SelectionChanged({
        Update-MacGamingSelectedGame $ui
    }.GetNewClosure())
    $controls.UseGameExecutable.Add_Click({
        try{$game=$ui.Controls.GameList.SelectedItem;$choice=$ui.Controls.GameExecutableChoice.SelectedItem;if($game -and $choice){$null=Set-GamingGameExecutable -GameId $game.Id -ExecutablePath $choice.Path;Update-MacGamingGameList $ui -Reload;Set-MacGamingStatus $ui 'Game executable saved.'}}catch{Set-MacGamingStatus $ui $_.Exception.Message}
    }.GetNewClosure())
    $controls.BrowseGameExecutable.Add_Click({
        try{$game=$ui.Controls.GameList.SelectedItem;if($game){$null=Set-GamingGameExecutable -GameId $game.Id;Update-MacGamingGameList $ui -Reload}}catch{Set-MacGamingStatus $ui $_.Exception.Message}
    }.GetNewClosure())
    foreach($pair in @(@('NvidiaPerformance','Performance'),@('NvidiaQuality','Quality'),@('NvidiaRestore','Restore'),@('NvidiaApplyCustom','Custom'))){
        $presetName=[string]$pair[1]
        $controls[$pair[0]].Add_Click({try{Invoke-MacGamingNvidiaPreset $ui $presetName}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    }
    $controls.RefreshProfiles.Add_Click({ & $ui.Actions.LoadProfiles }.GetNewClosure())
    $controls.ProfileList.Add_SelectionChanged({if($ui.Controls.ProfileList.SelectedItem){Update-MacGamingProfileEditor $ui $ui.Controls.ProfileList.SelectedItem}}.GetNewClosure())
    $controls.NewProfile.Add_Click({
        try{if(-not $ui.ProfileComponents){$ui.ProfileComponents=Get-GamingProfileComponents};$ui.Controls.ProfileList.SelectedIndex=-1;Update-MacGamingProfileEditor $ui ([pscustomobject]@{Id='';Name='New profile';Kind='Apps';Description='';MediaKeys=@();AppIds=@();CustomExecutables=@()});$ui.Controls.ProfileName.Focus()|Out-Null;$ui.Controls.ProfileName.SelectAll()}catch{Set-MacGamingStatus $ui $_.Exception.Message}
    }.GetNewClosure())
    $controls.SaveProfile.Add_Click({try{Save-MacGamingProfile $ui}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    $controls.ProfileAddExe.Add_Click({try{$path=Get-GamingCustomProfileExecutable;if($path){$ui.Controls.ProfileCustomExecutables.ItemsSource=@(@($ui.Controls.ProfileCustomExecutables.ItemsSource)+@($path)|Select-Object -Unique)}}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    $controls.ProfileRemoveExe.Add_Click({$selected=$ui.Controls.ProfileCustomExecutables.SelectedItem;if($selected){$ui.Controls.ProfileCustomExecutables.ItemsSource=@($ui.Controls.ProfileCustomExecutables.ItemsSource|Where-Object{$_ -ne $selected})}}.GetNewClosure())
    foreach($pair in @(@('ProfileStart','Start'),@('ProfileStop','Stop'),@('ProfileApply','Apply'),@('ProfileRestore','Restore'))){
        $profileOperation=[string]$pair[1]
        $controls[$pair[0]].Add_Click({try{Invoke-MacGamingProfileAction $ui $profileOperation}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    }
    $controls.SaveSettings.Add_Click({try{Save-MacGamingSettings $ui}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    $controls.SavePreferences.Add_Click({ try { Save-MacGamingPreferences $ui } catch { Set-MacGamingStatus $ui $_.Exception.Message } }.GetNewClosure())
    $controls.PresetLowest.Add_Click({ try { Set-MacGamingPreset $ui 'Lowest background' } catch { Set-MacGamingStatus $ui $_.Exception.Message } }.GetNewClosure())
    $controls.PresetBalanced.Add_Click({ try { Set-MacGamingPreset $ui 'Balanced' } catch { Set-MacGamingStatus $ui $_.Exception.Message } }.GetNewClosure())
    $controls.PresetISLC.Add_Click({ try { Set-MacGamingPreset $ui 'ISLC comparison' } catch { Set-MacGamingStatus $ui $_.Exception.Message } }.GetNewClosure())
    $controls.RunNetworkTest.Add_Click({ & $ui.Actions.Network }.GetNewClosure())
    $controls.AppearanceTheme.Add_SelectionChanged({
        if ($ui.ApplyingTheme -or $ui.Busy) { return }
        if($ui.Controls.AppearanceTheme.SelectedIndex -lt 0){return}
        $theme = [string]$ui.Controls.AppearanceTheme.SelectedItem.Id
        try { Save-MacGamingTheme $ui $theme } catch { Set-MacGamingStatus $ui $_.Exception.Message }
    }.GetNewClosure())
    foreach ($controlName in @('OpenGameMode','OpenGraphics','OpenCaptures','OpenDisplay')) {
        $controls[$controlName].Add_Click({try{Set-MacGamingPage $ui 'Performance';Update-MacGamingWindowsSettings $ui -IncludeDisplay;$ui.Controls.WindowsSettingsCard.BringIntoView()}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    }
    $controls.OpenPerGameGraphics.Add_Click({Set-MacGamingPage $ui 'Games';if(-not $ui.Games.Count){& $ui.Actions.LoadGames};$ui.Controls.WindowsGpuCard.BringIntoView()}.GetNewClosure())
    $controls.OpenNetwork.Content='DNS & network tools'
    $controls.OpenNetwork.Add_Click({Show-MacGamingWindowsTools $ui 'Pinger'}.GetNewClosure())
    $controls.OpenNvidia.Add_Click({try{$null=Open-GamingSetting -Name Nvidia}catch{Set-MacGamingStatus $ui $_.Exception.Message}}.GetNewClosure())
    Register-MacGamingV3Handlers $ui
    $window.Add_ContentRendered({
        Set-MacGamingPage $ui 'Overview'
        & $ui.Actions.Refresh
        if($ui.Controls.AutomaticUpdates.IsChecked){Start-FramewellUpdateCheck $ui -Download -Automatic}
        if ($InitialAction -in @('Enter','Restore','Media')) { & $ui.Actions[$InitialAction] }
        elseif($InitialAction -eq 'WindowsTools'){Show-MacGamingWindowsTools $ui}
        elseif($InitialAction -eq 'Games'){Set-MacGamingPage $ui 'Games';& $ui.Actions.LoadGames}
        elseif($InitialAction -eq 'Performance'){Set-MacGamingPage $ui 'Performance';try{Request-FramewellWindowsSettings $ui}catch{Set-MacGamingStatus $ui $_.Exception.Message}}
    }.GetNewClosure())
    if($CreateOnly){$script:GamingStatusCallback=$previousStatusCallback;return $ui}
    try { [void]$window.ShowDialog() }
    finally {
        try{Remove-MacGamingEmbeddedOptimizer $ui}catch{}
        if(Get-Command Stop-GamingMemoryTools -ErrorAction SilentlyContinue){$null=Stop-GamingMemoryTools}
        $script:GamingStatusCallback = $previousStatusCallback
        $window = $null
    }
}
