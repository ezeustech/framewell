using System;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Threading;
using System.Windows.Forms;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Reflection;

[assembly: AssemblyTitle("Framewell")]
[assembly: AssemblyProduct("Framewell")]
[assembly: AssemblyDescription("Per-game presets and reversible application profiles")]
[assembly: AssemblyVersion("3.1.1.0")]
[assembly: AssemblyFileVersion("3.1.1.0")]

internal static class GamingModeLauncher
{
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr window);
    private static void RaiseExisting(string root)
    {
        foreach(Process process in Process.GetProcessesByName("GamingMode"))
        {
            using(process) try {
                if(process.Id == Process.GetCurrentProcess().Id || process.MainWindowHandle == IntPtr.Zero) continue;
                if(!String.Equals(Path.GetDirectoryName(process.MainModule.FileName),root.TrimEnd(Path.DirectorySeparatorChar),StringComparison.OrdinalIgnoreCase)) continue;
                if(IsIconic(process.MainWindowHandle)) ShowWindowAsync(process.MainWindowHandle,9);
                SetForegroundWindow(process.MainWindowHandle);return;
            } catch { }
        }
    }
    [STAThread]
    private static void Main(string[] arguments)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string action = arguments.Length > 0 ? arguments[0] : "Panel";
        if (action != "Panel" && action != "Enter" && action != "Restore" && action != "Media" && action != "WindowsTools" && action != "Performance" && action != "Games")
            action = "Panel";
        Mutex panelMutex=null;
        bool panelOwned=false;
        try
        {
            // An explicit elevation restart waits for this installation's original
            // dashboard to release its mutex. PID creation time prevents PID reuse.
            if(arguments.Length == 3 && (action == "WindowsTools" || action == "Performance" || action == "Games")) {
                int parentId;long parentTicks;
                if(!Int32.TryParse(arguments[1],out parentId)||!Int64.TryParse(arguments[2],out parentTicks))throw new InvalidOperationException("Invalid dashboard handoff.");
                try {using(Process previous=Process.GetProcessById(parentId)) {
                    bool identityMatches=false;
                    try {
                        identityMatches=previous.StartTime.ToUniversalTime().Ticks==parentTicks && String.Equals(previous.MainModule.FileName,Path.Combine(root,"GamingMode.exe"),StringComparison.OrdinalIgnoreCase);
                    } catch(InvalidOperationException) { if(!previous.HasExited)throw; }
                      catch(System.ComponentModel.Win32Exception) { if(!previous.HasExited)throw; }
                    if(!previous.HasExited) {
                        if(!identityMatches)throw new InvalidOperationException("Dashboard handoff identity changed.");
                        if(!previous.WaitForExit(15000))throw new InvalidOperationException("The previous dashboard is still open. Close it and retry.");
                    }
                }}catch(ArgumentException) { }
            }
            if(action == "Panel" || action == "WindowsTools" || action == "Performance" || action == "Games") {
                string key;
                using(SHA256 hash=SHA256.Create()) key=BitConverter.ToString(hash.ComputeHash(Encoding.UTF8.GetBytes(root.ToLowerInvariant()))).Replace("-","");
                panelMutex=new Mutex(false,"Local\\GamingModePanel-"+key);
                try {panelOwned=panelMutex.WaitOne(0);}catch(AbandonedMutexException){panelOwned=true;}
                if(!panelOwned){RaiseExisting(root);return;}
            }
            using (Runspace runspace = RunspaceFactory.CreateRunspace())
            {
                runspace.ApartmentState = ApartmentState.STA;
                runspace.ThreadOptions = PSThreadOptions.UseCurrentThread;
                runspace.Open();
                using (PowerShell shell = PowerShell.Create())
                {
                    shell.Runspace = runspace;
                    shell.AddCommand("Set-ExecutionPolicy").AddParameter("Scope", "Process")
                        .AddParameter("ExecutionPolicy", "Bypass").AddParameter("Force");
                    shell.Invoke();
                    shell.Commands.Clear();
                    shell.Streams.Error.Clear();
                    // Dot-source in this dedicated runspace so UI event
                    // closures can resolve the workflow and module functions.
                    shell.AddScript(". $args[0] -Action $args[1]", false)
                        .AddArgument(Path.Combine(root, "GamingMode.ps1")).AddArgument(action);
                    shell.Invoke();
                    if (shell.HadErrors)
                        throw new InvalidOperationException(shell.Streams.Error[0].ToString());
                }
            }
        }
        catch (Exception error)
        {
            try { File.AppendAllText(Path.Combine(root, "launcher-errors.log"), DateTime.UtcNow.ToString("o") + " " + error.Message + Environment.NewLine); }
            catch { }
            MessageBox.Show(error.Message, "Framewell", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally { if(panelMutex!=null){if(panelOwned)panelMutex.ReleaseMutex();panelMutex.Dispose();} }
    }
}
