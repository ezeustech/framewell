#requires -Version 5.1
[CmdletBinding()]
param(
    [Alias('Worker')][switch]$OptionalHelpersWorker,
    [Alias('Operation')][ValidateSet('Stop', 'Restore')][string]$OptionalHelpersWorkerOperation,
    [Alias('RequestFile')][string]$OptionalHelpersWorkerRequestFile
)

$script:OptionalHelpersScriptPath = $PSCommandPath
$script:OptionalHelpersRoot = $PSScriptRoot
$script:OptionalHelpersBaseServiceNames = @('LGHUBUpdaterService', 'logi_lamparray_service', 'OVRService')
# Keep Fax ahead of Spooler so an allowed dependent can stop first. No dependent
# is ever stopped implicitly, and neither startup types nor triggers are changed.
$script:OptionalHelpersDeepServiceNames = @('Fax', 'Spooler', 'WSearch')
$script:OptionalHelpersServiceNames = @($script:OptionalHelpersBaseServiceNames + $script:OptionalHelpersDeepServiceNames)
$script:OptionalHelpersISLCPath = ''
$script:OptionalHelpersISLCTaskName = ''
$helperConfigPath=Join-Path $PSScriptRoot 'state\helper-config.json'
if(Test-Path -LiteralPath $helperConfigPath -PathType Leaf){
    $helperConfig=Get-Content -LiteralPath $helperConfigPath -Raw|ConvertFrom-Json
    if($helperConfig.Version -eq 1 -and [string]$helperConfig.ISLCPath -match '^[A-Za-z]:\\' -and [IO.Path]::GetFileName([string]$helperConfig.ISLCPath) -eq 'Intelligent standby list cleaner ISLC.exe'){
        $script:OptionalHelpersISLCPath=[string]$helperConfig.ISLCPath
        $script:OptionalHelpersISLCTaskName=[string]$helperConfig.ISLCTaskName
    }
}
$script:OptionalHelpersISLCName = 'Intelligent standby list cleaner ISLC.exe'

function Get-OptionalHelperStamp {
    param([Parameter(Mandatory = $true)]$Value)
    $date = if ($Value -is [datetime]) { $Value } else {
        [datetime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)
    }
    # Win32_Process exposes creation time to microsecond precision.
    return $date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.ffffffZ')
}

function Get-OptionalHelperSnapshot {
    [CmdletBinding()]
    param([bool]$DeepTrim = $false)
    $services = @()
    $selectedNames = @($script:OptionalHelpersBaseServiceNames)
    if ($DeepTrim) { $selectedNames += @($script:OptionalHelpersDeepServiceNames) }
    foreach ($name in $selectedNames) {
        $service = Get-Service -Name $name -ErrorAction SilentlyContinue
        if ($service -and $service.Status -eq 'Running') {
            $services += [pscustomobject]@{ Name = $name; Status = 'Running' }
        }
    }
    $processes = @()
    $filter = "Name='$($script:OptionalHelpersISLCName)'"
    foreach ($process in @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction Stop)) {
        # Elevated applications can hide ExecutablePath from a normal user.
        # Such candidates are validated by path again inside the elevated worker.
        if ($process.ExecutablePath -and
            -not [string]::Equals([string]$process.ExecutablePath, $script:OptionalHelpersISLCPath,
                [StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not $process.CreationDate) { continue }
        $processes += [pscustomobject]@{
            ProcessId = [int]$process.ProcessId
            CreationDate = Get-OptionalHelperStamp $process.CreationDate
            ExpectedPath = $script:OptionalHelpersISLCPath
            PathVerified = [bool]$process.ExecutablePath
        }
    }
    return [pscustomobject]@{
        Version = 1
        DeepTrim = $DeepTrim
        CapturedAtUtc = [datetime]::UtcNow.ToString('o')
        Services = @($services)
        ISLC = @($processes)
    }
}

function New-OptionalHelperResult {
    param([string]$Kind, [string]$Name, [string]$Status, [string]$Message,
        [int]$ProcessId = 0, [bool]$Stopped = $false)
    return [pscustomobject]@{
        Kind = $Kind; Name = $Name; Status = $Status
        Success = ($Status -notin @('Failed', 'Skipped'))
        Message = $Message; ProcessId = $ProcessId; Stopped = $Stopped
    }
}

function Get-OptionalHelperPreviousRows {
    param($PreviousResults)
    if ($null -eq $PreviousResults) { return @() }
    if ($PreviousResults.PSObject.Properties['Results']) { return @($PreviousResults.Results) }
    return @($PreviousResults)
}

function Get-OptionalHelperTargets {
    param($Snapshot, [string]$Operation, $PreviousResults, [switch]$RecoverSnapshot)
    if ($RecoverSnapshot -and $Operation -ne 'Restore') {
        throw 'Snapshot recovery is permitted only for Restore.'
    }
    if ($null -eq $Snapshot -or [int]$Snapshot.Version -ne 1) {
        throw 'Unsupported optional-helper snapshot.'
    }
    $deepTrimEnabled = $false
    if ($Snapshot.PSObject.Properties['DeepTrim']) {
        if ($Snapshot.DeepTrim -isnot [bool]) { throw 'The deep-trim flag must be a boolean.' }
        $deepTrimEnabled = $Snapshot.DeepTrim
    }
    $previous = @(Get-OptionalHelperPreviousRows $PreviousResults)
    $targets = @()
    $seenServices = @{}
    foreach ($entry in @($Snapshot.Services)) {
        if ($null -eq $entry) { continue }
        $name = [string]$entry.Name
        if ($name -notin $script:OptionalHelpersServiceNames) { throw 'Snapshot contains an unapproved service.' }
        if ($name -in $script:OptionalHelpersDeepServiceNames -and -not $deepTrimEnabled) {
            throw 'A deep-trim service was present without an enabled deep-trim snapshot.'
        }
        if ($seenServices.ContainsKey($name)) { continue }
        $seenServices[$name] = $true
        if ($entry.Status -ne 'Running') { continue }
        if ($Operation -eq 'Restore' -and -not $RecoverSnapshot -and -not @($previous | Where-Object {
            $_.Kind -eq 'Service' -and $_.Name -eq $name -and $_.Status -eq 'Stopped' -and
                $_.Success -eq $true -and $_.Stopped -eq $true
        }).Count) { continue }
        $targets += [pscustomobject]@{ Kind = 'Service'; Name = $name; ProcessId = 0 }
    }
    $seenProcesses = @{}
    foreach ($entry in @($Snapshot.ISLC)) {
        if ($null -eq $entry) { continue }
        if (-not [string]::Equals([string]$entry.ExpectedPath, $script:OptionalHelpersISLCPath,
                [StringComparison]::OrdinalIgnoreCase)) { throw 'Snapshot contains an unapproved process path.' }
        $processId = [int]$entry.ProcessId
        if ($processId -le 0 -or -not $entry.CreationDate) { throw 'ISLC process identity is incomplete.' }
        $stamp = Get-OptionalHelperStamp $entry.CreationDate
        if ($seenProcesses.ContainsKey($processId)) { continue }
        $seenProcesses[$processId] = $true
        if ($Operation -eq 'Restore' -and -not $RecoverSnapshot -and -not @($previous | Where-Object {
            $_.Kind -eq 'Process' -and $_.Name -eq 'ISLC' -and [int]$_.ProcessId -eq $processId -and
                $_.Status -eq 'Stopped' -and $_.Success -eq $true -and $_.Stopped -eq $true
        }).Count) { continue }
        $targets += [pscustomobject]@{
            Kind = 'Process'; Name = 'ISLC'; ProcessId = $processId; CreationDate = $stamp
        }
    }
    return @($targets)
}

function Test-OptionalHelperProcessIdentity {
    param($Process, $Target)
    if ($null -eq $Process) { return $false }
    if ([int]$Process.ProcessId -ne [int]$Target.ProcessId) { return $false }
    if (-not [string]::Equals([string]$Process.ExecutablePath, $script:OptionalHelpersISLCPath,
            [StringComparison]::OrdinalIgnoreCase)) { return $false }
    return (Get-OptionalHelperStamp $Process.CreationDate) -eq [string]$Target.CreationDate
}

function Get-OptionalHelperRunningISLC {
    $filter = "Name='$($script:OptionalHelpersISLCName)'"
    return @(Get-CimInstance Win32_Process -Filter $filter -ErrorAction Stop | Where-Object {
        [string]::Equals([string]$_.ExecutablePath, $script:OptionalHelpersISLCPath,
            [StringComparison]::OrdinalIgnoreCase)
    })
}

function Stop-OptionalHelperISLC {
    param($Target)
    $processId = [int]$Target.ProcessId
    $actual = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop
    if (-not $actual) {
        return New-OptionalHelperResult 'Process' 'ISLC' 'NotRunning' 'The original ISLC process has already exited.' $processId
    }
    if (-not (Test-OptionalHelperProcessIdentity $actual $Target)) {
        return New-OptionalHelperResult 'Process' 'ISLC' 'Skipped' 'ISLC path or creation time changed; no process was stopped.' $processId
    }
    $handle = Get-Process -Id $processId -ErrorAction Stop
    try {
        if ($handle.CloseMainWindow()) { [void]$handle.WaitForExit(5000) }
    } catch {
        # A hidden tray application may have no window to close.
    } finally { $handle.Dispose() }

    $remaining = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction Stop
    if ($remaining) {
        if (-not (Test-OptionalHelperProcessIdentity $remaining $Target)) {
            return New-OptionalHelperResult 'Process' 'ISLC' 'Skipped' 'ISLC identity changed while closing; no forced stop was attempted.' $processId
        }
        # Recheck the process creation time on the retained process handle as well.
        $handle = Get-Process -Id $processId -ErrorAction Stop
        try {
            if ((Get-OptionalHelperStamp $handle.StartTime) -ne [string]$Target.CreationDate) {
                return New-OptionalHelperResult 'Process' 'ISLC' 'Skipped' 'Process ID was reused; no forced stop was attempted.' $processId
            }
            Stop-Process -InputObject $handle -ErrorAction Stop
            if (-not $handle.WaitForExit(5000)) { throw 'ISLC did not exit within five seconds.' }
        } finally { $handle.Dispose() }
    }
    return New-OptionalHelperResult 'Process' 'ISLC' 'Stopped' 'ISLC stopped; its scheduled task and settings were preserved.' $processId $true
}

function Restore-OptionalHelperISLC {
    param($Target)
    $processId = [int]$Target.ProcessId
    if (@(Get-OptionalHelperRunningISLC).Count -gt 0) {
        return New-OptionalHelperResult 'Process' 'ISLC' 'AlreadyRunning' 'ISLC is already running.' $processId
    }
    if(-not $script:OptionalHelpersISLCTaskName){throw 'No existing ISLC startup task is configured.'}
    $task = Get-ScheduledTask -TaskPath '\' -TaskName $script:OptionalHelpersISLCTaskName -ErrorAction Stop
    $actions = @($task.Actions)
    if ($actions.Count -ne 1 -or
        -not [string]::Equals([string]$actions[0].Execute, $script:OptionalHelpersISLCPath,
            [StringComparison]::OrdinalIgnoreCase) -or
        ([string]$actions[0].Arguments).Trim() -notin @('', '-minimized')) {
        throw 'The existing ISLC task no longer matches its approved executable and arguments.'
    }
    if (-not (Test-Path -LiteralPath $script:OptionalHelpersISLCPath -PathType Leaf)) {
        throw 'The approved ISLC executable is missing.'
    }
    Start-ScheduledTask -TaskPath '\' -TaskName $script:OptionalHelpersISLCTaskName -ErrorAction Stop
    $deadline = [datetime]::UtcNow.AddSeconds(10)
    do {
        if (@(Get-OptionalHelperRunningISLC).Count -gt 0) {
            return New-OptionalHelperResult 'Process' 'ISLC' 'Restored' 'ISLC restarted through its existing elevated task.' $processId
        }
        Start-Sleep -Milliseconds 250
    } while ([datetime]::UtcNow -lt $deadline)
    throw 'The ISLC task was started, but its process was not observed within ten seconds.'
}

function Invoke-OptionalHelperWorker {
    param($Snapshot, [string]$Operation, $PreviousResults, [switch]$RecoverSnapshot)
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Optional-helper worker requires administrator rights.'
    }
    $targets = @(Get-OptionalHelperTargets $Snapshot $Operation $PreviousResults -RecoverSnapshot:$RecoverSnapshot)
    $rows = @()
    foreach ($target in $targets) {
        try {
            if ($target.Kind -eq 'Process') {
                if ($Operation -eq 'Stop') { $rows += Stop-OptionalHelperISLC $target }
                else { $rows += Restore-OptionalHelperISLC $target }
                continue
            }
            # Revalidate immediately before touching a service. Never alter StartType.
            if ($target.Name -notin $script:OptionalHelpersServiceNames) { throw 'Unapproved service.' }
            $service = Get-Service -Name $target.Name -ErrorAction Stop
            if ($Operation -eq 'Stop') {
                if ($service.Status -ne 'Running') {
                    $rows += New-OptionalHelperResult 'Service' $target.Name 'NotRunning' 'Service was not running; it was left unchanged.'
                    continue
                }
                $stopGuard = Test-OptionalHelperServiceStop -Service $service
                if (-not $stopGuard.Allowed) {
                    $rows += New-OptionalHelperResult 'Service' $target.Name 'Skipped' $stopGuard.Message
                    continue
                }
                # No -Force: do not stop any dependent services as a side effect.
                Stop-Service -Name $target.Name -ErrorAction Stop
                $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped, [timespan]::FromSeconds(15))
                $rows += New-OptionalHelperResult 'Service' $target.Name 'Stopped' 'Service stopped; its startup configuration was preserved.' 0 $true
            } else {
                if ($service.Status -eq 'Running') {
                    $rows += New-OptionalHelperResult 'Service' $target.Name 'AlreadyRunning' 'Service is already running.'
                    continue
                }
                Start-Service -Name $target.Name -ErrorAction Stop
                $service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Running, [timespan]::FromSeconds(15))
                $rows += New-OptionalHelperResult 'Service' $target.Name 'Restored' 'Previously stopped service restarted.'
            }
        } catch {
            $rows += New-OptionalHelperResult $target.Kind $target.Name 'Failed' $_.Exception.Message ([int]$target.ProcessId)
        }
    }
    $success = @($rows | Where-Object { -not $_.Success }).Count -eq 0
    return [pscustomobject]@{ Success = $success; Status = $(if ($success) { 'Completed' } else { 'Partial' }); Operation = $Operation; Results = @($rows) }
}

function Test-OptionalHelperServiceStop {
    param([Parameter(Mandatory=$true)]$Service)
    if ($Service.Name -notin $script:OptionalHelpersServiceNames) {
        return [pscustomobject]@{Allowed=$false;Message='The service is not in the optional-helper allowlist.'}
    }
    $dependents = @($Service.DependentServices | Where-Object { [string]$_.Status -ne 'Stopped' })
    if ($dependents.Count -gt 0) {
        return [pscustomobject]@{
            Allowed=$false
            Message=('Kept running because dependent services are active: '+(($dependents | ForEach-Object Name) -join ', ')+'.')
        }
    }
    if ($Service.Name -in @('Spooler','Fax')) {
        # Query again inside the elevated worker, immediately before Stop-Service.
        # Failure to inspect the queue also prevents stopping the service.
        try { $printJobs = @(Get-CimInstance Win32_PrintJob -ErrorAction Stop) }
        catch { return [pscustomobject]@{Allowed=$false;Message='Kept running because the print queue could not be checked.'} }
        if ($printJobs.Count -gt 0) {
            return [pscustomobject]@{Allowed=$false;Message='Kept running because a print job is queued or printing.'}
        }
    }
    if ($Service.Name -eq 'OVRService') {
        # Keep an already running VR runtime available to games.
        $vrProcesses = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -match '(?i)^(?:OVRServer_x64|vrserver|vrcompositor|vrmonitor)\.exe$'
        })
        if ($vrProcesses.Count -gt 0) {
            return [pscustomobject]@{Allowed=$false;Message='Kept running because a VR runtime is active.'}
        }
    }
    return [pscustomobject]@{Allowed=$true;Message='No active print jobs or dependent services prevent this optional stop.'}
}

function Get-OptionalHelperStatePath {
    param([string]$Path, [switch]$CreateDirectory)
    $stateRoot = [IO.Path]::GetFullPath((Join-Path $script:OptionalHelpersRoot 'state'))
    if ($CreateDirectory -and -not (Test-Path -LiteralPath $stateRoot)) {
        [void][IO.Directory]::CreateDirectory($stateRoot)
    }
    $directory = Get-Item -LiteralPath $stateRoot -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Optional-helper state must be a normal directory beneath the script.'
    }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not [string]::Equals([IO.Path]::GetDirectoryName($full), $stateRoot, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($full) -notmatch '^optionalhelpers-[0-9a-f]{32}\.request\.json(?:\.result\.json)?$') {
        throw 'Optional-helper state path is outside its permitted directory.'
    }
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -ErrorAction Stop
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Optional-helper state file must not be a link or directory.'
        }
    }
    return $full
}

function Invoke-OptionalHelpers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][ValidateSet('Stop', 'Restore')][string]$Operation,
        $PreviousResults,
        [switch]$RecoverSnapshot
    )
    $targets = @()
    try {
        $targets = @(Get-OptionalHelperTargets $Snapshot $Operation $PreviousResults -RecoverSnapshot:$RecoverSnapshot)
        if ($targets.Count -eq 0) {
            return [pscustomobject]@{ Success = $true; Status = 'NoAction'; Operation = $Operation; Results = @() }
        }
        $requestName = 'optionalhelpers-' + [guid]::NewGuid().ToString('N') + '.request.json'
        $requestPath = Get-OptionalHelperStatePath (Join-Path (Join-Path $script:OptionalHelpersRoot 'state') $requestName) -CreateDirectory
        $resultPath = Get-OptionalHelperStatePath ($requestPath + '.result.json')
        [pscustomobject]@{
            Version = 1; Operation = $Operation; Snapshot = $Snapshot
            PreviousResults = @(Get-OptionalHelperPreviousRows $PreviousResults)
            RecoverSnapshot = [bool]$RecoverSnapshot
        } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $requestPath -Encoding UTF8 -ErrorAction Stop
        $powershellPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if ($script:OptionalHelpersScriptPath.Contains('"') -or $requestPath.Contains('"')) { throw 'Invalid helper path.' }
        $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Worker -Operation {1} -RequestFile "{2}"' -f
            $script:OptionalHelpersScriptPath, $Operation, $requestPath
        # Only this fixed helper is elevated; the Gaming Mode UI stays unelevated.
        $workerProcess = Start-Process -FilePath $powershellPath -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru -ErrorAction Stop
        try {
            # ShellExecute handles the user's UAC decision. Once approved, keep
            # the normal-user UI responsive while this fixed worker finishes.
            $workerDeadline = [datetime]::UtcNow.AddSeconds(300)
            $formsApplication = 'System.Windows.Forms.Application' -as [type]
            while (-not $workerProcess.HasExited) {
                if ([datetime]::UtcNow -ge $workerDeadline) {
                    throw 'Optional-helper worker exceeded five minutes and may still be running. Check its result before starting another helper operation.'
                }
                if ($null -ne $formsApplication) { [System.Windows.Forms.Application]::DoEvents() }
                Start-Sleep -Milliseconds 150
            }
            $workerExitCode = $workerProcess.ExitCode
        } finally { $workerProcess.Dispose() }
        if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) { throw "Optional-helper worker exited ($workerExitCode) without a result." }
        $resultPath = Get-OptionalHelperStatePath $resultPath
        $result = Get-Content -LiteralPath $resultPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ($result.Operation -ne $Operation -or -not $result.PSObject.Properties['Success']) { throw 'Invalid optional-helper result.' }
        return $result
    } catch {
        $cancelled = $false
        $exception = $_.Exception
        while ($exception) {
            if ($exception.PSObject.Properties['NativeErrorCode'] -and $exception.NativeErrorCode -eq 1223) { $cancelled = $true }
            $exception = $exception.InnerException
        }
        $status = if ($cancelled) { 'Skipped' } else { 'Failed' }
        $message = if ($cancelled) { 'Administrator approval was cancelled; optional helpers were left unchanged.' } else { $_.Exception.Message }
        $rows = @($targets | ForEach-Object { New-OptionalHelperResult $_.Kind $_.Name $status $message ([int]$_.ProcessId) })
        if (-not $rows.Count) { $rows = @(New-OptionalHelperResult 'Worker' 'Optional helpers' $status $message) }
        # Return cancellation as data, never as a terminating error in the UI.
        return [pscustomobject]@{ Success = $false; Status = $status; Cancelled = $cancelled; Operation = $Operation; Results = @($rows) }
    }
}

if ($OptionalHelpersWorker) {
    $workerResultPath = $null
    $workerExitCode = 1
    try {
        if (-not $OptionalHelpersWorkerOperation -or -not $OptionalHelpersWorkerRequestFile) { throw 'Worker operation and request file are required.' }
        $validatedRequestPath = Get-OptionalHelperStatePath $OptionalHelpersWorkerRequestFile
        if ($validatedRequestPath -notmatch '\.request\.json$') { throw 'Worker requires a request file.' }
        $workerResultPath = Get-OptionalHelperStatePath ($validatedRequestPath + '.result.json')
        if ((Get-Item -LiteralPath $validatedRequestPath -ErrorAction Stop).Length -gt 1048576) { throw 'Optional-helper request is too large.' }
        $request = Get-Content -LiteralPath $validatedRequestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([int]$request.Version -ne 1 -or $request.Operation -ne $OptionalHelpersWorkerOperation) { throw 'Optional-helper request does not match the worker operation.' }
        $recoverSnapshot = $false
        if ($request.PSObject.Properties['RecoverSnapshot']) {
            if ($request.RecoverSnapshot -isnot [bool]) { throw 'Snapshot recovery flag must be a boolean.' }
            $recoverSnapshot = $request.RecoverSnapshot
        }
        $workerResult = Invoke-OptionalHelperWorker $request.Snapshot $OptionalHelpersWorkerOperation $request.PreviousResults -RecoverSnapshot:$recoverSnapshot
        $workerExitCode = 0
    } catch {
        $workerResult = [pscustomobject]@{
            Success = $false; Status = 'Failed'; Operation = $OptionalHelpersWorkerOperation
            Results = @(New-OptionalHelperResult 'Worker' 'Optional helpers' 'Failed' $_.Exception.Message)
        }
    }
    if ($workerResultPath) {
        try {
            $workerResultPath = Get-OptionalHelperStatePath $workerResultPath
            $workerResult | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $workerResultPath -Encoding UTF8 -ErrorAction Stop
        } catch { $workerExitCode = 1 }
    }
    exit $workerExitCode
}
