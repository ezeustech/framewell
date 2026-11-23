# Read-only network probes. No DNS, route, adapter or registry changes.
$script:GamingNetworkRoot=$PSScriptRoot

function ConvertTo-GamingNetworkHost {
    param([Parameter(Mandatory=$true)][string]$HostName)
    $value=$HostName.Trim().TrimEnd('.')
    $address=$null
    if([Net.IPAddress]::TryParse($value,[ref]$address)){return $address.ToString()}
    if($value.Length -gt 253 -or $value -notmatch '^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$'){
        throw 'Enter only a server hostname or IP address, without a URL, path, port or command.'
    }
    return $value.ToLowerInvariant()
}

function Resolve-GamingNetworkAddress {
    param([string]$HostName)
    $hostValue=ConvertTo-GamingNetworkHost $HostName
    $address=$null
    if([Net.IPAddress]::TryParse($hostValue,[ref]$address)){return $address.ToString()}
    $task=[Net.Dns]::GetHostAddressesAsync($hostValue)
    $deadline=[datetime]::UtcNow.AddSeconds(3)
    while(-not $task.IsCompleted -and [datetime]::UtcNow -lt $deadline){
        if('System.Windows.Forms.Application' -as [type]){[System.Windows.Forms.Application]::DoEvents()}
        Start-Sleep -Milliseconds 25
    }
    if(-not $task.IsCompleted -or $task.IsFaulted -or $task.IsCanceled){throw 'The server hostname could not be resolved within three seconds.'}
    $addresses=@($task.Result | Sort-Object @{Expression={if($_.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork){0}else{1}}})
    if(-not $addresses.Count){throw 'The server hostname did not return an IP address.'}
    return $addresses[0].ToString()
}

function Get-GamingNetworkServersPath {Join-Path $script:GamingNetworkRoot 'state\network-servers.json'}

function Test-GamingNetworkServerData {
    param([object]$Value)
    try {
        if(-not $Value -or $Value.Id -notmatch '^server-[a-f0-9]{32}$' -or [string]$Value.Name -notmatch '^.{1,100}$' -or [string]$Value.Name -match '[\x00-\x1f]' -or $Value.Protocol -notin @('ICMP','TCP')){return $false}
        $null=ConvertTo-GamingNetworkHost ([string]$Value.HostName)
        if($Value.GameId -and [string]$Value.GameId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$'){return $false}
        if($Value.Protocol -eq 'TCP'){return ([int]$Value.Port -ge 1 -and [int]$Value.Port -le 65535)}
        return ([int]$Value.Port -eq 0)
    } catch {return $false}
}

function Test-GamingNetworkPreferences {
    param([object]$Value)
    try {
        if(-not $Value -or $Value.Protocol -notin @('ICMP','TCP') -or [int]$Value.Samples -lt 4 -or [int]$Value.Samples -gt 20 -or [int]$Value.Port -lt 1 -or [int]$Value.Port -gt 65535){return $false}
        $null=ConvertTo-GamingNetworkHost ([string]$Value.InternetAddress)
        if([string]$Value.TargetName -match '[\x00-\x1f]' -or ([string]$Value.TargetName).Length -gt 160){return $false}
        if($Value.GameId -and [string]$Value.GameId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$'){return $false}
        return $true
    } catch {return $false}
}

function Get-GamingNetworkPreferences {
    $default=[pscustomobject]@{Version=1;InternetAddress='1.1.1.1';Protocol='ICMP';Port=443;Samples=12;TargetName='Cloudflare reference';GameId=''}
    $path=Join-Path $script:GamingNetworkRoot 'state\network-preferences.json'
    if(Test-Path -LiteralPath $path -PathType Leaf){try {$saved=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json;if([int]$saved.Version -eq 1 -and (Test-GamingNetworkPreferences $saved)){return $saved}}catch{ }}
    return $default
}

function Save-GamingNetworkPreferences {
    param([Parameter(Mandatory=$true)][object]$Preferences)
    if(-not(Test-GamingNetworkPreferences $Preferences)){throw 'Invalid network test settings.'}
    $value=[pscustomobject]@{Version=1;InternetAddress=(ConvertTo-GamingNetworkHost $Preferences.InternetAddress);Protocol=[string]$Preferences.Protocol;Port=[int]$Preferences.Port;Samples=[int]$Preferences.Samples;TargetName=[string]$Preferences.TargetName;GameId=[string]$Preferences.GameId}
    $directory=Join-Path $script:GamingNetworkRoot 'state';if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force | Out-Null}
    $pending=Join-Path $directory ('network-preferences.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    $value | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination (Join-Path $directory 'network-preferences.json') -Force
    return $value
}

function Read-GamingNetworkServers {
    $path=Get-GamingNetworkServersPath
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    try {
        $data=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if([int]$data.Version -ne 1){return @()}
        foreach($row in @($data.Servers)){
            try {
                if(-not(Test-GamingNetworkServerData $row)){continue}
                $hostValue=ConvertTo-GamingNetworkHost ([string]$row.HostName)
                if($row.Protocol -eq 'TCP' -and ([int]$row.Port -lt 1 -or [int]$row.Port -gt 65535)){continue}
                [pscustomobject]@{Id=[string]$row.Id;Name=[string]$row.Name;GameId=[string]$row.GameId;GameName=[string]$row.GameName;HostName=$hostValue;Protocol=[string]$row.Protocol;Port=$(if($row.Protocol -eq 'TCP'){[int]$row.Port}else{0});Source='Saved server';Notes='User-provided endpoint. This probe is a diagnostic estimate, not the in-game latency counter.';SourceUrl=''}
            } catch { }
        }
    } catch {return @()}
}

function Write-GamingNetworkServers {
    param([object[]]$Servers)
    $path=Get-GamingNetworkServersPath;$directory=Split-Path $path -Parent
    if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force | Out-Null}
    $pending=Join-Path $directory ('network-servers.'+[guid]::NewGuid().ToString('N')+'.pending.json')
    [pscustomobject]@{Version=1;Servers=@($Servers)} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pending -Encoding UTF8
    Move-Item -LiteralPath $pending -Destination $path -Force
}

function Save-GamingNetworkServer {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$HostName,[ValidateSet('ICMP','TCP')][string]$Protocol='ICMP',[ValidateRange(0,65535)][int]$Port=0,[string]$GameId='',[string]$Id='')
    $nameValue=$Name.Trim()
    if(-not $nameValue -or $nameValue.Length -gt 100 -or $nameValue -match '[\x00-\x1f]'){throw 'Use a server name of 1 to 100 characters.'}
    $hostValue=ConvertTo-GamingNetworkHost $HostName
    if($Protocol -eq 'TCP' -and $Port -lt 1){throw 'TCP tests need a port from 1 to 65535.'}
    if($GameId -and $GameId -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$'){throw 'Invalid game identifier.'}
    $game=$null
    if($GameId -and (Get-Command Get-GameLibrary -ErrorAction SilentlyContinue)){$game=Get-GameLibrary | Where-Object Id -eq $GameId | Select-Object -First 1;if(-not $game){throw 'Choose an installed game or leave the game blank.'}}
    if(-not $Id){$Id='server-'+[guid]::NewGuid().ToString('N')}
    if($Id -notmatch '^server-[a-f0-9]{32}$'){throw 'Invalid saved server identifier.'}
    $servers=@(Read-GamingNetworkServers | Where-Object Id -ne $Id)
    if($servers.Count -ge 200){throw 'The server list is full. Remove an unused server first.'}
    $row=[pscustomobject]@{Id=$Id;Name=$nameValue;GameId=$GameId;GameName=[string]$game.Name;HostName=$hostValue;Protocol=$Protocol;Port=$(if($Protocol -eq 'TCP'){$Port}else{0});Source='Saved server';Notes='User-provided endpoint. This probe is a diagnostic estimate, not the in-game latency counter.';SourceUrl=''}
    Write-GamingNetworkServers (@($servers)+@($row))
    return $row
}

function Remove-GamingNetworkServer {
    param([Parameter(Mandatory=$true)][string]$Id)
    if($Id -notmatch '^server-[a-f0-9]{32}$'){throw 'Only your saved server entries can be removed.'}
    Write-GamingNetworkServers @(Read-GamingNetworkServers | Where-Object Id -ne $Id)
    return [pscustomobject]@{Success=$true;Message='Saved server removed.'}
}

function Get-GamingNetworkServers {
    param([string]$GameId='')
    $games=@();if(Get-Command Get-GameLibrary -ErrorAction SilentlyContinue){$games=@(Get-GameLibrary)}
    foreach($pair in @(@('Cloudflare reference','1.1.1.1'),@('Google reference','8.8.8.8'),@('Quad9 reference','9.9.9.9'))){
        [pscustomobject]@{Id=('reference-'+$pair[1]);Name=$pair[0];GameId='';GameName='Internet reference';HostName=$pair[1];Protocol='ICMP';Port=0;Source='Internet reference';Notes='Reference connectivity only; not a game server.';SourceUrl=''}
    }
    foreach($row in @(Read-GamingNetworkServers)){if(-not $GameId -or -not $row.GameId -or $row.GameId -eq $GameId){$row}}
    # Epic publishes these diagnostic endpoints. Other games are not assigned guessed server IPs.
    $fortnite=@($games | Where-Object {$_.Name -match '(?i)^Fortnite(?:\s|$)' -and (-not $GameId -or $_.Id -eq $GameId)} | Select-Object -First 1)
    if($fortnite.Count){
        $url='https://www.epicgames.com/help/c-36624475/c-5719341627163/a22355516?lang=en-US'
        foreach($region in @(@('Oregon','or'),@('Northern California','ncal'),@('Iowa','ia'),@('Texas','tx'),@('Mexico','mx'),@('Ohio','oh'),@('Virginia','va'),@('United Kingdom','gb'),@('France','fr'),@('Germany','de'),@('Sao Paulo','sao'),@('Tokyo','tok'),@('Sydney','syd'),@('Bahrain','bah'),@('Mumbai','mum'),@('Israel','il'))){
            [pscustomobject]@{Id=('fortnite-'+$region[1]);Name=('Fortnite - '+$region[0]);GameId=$fortnite[0].Id;GameName='Fortnite';HostName=('ping-'+$region[1]+'.ds.on.epicgames.com');Protocol='ICMP';Port=0;Source='Epic published endpoint';Notes='Regional diagnostic endpoint, verified 2026-11-23. A match may use another datacenter; ICMP differs from gameplay UDP.';SourceUrl=$url}
        }
    }
}

function Get-GamingNetworkGameGuidance {
    param([string]$GameId='')
    $game=$null;if($GameId -and (Get-Command Get-GameLibrary -ErrorAction SilentlyContinue)){$game=Get-GameLibrary | Where-Object Id -eq $GameId | Select-Object -First 1}
    if($game.Name -match '(?i)^Fortnite(?:\s|$)'){return [pscustomobject]@{Message='Choose an Epic regional endpoint below. Compare its ICMP result with the game''s own network statistics; the probes do not select your matchmaking region.';SourceUrl='https://www.epicgames.com/help/c-36624475/c-5719341627163/a22355516?lang=en-US';SupportsPublishedEndpoints=$true}}
    if($game.Name -match '(?i)Apex Legends'){return [pscustomobject]@{Message='Apex lists its live data centers on the launch screen. Enable Settings > Gameplay > Performance Display for actual match latency and packet loss. You can also save a known server address here.';SourceUrl='https://help.ea.com/en/articles/apex-legends/troubleshoot-ping-packet-loss-lag/';SupportsPublishedEndpoints=$false}}
    return [pscustomobject]@{Message='No verified fixed diagnostic server list is bundled for this game. Use its in-game network statistics, save your server address, or inspect active TCP connections while it runs. Active connections may be login, relay or content services rather than the match server; UDP match endpoints are not discovered here.';SourceUrl='';SupportsPublishedEndpoints=$false}
}

function Get-GamingActiveGameEndpoints {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$GameId)
    if(-not(Get-Command Get-GameLibrary -ErrorAction SilentlyContinue)){return @()}
    $game=Get-GameLibrary | Where-Object Id -eq $GameId | Select-Object -First 1
    if(-not $game -or -not $game.ExecutablePath -or $game.IsLauncher){return @()}
    $targetPath=[IO.Path]::GetFullPath([string]$game.ExecutablePath)
    $processes=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {$_.ExecutablePath -and [string]$_.ExecutablePath -ieq $targetPath})
    $seen=@{}
    foreach($process in $processes){
        foreach($connection in @(Get-NetTCPConnection -OwningProcess ([uint32]$process.ProcessId) -State Established -ErrorAction SilentlyContinue | Select-Object -First 100)){
            $address=$null
            if(-not [Net.IPAddress]::TryParse([string]$connection.RemoteAddress,[ref]$address) -or [Net.IPAddress]::IsLoopback($address) -or [int]$connection.RemotePort -lt 1){continue}
            $key=$address.ToString()+':'+[int]$connection.RemotePort;if($seen.ContainsKey($key)){continue};$seen[$key]=$true
            [pscustomobject]@{Id=('active-'+$process.ProcessId+'-'+$seen.Count);Name=($game.Name+' - '+$key);GameId=$game.Id;GameName=$game.Name;HostName=$address.ToString();Protocol='TCP';Port=[int]$connection.RemotePort;Source='Active TCP connection';Notes='Observed connection from the bound game EXE. It may be a login, CDN, telemetry or relay service, not a match server. TCP connect time is not gameplay RTT.';SourceUrl='https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-nettcpconnection'}
        }
    }
}

function Get-GamingNetworkGateway {
    $physical=@(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {[int]$_.ifIndex})
    $routes=@(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object {
        [int]$_.InterfaceIndex -in $physical -and $_.NextHop -and $_.NextHop -ne '0.0.0.0'
    } | Sort-Object @{Expression={[int]$_.RouteMetric+[int]$_.InterfaceMetric}})
    foreach($route in $routes) {
        $address=$null
        if([Net.IPAddress]::TryParse([string]$route.NextHop,[ref]$address) -and $address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
            return [pscustomobject]@{Address=[string]$route.NextHop;InterfaceAlias=[string]$route.InterfaceAlias}
        }
    }
    return $null
}

function Write-GamingNetworkProgress([string]$Message) {
    if(Get-Command Write-GamingStatus -ErrorAction SilentlyContinue){Write-GamingStatus $Message}
    if('System.Windows.Forms.Application' -as [type]){[System.Windows.Forms.Application]::DoEvents()}
}

function Initialize-GamingNetworkNative {
    if('GamingNetworkProbe' -as [type]){return}
    Add-Type -ReferencedAssemblies 'System.dll','System.Core.dll' -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;
public sealed class GamingNetworkProbeResult { public bool Success; public double RoundtripTime; }
public static class GamingNetworkProbe {
    public static async Task<GamingNetworkProbeResult> Tcp(string address, int port, int timeout) {
        var result = new GamingNetworkProbeResult();
        IPAddress parsed = IPAddress.Parse(address);
        using (var client = new TcpClient(parsed.AddressFamily)) {
            try {
                var clock = Stopwatch.StartNew();
                Task connect = client.ConnectAsync(parsed, port);
                Task complete = await Task.WhenAny(connect, Task.Delay(timeout)).ConfigureAwait(false);
                if (complete == connect) {
                    await connect.ConfigureAwait(false);
                    clock.Stop();
                    result.Success = client.Connected;
                    result.RoundtripTime = clock.Elapsed.TotalMilliseconds;
                } else {
                    client.Close();
                    // Observe a later socket exception after the timeout closes the socket.
                    GC.KeepAlive(connect.ContinueWith(t => { t.Exception.Handle(e => true); }, TaskContinuationOptions.OnlyOnFaulted));
                }
            } catch (SocketException) { } catch (ObjectDisposedException) { }
        }
        return result;
    }
}
'@
}

function Invoke-GamingPingPair {
    param([string]$GatewayAddress,[ValidateRange(100,1500)][int]$TimeoutMilliseconds=1000,[string]$InternetAddress='1.1.1.1',[ValidateSet('ICMP','TCP')][string]$Protocol='ICMP',[ValidateRange(1,65535)][int]$Port=443)
    $probes=@()
    if($GatewayAddress){$probes+=@{Name='Gateway';Address=$GatewayAddress;Ping=(New-Object Net.NetworkInformation.Ping);Client=$null;Task=$null;Clock=$null;Protocol='ICMP'}}
    if($Protocol -eq 'TCP'){Initialize-GamingNetworkNative}
    $probes+=@{Name='Internet';Address=$InternetAddress;Ping=$(if($Protocol -eq 'ICMP'){New-Object Net.NetworkInformation.Ping}else{$null});Client=$null;Task=$null;Clock=$null;Protocol=$Protocol}
    try {
        foreach($probe in $probes){
            try {
                if($probe.Protocol -eq 'TCP'){$probe.Task=[GamingNetworkProbe]::Tcp([string]$probe.Address,$Port,$TimeoutMilliseconds)}
                else {$probe.Task=$probe.Ping.SendPingAsync([string]$probe.Address,[int]$TimeoutMilliseconds)}
            }catch{ }
        }
        $deadline=[datetime]::UtcNow.AddMilliseconds($TimeoutMilliseconds+250)
        while(@($probes | Where-Object {$_.Task -and -not $_.Task.IsCompleted}).Count -gt 0 -and [datetime]::UtcNow -lt $deadline){
            if('System.Windows.Forms.Application' -as [type]){[System.Windows.Forms.Application]::DoEvents()}
            Start-Sleep -Milliseconds 25
        }
        $result=@{Gateway=$null;Internet=$null}
        foreach($probe in $probes){
            if($probe.Protocol -eq 'TCP'){
                $ok=$probe.Task -and $probe.Task.IsCompleted -and -not $probe.Task.IsFaulted -and -not $probe.Task.IsCanceled -and $probe.Task.Result.Success
                $result[$probe.Name]=[pscustomobject]@{Success=[bool]$ok;RoundtripTime=$(if($ok){[math]::Round([double]$probe.Task.Result.RoundtripTime,2)}else{$null})};continue
            }
            $reply=$null
            if($probe.Task -and $probe.Task.IsCompleted -and -not $probe.Task.IsFaulted -and -not $probe.Task.IsCanceled){
                try {$reply=$probe.Task.Result}catch{ }
            }
            $result[$probe.Name]=[pscustomobject]@{Success=($reply -and $reply.Status -eq [Net.NetworkInformation.IPStatus]::Success);RoundtripTime=$(if($reply -and $reply.Status -eq [Net.NetworkInformation.IPStatus]::Success){[double]$reply.RoundtripTime}else{$null})}
        }
        return [pscustomobject]$result
    } finally {
        foreach($probe in $probes){if($probe.Ping){$probe.Ping.Dispose()};if($probe.Client){$probe.Client.Close();$probe.Client.Dispose()}}
    }
}

function Get-GamingPingSummary {
    param([string]$Label,[string]$Address,[double[]]$Samples,[int]$Sent)
    $samplesArray=@($Samples)
    $jitter=@()
    for($i=1;$i -lt $samplesArray.Count;$i++){$jitter+=[math]::Abs($samplesArray[$i]-$samplesArray[$i-1])}
    [pscustomobject]@{
        Label=$Label;Address=$Address;Available=($Sent -gt 0);Sent=$Sent;Received=$samplesArray.Count
        AverageMs=$(if($samplesArray.Count){[math]::Round(($samplesArray | Measure-Object -Average).Average,2)}else{$null})
        JitterMs=$(if($jitter.Count){[math]::Round(($jitter | Measure-Object -Average).Average,2)}else{$null})
        LossPercent=$(if($Sent -gt 0){[math]::Round((($Sent-$samplesArray.Count)*100.0/$Sent),2)}else{$null})
        MinMs=$(if($samplesArray.Count){($samplesArray | Measure-Object -Minimum).Minimum}else{$null})
        MaxMs=$(if($samplesArray.Count){($samplesArray | Measure-Object -Maximum).Maximum}else{$null})
    }
}

function Get-GamingNetworkHistoryPath {Join-Path $script:GamingNetworkRoot 'state\network-history.json'}

function Get-GamingNetworkHistory {
    $path=Get-GamingNetworkHistoryPath
    if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return @()}
    try {
        $saved=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        foreach($entry in @($saved)){if($entry -and $entry.CheckedUtc){$entry}}
    } catch {return @()}
}

function Invoke-GamingNetworkTest {
    [CmdletBinding()]
    param([ValidateRange(4,20)][int]$Samples=12,[string]$InternetAddress='1.1.1.1',[ValidateSet('ICMP','TCP')][string]$Protocol='ICMP',[ValidateRange(1,65535)][int]$Port=443,[string]$TargetName='',[string]$GameId='')
    $InternetAddress=ConvertTo-GamingNetworkHost $InternetAddress
    if($TargetName.Length -gt 160 -or $TargetName -match '[\x00-\x1f]'){throw 'Use a target name of up to 160 characters.'}
    Save-GamingNetworkPreferences ([pscustomobject]@{InternetAddress=$InternetAddress;Protocol=$Protocol;Port=$Port;Samples=$Samples;TargetName=$TargetName;GameId=$GameId}) | Out-Null
    $resolved=Resolve-GamingNetworkAddress $InternetAddress
    $gateway=Get-GamingNetworkGateway
    $routerTimes=New-Object 'System.Collections.Generic.List[double]'
    $internetTimes=New-Object 'System.Collections.Generic.List[double]'
    $sent=0
    $deadline=[datetime]::UtcNow.AddSeconds(26)
    for($i=1;$i -le $Samples;$i++) {
        if([datetime]::UtcNow -ge $deadline){break}
        Write-GamingNetworkProgress ('Measuring '+$Protocol+' to '+$InternetAddress+': '+$i+' / '+$Samples+'...')
        $pair=Invoke-GamingPingPair -GatewayAddress ([string]$gateway.Address) -InternetAddress $resolved -Protocol $Protocol -Port $Port
        $sent++
        if($gateway -and $pair.Gateway.Success){$routerTimes.Add([double]$pair.Gateway.RoundtripTime)}
        if($pair.Internet.Success){$internetTimes.Add([double]$pair.Internet.RoundtripTime)}
        if($i -lt $Samples){Start-Sleep -Milliseconds 100}
    }
    $history=@(Get-GamingNetworkHistory)
    $previous=$history|Where-Object{$_.Internet.Address -eq $InternetAddress -and $_.InterfaceAlias -eq [string]$gateway.InterfaceAlias -and ($(if($_.Protocol){$_.Protocol}else{'ICMP'})) -eq $Protocol -and ($Protocol -ne 'TCP' -or [int]$_.Port -eq $Port)}|Select-Object -Last 1
    $label=if($TargetName){$TargetName}elseif($Protocol -eq 'TCP'){'TCP connection to chosen server'}elseif($InternetAddress -in @('1.1.1.1','8.8.8.8','9.9.9.9')){'Internet reference (not game-server ping)'}else{'ICMP to chosen server'}
    $targetSummary=Get-GamingPingSummary -Label $label -Address $InternetAddress -Samples $internetTimes.ToArray() -Sent $sent
    $targetSummary | Add-Member -NotePropertyName FailureLabel -NotePropertyValue $(if($Protocol -eq 'TCP'){'Connection failure % (not packet loss)'}else{'ICMP unanswered %'})
    $result=[pscustomobject]@{
        Gateway=Get-GamingPingSummary -Label 'Router' -Address ([string]$gateway.Address) -Samples $routerTimes.ToArray() -Sent $(if($gateway){$sent}else{0})
        Internet=$targetSummary;Target=$targetSummary;Protocol=$Protocol;Port=$(if($Protocol -eq 'TCP'){$Port}else{0});TargetName=$TargetName;GameId=$GameId;ResolvedAddress=$resolved
        InterfaceAlias=[string]$gateway.InterfaceAlias;CheckedUtc=[datetime]::UtcNow.ToString('o')
        Measurement=$(if($Protocol -eq 'TCP'){'TCP handshake duration to the selected host and port. Connection failures are not packet-loss measurements. This is not gameplay RTT, bandwidth or input latency.'}else{'ICMP diagnostic latency to the selected endpoint. Games may use different servers, UDP paths or packet priorities. Unanswered ICMP does not prove gameplay packet loss. This is not bandwidth or input latency.'})
        Success=($targetSummary.Received -gt 0);Message=$(if($targetSummary.Received -gt 0){'Server latency measurement complete.'}else{'No probe replies. The server may block this probe or the chosen port may be closed; compare with in-game network statistics.'})
        PreviousCheckedUtc=$(if($previous){$previous.CheckedUtc}else{$null})
        InternetAverageChangeMs=$null
    }
    if($previous -and $null -ne $previous.Internet.AverageMs -and $null -ne $result.Internet.AverageMs){
        $result.InternetAverageChangeMs=[math]::Round(($result.Internet.AverageMs-$previous.Internet.AverageMs),2)
    }
    $save=Get-GamingNetworkHistoryPath
    $directory=Split-Path $save -Parent
    if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory -Force | Out-Null}
    $updated=@(@($history)+@($result) | Select-Object -Last 20)
    $temporary=Join-Path $directory ('network.'+[Guid]::NewGuid().ToString('N')+'.pending.json')
    ConvertTo-Json -InputObject $updated -Depth 12 | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $save -Force
    Write-GamingNetworkProgress 'Network measurement complete. Compare results under the same conditions.'
    return $result
}
