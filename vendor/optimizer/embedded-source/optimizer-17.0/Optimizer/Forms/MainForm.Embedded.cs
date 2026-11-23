// Gaming Mode's same-process embedding adapter. GPL-3.0-only.
using System;
using System.Drawing;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Windows.Forms;

namespace Optimizer {
    public sealed partial class MainForm {
        private bool _embeddedHardwareLoaded;
        private bool _embeddedCleanerLoaded;
        private bool _embeddedDisposed;
        private bool _embeddedConfigured;
        private bool _embeddedModernLoaded;
        private readonly ToolTip _tips = new ToolTip();
        internal void ConfigureEmbedding(bool enableActions) {
            SuspendLayout();
            _revealPending = false;
            TopLevel = false;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            MinimumSize = Size.Empty;
            MaximumSize = Size.Empty;
            AutoSize = false;
            Size = new Size(780, 620);
            Dock = DockStyle.Fill;
            WindowState = FormWindowState.Normal;
            tpanel.Visible = false;
            sidebarNav.Visible = false;
            lblPageTitle.Visible = false;
            bpanel.Dock = DockStyle.Fill;
            bpanel.Padding = Padding.Empty;
            tabCollection.Dock = DockStyle.Fill;
            tabCollection.Multiline = true;
            launcherIcon.Visible = false;
            _trayMenu = false;

            // Lifetime, updates, and startup belong to the host app; Windows tools stay available.
            autoStartToggle.Enabled = false;
            quickAccessToggle.Enabled = false;
            autoUpdateToggle.Enabled = false;
            btnUpdate.Text = "Gaming Mode updates";
            btnShodan.Text = "Shodan IP details";
            btnOpenNetwork.Text = "Adapter details";
            btnWinClean.Text = "Preview cleanup";
            btnResetConfig.Enabled = false;
            _tips.SetToolTip(autoStartToggle, "Use Gaming Mode Settings to start the host app with Windows.");
            _tips.SetToolTip(quickAccessToggle, "Window and tray lifetime are managed by Gaming Mode.");
            _tips.SetToolTip(autoUpdateToggle, "Update Gaming Mode to update the embedded tools.");
            _tips.SetToolTip(btnResetConfig, "Close Gaming Mode before resetting its private Windows-tools state.");

            TabPage extras = new TabPage("CPU & process controls") { Name = "advancedExtrasTab", AutoScroll = true };
            extras.Controls.Add(CreateEmbeddedAdvancedExtras());
            // Add avoids TabPageCollection.Insert's stale cache during SidebarNav's ControlAdded callback.
            tabCollection.TabPages.Add(extras);
            foreach (TabPage page in tabCollection.TabPages) {
                page.AutoScroll = true;
                // Keep each section's scrollbar usable while its system-changing controls are gated.
                if (!enableActions) foreach (Control child in page.Controls) child.Enabled = false;
            }
            ResumeLayout(true);
            _embeddedConfigured = true;
            Visible = true;
        }
        internal EmbeddedSection[] EmbeddedSections() {
            return tabCollection.TabPages.Cast<TabPage>().Select(p => new EmbeddedSection(p.Name, p.Text)).ToArray();
        }
        internal void EmbeddedSelectSection(string id) {
            TabPage page = tabCollection.TabPages.Cast<TabPage>().FirstOrDefault(p => string.Equals(p.Name, id, StringComparison.OrdinalIgnoreCase));
            if (page == null) throw new ArgumentException("This Windows-tools section is unavailable on this Windows version: " + id, "id");
            tabCollection.SelectedTab = page;
            if (page == modernAppsTab && !_embeddedModernLoaded) { _embeddedModernLoaded = true; GetModernApps(!chkOnlyRemovable.Checked); }
            if (page == indiciumTab && !_embeddedHardwareLoaded) { _embeddedHardwareLoaded = true; LoadHardwareSpecsAsync(); }
            if (page == cleanerTab && !_embeddedCleanerLoaded) { _embeddedCleanerLoaded = true; GetFootprint(); }
        }
        internal void DisposeEmbeddedResources() {
            if (_embeddedDisposed) return;
            _embeddedDisposed = true;
            if (_daClock != null) _daClock.Dispose();
            if (_daMonitor != null) _daMonitor.Dispose();
            if (_dnsCopiedTimer != null) _dnsCopiedTimer.Dispose();
            if (_cleanCheckTimer != null) _cleanCheckTimer.Dispose();
            if (_modernTips != null) _modernTips.Dispose();
            if (_startupTips != null) _startupTips.Dispose();
            if (_tips != null) _tips.Dispose();
            if (_daRowMenu != null) _daRowMenu.Dispose();
            if (_daDriveMenu != null) _daDriveMenu.Dispose();
            TipBubble.CloseAll();
        }
        private Form CreateEmbeddedReport(string title, string description, out TextBox output) {
            Form dialog = new Form { Text = title, StartPosition = FormStartPosition.CenterParent, Size = new Size(740, 560), MinimumSize = new Size(500, 360), ShowInTaskbar = false };
            Label notice = new Label { Text = description, Dock = DockStyle.Top, Height = 68, Padding = new Padding(14), AutoSize = false };
            output = new TextBox { Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false, Dock = DockStyle.Fill, BorderStyle = BorderStyle.None, Font = new Font("Consolas", 10f) };
            dialog.Controls.Add(output);
            dialog.Controls.Add(notice);
            ThemeManager.Apply(dialog);
            return dialog;
        }
        private void ShowEmbeddedNetworkDetails() {
            TextBox output;
            using (Form dialog = CreateEmbeddedReport("Network adapter details", "Read-only adapter information. Use this workspace's Network / DNS controls to change DNS settings.", out output)) {
                StringBuilder report = new StringBuilder();
                foreach (NetworkInterface adapter in NetworkInterface.GetAllNetworkInterfaces()) {
                    report.AppendLine(adapter.Name + " — " + adapter.OperationalStatus);
                    report.AppendLine(adapter.Description);
                    report.AppendLine("Link speed: " + (adapter.Speed / 1000000L) + " Mbps");
                    try {
                        IPInterfaceProperties ip = adapter.GetIPProperties();
                        report.AppendLine("Addresses: " + string.Join(", ", ip.UnicastAddresses.Select(a => a.Address.ToString())));
                        report.AppendLine("Gateways: " + string.Join(", ", ip.GatewayAddresses.Select(a => a.Address.ToString())));
                        report.AppendLine("DNS: " + string.Join(", ", ip.DnsAddresses.Select(a => a.ToString())));
                    } catch (NetworkInformationException ex) { report.AppendLine(ex.Message); }
                    report.AppendLine();
                }
                output.Text = report.ToString();
                dialog.ShowDialog(EmbeddedHost.DialogOwner ?? this);
            }
        }
        private void ShowEmbeddedShodanLookup() {
            IPAddress address;
            string target = txtPingInput.Text.Trim();
            if (!IPAddress.TryParse(target, out address) && !IPAddress.TryParse(_shodanIP, out address)) {
                MessageBox.Show("Enter a public IPv4 address, or ping a hostname first so its address is available.", "Shodan IP details"); return;
            }
            if (address.AddressFamily != AddressFamily.InterNetwork) { MessageBox.Show("The embedded InternetDB lookup uses IPv4 addresses.", "Shodan IP details"); return; }
            byte[] bytes = address.GetAddressBytes();
            if (IPAddress.IsLoopback(address) || bytes[0] == 0 || bytes[0] == 10 || bytes[0] >= 224 ||
                (bytes[0] == 192 && bytes[1] == 168) || (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
                (bytes[0] == 169 && bytes[1] == 254) || (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127)) {
                MessageBox.Show("This lookup is for public addresses. Local and private addresses are not sent to Shodan.", "Shodan IP details"); return;
            }
            TextBox output;
            using (Form dialog = CreateEmbeddedReport("Shodan IP details — " + address, "Queries Shodan InternetDB for this address. Weekly snapshot, not a live scan. Free for non-commercial use; commercial use requires Shodan's license. Results are more limited than a full Shodan account lookup.", out output)) {
                output.Text = "Loading public IP information…";
                dialog.Shown += async (sender, args) => {
                    try {
                        using (HttpClient client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) }) {
                            string json = await client.GetStringAsync("https://internetdb.shodan.io/" + Uri.EscapeDataString(address.ToString()));
                            if (!dialog.IsDisposed) output.Text = Newtonsoft.Json.Linq.JToken.Parse(json).ToString(Newtonsoft.Json.Formatting.Indented);
                        }
                    } catch (Exception ex) { if (!dialog.IsDisposed) output.Text = "No result could be retrieved. An address may have no InternetDB record.\r\n\r\n" + ex.Message; }
                };
                dialog.ShowDialog(EmbeddedHost.DialogOwner ?? this);
            }
        }
    }
}
