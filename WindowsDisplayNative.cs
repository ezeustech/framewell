using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public sealed class GamingDisplayMode {
 public string DeviceName {get;set;} public string Key {get;set;} public string Label {get;set;}
 public uint Width {get;set;} public uint Height {get;set;} public uint RefreshHz {get;set;} public uint BitsPerPixel {get;set;} public bool IsCurrent {get;set;}
}
public static class GamingWindowsDisplay {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Device {
  public uint cb;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string name;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)]public string text;public uint flags;
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)]public string id;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)]public string key;
 }
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Mode {
  [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string device;public ushort spec,driver,size,extra;public uint fields;public int x,y;public uint orientation,fixedOutput;
  public short color,duplex,yResolution,ttOption,collate;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string form;public ushort logPixels;
  public uint bits,width,height,flags,hz,icmMethod,icmIntent,mediaType,dither,reserved1,reserved2,panningWidth,panningHeight;
 }
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool EnumDisplayDevices(string device,uint index,ref Device result,uint flags);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="EnumDisplaySettingsW")]static extern bool EnumSettings(string device,int index,ref Mode mode);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,EntryPoint="ChangeDisplaySettingsExW")]static extern int Change(string device,ref Mode mode,IntPtr window,uint flags,IntPtr param);
 static Mode NewMode(){Mode value=new Mode();value.size=(ushort)Marshal.SizeOf(typeof(Mode));return value;}
 static string Primary(){for(uint i=0;i<32;i++){Device d=new Device();d.cb=(uint)Marshal.SizeOf(typeof(Device));if(!EnumDisplayDevices(null,i,ref d,0))break;if((d.flags&5)==5)return d.name;}throw new InvalidOperationException("No active primary display was found.");}
 static Mode Current(string device){Mode value=NewMode();if(!EnumSettings(device,-1,ref value))throw new InvalidOperationException("Windows did not return the current display mode.");return value;}
 static string Key(string device,Mode value){return device+"|"+value.width+"|"+value.height+"|"+value.bits+"|"+value.hz+"|"+value.flags+"|"+value.orientation;}
 public static string CurrentKey(){string device=Primary();return Key(device,Current(device));}
 public static GamingDisplayMode[] Modes(){
  string device=Primary();Mode current=Current(device);List<GamingDisplayMode> modes=new List<GamingDisplayMode>();HashSet<string> seen=new HashSet<string>();
  for(int index=0;index<4096;index++){Mode value=NewMode();if(!EnumSettings(device,index,ref value))break;
   if(value.width!=current.width||value.height!=current.height||value.bits!=current.bits||value.orientation!=current.orientation||value.flags!=current.flags||value.hz<20||value.hz>1000)continue;
   string key=Key(device,value);if(!seen.Add(key))continue;
   modes.Add(new GamingDisplayMode{DeviceName=device,Key=key,Label=value.width+" × "+value.height+" · "+value.hz+" Hz",Width=value.width,Height=value.height,RefreshHz=value.hz,BitsPerPixel=value.bits,IsCurrent=key==Key(device,current)});
  }return modes.ToArray();
 }
 public static void Apply(string key,bool persist){
  string device=Primary();Mode current=Current(device);bool found=false;Mode wanted=NewMode();
  for(int index=0;index<4096;index++){Mode value=NewMode();if(!EnumSettings(device,index,ref value))break;if(Key(device,value)!=key)continue;
   if(value.width!=current.width||value.height!=current.height||value.bits!=current.bits||value.orientation!=current.orientation||value.flags!=current.flags)throw new InvalidOperationException("This control changes only refresh rate at the current display resolution.");wanted=value;found=true;break;}
  if(!found)throw new InvalidOperationException("That refresh mode is no longer supported.");
  wanted.fields=0x00400000;int test=Change(device,ref wanted,IntPtr.Zero,2,IntPtr.Zero);if(test!=0)throw new InvalidOperationException("Windows rejected the display mode test: "+test);
  Mode saved=NewMode();
  // A failed persistence/readback must not leave the next Windows login set to
  // an unconfirmed mode. Capture the prior stored frequency before committing.
  if(persist&&!EnumSettings(device,-2,ref saved))throw new InvalidOperationException("Windows did not return the stored mode; this rate was not saved.");
  try {
   int applied=Change(device,ref wanted,IntPtr.Zero,persist?1U:0U,IntPtr.Zero);if(applied!=0)throw new InvalidOperationException("Display mode was not applied: "+applied);
   if(CurrentKey()!=key)throw new InvalidOperationException("The requested display mode did not verify.");
  } catch(Exception failure) {
   if(persist){saved.fields=0x00400000;int restored=Change(device,ref saved,IntPtr.Zero,0x10000001U,IntPtr.Zero);if(restored!=0)throw new InvalidOperationException(failure.Message+" The previously stored display frequency could not be restored: "+restored,failure);}
   throw;
  }
 }
}
