// Framewell integration of Optimizer 17.0. GPL-3.0-only; see repository LICENSE.
using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

namespace Optimizer {
    public sealed class EmbeddedSection {
        public string Id { get; private set; }
        public string Name { get; private set; }
        public EmbeddedSection(string id, string name) { Id = id; Name = name; }
        public override string ToString() { return Name; }
    }

    /// <summary>Same-process WinForms bridge. Never invokes Program.Main, UAC, or a message loop.</summary>
    public static class EmbeddedHost {
        private static string _stateDirectory;
        internal static bool Enabled { get { return true; } }
        internal static string StateDirectory {
            get { if (_stateDirectory == null) throw new InvalidOperationException("Configure the embedded state directory with CreateView first."); return _stateDirectory; }
        }
        public static bool IsAdministrator {
            get { using (WindowsIdentity identity = WindowsIdentity.GetCurrent()) return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator); }
        }
        private sealed class WindowOwner : IWin32Window {
            public IntPtr Handle { get; private set; }
            public WindowOwner(IntPtr handle) { Handle = handle; }
        }
        internal static IWin32Window DialogOwner { get; private set; }
        public static void SetOwnerWindow(IntPtr windowHandle) { DialogOwner = windowHandle == IntPtr.Zero ? null : new WindowOwner(windowHandle); }
        public static EmbeddedSection[] GetSections() {
            return new[] {
                new EmbeddedSection("universalTab", "General"), new EmbeddedSection("windows10Tab", "Windows"),
                new EmbeddedSection("advancedTab", "Advanced"), new EmbeddedSection("advancedExtrasTab", "CPU & process controls"),
                new EmbeddedSection("modernAppsTab", "UWP apps"), new EmbeddedSection("startupTab", "Startup"),
                new EmbeddedSection("appsTab", "App downloads"), new EmbeddedSection("cleanerTab", "Cleaner"),
                new EmbeddedSection("pingerTab", "Network & DNS"), new EmbeddedSection("hostsEditorTab", "Hosts editor"),
                new EmbeddedSection("registryFixerTab", "Registry"), new EmbeddedSection("indiciumTab", "Hardware"),
                new EmbeddedSection("fileHandlesTab", "File handles"), new EmbeddedSection("diskActivityTab", "Disk activity"),
                new EmbeddedSection("integratorTab", "Integrator"), new EmbeddedSection("optionsTab", "Tool preferences")
            };
        }
        public static EmbeddedSection[] GetSections(Control view) { return RequireView(view).EmbeddedSections(); }
        public static Control CreateView(string stateDirectory) { return CreateView(stateDirectory, false); }
        public static Control CreateView(string stateDirectory, bool enableActions) {
            if (Thread.CurrentThread.GetApartmentState() != ApartmentState.STA) throw new InvalidOperationException("The embedded tools require the host UI STA thread.");
            if (string.IsNullOrWhiteSpace(stateDirectory) || !Path.IsPathRooted(stateDirectory)) throw new ArgumentException("Use an absolute, private application-state directory.", "stateDirectory");
            string configured = Path.GetFullPath(stateDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (_stateDirectory != null && !string.Equals(_stateDirectory, configured, StringComparison.OrdinalIgnoreCase)) throw new InvalidOperationException("Embedded state is fixed for the lifetime of the application.");
            if (Program._MainForm != null && !Program._MainForm.IsDisposed) throw new InvalidOperationException("Only one embedded Optimizer workspace can be open.");
            _stateDirectory = configured;
            return CreateConfiguredView(enableActions && IsAdministrator);
        }
        // Kept separate so the CLR cannot initialize CoreHelper/OptionsHelper before state is set.
        private static Control CreateConfiguredView(bool enableActions) {
            CoreHelper.Deploy();
            OptionsHelper.LoadSettings();
            OptionsHelper.CurrentOptions.EnableTray = false;
            OptionsHelper.CurrentOptions.AutoStart = false;
            OptionsHelper.CurrentOptions.UpdateOnLaunch = false;
            OptionsHelper.SaveSettings();
            Program.DPI_PREFERENCE = 96;
            Program.UNSAFE_MODE = true;
            Program.SILENT_MODE = false;
            MainForm view = new MainForm(false, false, false, false, false, false, false, false);
            view.ConfigureEmbedding(enableActions);
            return view;
        }
        private static MainForm RequireView(Control view) {
            MainForm result = view as MainForm;
            if (result == null || result.IsDisposed) throw new ArgumentException("The embedded view is unavailable.", "view");
            return result;
        }
        public static void SelectSection(Control view, string sectionId) { RequireView(view).EmbeddedSelectSection(sectionId); }
        public static EmbeddedSection[] GetCategories() { return GetSections(); }
        public static void SelectCategory(Control view, string categoryId) { SelectSection(view, categoryId); }
        public static void ApplyTheme(Control view, string accentHex, bool light) {
            MainForm form = RequireView(view);
            OptionsHelper.CurrentOptions.Theme = ColorTranslator.FromHtml(accentHex);
            OptionsHelper.CurrentOptions.ThemeMode = light ? ThemeMode.Light : ThemeMode.Dark;
            OptionsHelper.ApplyTheme(form);
        }
        public static void ApplyTheme(Control view, string accentHex, bool light, string background, string surface, string text) {
            ApplyTheme(view, accentHex, light);
            ThemeManager.Current.ApplyHostSurfaces(ColorTranslator.FromHtml(background), ColorTranslator.FromHtml(surface), ColorTranslator.FromHtml(text));
            ThemeManager.Apply(view);
        }
        public static void DisposeView(Control view) {
            MainForm form = view as MainForm;
            if (form == null || form.IsDisposed) return;
            OptionsHelper.SaveSettings();
            form.Dispose();
            if (ReferenceEquals(Program._MainForm, form)) Program._MainForm = null;
        }
        internal static void NotifyRestartRequired() { MessageBox.Show("Close and reopen Framewell to reload the Windows tools. Your settings have been saved.", "Framewell", MessageBoxButtons.OK, MessageBoxIcon.Information); }
        internal static bool ConfirmRestart(string message) { return MessageBox.Show(message, "Restart Windows", MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes; }
        internal static void ShowUpdateInformation() { MessageBox.Show("These Windows tools are built into Framewell. Update Framewell to receive a reviewed, compatible tools release. The standalone Optimizer updater is not used.", "Framewell", MessageBoxButtons.OK, MessageBoxIcon.Information); }
    }

    // Own upstream dialogs with the WPF host HWND when supplied, including utility/helper dialogs.
    internal static class MessageBox {
        public static DialogResult Show(string text) { return Show(text, "Framewell", MessageBoxButtons.OK, MessageBoxIcon.None); }
        public static DialogResult Show(string text, string caption) { return Show(text, caption, MessageBoxButtons.OK, MessageBoxIcon.None); }
        public static DialogResult Show(string text, string caption, MessageBoxButtons buttons) { return Show(text, caption, buttons, MessageBoxIcon.None); }
        public static DialogResult Show(string text, string caption, MessageBoxButtons buttons, MessageBoxIcon icon) {
            return System.Windows.Forms.MessageBox.Show(EmbeddedHost.DialogOwner, text, caption, buttons, icon);
        }
        public static DialogResult Show(IWin32Window owner, string text, string caption, MessageBoxButtons buttons, MessageBoxIcon icon) {
            return System.Windows.Forms.MessageBox.Show(EmbeddedHost.DialogOwner ?? owner, text, caption, buttons, icon);
        }
        public static DialogResult Show(IWin32Window owner, string text, string caption, MessageBoxButtons buttons, MessageBoxIcon icon, MessageBoxDefaultButton defaultButton) {
            return System.Windows.Forms.MessageBox.Show(EmbeddedHost.DialogOwner ?? owner, text, caption, buttons, icon, defaultButton);
        }
    }
}
