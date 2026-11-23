// Framewell adaptation, 2026. GPL-3.0: native controls for Optimizer's CLI-only actions.
// Opening this panel only constructs controls and reads the local restore journal.
using Microsoft.Win32;
using Newtonsoft.Json;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Principal;
using System.Text.RegularExpressions;
using System.Windows.Forms;

namespace Optimizer {
    public sealed partial class MainForm {
        internal Control CreateEmbeddedAdvancedExtras()
        {
            return new EmbeddedAdvancedPanel();
        }
    }

    internal sealed class EmbeddedRegistryChange {
        public string KeyPath;
        public string ValueName;
        public object Value;
        public RegistryValueKind Kind;
        public bool Remove;
    }

    internal sealed class EmbeddedValueSnapshot {
        public string KeyPath;
        public string ValueName;
        public bool Exists;
        public int Kind;
        public string JsonValue;
    }

    internal sealed class EmbeddedChangeReceipt {
        public string Operation;
        public string CreatedUtc;
        public List<EmbeddedValueSnapshot> Before = new List<EmbeddedValueSnapshot>();
        public List<EmbeddedValueSnapshot> Written = new List<EmbeddedValueSnapshot>();
        public bool Complete;
    }

    internal static class EmbeddedAdvancedActions {
        internal const string CoreParkingKey = @"SYSTEM\ControlSet001\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583";
        internal const string ServiceControlKey = @"SYSTEM\CurrentControlSet\Control";
        internal const string IfeoKey = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options";
        internal const string OwnedDebugger = @"%windir%\System32\taskkill.exe";
        internal static readonly string[] Operations = {
            "Core parking range (Optimizer UnlockAllCores)",
            "Group service hosts using a RAM threshold",
            "Reset service-host threshold to Optimizer's value",
            "Prevent an app from starting",
            "Allow a previously blocked app to start"
        };

        internal static bool IsAdministrator {
            get { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); }
        }

        internal static string ValidateProcessName(string name)
        {
            name = (name ?? string.Empty).Trim();
            if (name.Length > 128 || !Regex.IsMatch(name, @"\A[a-zA-Z0-9][a-zA-Z0-9 ._-]*\.exe\z", RegexOptions.IgnoreCase)
                || name.Contains("..") || Path.GetFileName(name) != name)
                throw new ArgumentException("Enter an executable filename such as ExampleGame.exe, without a path or arguments.");
            string[] protectedNames = {
                "gamingmode.exe", "framewell.exe", "optimizer.exe", "codex.exe", "chatgpt.exe", "explorer.exe", "steam.exe", "discord.exe",
                "system.exe", "registry.exe", "smss.exe", "csrss.exe", "wininit.exe", "services.exe", "lsass.exe", "winlogon.exe",
                "svchost.exe", "dwm.exe", "sihost.exe", "taskhostw.exe", "userinit.exe", "logonui.exe", "fontdrvhost.exe",
                "cmd.exe", "powershell.exe", "pwsh.exe", "reg.exe", "regedit.exe", "taskkill.exe", "taskmgr.exe",
                "msmpeng.exe", "mssense.exe", "nissrv.exe", "securityhealthservice.exe", "securityhealthsystray.exe",
                "smartscreen.exe", "msseces.exe", "senseir.exe", "sensece.exe", "avp.exe", "avastsvc.exe", "avgsvc.exe",
                "mbamservice.exe", "mbam.exe", "ekrn.exe", "mcshield.exe", "nortonsecurity.exe", "sophoshealth.exe",
                "csfalconservice.exe", "sentinelagent.exe", "windefend.exe", "vgc.exe", "easyanticheat.exe", "beservice.exe"
            };
            if (protectedNames.Contains(name, StringComparer.OrdinalIgnoreCase)
                || string.Equals(Process.GetCurrentProcess().ProcessName + ".exe", name, StringComparison.OrdinalIgnoreCase))
                throw new ArgumentException("Windows, security, Framewell, Steam and Discord executables are protected. Choose an app you own.");
            string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            foreach (string folder in new[] { windows, Path.Combine(windows, "System32"), Path.Combine(windows, "SysWOW64") })
                if (File.Exists(Path.Combine(folder, name)))
                    throw new ArgumentException("This filename belongs to a Windows component. Choose an app you own.");
            return name;
        }

        // Pure planning: no registry writes, process starts, or elevation.
        internal static List<EmbeddedRegistryChange> Plan(int operation, int ramGB, string processName)
        {
            var changes = new List<EmbeddedRegistryChange>();
            if (operation == 0) {
                changes.Add(new EmbeddedRegistryChange { KeyPath = CoreParkingKey, ValueName = "ValueMin", Kind = RegistryValueKind.DWord, Value = 0 });
                changes.Add(new EmbeddedRegistryChange { KeyPath = CoreParkingKey, ValueName = "ValueMax", Kind = RegistryValueKind.DWord, Value = 0 });
            } else if (operation == 1 || operation == 2) {
                if (ramGB < 1 || ramGB > 2047) throw new ArgumentOutOfRangeException("ramGB", "RAM must be between 1 and 2047 GB.");
                int threshold = operation == 1 ? checked(ramGB * 1024 * 1024) : 380000;
                changes.Add(new EmbeddedRegistryChange { KeyPath = ServiceControlKey, ValueName = "SvcHostSplitThresholdInKB", Kind = RegistryValueKind.DWord, Value = threshold });
            } else if (operation == 3 || operation == 4) {
                string name = ValidateProcessName(processName);
                changes.Add(new EmbeddedRegistryChange { KeyPath = IfeoKey + "\\" + name, ValueName = "Debugger", Kind = RegistryValueKind.String, Value = OwnedDebugger, Remove = operation == 4 });
            } else throw new ArgumentOutOfRangeException("operation");
            return changes;
        }

        internal static string Describe(int operation, IList<EmbeddedRegistryChange> changes)
        {
            string text = string.Join(Environment.NewLine + Environment.NewLine, changes.Select(c =>
                "HKLM (64-bit)\\" + c.KeyPath + Environment.NewLine + c.ValueName + " = " +
                (c.Remove ? "remove only Optimizer's own Debugger marker" : Convert.ToString(c.Value, CultureInfo.InvariantCulture))));
            if (operation == 0) text += "\r\n\r\nMatches upstream UnlockAllCores: changes the core-parking setting's min/max metadata. It does not select game CPU affinity or guarantee that cores remain unparked.";
            if (operation == 1 || operation == 2) text += "\r\n\r\nChanges service grouping after a Windows restart. Fewer processes reduce service isolation and do not guarantee higher FPS. 380000 is Optimizer's reset value, not a verified default for every Windows build. No restart occurs automatically.";
            if (operation == 3 || operation == 4) text += "\r\n\r\nApplies to future launches of this filename for all users, not just one folder. Existing Debugger settings owned by other tools are preserved. Running processes are not closed.";
            return text + "\r\n\r\nThe original registry values are saved before writing. Restore last change preserves later edits made by other tools.";
        }

        internal static EmbeddedValueSnapshot Read(EmbeddedRegistryChange c)
        {
            ValidateAddress(c.KeyPath, c.ValueName);
            using (RegistryKey hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64))
            using (RegistryKey key = hive.OpenSubKey(c.KeyPath, false)) {
                bool exists = key != null && key.GetValueNames().Contains(c.ValueName, StringComparer.OrdinalIgnoreCase);
                return new EmbeddedValueSnapshot { KeyPath = c.KeyPath, ValueName = c.ValueName, Exists = exists,
                    Kind = exists ? (int)key.GetValueKind(c.ValueName) : 0,
                    JsonValue = exists ? JsonConvert.SerializeObject(key.GetValue(c.ValueName, null, RegistryValueOptions.DoNotExpandEnvironmentNames)) : null };
            }
        }

        internal static EmbeddedValueSnapshot Expected(EmbeddedRegistryChange c)
        {
            return new EmbeddedValueSnapshot { KeyPath = c.KeyPath, ValueName = c.ValueName, Exists = !c.Remove,
                Kind = c.Remove ? 0 : (int)c.Kind, JsonValue = c.Remove ? null : JsonConvert.SerializeObject(c.Value) };
        }

        internal static bool Equal(EmbeddedValueSnapshot a, EmbeddedValueSnapshot b)
        {
            return a.Exists == b.Exists && (!a.Exists || (a.Kind == b.Kind && a.JsonValue == b.JsonValue));
        }

        internal static void ValidateAddress(string path, string name)
        {
            if (string.Equals(path, CoreParkingKey, StringComparison.OrdinalIgnoreCase)
                && (name == "ValueMin" || name == "ValueMax")) return;
            if (string.Equals(path, ServiceControlKey, StringComparison.OrdinalIgnoreCase)
                && name == "SvcHostSplitThresholdInKB") return;
            string prefix = IfeoKey + "\\";
            if (path != null && path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) && name == "Debugger") {
                ValidateProcessName(path.Substring(prefix.Length)); return;
            }
            throw new InvalidDataException("The restore record contains an unsupported registry address. No value was written.");
        }

        internal static void CheckOwnership(EmbeddedRegistryChange c, EmbeddedValueSnapshot before)
        {
            if (c.ValueName == "Debugger" && before.Exists &&
                !string.Equals(JsonConvert.DeserializeObject<string>(before.JsonValue), OwnedDebugger, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Another tool owns this executable's Debugger value. No change was made; its configuration must be handled in that tool.");
        }

        static object Decode(EmbeddedValueSnapshot s)
        {
            switch ((RegistryValueKind)s.Kind) {
                case RegistryValueKind.DWord: return JsonConvert.DeserializeObject<int>(s.JsonValue);
                case RegistryValueKind.QWord: return JsonConvert.DeserializeObject<long>(s.JsonValue);
                case RegistryValueKind.Binary: case RegistryValueKind.None: return JsonConvert.DeserializeObject<byte[]>(s.JsonValue);
                case RegistryValueKind.MultiString: return JsonConvert.DeserializeObject<string[]>(s.JsonValue);
                default: return JsonConvert.DeserializeObject<string>(s.JsonValue);
            }
        }

        static void Write(EmbeddedValueSnapshot s)
        {
            if (!IsAdministrator) throw new InvalidOperationException("Open Framewell as administrator before changing these settings.");
            ValidateAddress(s.KeyPath, s.ValueName);
            using (RegistryKey hive = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64)) {
                if (s.Exists) using (RegistryKey key = hive.CreateSubKey(s.KeyPath)) key.SetValue(s.ValueName, Decode(s), (RegistryValueKind)s.Kind);
                else using (RegistryKey key = hive.OpenSubKey(s.KeyPath, true)) if (key != null) key.DeleteValue(s.ValueName, false);
            }
        }

        static string Journal { get { return Path.Combine(CoreHelper.CoreFolder, "embedded-advanced-restore.json"); } }
        static List<EmbeddedChangeReceipt> ReadJournal()
        {
            if (!File.Exists(Journal)) return new List<EmbeddedChangeReceipt>();
            var receipts = JsonConvert.DeserializeObject<List<EmbeddedChangeReceipt>>(File.ReadAllText(Journal)) ?? new List<EmbeddedChangeReceipt>();
            foreach (EmbeddedChangeReceipt receipt in receipts) {
                if (receipt == null || receipt.Before == null || receipt.Written == null || receipt.Before.Count != receipt.Written.Count || receipt.Before.Count > 2)
                    throw new InvalidDataException("The restore journal is invalid. No value was written.");
                for (int i = 0; i < receipt.Before.Count; i++) {
                    EmbeddedValueSnapshot before = receipt.Before[i], written = receipt.Written[i];
                    if (before == null || written == null || before.KeyPath != written.KeyPath || before.ValueName != written.ValueName)
                        throw new InvalidDataException("The restore journal contains mismatched values. No value was written.");
                    ValidateAddress(before.KeyPath, before.ValueName);
                    if (before.Exists) Decode(before);
                    if (written.Exists) Decode(written);
                }
            }
            return receipts;
        }
        static void SaveJournal(List<EmbeddedChangeReceipt> receipts)
        {
            Directory.CreateDirectory(CoreHelper.CoreFolder);
            string temp = Journal + ".new";
            File.WriteAllText(temp, JsonConvert.SerializeObject(receipts, Formatting.Indented));
            if (File.Exists(Journal)) File.Replace(temp, Journal, null); else File.Move(temp, Journal);
        }

        internal static void Apply(int operation, IList<EmbeddedRegistryChange> changes)
        {
            if (!IsAdministrator) throw new InvalidOperationException("Administrator access is required.");
            var receipt = new EmbeddedChangeReceipt { Operation = Operations[operation], CreatedUtc = DateTime.UtcNow.ToString("o") };
            foreach (EmbeddedRegistryChange change in changes) {
                EmbeddedValueSnapshot before = Read(change);
                CheckOwnership(change, before);
                receipt.Before.Add(before); receipt.Written.Add(Expected(change));
            }
            List<EmbeddedChangeReceipt> receipts = ReadJournal();
            receipts.Add(receipt);
            SaveJournal(receipts); // Durable restore information must exist before the first write.
            foreach (EmbeddedValueSnapshot value in receipt.Written) Write(value);
            foreach (EmbeddedRegistryChange change in changes)
                if (!Equal(Read(change), Expected(change))) throw new IOException("Windows did not retain a requested value. Use Restore last change; details are saved in the restore journal.");
            receipt.Complete = true;
            SaveJournal(receipts);
        }

        internal static string Restore()
        {
            if (!IsAdministrator) throw new InvalidOperationException("Administrator access is required.");
            List<EmbeddedChangeReceipt> receipts = ReadJournal();
            if (receipts.Count == 0) return "There are no changes from this panel to restore.";
            EmbeddedChangeReceipt receipt = receipts[receipts.Count - 1];
            int restored = 0, preserved = 0;
            for (int i = receipt.Before.Count - 1; i >= 0; i--) {
                EmbeddedValueSnapshot before = receipt.Before[i], written = receipt.Written[i];
                var identity = new EmbeddedRegistryChange { KeyPath = before.KeyPath, ValueName = before.ValueName };
                EmbeddedValueSnapshot current = Read(identity);
                if (Equal(current, before)) continue;
                if (!Equal(current, written)) { preserved++; continue; }
                Write(before);
                if (!Equal(Read(identity), before)) throw new IOException("Windows did not retain a restored value. The journal remains available for another attempt.");
                restored++;
            }
            receipts.RemoveAt(receipts.Count - 1); SaveJournal(receipts);
            return restored + " original value(s) restored; " + preserved + " later change(s) preserved. Restart Windows manually if the setting requires it.";
        }
    }

    internal sealed class EmbeddedAdvancedPanel : UserControl {
        readonly ComboBox _action = new ComboBox { Name = "EmbeddedAdvancedAction", DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        readonly NumericUpDown _ram = new NumericUpDown { Name = "EmbeddedAdvancedRamGB", Minimum = 1, Maximum = 2047, Value = 32, Width = 120 };
        readonly TextBox _process = new TextBox { Name = "EmbeddedAdvancedProcessName", Width = 330 };
        readonly TextBox _preview = new TextBox { Name = "EmbeddedAdvancedPreview", Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical, Dock = DockStyle.Fill };
        readonly Label _status = new Label { Name = "EmbeddedAdvancedStatus", AutoSize = true, MaximumSize = new Size(850, 0) };
        readonly Button _apply = new Button { Name = "EmbeddedAdvancedApply", Text = "Apply previewed change", AutoSize = true };
        readonly Button _restore = new Button { Name = "EmbeddedAdvancedRestore", Text = "Restore last change", AutoSize = true };
        List<EmbeddedRegistryChange> _planned;

        internal EmbeddedAdvancedPanel()
        {
            Name = "EmbeddedAdvancedPanel"; Dock = DockStyle.Fill; AutoScroll = true; Padding = new Padding(16);
            Font = SystemFonts.MessageBoxFont;
            var layout = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 1, RowCount = 9, Padding = new Padding(0, 0, 10, 12) };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            layout.Controls.Add(new Label { Text = "CPU & process controls", Font = new Font(Font.FontFamily, 16, FontStyle.Bold), AutoSize = true, Margin = new Padding(0, 0, 0, 12) });
            layout.Controls.Add(new Label { Text = "Advanced Optimizer actions run inside Framewell. Each change is optional, affects Windows globally, and has its own restore record.", AutoSize = true, MaximumSize = new Size(850, 0), Margin = new Padding(0, 0, 0, 12) });
            layout.Controls.Add(_action);
            var inputs = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill, WrapContents = true, Margin = new Padding(0, 12, 0, 12) };
            inputs.Controls.Add(new Label { Text = "RAM threshold (GB)", AutoSize = true, Padding = new Padding(0, 5, 0, 0) }); inputs.Controls.Add(_ram);
            inputs.Controls.Add(new Label { Text = "App filename", AutoSize = true, Padding = new Padding(12, 5, 0, 0) }); inputs.Controls.Add(_process);
            layout.Controls.Add(inputs);
            layout.Controls.Add(new Label { Text = "Exact change preview", AutoSize = true, Font = new Font(Font, FontStyle.Bold) });
            var previewBox = new Panel { Dock = DockStyle.Fill, Height = 290 }; previewBox.Controls.Add(_preview); layout.Controls.Add(previewBox);
            var buttons = new FlowLayoutPanel { Dock = DockStyle.Fill, AutoSize = true, Margin = new Padding(0, 12, 0, 12) }; buttons.Controls.Add(_apply); buttons.Controls.Add(_restore); layout.Controls.Add(buttons);
            layout.Controls.Add(_status); Controls.Add(layout);
            _action.Items.AddRange(EmbeddedAdvancedActions.Operations);
            _action.SelectedIndexChanged += (s, e) => RefreshPreview(); _ram.ValueChanged += (s, e) => RefreshPreview(); _process.TextChanged += (s, e) => RefreshPreview();
            _apply.Click += Apply_Click; _restore.Click += Restore_Click;
            _action.SelectedIndex = 0;
            _restore.Enabled = EmbeddedAdvancedActions.IsAdministrator;
            _status.Text = EmbeddedAdvancedActions.IsAdministrator ? "No change is made until you apply and confirm the preview." : "Read-only preview. Open Framewell as administrator to apply or restore these changes.";
        }

        void RefreshPreview()
        {
            _ram.Enabled = _action.SelectedIndex == 1; _process.Enabled = _action.SelectedIndex >= 3;
            try {
                _planned = EmbeddedAdvancedActions.Plan(_action.SelectedIndex, (int)_ram.Value, _process.Text);
                _preview.Text = EmbeddedAdvancedActions.Describe(_action.SelectedIndex, _planned);
                _apply.Enabled = EmbeddedAdvancedActions.IsAdministrator;
            } catch (Exception ex) { _planned = null; _preview.Text = ex.Message; _apply.Enabled = false; }
        }

        void Apply_Click(object sender, EventArgs e)
        {
            if (_planned == null || !EmbeddedAdvancedActions.IsAdministrator) return;
            if (System.Windows.Forms.MessageBox.Show(EmbeddedHost.DialogOwner ?? this, _preview.Text + "\r\n\r\nApply this exact change now?", "Confirm Windows change", MessageBoxButtons.YesNo, MessageBoxIcon.Warning, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return;
            try { EmbeddedAdvancedActions.Apply(_action.SelectedIndex, _planned); _status.Text = "Applied and read back successfully. Original values are saved. No automatic restart was requested."; }
            catch (Exception ex) { _status.Text = "Could not complete: " + ex.Message + " If a partial change occurred, use Restore last change."; }
        }

        void Restore_Click(object sender, EventArgs e)
        {
            if (!EmbeddedAdvancedActions.IsAdministrator) return;
            if (System.Windows.Forms.MessageBox.Show(EmbeddedHost.DialogOwner ?? this, "Restore the last change made from this panel? Values subsequently changed by another tool will be preserved.", "Restore previous values", MessageBoxButtons.YesNo, MessageBoxIcon.Question, MessageBoxDefaultButton.Button2) != DialogResult.Yes) return;
            try { _status.Text = EmbeddedAdvancedActions.Restore(); } catch (Exception ex) { _status.Text = "Restore could not complete: " + ex.Message; }
        }
    }
}
