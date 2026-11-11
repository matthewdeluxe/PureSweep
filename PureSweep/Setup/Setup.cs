using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("PureSweep Setup")]
[assembly: AssemblyProduct("PureSweep")]
[assembly: AssemblyVersion("1.0.0.0")]

namespace PureSweepSetup
{
    /// <summary>
    /// Self-contained per-user installer. The app's files are embedded as resources.
    ///   PureSweepSetup.exe              interactive install
    ///   PureSweepSetup.exe /quiet       silent install
    ///   Uninstall.exe /uninstall [/quiet]
    /// </summary>
    static class Program
    {
        const string AppName = "PureSweep";
        const string Version = "1.0.0";
        const string UninstallKey = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\PureSweep";
        static readonly string[] Payload = { "PureSweep.exe", "ModernWpf.dll", "ModernWpf.Controls.dll" };

        static string InstallDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", AppName);
        static string StartMenuLink => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), AppName + ".lnk");
        static string DesktopLink => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), AppName + ".lnk");

        [STAThread]
        static int Main(string[] args)
        {
            bool quiet = args.Any(a => a.Equals("/quiet", StringComparison.OrdinalIgnoreCase));
            bool uninstall = args.Any(a => a.Equals("/uninstall", StringComparison.OrdinalIgnoreCase));
            Application.EnableVisualStyles();
            try
            {
                if (uninstall)
                {
                    if (!quiet && MessageBox.Show("Remove PureSweep and its settings from this PC?", "Uninstall PureSweep",
                            MessageBoxButtons.OKCancel, MessageBoxIcon.Question) != DialogResult.OK) return 1;
                    Uninstall();
                    if (!quiet) MessageBox.Show("PureSweep has been removed.", "Uninstall PureSweep", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 0;
                }
                if (quiet) { Install(false); return 0; }
                Application.Run(new SetupForm());
                return 0;
            }
            catch (Exception ex)
            {
                if (!quiet) MessageBox.Show(ex.Message, "PureSweep Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 2;
            }
        }

        static void EnsureNotRunning()
        {
            foreach (Process p in Process.GetProcessesByName(AppName))
            {
                try
                {
                    if (!string.Equals(Path.GetDirectoryName(p.MainModule.FileName), InstallDir, StringComparison.OrdinalIgnoreCase)) continue;
                    p.CloseMainWindow();
                    if (!p.WaitForExit(5000)) throw new InvalidOperationException("PureSweep is running. Close it and try again.");
                }
                catch (System.ComponentModel.Win32Exception) { /* elevated instance we can't inspect */ }
            }
        }

        public static void Install(bool desktopShortcut)
        {
            EnsureNotRunning();
            Directory.CreateDirectory(InstallDir);
            Assembly me = Assembly.GetExecutingAssembly();
            long bytes = 0;
            foreach (string name in Payload)
            {
                using (Stream src = me.GetManifestResourceStream(name) ?? throw new InvalidOperationException("Setup is damaged: missing " + name))
                using (FileStream dst = File.Create(Path.Combine(InstallDir, name)))
                {
                    src.CopyTo(dst);
                    bytes += dst.Length;
                }
            }

            string exe = Path.Combine(InstallDir, "PureSweep.exe");
            string uninstaller = Path.Combine(InstallDir, "Uninstall.exe");
            if (!string.Equals(me.Location, uninstaller, StringComparison.OrdinalIgnoreCase))
                File.Copy(me.Location, uninstaller, true);
            bytes += new FileInfo(uninstaller).Length;

            CreateShortcut(StartMenuLink, exe);
            if (desktopShortcut) CreateShortcut(DesktopLink, exe);

            using (RegistryKey k = Registry.CurrentUser.CreateSubKey(UninstallKey))
            {
                k.SetValue("DisplayName", AppName);
                k.SetValue("DisplayVersion", Version);
                k.SetValue("Publisher", AppName);
                k.SetValue("DisplayIcon", exe);
                k.SetValue("InstallLocation", InstallDir);
                k.SetValue("UninstallString", "\"" + uninstaller + "\" /uninstall");
                k.SetValue("QuietUninstallString", "\"" + uninstaller + "\" /uninstall /quiet");
                k.SetValue("EstimatedSize", (int)(bytes / 1024), RegistryValueKind.DWord);
                k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
            }
        }

        static void Uninstall()
        {
            EnsureNotRunning();
            foreach (string link in new[] { StartMenuLink, DesktopLink })
                try { File.Delete(link); } catch { }
            Registry.CurrentUser.DeleteSubKeyTree(UninstallKey, false);
            try { Directory.Delete(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), AppName), true); } catch { }

            foreach (string name in Payload)
                try { File.Delete(Path.Combine(InstallDir, name)); } catch { }

            // This exe usually lives in the install folder and can't delete itself,
            // so hand the final folder removal to a short-lived background command.
            Process.Start(new ProcessStartInfo("cmd.exe", "/c ping 127.0.0.1 -n 3 >nul & rmdir /s /q \"" + InstallDir + "\"")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                WorkingDirectory = Path.GetTempPath()
            });
        }

        static void CreateShortcut(string linkPath, string target)
        {
            Type t = Type.GetTypeFromProgID("WScript.Shell");
            object shell = Activator.CreateInstance(t);
            object link = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { linkPath });
            Type lt = link.GetType();
            lt.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] { target });
            lt.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] { Path.GetDirectoryName(target) });
            lt.InvokeMember("Description", BindingFlags.SetProperty, null, link, new object[] { "Clean up and maintain your PC" });
            lt.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
        }

        public static void Launch() => Process.Start(Path.Combine(InstallDir, "PureSweep.exe"));

        public static string InstallDirForDisplay => InstallDir;
    }

    class SetupForm : Form
    {
        readonly CheckBox _desktop = new CheckBox { Text = "Create a desktop shortcut", AutoSize = true, Checked = true };
        readonly CheckBox _launch = new CheckBox { Text = "Launch PureSweep when finished", AutoSize = true, Checked = true };
        readonly Button _install = new Button { Text = "Install", AutoSize = true, Padding = new Padding(16, 4, 16, 4) };
        readonly Button _cancel = new Button { Text = "Cancel", AutoSize = true, Padding = new Padding(16, 4, 16, 4) };

        public SetupForm()
        {
            Text = "PureSweep Setup";
            Font = new Font("Segoe UI", 9.75f);
            AutoScaleMode = AutoScaleMode.Dpi;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false; MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            Icon = Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location);
            AutoSize = true; AutoSizeMode = AutoSizeMode.GrowAndShrink;
            Padding = new Padding(24);

            var layout = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, WrapContents = false, Dock = DockStyle.Fill };
            layout.Controls.Add(new Label { Text = "Install PureSweep 1.0", Font = new Font("Segoe UI Semibold", 15f), AutoSize = true, Margin = new Padding(0, 0, 0, 8) });
            layout.Controls.Add(new Label
            {
                Text = "PureSweep will be installed for your user account only.\nNo administrator rights are needed.\n\nLocation:  " + Program.InstallDirForDisplay,
                AutoSize = true, MaximumSize = new Size(520, 0), Margin = new Padding(0, 0, 0, 16)
            });
            layout.Controls.Add(_desktop);
            layout.Controls.Add(_launch);

            var buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Anchor = AnchorStyles.Right, Margin = new Padding(0, 20, 0, 0) };
            buttons.Controls.Add(_cancel);
            buttons.Controls.Add(_install);
            layout.Controls.Add(buttons);
            Controls.Add(layout);

            AcceptButton = _install; CancelButton = _cancel;
            _cancel.Click += (s, e) => Close();
            _install.Click += (s, e) =>
            {
                try
                {
                    _install.Enabled = false;
                    Program.Install(_desktop.Checked);
                    if (_launch.Checked) Program.Launch();
                    else MessageBox.Show(this, "PureSweep is installed. You'll find it in the Start menu.", Text, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    Close();
                }
                catch (Exception ex)
                {
                    _install.Enabled = true;
                    MessageBox.Show(this, ex.Message, Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            };
        }
    }
}
