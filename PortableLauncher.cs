// Framewell portable entry point. GPL-3.0; component notices remain with the payload.
// This process performs startup checks, opens the fixed bundled host, then exits.
using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("Framewell")]
[assembly: AssemblyProduct("Framewell")]
[assembly: AssemblyDescription("Gaming sessions, app profiles, and PC performance tools")]
[assembly: AssemblyVersion("3.2.0.0")]
[assembly: AssemblyFileVersion("3.2.0.0")]

/// <summary>Pure package/argument rules shared with isolated publication checks.</summary>
public static class PortableLayout
{
    public static string NormalizeAction(string[] arguments)
    {
        if (arguments == null || arguments.Length == 0) return "Panel";
        if (arguments.Length != 1)
            throw new ArgumentException("Open Framewell.exe directly, or pass one supported action.");
        foreach (string action in new[] { "Panel", "Enter", "Restore", "Media", "WindowsTools", "Performance", "Games" })
            if (string.Equals(arguments[0], action, StringComparison.OrdinalIgnoreCase)) return action;
        throw new ArgumentException("That startup action is not supported. Open Framewell.exe directly to use the dashboard.");
    }

    public static string ResolvePayloadPath(string packageRoot)
    {
        if (string.IsNullOrWhiteSpace(packageRoot) || packageRoot.Length < 3 ||
            !char.IsLetter(packageRoot[0]) || packageRoot[1] != ':' ||
            (packageRoot[2] != '\\' && packageRoot[2] != '/'))
            throw new ArgumentException("Extract Framewell to a local drive before opening it. Network paths are not supported.");
        string root = Path.GetFullPath(packageRoot);
        return Path.Combine(root, "app", "GamingMode.exe");
    }

    public static string[] GetRequiredFiles()
    {
        return new[] {
            "GamingMode.exe", "GamingMode.exe.config", "GamingMode.ico", "GamingMode.ps1",
            "OptionalApps.ps1", "MediaStack.ps1", "OptionalHelpers.ps1", "SessionExtras.ps1",
            "ThemeCatalog.ps1", "Performance.ps1", "TuningElevation.ps1", "GameLibrary.ps1",
            "GameDiscovery.ps1", "AppProfiles.ps1", "NvidiaProfiles.ps1", "NvidiaDrs.cs",
            "NetworkDiagnostics.ps1", "FrameBenchmark.ps1", "GameProcessTuning.ps1",
            "GamingSystemNative.cs", "MemoryTools.ps1", "MemoryWorker.ps1", "SettingsProfiles.ps1",
            "OptimizerTools.ps1", "WindowsGameSettings.ps1", "WindowsDisplayNative.cs",
            "DisplayWorker.ps1", "EmbeddedOptimizer.ps1", "MacInterface.ps1",
            "ResponsiveUI.ps1", "FramewellUpdateUI.ps1", "Framewell.Updater.exe",
            "vendor\\optimizer\\GamingMode.Optimizer.dll", "vendor\\optimizer\\Newtonsoft.Json.dll",
            "vendor\\optimizer\\features.json"
        };
    }
}

internal static class FramewellPortableLauncher
{
    [StructLayout(LayoutKind.Sequential)]
    private struct NativeSystemInfo
    {
        public ushort ProcessorArchitecture;
        public ushort Reserved;
        public uint PageSize;
        public IntPtr MinimumApplicationAddress;
        public IntPtr MaximumApplicationAddress;
        public UIntPtr ActiveProcessorMask;
        public uint NumberOfProcessors;
        public uint ProcessorType;
        public uint AllocationGranularity;
        public ushort ProcessorLevel;
        public ushort ProcessorRevision;
    }
    [DllImport("kernel32.dll")]
    private static extern void GetNativeSystemInfo(out NativeSystemInfo info);

    private static void CheckWindowsComponents()
    {
        NativeSystemInfo systemInfo;
        GetNativeSystemInfo(out systemInfo);
        if (!Environment.Is64BitOperatingSystem || systemInfo.ProcessorArchitecture != 9)
            throw new InvalidOperationException("This Framewell download is for Windows 10 version 1903 or newer, or Windows 11, on an x64 PC.");

        using (RegistryKey machine = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
        {
            using (RegistryKey version = machine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion"))
            {
                int build;
                string value = version == null ? null : Convert.ToString(version.GetValue("CurrentBuildNumber"), CultureInfo.InvariantCulture);
                // Read the actual Windows build: unmanifested OSVersion values can be compatibility values.
                if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out build) || build < 18362)
                    throw new InvalidOperationException("Framewell requires Windows 10 version 1903 or newer, or Windows 11, on an x64 PC.");
            }
            using (RegistryKey framework = machine.OpenSubKey(@"SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"))
            {
                object release = framework == null ? null : framework.GetValue("Release");
                if (release == null || Convert.ToInt32(release, CultureInfo.InvariantCulture) < 528040)
                    throw new InvalidOperationException("Framewell needs Microsoft .NET Framework 4.8 or newer. It is included with Windows 11 and Windows 10 version 1903 or newer. Update Windows or install .NET Framework 4.8 from Microsoft, then try again.");
            }
            using (RegistryKey engine = machine.OpenSubKey(@"SOFTWARE\Microsoft\PowerShell\3\PowerShellEngine"))
            {
                Version version;
                string value = engine == null ? null : Convert.ToString(engine.GetValue("PowerShellVersion"), CultureInfo.InvariantCulture);
                if (!Version.TryParse(value, out version) || version < new Version(5, 1))
                    throw new InvalidOperationException("Framewell needs the Windows PowerShell 5.1 component that ships with Windows. Restore that Windows component, then try again. Installing PowerShell 7 alone does not replace it.");
            }
        }
        string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (!File.Exists(powershell))
            throw new InvalidOperationException("The Windows PowerShell 5.1 component is missing. Restore that Windows component, then open Framewell again.");
        try
        {
            // Windows installs this strong-named assembly in its GAC, not beside powershell.exe.
            // Keep this a reflection load so a missing component can produce a friendly error.
            Assembly.Load("System.Management.Automation, Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35");
        }
        catch (Exception error)
        {
            throw new InvalidOperationException("Windows PowerShell could not be loaded. Repair or restore the Windows PowerShell 5.1 component, then try again.", error);
        }
    }

    private static void CheckPayload(string payload)
    {
        string appDirectory = Path.GetDirectoryName(payload);
        foreach (string relative in PortableLayout.GetRequiredFiles())
            if (!File.Exists(Path.Combine(appDirectory, relative)))
                throw new FileNotFoundException("The download is not fully extracted or an app file is missing: app\\" + relative +
                    "\n\nUse Extract All on the Framewell Windows portable ZIP, then open Framewell.exe in the extracted folder. Keep its app folder beside it. GitHub's source-code ZIP is for building the app.");
    }

    private static void CheckWritableState(string appDirectory)
    {
        try
        {
            string state = Path.Combine(appDirectory, "state");
            Directory.CreateDirectory(state);
            string probe = Path.Combine(state, ".framewell-startup-" + Guid.NewGuid().ToString("N") + ".tmp");
            // DeleteOnClose removes only this newly created probe, including on exceptional exit.
            using (FileStream stream = new FileStream(probe, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 1, FileOptions.DeleteOnClose))
            {
                stream.WriteByte(0);
            }
        }
        catch (Exception error)
        {
            if (!(error is IOException) && !(error is UnauthorizedAccessException)) throw;
            throw new InvalidOperationException("Framewell cannot save settings in this folder. Extract the ZIP to a writable local folder such as Downloads, then open Framewell.exe there.", error);
        }
    }

    [STAThread]
    private static int Main(string[] arguments)
    {
        try
        {
            string action = PortableLayout.NormalizeAction(arguments);
            string payload = PortableLayout.ResolvePayloadPath(AppDomain.CurrentDomain.BaseDirectory);
            CheckPayload(payload);
            CheckWindowsComponents();
            string appDirectory = Path.GetDirectoryName(payload);
            CheckWritableState(appDirectory);
            ProcessStartInfo launch = new ProcessStartInfo {
                FileName = payload,
                Arguments = action,
                WorkingDirectory = appDirectory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Normal
            };
            using (Process started = Process.Start(launch))
            {
                if (started == null) throw new InvalidOperationException("Windows could not start Framewell. Try extracting the ZIP again.");
            }
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Framewell could not start", MessageBoxButtons.OK, MessageBoxIcon.Information);
            return 1;
        }
    }
}
