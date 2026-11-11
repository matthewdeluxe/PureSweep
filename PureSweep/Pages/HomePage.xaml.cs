using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class HomePage : UserControl
    {
        readonly DispatcherTimer _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(2) };
        long _idle, _busy;   // previous CPU time samples

        public HomePage()
        {
            InitializeComponent();
            _timer.Tick += (s, e) => UpdateLive();
            Loaded += (s, e) => { SampleCpu(out _idle, out _busy); UpdateLive(); UpdateStats(); _timer.Start(); };
            Unloaded += (s, e) => _timer.Stop();
        }

        MainWindow Shell => (MainWindow)Window.GetWindow(this);

        void SmartScan_Click(object sender, RoutedEventArgs e) => Shell.SmartScan();
        void Tile_Click(object sender, RoutedEventArgs e) => Shell.Go((string)((Button)sender).Tag);

        // ---- gauges, refreshed every two seconds while the page is visible

        void UpdateLive()
        {
            try
            {
                var d = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory));
                double used = 100.0 * (d.TotalSize - d.TotalFreeSpace) / d.TotalSize;
                DiskRing.AnimateTo(used);
                DiskPct.Text = used.ToString("0") + "%";
                DiskDetail.Text = $"{Util.Size(d.TotalFreeSpace)} free of {Util.Size(d.TotalSize)}";
            }
            catch { }

            var m = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)) };
            if (GlobalMemoryStatusEx(ref m))
            {
                MemRing.AnimateTo(m.dwMemoryLoad);
                MemPct.Text = m.dwMemoryLoad + "%";
                MemDetail.Text = $"{Util.Size((long)(m.ullTotalPhys - m.ullAvailPhys))} of {Util.Size((long)m.ullTotalPhys)}";
            }

            SampleCpu(out long idle, out long busy);
            long dIdle = idle - _idle, dBusy = busy - _busy;
            _idle = idle; _busy = busy;
            if (dIdle + dBusy > 0)
            {
                double cpu = 100.0 * dBusy / (dIdle + dBusy);
                CpuRing.AnimateTo(cpu);
                CpuPct.Text = cpu.ToString("0") + "%";
                CpuDetail.Text = Environment.ProcessorCount + " logical processors";
            }
        }

        static void SampleCpu(out long idle, out long busy)
        {
            GetSystemTimes(out idle, out long kernel, out long user);
            busy = kernel + user - idle;     // kernel time includes idle time
        }

        // ---- tiles

        async void UpdateStats()
        {
            if (AppSettings.LastCleanUtc is DateTime last)
            {
                CleanValue.Text = $"{Util.Size(AppSettings.LastFreed)} freed {Ago(last)}";
                CleanLabel.Text = $"Last cleanup  •  {Util.Size(AppSettings.TotalFreed)} reclaimed in total";
            }

            List<StartupItem> startup = StartupItem.Load();
            StartupValue.Text = $"{startup.Count(i => i.IsEnabled)} of {startup.Count} enabled";

            long hiber = Util.HibernationFileSize();
            HiberValue.Text = hiber > 0 ? Util.Size(hiber) + " reserved" : "Off — no space used";

            List<InstalledApp> apps = await Task.Run(() => InstalledApp.Load(false));
            AppsValue.Text = $"{apps.Count} programs  •  {Util.Size(apps.Sum(a => a.SizeBytes))}";
        }

        static string Ago(DateTime utc)
        {
            TimeSpan t = DateTime.UtcNow - utc;
            if (t.TotalMinutes < 2) return "just now";
            if (t.TotalHours < 1) return $"{(int)t.TotalMinutes} minutes ago";
            if (t.TotalDays < 1) return (int)t.TotalHours == 1 ? "an hour ago" : $"{(int)t.TotalHours} hours ago";
            return (int)t.TotalDays == 1 ? "yesterday" : $"{(int)t.TotalDays} days ago";
        }

        [StructLayout(LayoutKind.Sequential)]
        struct MEMORYSTATUSEX
        {
            public uint dwLength, dwMemoryLoad;
            public ulong ullTotalPhys, ullAvailPhys, ullTotalPageFile, ullAvailPageFile, ullTotalVirtual, ullAvailVirtual, ullAvailExtendedVirtual;
        }

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX buffer);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
    }
}
