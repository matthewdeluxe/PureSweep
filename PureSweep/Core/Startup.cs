using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Linq;
using Microsoft.Win32;

namespace PureSweep.Core
{
    /// <summary>
    /// A program that runs at sign-in. Enabling/disabling uses the same StartupApproved
    /// registry flags as Task Manager, so nothing is deleted and changes are reversible.
    /// </summary>
    public class StartupItem : INotifyPropertyChanged
    {
        public string Name { get; set; }
        public string Command { get; set; }
        public string Location { get; set; }

        RegistryHive _approvedHive;
        string _approvedKey;     // Run, Run32 or StartupFolder
        string _valueName;
        bool _enabled;

        public event PropertyChangedEventHandler PropertyChanged;

        public bool IsEnabled => _enabled;
        public string StatusText => _enabled ? "Enabled" : "Disabled";
        public System.Windows.Media.Brush StatusBrush => _enabled ? Green : Grey;
        static readonly System.Windows.Media.Brush Green = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0x10, 0x89, 0x3E));
        static readonly System.Windows.Media.Brush Grey = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(0x7A, 0x84, 0x8B));
        public string ActionText => _enabled ? "Disable" : "Enable";
        public double RowOpacity => _enabled ? 1.0 : 0.55;

        const string Approved = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\";

        public void Toggle()
        {
            bool enable = !_enabled;
            using (RegistryKey root = RegistryKey.OpenBaseKey(_approvedHive, RegistryView.Registry64))
            using (RegistryKey k = root.CreateSubKey(Approved + _approvedKey))
            {
                var data = new byte[12];
                data[0] = (byte)(enable ? 2 : 3);
                if (!enable) BitConverter.GetBytes(DateTime.UtcNow.ToFileTimeUtc()).CopyTo(data, 4);
                k.SetValue(_valueName, data, RegistryValueKind.Binary);
            }
            _enabled = enable;
            foreach (string n in new[] { nameof(IsEnabled), nameof(StatusText), nameof(ActionText), nameof(RowOpacity), nameof(StatusBrush) })
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(n));
        }

        static bool ReadEnabled(RegistryHive hive, string approvedKey, string valueName)
        {
            try
            {
                using (RegistryKey root = RegistryKey.OpenBaseKey(hive, RegistryView.Registry64))
                using (RegistryKey k = root.OpenSubKey(Approved + approvedKey))
                {
                    return !(k?.GetValue(valueName) is byte[] b) || b.Length == 0 || (b[0] & 1) == 0;
                }
            }
            catch { return true; }
        }

        public static List<StartupItem> Load()
        {
            var items = new List<StartupItem>();
            const string run = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Run";
            FromRun(items, RegistryHive.CurrentUser, RegistryView.Registry64, run, "Run", "Registry • current user");
            FromRun(items, RegistryHive.LocalMachine, RegistryView.Registry64, run, "Run", "Registry • all users");
            FromRun(items, RegistryHive.LocalMachine, RegistryView.Registry32, run, "Run32", "Registry • all users (32-bit)");
            FromFolder(items, Environment.GetFolderPath(Environment.SpecialFolder.Startup), RegistryHive.CurrentUser, "Startup folder • current user");
            FromFolder(items, Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup), RegistryHive.LocalMachine, "Startup folder • all users");
            return items.OrderBy(i => i.Name, StringComparer.CurrentCultureIgnoreCase).ToList();
        }

        static void FromRun(List<StartupItem> items, RegistryHive hive, RegistryView view, string path, string approvedKey, string location)
        {
            try
            {
                using (RegistryKey root = RegistryKey.OpenBaseKey(hive, view))
                using (RegistryKey k = root.OpenSubKey(path))
                {
                    if (k == null) return;
                    foreach (string name in k.GetValueNames())
                    {
                        if (string.IsNullOrEmpty(name)) continue;
                        items.Add(new StartupItem
                        {
                            Name = name,
                            Command = Convert.ToString(k.GetValue(name)),
                            Location = location,
                            _approvedHive = hive,
                            _approvedKey = approvedKey,
                            _valueName = name,
                            _enabled = ReadEnabled(hive, approvedKey, name)
                        });
                    }
                }
            }
            catch { }
        }

        static void FromFolder(List<StartupItem> items, string folder, RegistryHive hive, string location)
        {
            try
            {
                foreach (string f in Directory.GetFiles(folder))
                {
                    string file = Path.GetFileName(f);
                    if (file.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase)) continue;
                    items.Add(new StartupItem
                    {
                        Name = Path.GetFileNameWithoutExtension(f),
                        Command = f,
                        Location = location,
                        _approvedHive = hive,
                        _approvedKey = "StartupFolder",
                        _valueName = file,
                        _enabled = ReadEnabled(hive, "StartupFolder", file)
                    });
                }
            }
            catch { }
        }
    }
}
