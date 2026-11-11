using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace PureSweep.Core
{
    public class InstalledApp
    {
        public string Name { get; set; }
        public string Publisher { get; set; }
        public string Version { get; set; }
        public long SizeBytes { get; set; }
        public string UninstallCommand { get; set; }
        public ImageSource Icon { get; set; }

        public string SizeText => SizeBytes > 0 ? Util.Size(SizeBytes) : "";
        public string Subtitle => string.Join("  •  ", new[] { Publisher, Version }.Where(s => !string.IsNullOrWhiteSpace(s)));

        public static List<InstalledApp> Load(bool withIcons = true)
        {
            var apps = new Dictionary<string, InstalledApp>(StringComparer.OrdinalIgnoreCase);
            const string key = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall";
            Read(RegistryHive.LocalMachine, RegistryView.Registry64, key, apps, withIcons);
            Read(RegistryHive.LocalMachine, RegistryView.Registry32, key, apps, withIcons);
            Read(RegistryHive.CurrentUser, RegistryView.Registry64, key, apps, withIcons);
            return apps.Values.OrderBy(a => a.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        }

        static void Read(RegistryHive hive, RegistryView view, string path, Dictionary<string, InstalledApp> apps, bool withIcons)
        {
            try
            {
                using (RegistryKey root = RegistryKey.OpenBaseKey(hive, view))
                using (RegistryKey k = root.OpenSubKey(path))
                {
                    if (k == null) return;
                    foreach (string sub in k.GetSubKeyNames())
                    {
                        try
                        {
                            using (RegistryKey a = k.OpenSubKey(sub))
                            {
                                string name = a.GetValue("DisplayName") as string;
                                string cmd = a.GetValue("UninstallString") as string;
                                if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(cmd)) continue;
                                if (Convert.ToInt32(a.GetValue("SystemComponent", 0)) == 1) continue;
                                if (a.GetValue("ParentKeyName") != null) continue;
                                if (apps.ContainsKey(name)) continue;

                                // MSI entries register "/I{guid}" (modify); "/X" is the actual uninstall.
                                if (Regex.IsMatch(cmd, @"^\s*msiexec", RegexOptions.IgnoreCase))
                                    cmd = Regex.Replace(cmd, @"/I\s*\{", "/X{", RegexOptions.IgnoreCase);

                                apps[name] = new InstalledApp
                                {
                                    Name = name.Trim(),
                                    Publisher = a.GetValue("Publisher") as string,
                                    Version = a.GetValue("DisplayVersion") as string,
                                    SizeBytes = Convert.ToInt64(a.GetValue("EstimatedSize", 0)) * 1024,
                                    UninstallCommand = cmd,
                                    Icon = withIcons ? LoadIcon(a.GetValue("DisplayIcon") as string) : null
                                };
                            }
                        }
                        catch { }
                    }
                }
            }
            catch { }
        }

        static ImageSource LoadIcon(string displayIcon)
        {
            try
            {
                if (string.IsNullOrWhiteSpace(displayIcon)) return null;
                string p = Regex.Replace(displayIcon, @",\s*-?\d+\s*$", "").Trim().Trim('"');
                p = Util.Env(p);
                if (!File.Exists(p)) return null;
                using (var ico = System.Drawing.Icon.ExtractAssociatedIcon(p))
                {
                    BitmapSource src = Imaging.CreateBitmapSourceFromHIcon(ico.Handle, Int32Rect.Empty, BitmapSizeOptions.FromEmptyOptions());
                    src.Freeze();
                    return src;
                }
            }
            catch { return null; }
        }

        /// <summary>Launches the app's own uninstaller and returns the process to wait on.</summary>
        public Process StartUninstall()
        {
            return Process.Start(new ProcessStartInfo("cmd.exe", "/c \"" + UninstallCommand + "\"")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            });
        }
    }
}
