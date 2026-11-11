using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using ModernWpf;
using ModernWpf.Controls;

namespace PureSweep.Core
{
    public static class Util
    {
        static readonly string[] Units = { "B", "KB", "MB", "GB", "TB" };

        public static string Size(long bytes)
        {
            double v = bytes;
            int u = 0;
            while (v >= 1024 && u < Units.Length - 1) { v /= 1024; u++; }
            return u == 0 ? $"{bytes} B" : v.ToString(v >= 100 ? "0" : v >= 10 ? "0.0" : "0.00", CultureInfo.CurrentCulture) + " " + Units[u];
        }

        public static readonly bool IsAdmin =
            new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);

        /// <summary>Size of hiberfil.sys on the system drive, or 0 when hibernation is off.</summary>
        public static long HibernationFileSize()
        {
            try
            {
                var f = new FileInfo(Path.Combine(Path.GetPathRoot(Environment.SystemDirectory), "hiberfil.sys"));
                return f.Exists ? f.Length : 0;
            }
            catch { return 0; }
        }

        public static string Env(string s) => Environment.ExpandEnvironmentVariables(s);

        /// <summary>Relaunches the app elevated. Returns false if the user declined the UAC prompt.</summary>
        public static bool RestartElevated()
        {
            try
            {
                Process.Start(new ProcessStartInfo(Assembly.GetExecutingAssembly().Location) { Verb = "runas", UseShellExecute = true });
                Application.Current.Shutdown();
                return true;
            }
            catch (Win32Exception) { return false; }
        }

        public static async Task<bool> Confirm(string title, string message, string primary)
        {
            var dlg = new ContentDialog
            {
                Title = title,
                Content = new System.Windows.Controls.TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, MaxWidth = 420 },
                PrimaryButtonText = primary,
                CloseButtonText = "Cancel",
                DefaultButton = ContentDialogButton.Close
            };
            return await dlg.ShowAsync() == ContentDialogResult.Primary;
        }

        public static async Task Message(string title, string message)
        {
            await new ContentDialog
            {
                Title = title,
                Content = new System.Windows.Controls.TextBlock { Text = message, TextWrapping = TextWrapping.Wrap, MaxWidth = 420 },
                CloseButtonText = "OK"
            }.ShowAsync();
        }
    }

    public static class AppSettings
    {
        public static int Theme;                 // 0 = follow Windows, 1 = light, 2 = dark
        public static string Accent = "";        // "" = Windows accent, else #RRGGBB
        public static bool KeepRecentTemp = true;
        public static DateTime? LastCleanUtc;    // cleaning history shown on the Home page
        public static long LastFreed, TotalFreed;

        public static string Folder
        {
            get
            {
                string f = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PureSweep");
                Directory.CreateDirectory(f);
                return f;
            }
        }

        static string FilePath => Path.Combine(Folder, "settings.txt");

        public static void Load()
        {
            try
            {
                foreach (string line in File.ReadAllLines(FilePath))
                {
                    int i = line.IndexOf('=');
                    if (i < 0) continue;
                    string k = line.Substring(0, i), v = line.Substring(i + 1);
                    if (k == "theme") int.TryParse(v, out Theme);
                    else if (k == "accent") Accent = v;
                    else if (k == "keepRecentTemp") KeepRecentTemp = v == "1";
                    else if (k == "lastClean" && long.TryParse(v, out long t)) LastCleanUtc = t > 0 ? new DateTime(t, DateTimeKind.Utc) : (DateTime?)null;
                    else if (k == "lastFreed") long.TryParse(v, out LastFreed);
                    else if (k == "totalFreed") long.TryParse(v, out TotalFreed);
                }
            }
            catch { }
        }

        public static void Save()
        {
            try { File.WriteAllLines(FilePath, new[] { "theme=" + Theme, "accent=" + Accent, "keepRecentTemp=" + (KeepRecentTemp ? "1" : "0"), "lastClean=" + (LastCleanUtc?.Ticks ?? 0), "lastFreed=" + LastFreed, "totalFreed=" + TotalFreed }); }
            catch { }
        }

        public static void Apply()
        {
            ThemeManager.Current.ApplicationTheme =
                Theme == 1 ? ApplicationTheme.Light : Theme == 2 ? ApplicationTheme.Dark : (ApplicationTheme?)null;
            Color? accent = null;
            try { if (Accent != "") accent = (Color)ColorConverter.ConvertFromString(Accent); } catch { }
            ThemeManager.Current.AccentColor = accent;
        }
    }
}
