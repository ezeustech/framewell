// Framewell release updates. No service, scheduled task, or elevation is installed.
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace Framewell {
 public sealed class UpdateJob {
  public volatile string Status = "Checking for updates...";
  public volatile string PlanPath;
  public volatile bool Complete;
  public volatile bool Failed;
 }
 public static class Updates {
  public const string Repository = "ezeustech/framewell";
  static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 16 * 1024 * 1024 };
  public static Version ParseVersion(string value) {
   var match=Regex.Match(value??"", @"^v?(\d+\.\d+\.\d+)(?:-[0-9A-Za-z.-]+)?$");
   if(!match.Success) throw new InvalidDataException("Unrecognized release version.");
   return new Version(match.Groups[1].Value);
  }
  public static string SafePath(string root,string relative) {
   if(String.IsNullOrWhiteSpace(relative)||Path.IsPathRooted(relative)||relative.Contains(":")) throw new InvalidDataException("Invalid package path.");
   var parts=relative.Replace('\\','/').Split('/');
   if(parts.Any(p=>p==".."||p=="."||p.EndsWith(".")||p.EndsWith(" ")||p.IndexOfAny(Path.GetInvalidFileNameChars())>=0||p.Equals("state",StringComparison.OrdinalIgnoreCase)||p.Equals("backups",StringComparison.OrdinalIgnoreCase))) throw new InvalidDataException("Package includes a protected or invalid path.");
   string prefix=Path.GetFullPath(root).TrimEnd('\\','/')+Path.DirectorySeparatorChar;
   string result=Path.GetFullPath(Path.Combine(root,relative));
   if(!result.StartsWith(prefix,StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Package escapes its folder.");
   return result;
  }
  public static string Hash(string file) { using(var input=File.OpenRead(file)) using(var hash=SHA256.Create()) return BitConverter.ToString(hash.ComputeHash(input)).Replace("-","").ToLowerInvariant(); }
  public static void VerifyHash(string file,string expected) {
   if(!Regex.IsMatch(expected??"", "^[0-9a-fA-F]{64}$")||!String.Equals(Hash(file),expected,StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Update checksum did not match.");
  }
  public static void ExtractPackage(string archive,string destination) {
   using(var zip=ZipFile.OpenRead(archive)) {
    if(zip.Entries.Count>5000 || zip.Entries.Sum(e=>e.Length)>1024L*1024*1024) throw new InvalidDataException("Update package is too large.");
    var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    foreach(var entry in zip.Entries) {
     string path=SafePath(destination,entry.FullName);
     if(!seen.Add(path)) throw new InvalidDataException("Duplicate package path.");
     if(String.IsNullOrEmpty(entry.Name)){Directory.CreateDirectory(path);continue;}
     Directory.CreateDirectory(Path.GetDirectoryName(path));entry.ExtractToFile(path,false);
    }
   }
   foreach(string name in new[]{"app/GamingMode.exe","app/GamingMode.ps1","app/runtime-files.json","Framewell.exe"})
    if(!File.Exists(SafePath(destination,name))) throw new InvalidDataException("Incomplete Framewell update.");
  }
  static void CheckUrl(string value,string release) {
   Uri uri;
   if(!Uri.TryCreate(value,UriKind.Absolute,out uri)||uri.Scheme!="https"||uri.Host!="github.com"||!uri.AbsolutePath.StartsWith("/"+Repository+"/releases/download/"+release+"/",StringComparison.Ordinal)) throw new InvalidDataException("Unexpected release download location.");
  }
  public static void ValidateManifest(string stage,string version) {
   var manifest=Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(SafePath(stage,"app/runtime-files.json")));
   if(!String.Equals((string)manifest["Version"],version,StringComparison.Ordinal))throw new InvalidDataException("Package version does not match the release.");
   foreach(var entry in (IEnumerable)manifest["Files"])
    if(!File.Exists(SafePath(Path.Combine(stage,"app"),(string)entry)))throw new InvalidDataException("An application file is missing from the update.");
   foreach(string name in new[]{"Framewell.exe.config","START HERE.txt"})
    if(!File.Exists(SafePath(stage,name)))throw new InvalidDataException("Incomplete portable launcher.");
  }
  public static UpdateJob Start(string runtimeRoot,string currentVersion,bool download) {
   var job=new UpdateJob();
   Task.Run(async delegate {
    try {
     ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;
     using(var client=new HttpClient()) {
      client.Timeout=TimeSpan.FromMinutes(5);client.DefaultRequestHeaders.UserAgent.ParseAdd("Framewell/"+ParseVersion(currentVersion));
      using(var response=await client.GetAsync("https://api.github.com/repos/"+Repository+"/releases/latest").ConfigureAwait(false)) {
       if(response.StatusCode==HttpStatusCode.NotFound){job.Status="No newer stable release is available.";return;}
       response.EnsureSuccessStatusCode();
       var release=Json.Deserialize<Dictionary<string,object>>(await response.Content.ReadAsStringAsync().ConfigureAwait(false));
       string tag=(string)release["tag_name"];var version=ParseVersion(tag);
       if((bool)release["draft"]||(bool)release["prerelease"]||version<=ParseVersion(currentVersion)){job.Status="Framewell is up to date.";return;}
       if(!download){job.Status="Framewell "+version+" is available. Choose Download update.";return;}
       string expectedName="Framewell-"+version+"-win-x64.zip";
       var assets=((IEnumerable)release["assets"]).Cast<Dictionary<string,object>>().ToArray();
       var asset=assets.SingleOrDefault(x=>(string)x["name"]==expectedName);
       if(asset==null) throw new InvalidDataException("The Windows release package is missing.");
       if(Convert.ToInt64(asset["size"])>256L*1024*1024) throw new InvalidDataException("Update download is too large.");
       string url=(string)asset["browser_download_url"];CheckUrl(url,tag);
       string digest=asset.ContainsKey("digest")?asset["digest"] as string:null;
       if(digest!=null&&digest.StartsWith("sha256:"))digest=digest.Substring(7);else {
        var sums=assets.SingleOrDefault(x=>(string)x["name"]=="SHA256SUMS.txt");if(sums==null)throw new InvalidDataException("No published update checksum.");
        string sumsUrl=(string)sums["browser_download_url"];CheckUrl(sumsUrl,tag);
        string sumsText=await client.GetStringAsync(sumsUrl).ConfigureAwait(false);
        var line=sumsText.Split('\n').Select(x=>x.Trim()).FirstOrDefault(x=>x.EndsWith("  "+expectedName,StringComparison.Ordinal));
        if(line==null)throw new InvalidDataException("The update checksum is missing.");digest=line.Split(' ')[0];
       }
       string work=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Framewell","Updates",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(work);
       string archive=Path.Combine(work,"package.zip");job.Status="Downloading Framewell "+version+"...";
       using(var data=await client.GetStreamAsync(url).ConfigureAwait(false))using(var output=File.Create(archive))await data.CopyToAsync(output).ConfigureAwait(false);
       VerifyHash(archive,digest);job.Status="Verifying update package...";
       string stage=Path.Combine(work,"package");ExtractPackage(archive,stage);
       ValidateManifest(stage,version.ToString());
       var entries=new Dictionary<string,string>();foreach(string file in Directory.GetFiles(Path.Combine(stage,"app"),"*",SearchOption.AllDirectories))entries[file.Substring(Path.Combine(stage,"app").Length+1)]=Hash(file);
       var plan=new UpdatePlan { RuntimeRoot=Path.GetFullPath(runtimeRoot),StageRoot=stage,Version=version.ToString(),Files=entries,PackageHash=digest,Archive=archive };
       string planPath=Path.Combine(work,"plan.json");File.WriteAllText(planPath,Json.Serialize(plan),Encoding.UTF8);
       job.PlanPath=planPath;job.Status="Framewell "+version+" is ready. It will install when you close the app.";
      }
     }
    }catch(Exception error){job.Failed=true;job.Status="Update check failed: "+error.Message;}
    finally{job.Complete=true;}
   });
   return job;
  }
  public static void InstallAfterExit(string planPath,int processId,long startTicks) {
   string work=Path.GetDirectoryName(Path.GetFullPath(planPath));string helper=Path.Combine(work,"Framewell.Updater.exe");
   File.Copy(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"Framewell.Updater.exe"),helper,true);
   Process.Start(new ProcessStartInfo(helper,"\""+planPath+"\" "+processId+" "+startTicks) { UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,WorkingDirectory=work });
  }
  public static void Apply(string planPath) {
   var plan=Json.Deserialize<UpdatePlan>(File.ReadAllText(planPath));string root=Path.GetFullPath(plan.RuntimeRoot).TrimEnd('\\');
   if(root.Length<4||!File.Exists(Path.Combine(root,"GamingMode.exe"))||!File.Exists(Path.Combine(root,"runtime-files.json")))throw new InvalidDataException("Framewell installation not found.");
   VerifyHash(plan.Archive,plan.PackageHash);
   // Re-extract the verified archive so staged files (including the portable launcher)
   // cannot drift between verification and installation.
   string verified=Path.Combine(Path.GetDirectoryName(planPath),"verified-"+Guid.NewGuid().ToString("N"));
   ExtractPackage(plan.Archive,verified);ValidateManifest(verified,plan.Version);
   plan.StageRoot=verified;
   var copies=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
   foreach(var entry in plan.Files){string source=SafePath(Path.Combine(plan.StageRoot,"app"),entry.Key);VerifyHash(source,entry.Value);copies.Add(SafePath(root,entry.Key),source);}
   var parent=Directory.GetParent(root);
   if(String.Equals(Path.GetFileName(root),"app",StringComparison.OrdinalIgnoreCase)&&parent!=null&&File.Exists(Path.Combine(parent.FullName,"Framewell.exe")))
    foreach(string name in new[]{"Framewell.exe","Framewell.exe.config","START HERE.txt"})copies.Add(SafePath(parent.FullName,name),SafePath(plan.StageRoot,name));
   foreach(var file in copies.Keys) {
    for(var dir=Directory.GetParent(file);dir!=null;dir=dir.Parent)if(dir.Exists&&(dir.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Updates cannot target a linked installation directory.");
    if(File.Exists(file)&&(File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)throw new IOException("Update target is a linked file.");
   }
   string backup=Path.Combine(Path.GetDirectoryName(planPath),"rollback-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(backup);
   var replaced=new List<string>();var originals=new Dictionary<string,string>();
   try {
    foreach(var pair in copies) {
     Directory.CreateDirectory(Path.GetDirectoryName(pair.Key));
     if(File.Exists(pair.Key)){string original=Path.Combine(backup,originals.Count.ToString()+".bak");File.Copy(pair.Key,original);originals[pair.Key]=original;}
     string pending=pair.Key+".framewell-update-"+Guid.NewGuid().ToString("N");
     try {
      File.Copy(pair.Value,pending);
      if(File.Exists(pair.Key))File.Replace(pending,pair.Key,null);else File.Move(pending,pair.Key);
      replaced.Add(pair.Key);
     }finally{if(File.Exists(pending))File.Delete(pending);}
    }
    File.WriteAllText(Path.Combine(Path.GetDirectoryName(planPath),"installed.txt"),plan.Version);
   }catch(Exception installError) {
    var failures=new List<Exception>();
    foreach(string target in Enumerable.Reverse(replaced))try{if(originals.ContainsKey(target))File.Copy(originals[target],target,true);else if(File.Exists(target))File.Delete(target);}catch(Exception restoreError){failures.Add(restoreError);}
    if(failures.Count>0)throw new IOException("Update failed and some files could not be restored. Recovery copies are in "+backup,installError);
    throw;
   }
  }
 }
 public sealed class UpdatePlan {
  public string RuntimeRoot {get;set;} public string StageRoot {get;set;} public string Version {get;set;}
  public string Archive {get;set;} public string PackageHash {get;set;} public Dictionary<string,string> Files {get;set;}
 }
}
