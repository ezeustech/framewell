// Narrow NVAPI DRS bridge. ABI declarations/IDs follow NVIDIA's MIT-licensed
// nvapi.h, nvapi_interface.h and NvApiDriverSettings.h (NVIDIA/nvapi).
// No global-profile mutator, executable launch, shell, or file import API exists here.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace GamingNvidia {
 public sealed class DriverException : Exception {
  public readonly int Status;
  public DriverException(string operation,int status):base(operation+" failed (NVAPI "+status+").") {Status=status;}
 }
 public sealed class SettingState {
  public uint Id,Value,Location,IsCurrentPredefined,IsPredefinedValid,PredefinedValue,Type;
  public bool Found;
 }
 public sealed class ApplicationInfo {
  public string Name,FriendlyName,Launcher,FileInFolder,CommandLine; public uint Flags,IsPredefined;
 }
 public sealed class ProfileInfo {
  public bool Found,IsBase,IsPredefined; public string Name; public ApplicationInfo[] Applications;
 }
 [StructLayout(LayoutKind.Sequential,Pack=4,CharSet=CharSet.Unicode)] internal struct Setting {
  public uint Version;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=2048)] public string Name;
  public uint Id,Type,Location,CurrentPredefined,PredefinedValid;
  [MarshalAs(UnmanagedType.ByValArray,SizeConst=4100)] public byte[] Predefined;
  [MarshalAs(UnmanagedType.ByValArray,SizeConst=4100)] public byte[] Current;
  public static Setting Empty(uint id) {return new Setting {Version=(uint)Marshal.SizeOf(typeof(Setting))|0x10000,Id=id,Name="",Predefined=new byte[4100],Current=new byte[4100]};}
 }
 [StructLayout(LayoutKind.Sequential,Pack=8,CharSet=CharSet.Unicode)] internal struct App {
  public uint Version,Predefined;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=2048)] public string Name;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=2048)] public string Friendly;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=2048)] public string Launcher;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=2048)] public string FileInFolder;
  public uint Flags;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=2048)] public string CommandLine;
  public static App Empty() {return new App {Version=(uint)Marshal.SizeOf(typeof(App))|0x40000,Name="",Friendly="",Launcher="",FileInFolder="",CommandLine=""};}
 }
 [StructLayout(LayoutKind.Sequential,Pack=8,CharSet=CharSet.Unicode)] internal struct Profile {
  public uint Version;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=2048)] public string Name;
  public uint GpuSupport,Predefined,AppCount,SettingCount;
  public static Profile Empty() {return new Profile {Version=(uint)Marshal.SizeOf(typeof(Profile))|0x10000,Name=""};}
 }
 public sealed class Session : IDisposable {
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
  [DllImport("kernel32.dll",SetLastError=true)] [return:MarshalAs(UnmanagedType.Bool)] static extern bool FreeLibrary(IntPtr module);
  [DllImport("kernel32.dll",CharSet=CharSet.Ansi,ExactSpelling=true)] static extern IntPtr GetProcAddress(IntPtr module,string name);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate IntPtr Query(uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Init();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int Create(out IntPtr session);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SessionCall(IntPtr session);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int HandleCall(IntPtr session,IntPtr profile);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetBase(IntPtr session,out IntPtr profile);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl,CharSet=CharSet.Unicode)] delegate int FindApp(IntPtr session,[MarshalAs(UnmanagedType.LPWStr)]string name,out IntPtr profile,ref App app);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl,CharSet=CharSet.Unicode)] delegate int FindProfile(IntPtr session,[MarshalAs(UnmanagedType.LPWStr)]string name,out IntPtr profile);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int ProfileCall(IntPtr session,IntPtr profile,ref Profile info);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int CreateProfile(IntPtr session,ref Profile info,out IntPtr profile);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int AppCall(IntPtr session,IntPtr profile,ref App app);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int EnumApp(IntPtr session,IntPtr profile,uint index,ref uint count,[In,Out]App[] apps);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int GetSetting(IntPtr session,IntPtr profile,uint id,ref Setting setting);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SetSetting(IntPtr session,IntPtr profile,ref Setting setting);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DeleteSetting(IntPtr session,IntPtr profile,uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int DriverVersion(out uint version,[Out,MarshalAs(UnmanagedType.LPStr)]StringBuilder branch);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int SettingIds([Out]uint[] ids,ref uint count);
  static Query query; static readonly object initLock=new object(); static IntPtr library;
  static int activeSessions;
  IntPtr handle,baseProfile; bool libraryReferenceHeld;
  static T Function<T>(uint id) where T:class {IntPtr p=query(id);if(p==IntPtr.Zero)throw new NotSupportedException("NVAPI interface unavailable: "+id.ToString("X8"));return Marshal.GetDelegateForFunctionPointer(p,typeof(T)) as T;}
  static void Check(int status,string operation) {if(status!=0)throw new DriverException(operation,status);}
  public static uint[] AllowedIds { get {return new uint[]{0x1057EB71,0x00CE2691,0x00E73211,0x002ECAF2,0x0019BB68,0x00A879CF,0x0064B541,0x10835002,0x0005F543,0x10835000,0x007BA09E};} }
  static void Allowed(uint id) {if(Array.IndexOf(AllowedIds,id)<0)throw new ArgumentException("Setting ID is outside the fixed allowlist.");}
  public Session() {
   lock(initLock) {
    if(query==null) {
     if(!Environment.Is64BitProcess)throw new NotSupportedException("Use 64-bit Windows PowerShell for NVIDIA profiles.");
     try {
      if(library==IntPtr.Zero) {
       string dll=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"nvapi64.dll");
       library=LoadLibraryEx(dll,IntPtr.Zero,0x800);if(library==IntPtr.Zero)throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      }
      IntPtr p=GetProcAddress(library,"nvapi_QueryInterface");if(p==IntPtr.Zero)throw new NotSupportedException("NVIDIA QueryInterface is unavailable.");
      query=(Query)Marshal.GetDelegateForFunctionPointer(p,typeof(Query));Check(Function<Init>(0x0150e828)(),"Initialize");
     } catch {
      query=null;if(library!=IntPtr.Zero && FreeLibrary(library))library=IntPtr.Zero;
      throw;
     }
    }
    // Own the library reference before leaving the lock, including while a
    // concurrent constructor is still creating/loading its DRS session.
    activeSessions++;libraryReferenceHeld=true;
   }
   try {
    Check(Function<Create>(0x0694d52e)(out handle),"CreateSession");
    Check(Function<SessionCall>(0x375dbd6b)(handle),"LoadSettings");
    Check(Function<GetBase>(0xda8466a0)(handle,out baseProfile),"GetBaseProfile");
   } catch {try {Dispose();}catch {}throw;}
  }
  void EnsureOpen() {if(!libraryReferenceHeld || handle==IntPtr.Zero)throw new ObjectDisposedException("GamingNvidia.Session");}
  public string Driver {get {EnsureOpen();uint v;var b=new StringBuilder(64);Check(Function<DriverVersion>(0x2926aaad)(out v,b),"DriverVersion");return (v/100)+"."+(v%100).ToString("00")+" ("+b+")";}}
  public uint[] AvailableIds() {EnsureOpen();uint count=4096;var ids=new uint[count];Check(Function<SettingIds>(0xf020614a)(ids,ref count),"EnumAvailableSettingIds");Array.Resize(ref ids,(int)count);return ids;}
  IntPtr Find(string path,out App app) {EnsureOpen();app=App.Empty();IntPtr profile;int code=Function<FindApp>(0xeee566b2)(handle,path,out profile,ref app);if(code==-166)return IntPtr.Zero;Check(code,"FindApplicationByName");return profile;}
  Profile GetProfile(IntPtr profile) {var info=Profile.Empty();Check(Function<ProfileCall>(0x61cd6fd6)(handle,profile,ref info),"GetProfileInfo");return info;}
  App[] Apps(IntPtr profile) {
   var result=new List<App>();
   for(uint i=0;i<4096;i++) {uint count=1;var apps=new[]{App.Empty()};int code=Function<EnumApp>(0x7fa2173a)(handle,profile,i,ref count,apps);if(code==-7||count==0)break;Check(code,"EnumApplications");result.Add(apps[0]);}
   return result.ToArray();
  }
  public ProfileInfo Inspect(string path) {
   App match;IntPtr p=Find(path,out match);if(p==IntPtr.Zero)return new ProfileInfo {Found=false,Name="",Applications=new ApplicationInfo[0]};
   var raw=GetProfile(p);var apps=new List<ApplicationInfo>();foreach(var a in Apps(p))apps.Add(new ApplicationInfo {Name=a.Name,FriendlyName=a.Friendly,Launcher=a.Launcher,FileInFolder=a.FileInFolder,CommandLine=a.CommandLine,Flags=a.Flags,IsPredefined=a.Predefined});
   return new ProfileInfo {Found=true,Name=raw.Name,IsBase=p==baseProfile,IsPredefined=raw.Predefined!=0,Applications=apps.ToArray()};
  }
  IntPtr Target(string path,string expected,bool allowBaseRead) {
   App a;IntPtr p=Find(path,out a);if(p==IntPtr.Zero) {if(allowBaseRead)return baseProfile;throw new InvalidOperationException("The selected executable no longer has an NVIDIA profile.");}
   if(!allowBaseRead) {
    if(p==baseProfile||p==new IntPtr(-1))throw new InvalidOperationException("Global profile edits are forbidden.");
    var info=GetProfile(p);if(!String.Equals(info.Name,expected,StringComparison.Ordinal))throw new InvalidOperationException("The executable profile changed; refresh before applying.");
    var apps=Apps(p);if(apps.Length!=1)throw new InvalidOperationException("This NVIDIA profile is shared by other executables; no settings were changed.");
    if(apps[0].Flags!=0||!String.IsNullOrEmpty(apps[0].CommandLine))throw new InvalidOperationException("Command-line/packaged-app associations are not supported.");
   }
   return p;
  }
  public SettingState Read(string path,uint id) {Allowed(id);return ReadHandle(Target(path,null,true),id);}
  SettingState ReadHandle(IntPtr profile,uint id) {
   var s=Setting.Empty(id);int code=Function<GetSetting>(0x73bf8338)(handle,profile,id,ref s);if(code==-160)return new SettingState {Id=id,Found=false};Check(code,"GetSetting");
   return new SettingState {Id=id,Found=true,Value=BitConverter.ToUInt32(s.Current,0),Location=s.Location,IsCurrentPredefined=s.CurrentPredefined,IsPredefinedValid=s.PredefinedValid,PredefinedValue=BitConverter.ToUInt32(s.Predefined,0),Type=s.Type};
  }
  public string CreateForExecutable(string path,string name) {
   App found; if(Find(path,out found)!=IntPtr.Zero)throw new InvalidOperationException("The executable acquired a profile; refresh before applying.");
   if(!name.StartsWith("Gaming Mode - ",StringComparison.Ordinal)||name.Length>150)throw new ArgumentException("Invalid owned profile name.");
   IntPtr existing;int exists=Function<FindProfile>(0x7e4a9a0b)(handle,name,out existing);if(exists!=-163)throw new InvalidOperationException("The proposed NVIDIA profile name is already in use.");
   var p=Profile.Empty();p.Name=name;IntPtr created;Check(Function<CreateProfile>(0xcc176068)(handle,ref p,out created),"CreateProfile");
   var app=App.Empty();app.Name=path;app.Friendly=Path.GetFileNameWithoutExtension(path);Check(Function<AppCall>(0x4347a9de)(handle,created,ref app),"CreateApplication");
   Target(path,name,false);return name;
  }
  public void Write(string path,string expected,uint id,uint value) {
   Allowed(id);IntPtr p=Target(path,expected,false);var s=Setting.Empty(id);s.Type=0;Buffer.BlockCopy(BitConverter.GetBytes(value),0,s.Current,0,4);Check(Function<SetSetting>(0x577dd202)(handle,p,ref s),"SetSetting");
  }
  public void RemoveOverride(string path,string expected,uint id) {
   Allowed(id);int result=Function<DeleteSetting>(0xe4a26362)(handle,Target(path,expected,false),id);if(result!=-160)Check(result,"DeleteProfileSetting");
  }
  public void DeleteOwned(string path,string expected) {
   if(!expected.StartsWith("Gaming Mode - ",StringComparison.Ordinal))throw new ArgumentException("Only this tool's private profiles may be removed.");
   IntPtr p=Target(path,expected,false);var info=GetProfile(p);if(info.Predefined!=0)throw new InvalidOperationException("Predefined profiles cannot be removed.");
   // Called only after our overrides were removed. Retain any foreign additions.
   if(info.SettingCount!=0)throw new InvalidOperationException("The profile contains other settings. It has been retained to preserve them.");
   Check(Function<HandleCall>(0x17093206)(handle,p),"DeleteProfile");
  }
  public void Save() {EnsureOpen();Check(Function<SessionCall>(0xfcbc7e14)(handle),"SaveSettings");}
  public void Dispose() {
   lock(initLock) {
    if(!libraryReferenceHeld)return;
    if(handle!=IntPtr.Zero) {
     // A failed destroy leaves a potentially live native resource. Keep both
     // references so a later Dispose can retry; never unload beneath it.
     Check(Function<SessionCall>(0xdad9cff8)(handle),"DestroySession");
     handle=IntPtr.Zero;baseProfile=IntPtr.Zero;
    }
    libraryReferenceHeld=false;activeSessions--;
    if(activeSessions==0 && query!=null) {
     // NVIDIA requires one Unload per successful Initialize, after all owned
     // resource pairs have been completed. If it refuses, retain the library.
     int status=Function<Init>(0xd22bdd7e)();
     if(status==0) {
      query=null;
      if(library!=IntPtr.Zero && FreeLibrary(library))library=IntPtr.Zero;
     }
    }
   }
  }
 }
}
