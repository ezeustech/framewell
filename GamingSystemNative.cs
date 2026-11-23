// Original interop implementation. See SystemToolsReferences.txt for API contracts.
using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading;

public sealed class GamingProcessState {
    public int ProcessId;
    public string ExecutablePath;
    public long StartTimeTicks;
    public string Priority;
    public ulong Affinity;
    public ulong SystemAffinity;
}
public sealed class GamingMemoryState {
    public double TotalMB, AvailableMB, StandbyMB, FreeMB;
    public uint MemoryLoadPercent;
    public double CurrentTimerMs, MinimumTimerMs, MaximumTimerMs;
    public bool StandbyAvailable;
    public string Message;
}
public sealed class GamingMemoryRuntimeState {
    public bool MonitorRunning, TimerEnabled, NativeTimer;
    public double TimerMilliseconds, RequestedTimerMilliseconds, ObservedTimerMilliseconds;
    public long PurgeCount;
    public string LastMessage;
}
public static class GamingSystemNative {
    const uint Query = 0x1000, Set = 0x0200;
    [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint rights, bool inherit, int id);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool QueryFullProcessImageName(IntPtr h, uint flags, StringBuilder text, ref uint size);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessTimes(IntPtr h, out long created, out long exited, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError=true)] static extern uint GetPriorityClass(IntPtr h);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetPriorityClass(IntPtr h, uint value);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessAffinityMask(IntPtr h, out UIntPtr process, out UIntPtr system);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetProcessAffinityMask(IntPtr h, UIntPtr mask);
    [DllImport("kernel32.dll")] public static extern ushort GetActiveProcessorGroupCount();
    [DllImport("kernel32.dll")] public static extern uint GetActiveProcessorCount(ushort group);
    [StructLayout(LayoutKind.Sequential)] struct MemoryStatus {
        public uint Length, Load;
        public ulong TotalPhysical, AvailablePhysical, TotalPageFile, AvailablePageFile, TotalVirtual, AvailableVirtual, AvailableExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(int informationClass, IntPtr buffer, uint length, out uint returned);
    [DllImport("ntdll.dll")] static extern int NtSetSystemInformation(int informationClass, ref int command, uint length);
    [DllImport("ntdll.dll")] static extern int NtQueryTimerResolution(out uint maximum, out uint minimum, out uint current);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
    [StructLayout(LayoutKind.Sequential)] struct Luid { public uint LowPart; public int HighPart; }
    [StructLayout(LayoutKind.Sequential)] struct TokenPrivileges { public uint Count; public Luid Luid; public uint Attributes; }
    [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool LookupPrivilegeValue(string system, string name, out Luid luid);
    [DllImport("advapi32.dll", SetLastError=true)] static extern bool AdjustTokenPrivileges(IntPtr token, bool disableAll, ref TokenPrivileges state, int size, out TokenPrivileges previous, out int returned);
    static readonly object Gate = new object();
    static Timer monitor;
    static bool monitoring;
    static readonly GamingTimerRequest timerRequest = new GamingTimerRequest(new GamingNativeTimerApi());
    static long purgeCount;
    static string lastMessage = "Memory tools are off.";
    static GamingSystemNative(){AppDomain.CurrentDomain.ProcessExit+=delegate(object sender,EventArgs args){try{StopAll();}catch{ }};}

    static void Check(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    static uint PriorityValue(string value) {
        switch(value) {
            case "Idle": return 0x40; case "BelowNormal": return 0x4000;
            case "Normal": return 0x20; case "AboveNormal": return 0x8000; case "High": return 0x80;
            default: throw new ArgumentException("Unsupported priority. Realtime is intentionally excluded.");
        }
    }
    static string PriorityName(uint value) {
        switch(value) {
            case 0x40:return "Idle";case 0x4000:return "BelowNormal";case 0x20:return "Normal";
            case 0x8000:return "AboveNormal";case 0x80:return "High";case 0x100:return "RealTime";
            default:return "Unknown";
        }
    }
    static GamingProcessState ReadHandle(IntPtr handle, int id) {
        uint length=32768; StringBuilder name=new StringBuilder((int)length);
        Check(QueryFullProcessImageName(handle,0,name,ref length));
        long created,exited,kernel,user; Check(GetProcessTimes(handle,out created,out exited,out kernel,out user));
        uint priority=GetPriorityClass(handle); if(priority==0)throw new Win32Exception();
        UIntPtr affinity,system;
        bool readMask=GetProcessAffinityMask(handle,out affinity,out system);
        return new GamingProcessState { ProcessId=id, ExecutablePath=name.ToString(),
            StartTimeTicks=DateTime.FromFileTimeUtc(created).Ticks, Priority=PriorityName(priority),
            Affinity=readMask?affinity.ToUInt64():0, SystemAffinity=readMask?system.ToUInt64():0 };
    }
    public static GamingProcessState ReadProcess(int id) {
        IntPtr handle=OpenProcess(Query,false,id); if(handle==IntPtr.Zero)throw new Win32Exception();
        try {return ReadHandle(handle,id);} finally {CloseHandle(handle);}
    }
    public static GamingProcessState WriteProcess(int id,string expectedPath,long expectedStartTicks,string priority,ulong mask,bool changeAffinity) {
        // The same open handle is used for identity validation and every write, preventing PID reuse races.
        IntPtr handle=OpenProcess(Query|Set,false,id); if(handle==IntPtr.Zero)throw new Win32Exception();
        try {
            GamingProcessState before=ReadHandle(handle,id);
            if(before.StartTimeTicks!=expectedStartTicks || !String.Equals(before.ExecutablePath,expectedPath,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("The game process changed. Refresh and try again.");
            if(priority!="Unchanged")PriorityValue(priority);
            if(changeAffinity && (GetActiveProcessorGroupCount()!=1 || mask==0 || before.SystemAffinity==0 || (mask & before.SystemAffinity)!=mask))throw new ArgumentException("Invalid or unsupported processor affinity.");
            bool affinityWritten=false,priorityWritten=false;
            try {
                if(changeAffinity && before.Affinity!=mask){Check(SetProcessAffinityMask(handle,new UIntPtr(mask)));affinityWritten=true;}
                if(priority!="Unchanged" && priority!=before.Priority){Check(SetPriorityClass(handle,PriorityValue(priority)));priorityWritten=true;}
                return ReadHandle(handle,id);
            } catch {
                if(priorityWritten && before.Priority!="RealTime" && before.Priority!="Unknown")SetPriorityClass(handle,PriorityValue(before.Priority));
                if(affinityWritten)SetProcessAffinityMask(handle,new UIntPtr(before.Affinity));
                throw;
            }
        } finally {CloseHandle(handle);}
    }
    public static ulong Mask(int[] indices) {
        if(GetActiveProcessorGroupCount()!=1)throw new NotSupportedException("Affinity selection is unavailable on systems with multiple processor groups.");
        uint count=GetActiveProcessorCount(0); ulong mask=0;
        foreach(int index in indices){if(index<0||index>=count||index>=64)throw new ArgumentOutOfRangeException("indices");mask|=1UL<<index;}
        if(mask==0)throw new ArgumentException("Choose at least one logical processor.");return mask;
    }
    public static int[] Indices(ulong mask) {
        System.Collections.Generic.List<int> result=new System.Collections.Generic.List<int>();
        for(int index=0;index<64;index++)if((mask & (1UL<<index))!=0)result.Add(index);return result.ToArray();
    }
    public static GamingMemoryState ReadMemory() {
        MemoryStatus status=new MemoryStatus();status.Length=(uint)Marshal.SizeOf(typeof(MemoryStatus));Check(GlobalMemoryStatusEx(ref status));
        GamingMemoryState result=new GamingMemoryState {TotalMB=status.TotalPhysical/1048576.0,AvailableMB=status.AvailablePhysical/1048576.0,MemoryLoadPercent=status.Load,StandbyMB=-1,FreeMB=-1,Message="Standby is reusable file cache, already included in available RAM."};
        // Native memory-list information is version-dependent. Failure hides standby rather than inventing a value.
        int bytes=IntPtr.Size*22;IntPtr buffer=Marshal.AllocHGlobal(bytes);
        try {
            uint returned;int code=NtQuerySystemInformation(80,buffer,(uint)bytes,out returned);
            if(code==0 && returned<=bytes){
                ulong zero=ReadSize(buffer,0),free=ReadSize(buffer,1),standby=0;
                for(int index=5;index<13;index++)standby+=ReadSize(buffer,index);
                double page=Environment.SystemPageSize/1048576.0;
                result.FreeMB=(zero+free)*page;result.StandbyMB=standby*page;result.StandbyAvailable=true;
                if(result.StandbyMB>result.TotalMB || result.FreeMB>result.TotalMB){result.StandbyAvailable=false;result.FreeMB=-1;result.StandbyMB=-1;}
            }
        } finally {Marshal.FreeHGlobal(buffer);}
        uint max,min,current;if(NtQueryTimerResolution(out max,out min,out current)==0){result.MaximumTimerMs=max/10000.0;result.MinimumTimerMs=min/10000.0;result.CurrentTimerMs=current/10000.0;}
        if(!result.StandbyAvailable)result.Message="Windows did not expose standby-list counters. Available RAM remains valid.";
        return result;
    }
    static ulong ReadSize(IntPtr buffer,int index) { return IntPtr.Size==8?unchecked((ulong)Marshal.ReadInt64(buffer,index*8)):unchecked((uint)Marshal.ReadInt32(buffer,index*4)); }
    public static bool IsAdministrator() { using(WindowsIdentity identity=WindowsIdentity.GetCurrent()){return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);} }
    public static void PurgeStandby() {
        if(!IsAdministrator())throw new UnauthorizedAccessException("Clearing the system standby list requires Windows administrator approval.");
        IntPtr token;Check(OpenProcessToken(GetCurrentProcess(),0x20|0x8,out token));
        TokenPrivileges previous=new TokenPrivileges();bool changed=false;
        try {
            Luid luid;Check(LookupPrivilegeValue(null,"SeProfileSingleProcessPrivilege",out luid));
            TokenPrivileges enabled=new TokenPrivileges{Count=1,Luid=luid,Attributes=2};int returned;
            Check(AdjustTokenPrivileges(token,false,ref enabled,Marshal.SizeOf(typeof(TokenPrivileges)),out previous,out returned));
            int error=Marshal.GetLastWin32Error();if(error!=0)throw new Win32Exception(error);changed=true;
            // Fixed MEMORY_LIST_COMMAND = MemoryPurgeStandbyList. Never empties process working sets.
            int command=4;int result=NtSetSystemInformation(80,ref command,4);
            if(result!=0)throw new InvalidOperationException("Windows rejected standby clearing (NTSTATUS 0x"+unchecked((uint)result).ToString("X8")+").");
            lock(Gate){purgeCount++;lastMessage="Standby list cleared at "+DateTime.Now.ToString("T")+". Cached files may need to be read again.";}
        } finally {
            if(changed){TokenPrivileges ignored;int returned;AdjustTokenPrivileges(token,false,ref previous,Marshal.SizeOf(typeof(TokenPrivileges)),out ignored,out returned);}
            CloseHandle(token);
        }
    }
    public static void SetTimer(bool enabled,double milliseconds) {
        lock(Gate){
            timerRequest.Set(enabled,milliseconds);
            lastMessage=enabled?(timerRequest.Native?"Experimental native timer request active. Windows timer readback does not prove a game uses that resolution.":"Documented timer request active for this app; it does not force another game's timing."):"This app's timer request was released.";
        }
    }
    public static void StartMonitor(int standbyMB,int availableMB,int seconds) {
        if(standbyMB<128||standbyMB>1048576||availableMB<128||availableMB>1048576||seconds<15||seconds>600)throw new ArgumentOutOfRangeException();
        if(!IsAdministrator())throw new UnauthorizedAccessException("The standby monitor needs administrator approval.");
        if(!ReadMemory().StandbyAvailable)throw new NotSupportedException("Windows did not expose standby counters. Automatic clearing remains off.");
        lock(Gate){
            StopMonitor();monitoring=true;lastMessage="Monitoring memory thresholds every "+seconds+" seconds.";
            monitor=new Timer(delegate(object ignored){lock(Gate){if(!monitoring)return;try{GamingMemoryState memory=ReadMemory();if(!memory.StandbyAvailable)throw new NotSupportedException("Standby counters became unavailable.");if(ShouldPurge(memory,standbyMB,availableMB))PurgeStandby();}catch(Exception error){StopMonitor();lastMessage="Monitor stopped: "+error.Message;}}},null,seconds*1000,seconds*1000);
        }
    }
    public static bool ShouldPurge(GamingMemoryState memory,int standbyMB,int availableMB) {
        return memory!=null && memory.StandbyAvailable && memory.StandbyMB>=standbyMB && memory.AvailableMB<=availableMB;
    }
    public static void StopMonitor() {lock(Gate){monitoring=false;if(monitor!=null){monitor.Dispose();monitor=null;}}}
    public static GamingMemoryRuntimeState Runtime() {lock(Gate){return new GamingMemoryRuntimeState{MonitorRunning=monitoring,TimerEnabled=timerRequest.Active,NativeTimer=timerRequest.Native,TimerMilliseconds=timerRequest.EffectiveMilliseconds,RequestedTimerMilliseconds=timerRequest.RequestedMilliseconds,ObservedTimerMilliseconds=timerRequest.ObservedMilliseconds,PurgeCount=purgeCount,LastMessage=lastMessage};}}
    public static void StopAll() {StopMonitor();lock(Gate){timerRequest.Set(false,1);lastMessage="Memory tools stopped.";}}
}

// An injectable timer boundary permits complete acquire/release tests without changing Windows timers.
public interface IGamingTimerApi {
    int Query(out uint maximum,out uint minimum,out uint current);
    uint Begin(uint milliseconds);
    uint End(uint milliseconds);
    int Native(uint resolution,bool acquire,out uint actual);
}
public sealed class GamingNativeTimerApi : IGamingTimerApi {
    [DllImport("ntdll.dll")] static extern int NtQueryTimerResolution(out uint maximum,out uint minimum,out uint current);
    [DllImport("ntdll.dll")] static extern int NtSetTimerResolution(uint desired,[MarshalAs(UnmanagedType.U1)]bool set,out uint current);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint period);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint period);
    public int Query(out uint maximum,out uint minimum,out uint current){return NtQueryTimerResolution(out maximum,out minimum,out current);}
    public uint Begin(uint milliseconds){return timeBeginPeriod(milliseconds);}
    public uint End(uint milliseconds){return timeEndPeriod(milliseconds);}
    public int Native(uint resolution,bool acquire,out uint actual){return NtSetTimerResolution(resolution,acquire,out actual);}
}
public sealed class GamingTimerRequest {
    readonly IGamingTimerApi api;
    readonly object gate=new object();
    public bool Active {get;private set;}
    public bool Native {get;private set;}
    public double RequestedMilliseconds {get;private set;}
    public double EffectiveMilliseconds {get;private set;}
    public double ObservedMilliseconds {get;private set;}
    uint nativeUnits;
    public GamingTimerRequest(IGamingTimerApi api){if(api==null)throw new ArgumentNullException("api");this.api=api;}
    void Release(){
        if(!Active)return;
        uint observed;
        bool success=Native?api.Native(nativeUnits,false,out observed)==0:api.End((uint)EffectiveMilliseconds)==0;
        if(!success)throw new InvalidOperationException("Windows could not release this app's timer request. The active request remains tracked; retry stop or exit the app.");
        Active=false;Native=false;RequestedMilliseconds=0;EffectiveMilliseconds=0;ObservedMilliseconds=0;nativeUnits=0;
    }
    public void Set(bool enabled,double milliseconds){
        if(Double.IsNaN(milliseconds)||Double.IsInfinity(milliseconds)||milliseconds<0.5||milliseconds>16||Math.Abs(milliseconds*2-Math.Round(milliseconds*2))>0.000001)throw new ArgumentOutOfRangeException("milliseconds","Choose 0.5 to 16 ms in steps of 0.5 ms.");
        lock(gate){
            if(!enabled){Release();return;}
            if(Active && RequestedMilliseconds==milliseconds)return;
            bool useNative=milliseconds!=Math.Truncate(milliseconds);
            uint effectiveUnits=0,maximum=0,minimum=0,current=0;
            if(useNative){
                if(api.Query(out maximum,out minimum,out current)!=0||minimum==0||maximum<minimum)throw new NotSupportedException("Windows did not expose valid native timer bounds; the existing request was preserved.");
                uint requested=(uint)Math.Round(milliseconds*10000.0);
                effectiveUnits=Math.Min(maximum,Math.Max(minimum,requested));
            }
            Release();
            uint actual;
            if(useNative){
                int result=api.Native(effectiveUnits,true,out actual);
                if(result!=0)throw new InvalidOperationException("Windows rejected the experimental timer request (NTSTATUS 0x"+unchecked((uint)result).ToString("X8")+").");
                Active=true;Native=true;nativeUnits=effectiveUnits;RequestedMilliseconds=milliseconds;EffectiveMilliseconds=effectiveUnits/10000.0;
                if(api.Query(out maximum,out minimum,out current)!=0||current==0){
                    Release();throw new InvalidOperationException("Native timer readback failed; the request was released.");
                }
                ObservedMilliseconds=current/10000.0;
            }else{
                if(api.Begin((uint)milliseconds)!=0)throw new InvalidOperationException("Windows rejected the documented timer request.");
                Active=true;Native=false;RequestedMilliseconds=milliseconds;EffectiveMilliseconds=milliseconds;
                if(api.Query(out maximum,out minimum,out current)==0)ObservedMilliseconds=current/10000.0;
            }
        }
    }
}
