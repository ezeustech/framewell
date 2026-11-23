# Windows PowerShell 5.1 compatible. Dot-sourcing only defines functions.
# The caller owns the mode lock and persists snapshots before making changes.
# No passwords, API keys, cookies, or arbitrary process command lines are returned.

function Get-GMMediaRoot {
    $config=Get-GMMediaConfiguration
    if($config){return [string]$config.Root}
    return ''
}

function Get-GMMediaConfiguration {
    $path=Join-Path $PSScriptRoot 'state\media-stack-config.json'
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    $config=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    if($config.Version -ne 1 -or [string]$config.Root -notmatch '^[A-Za-z]:\\'){throw 'Invalid local media-stack configuration.'}
    $allowed=@{JellyfinTray=@('Tray','Jellyfin.Windows.Tray.exe');Jellyfin=@('Jellyfin','jellyfin.exe');QBit=@('QBit','qbittorrent.exe');Seerr=@('Seerr','node.exe');Caddy=@('Caddy','caddy.exe');Radarr=@('Arr','Radarr.Console.exe');Sonarr=@('Arr','Sonarr.Console.exe');Prowlarr=@('Arr','Prowlarr.Console.exe')}
    foreach($definition in @($config.Definitions)){
        $rule=$allowed[[string]$definition.Key]
        if(-not $rule -or $definition.Kind -ne $rule[0] -or [IO.Path]::GetFileName([string]$definition.ExecutablePath) -ine $rule[1] -or [string]$definition.ExecutablePath -notmatch '^[A-Za-z]:\\' -or [int]$definition.Port -lt 0 -or [int]$definition.Port -gt 65535){throw 'Invalid local media component.'}
    }
    return $config
}

function Get-GMMediaDefinitions {
    $config=Get-GMMediaConfiguration
    if($config){return @($config.Definitions)}
    return @()
}

function Test-GMMediaProcessMatch {
    param($Process, $Definition)
    if (-not $Process -or -not $Process.ExecutablePath -or
        -not [string]::Equals([string]$Process.ExecutablePath,[string]$Definition.ExecutablePath,[StringComparison]::OrdinalIgnoreCase)) { return $false }
    $command = [string]$Process.CommandLine
    $root = Get-GMMediaRoot
    switch ($Definition.Kind) {
        'QBit' { return ($command -match '(?i)--configuration(?:=|\s+)"?automation(?:"|\s|$)' -and $command.IndexOf(($root+'\data\qBittorrent'),[StringComparison]::OrdinalIgnoreCase) -ge 0) }
        'Seerr' { return $command.IndexOf(($root+'\seerr\dist\index.js'),[StringComparison]::OrdinalIgnoreCase) -ge 0 }
        'Caddy' { return ($command -match '(?i)(?:^|\s)run(?:\s|$)' -and $command.IndexOf(($root+'\remote-access\Caddyfile'),[StringComparison]::OrdinalIgnoreCase) -ge 0) }
        'Arr' { return $command.IndexOf(($root+'\data\'+$Definition.Key),[StringComparison]::OrdinalIgnoreCase) -ge 0 }
        'Jellyfin' {
            $data=[regex]::Match([string]$Definition.Arguments,'(?i)--datadir\s+(?:"([^"]+)"|(\S+))')
            if(-not $data.Success){return $false}
            $directory=if($data.Groups[1].Success){$data.Groups[1].Value}else{$data.Groups[2].Value}
            return $command -match ('(?i)--datadir\s+"?'+[regex]::Escape($directory)+'(?:"|\s|$)')
        }
        default { return $true }
    }
}

function Get-GMMediaMatchedProcesses {
    param($Definition, [object[]]$Processes)
    if (-not $PSBoundParameters.ContainsKey('Processes')) { $Processes = @(Get-CimInstance Win32_Process -ErrorAction Stop) }
    return @($Processes | Where-Object { Test-GMMediaProcessMatch -Process $_ -Definition $Definition })
}

function ConvertTo-GMMediaIdentity {
    param($Process)
    return [pscustomobject]@{
        ProcessId=[int]$Process.ProcessId
        ParentProcessId=[int]$Process.ParentProcessId
        Name=[string]$Process.Name
        ExecutablePath=[string]$Process.ExecutablePath
        CreationTimeUtc=([datetime]$Process.CreationDate).ToUniversalTime().ToString('o')
    }
}

function Test-GMMediaIdentityAlive {
    param($Identity)
    if (-not $Identity -or [int]$Identity.ProcessId -le 0) { return $false }
    $current = Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$Identity.ProcessId) -ErrorAction SilentlyContinue
    if (-not $current -or -not $current.ExecutablePath) { return $false }
    if (-not [string]::Equals([string]$current.ExecutablePath,[string]$Identity.ExecutablePath,[StringComparison]::OrdinalIgnoreCase)) { return $false }
    return ([datetime]$current.CreationDate).ToUniversalTime().Ticks -eq ([datetime]$Identity.CreationTimeUtc).ToUniversalTime().Ticks
}

function Get-MediaStackSnapshot {
    $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    $components = @(foreach ($definition in Get-GMMediaDefinitions) {
        $matched = @(Get-GMMediaMatchedProcesses -Definition $definition -Processes $processes)
        [pscustomobject]@{
            Key=$definition.Key;Name=$definition.Name;Running=($matched.Count -gt 0)
            ExecutablePath=$definition.ExecutablePath;WorkingDirectory=$definition.WorkingDirectory
            Arguments=$definition.Arguments
            Processes=@($matched | ForEach-Object { ConvertTo-GMMediaIdentity $_ })
        }
    })
    $serverIds = @($components | Where-Object Key -eq 'Jellyfin' | ForEach-Object { $_.Processes | ForEach-Object { [int]$_.ProcessId } })
    $serverDefinition=Get-GMMediaDefinitions|Where-Object Key -eq 'Jellyfin'|Select-Object -First 1
    $transcoderPaths=if($serverDefinition){@((Join-Path $serverDefinition.WorkingDirectory 'ffmpeg.exe'),(Join-Path $serverDefinition.WorkingDirectory 'ffprobe.exe'))}else{@()}
    $transcoders = @($processes | Where-Object {
        $_.ParentProcessId -in $serverIds -and
        $_.ExecutablePath -in $transcoderPaths
    } | ForEach-Object { ConvertTo-GMMediaIdentity $_ })
    return [pscustomobject]@{SchemaVersion=1;CapturedUtc=[DateTime]::UtcNow.ToString('o');Components=@($components);JellyfinTranscoders=$transcoders}
}

function New-GMMediaResult {
    param([string]$Key,[string]$Name,[string]$Action,[string]$Status,[bool]$Success,[string]$Message)
    return [pscustomobject]@{Key=$Key;Name=$Name;Action=$Action;Status=$Status;Success=$Success;Message=$Message}
}

function Get-GMMediaSafeError {
    param($ErrorRecord)
    $exception = $ErrorRecord.Exception
    if ($exception.PSObject.Properties['Response'] -and $exception.Response -and
        $exception.Response.PSObject.Properties['StatusCode'] -and $exception.Response.StatusCode) { return ('HTTP '+[int]$exception.Response.StatusCode) }
    return $exception.GetType().Name
}

function Wait-GMMediaStopped {
    param($Definition,[int]$TimeoutSeconds=30)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (@(Get-GMMediaMatchedProcesses -Definition $Definition).Count -eq 0) { return $true }
        Start-Sleep -Milliseconds 300
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

function Test-GMMediaPortOwner {
    param($Definition,[int[]]$ProcessIds)
    if ([int]$Definition.Port -eq 0) { return $true }
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort ([int]$Definition.Port) -ErrorAction SilentlyContinue)
    return ($listeners.Count -gt 0 -and @($listeners | Where-Object { [int]$_.OwningProcess -notin $ProcessIds }).Count -eq 0)
}

function Invoke-GMMediaShutdown {
    param($Definition,[object[]]$Identities)
    $root = Get-GMMediaRoot
    $live = @($Identities | Where-Object { Test-GMMediaIdentityAlive $_ })
    if ($live.Count -eq 0) { return }
    if ($Definition.Kind -in @('Tray','Seerr')) {
        foreach ($identity in $live) {
            # Only these two apps lack an applicable shutdown API. Match PID,
            # executable path AND creation time immediately before terminating.
            if (Test-GMMediaIdentityAlive $identity) {
                Stop-Process -Id ([int]$identity.ProcessId) -ErrorAction Stop
            }
        }
        return
    }
    if (-not (Test-GMMediaPortOwner -Definition $Definition -ProcessIds @($live | ForEach-Object { [int]$_.ProcessId }))) {
        throw [InvalidOperationException]::new('The expected component does not own its listening port.')
    }
    switch ($Definition.Kind) {
        'Arr' {
            [xml]$config = Get-Content -LiteralPath ($root+'\data\'+$Definition.Key+'\config.xml') -Raw -ErrorAction Stop
            $headers = @{'X-Api-Key'=[string]$config.Config.ApiKey}
            $null = Invoke-RestMethod ('http://127.0.0.1:'+$Definition.Port+'/api/'+$Definition.ApiVersion+'/system/shutdown') -Method Post -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        }
        'Jellyfin' {
            $settings = Get-Content -LiteralPath ($root+'\seerr\config\settings.json') -Raw -ErrorAction Stop | ConvertFrom-Json
            $headers = @{Authorization=('MediaBrowser Client="GamingMode", Device="Server", DeviceId="gaming-mode-local", Version="1.0", Token="'+[string]$settings.jellyfin.apiKey+'"')}
            $null = Invoke-RestMethod 'http://127.0.0.1:8096/System/Shutdown' -Method Post -Headers $headers -TimeoutSec 10 -ErrorAction Stop
        }
        'QBit' {
            $credentials = Import-Clixml -LiteralPath ($root+'\private\service-credentials.clixml') -ErrorAction Stop
            $headers = @{Referer='http://127.0.0.1:8085/'}
            $login = Invoke-RestMethod 'http://127.0.0.1:8085/api/v2/auth/login' -Method Post -Headers $headers -Body @{
                username=$credentials.QBittorrent.UserName
                password=$credentials.QBittorrent.GetNetworkCredential().Password
            } -SessionVariable mediaQbSession -TimeoutSec 10 -ErrorAction Stop
            if ([string]$login -ne 'Ok.') { throw [UnauthorizedAccessException]::new('qBittorrent login failed.') }
            # App shutdown writes native resume state. Do not pause/start torrents.
            $null = Invoke-RestMethod 'http://127.0.0.1:8085/api/v2/app/shutdown' -Method Post -Headers $headers -WebSession $mediaQbSession -TimeoutSec 10 -ErrorAction Stop
        }
        'Caddy' {
            $adminListeners = @(Get-NetTCPConnection -State Listen -LocalPort 2019 -ErrorAction SilentlyContinue)
            $liveIds = @($live | ForEach-Object { [int]$_.ProcessId })
            if (-not $adminListeners.Count -or @($adminListeners | Where-Object { [int]$_.OwningProcess -notin $liveIds }).Count) {
                throw [InvalidOperationException]::new('Caddy does not own its admin endpoint.')
            }
            $null = Invoke-RestMethod 'http://127.0.0.1:2019/stop' -Method Post -TimeoutSec 10 -ErrorAction Stop
        }
    }
}

function Stop-MediaStack {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Snapshot,[ValidateRange(1,120)][int]$TimeoutSeconds=30,[scriptblock]$OnProgress)
    if ([int]$Snapshot.SchemaVersion -ne 1 -or -not $Snapshot.Components) { throw 'A valid Get-MediaStackSnapshot result is required.' }
    $results = New-Object 'System.Collections.Generic.List[object]'
    $definitions = @(Get-GMMediaDefinitions)
    # Stop the tray first, then incoming requests and automation, then downloads
    # and Jellyfin. No Windows services or startup tasks are altered.
    foreach ($key in @('JellyfinTray','Caddy','Seerr','Radarr','Sonarr','Prowlarr','QBit','Jellyfin')) {
        $definition = $definitions | Where-Object Key -eq $key | Select-Object -First 1
        $saved = $Snapshot.Components | Where-Object Key -eq $key | Select-Object -First 1
        if (-not $saved -or -not $saved.Running) { continue }
        if ($OnProgress) { & $OnProgress ('Stopping '+$definition.Name+'...') | Out-Null }
        try {
            $current = @(Get-GMMediaMatchedProcesses -Definition $definition)
            if (-not $current.Count) {
                $results.Add((New-GMMediaResult $key $definition.Name 'Stop' 'AlreadyStopped' $true 'Already stopped.'))
                continue
            }
            $currentIds = @($current | ForEach-Object { [int]$_.ProcessId })
            $liveSaved = @($saved.Processes | Where-Object {
                [int]$_.ProcessId -in $currentIds -and
                [string]::Equals([string]$_.ExecutablePath,[string]$definition.ExecutablePath,[StringComparison]::OrdinalIgnoreCase) -and
                (Test-GMMediaIdentityAlive $_)
            })
            $savedIds = @($liveSaved | ForEach-Object { [int]$_.ProcessId })
            if (-not $liveSaved.Count -or @($current | Where-Object { [int]$_.ProcessId -notin $savedIds }).Count) {
                $results.Add((New-GMMediaResult $key $definition.Name 'Stop' 'IdentityChanged' $false 'The process changed after the snapshot; it was left running.'))
                continue
            }
            $shutdownError = $null
            try { Invoke-GMMediaShutdown -Definition $definition -Identities $liveSaved } catch { $shutdownError = Get-GMMediaSafeError $_ }
            if (Wait-GMMediaStopped -Definition $definition -TimeoutSeconds $TimeoutSeconds) {
                $results.Add((New-GMMediaResult $key $definition.Name 'Stop' 'Stopped' $true 'Stopped.'))
            } else {
                $message = 'Still running; no forced server or download termination was attempted.'
                if ($shutdownError) { $message += (' Shutdown result: '+$shutdownError+'.') }
                $results.Add((New-GMMediaResult $key $definition.Name 'Stop' 'StillRunning' $false $message))
            }
        } catch {
            $results.Add((New-GMMediaResult $key $definition.Name 'Stop' 'Failed' $false ('Could not stop this component: '+(Get-GMMediaSafeError $_)+'.')))
        }
    }
    $serverSelected=@($Snapshot.Components | Where-Object {$_.Key -eq 'Jellyfin' -and $_.Running}).Count -gt 0
    $remainingTranscoders = @(if($serverSelected){$Snapshot.JellyfinTranscoders | Where-Object { Test-GMMediaIdentityAlive $_ }})
    if ($remainingTranscoders.Count) {
        # Jellyfin owns these children. Give its normal shutdown time to finish;
        # do not kill ffmpeg globally or interrupt an unfinished server shutdown.
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Milliseconds 300
            $remainingTranscoders = @($Snapshot.JellyfinTranscoders | Where-Object { Test-GMMediaIdentityAlive $_ })
        } while ($remainingTranscoders.Count -and [DateTime]::UtcNow -lt $deadline)
        if ($remainingTranscoders.Count) {
            $results.Add((New-GMMediaResult 'JellyfinTranscoders' 'Jellyfin transcoders' 'Stop' 'StillRunning' $false 'A Jellyfin-owned transcoder is still finishing; it was not forcibly terminated.'))
        }
    }
    return [pscustomobject]@{Success=(@($results | Where-Object { -not $_.Success }).Count -eq 0);Results=@($results.ToArray());Snapshot=$Snapshot}
}

function Start-GMMediaComponent {
    param($Definition)
    $root = Get-GMMediaRoot
    if (-not (Test-Path -LiteralPath $Definition.ExecutablePath -PathType Leaf)) { throw [IO.FileNotFoundException]::new('The configured executable was not found.') }
    $environment = @{}
    $previousEnvironment = @{}
    $launch = @{FilePath=$Definition.ExecutablePath;WorkingDirectory=$Definition.WorkingDirectory;WindowStyle='Hidden';PassThru=$true;ErrorAction='Stop'}
    if ($Definition.Arguments) { $launch.ArgumentList = [string]$Definition.Arguments }
    if ($Definition.Kind -eq 'Seerr') {
        $startup = Get-Content -LiteralPath ($root+'\startup-settings.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        $serverHost = '127.0.0.1'
        if ($startup.SeerrHost) { $serverHost = [string]$startup.SeerrHost }
        $environment = @{NODE_ENV='production';PORT='5055';HOST=$serverHost;CONFIG_DIRECTORY=($root+'\seerr\config');NEXT_TELEMETRY_DISABLED='1';TZ='America/Chicago'}
    } elseif ($Definition.Kind -eq 'Caddy') {
        $settings = Get-Content -LiteralPath ($root+'\remote-access\settings.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        if (-not $settings.Enabled -or -not $settings.Hostname) { throw [InvalidOperationException]::new('HTTPS is not configured as enabled.') }
        $environment = @{JELLYFIN_HOST=[string]$settings.Hostname;JELLYFIN_CADDY_DATA=($root+'\private\caddy-data').Replace('\','/')}
    }
    if ($Definition.Kind -in @('Seerr','Caddy')) {
        $logDirectory = Join-Path $root 'logs'
        $null = New-Item -ItemType Directory -Path $logDirectory -Force -ErrorAction Stop
        $stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
        $launch.RedirectStandardOutput = Join-Path $logDirectory ('gamingmode-'+$Definition.Key+'-'+$stamp+'-stdout.log')
        $launch.RedirectStandardError = Join-Path $logDirectory ('gamingmode-'+$Definition.Key+'-'+$stamp+'-stderr.log')
    }
    try {
        foreach ($name in $environment.Keys) {
            $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
            [Environment]::SetEnvironmentVariable($name,[string]$environment[$name],'Process')
        }
        $launched = Start-Process @launch
        return [int]$launched.Id
    } finally {
        foreach ($name in $previousEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name,$previousEnvironment[$name],'Process') }
    }
}

function Start-MediaStack {
    [CmdletBinding(DefaultParameterSetName='Snapshot')]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Snapshot')]$Snapshot,
        [Parameter(Mandatory=$true,ParameterSetName='All')][switch]$All,
        [ValidateRange(1,120)][int]$TimeoutSeconds=30,
        [scriptblock]$OnProgress
    )
    if (-not $All -and ([int]$Snapshot.SchemaVersion -ne 1 -or -not $Snapshot.Components)) { throw 'A valid Get-MediaStackSnapshot result is required for selective restore.' }
    $wanted = @()
    if ($All) { $wanted = @((Get-GMMediaDefinitions) | ForEach-Object Key) }
    else { $wanted = @($Snapshot.Components | Where-Object Running | ForEach-Object Key) }
    $definitions = @(Get-GMMediaDefinitions)
    $results = New-Object 'System.Collections.Generic.List[object]'
    foreach ($key in @('QBit','Prowlarr','Sonarr','Radarr','Seerr','Jellyfin','JellyfinTray','Caddy')) {
        if ($key -notin $wanted) { continue }
        $definition = $definitions | Where-Object Key -eq $key | Select-Object -First 1
        if ($OnProgress) { & $OnProgress ('Starting '+$definition.Name+'...') | Out-Null }
        try {
            $current = @(Get-GMMediaMatchedProcesses -Definition $definition)
            if ($current.Count) {
                $ready = Test-GMMediaPortOwner -Definition $definition -ProcessIds @($current | ForEach-Object { [int]$_.ProcessId })
                $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
                while (-not $ready -and [DateTime]::UtcNow -lt $deadline) {
                    Start-Sleep -Milliseconds 300
                    $current = @(Get-GMMediaMatchedProcesses -Definition $definition)
                    if (-not $current.Count) { break }
                    $ready = Test-GMMediaPortOwner -Definition $definition -ProcessIds @($current | ForEach-Object { [int]$_.ProcessId })
                }
                if ($ready) { $results.Add((New-GMMediaResult $key $definition.Name 'Start' 'AlreadyRunning' $true 'Already running; its listening port is ready where applicable.')) }
                else { $results.Add((New-GMMediaResult $key $definition.Name 'Start' 'NotReady' $false 'An existing process is not ready; it was not duplicated or forcibly restarted.')) }
                continue
            }
            if ($key -eq 'JellyfinTray' -and 'Jellyfin' -notin $wanted) {
                $results.Add((New-GMMediaResult $key $definition.Name 'Start' 'PreservedServerOff' $false 'The tray would start Jellyfin, which was previously stopped; the tray was left closed.'))
                continue
            }
            if ($Definition.Port -gt 0 -and @(Get-NetTCPConnection -State Listen -LocalPort ([int]$Definition.Port) -ErrorAction SilentlyContinue).Count) {
                $results.Add((New-GMMediaResult $key $definition.Name 'Start' 'PortInUse' $false 'Another process is using the required port; it was left untouched.'))
                continue
            }
            $launchedId = Start-GMMediaComponent -Definition $definition
            $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
            $ready = $false
            do {
                Start-Sleep -Milliseconds 300
                $current = @(Get-GMMediaMatchedProcesses -Definition $definition)
                if ($current.Count -and (Test-GMMediaPortOwner -Definition $definition -ProcessIds @($current | ForEach-Object { [int]$_.ProcessId }))) { $ready=$true;break }
            } while ([DateTime]::UtcNow -lt $deadline)
            if ($ready) {
                $results.Add((New-GMMediaResult $key $definition.Name 'Start' 'Started' $true 'Running; its listening port is ready where applicable.'))
            } else {
                $results.Add((New-GMMediaResult $key $definition.Name 'Start' 'NotReady' $false 'Launched but not ready before the timeout; retry Restore or Start media stack.'))
            }
        } catch {
            $results.Add((New-GMMediaResult $key $definition.Name 'Start' 'Failed' $false ('Could not start this component: '+(Get-GMMediaSafeError $_)+'.')))
        }
    }
    return [pscustomobject]@{Success=(@($results | Where-Object { -not $_.Success }).Count -eq 0);Results=@($results.ToArray())}
}
