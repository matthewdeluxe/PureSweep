using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class CleanupPage : UserControl
    {
        readonly List<JunkCategory> _cats = JunkCatalog.Create();
        bool _scanned, _busy;

        public CleanupPage()
        {
            InitializeComponent();
            List.ItemsSource = _cats;
            AdminBar.Visibility = Util.IsAdmin ? Visibility.Collapsed : Visibility.Visible;
            foreach (JunkCategory c in _cats)
                c.PropertyChanged += (s, e) => { if (e.PropertyName == nameof(JunkCategory.SelectedBytes)) UpdateTotal(); };
            UpdateDisk();
        }

        long Selected => _cats.Sum(c => c.SelectedBytes);

        void UpdateDisk()
        {
            try
            {
                var d = new DriveInfo(Path.GetPathRoot(Environment.SystemDirectory));
                DiskBar.Value = 100.0 * (d.TotalSize - d.TotalFreeSpace) / d.TotalSize;
                DiskText.Text = $"{d.Name.TrimEnd('\\')}  {Util.Size(d.TotalFreeSpace)} free of {Util.Size(d.TotalSize)}";
            }
            catch { DiskText.Text = ""; }
        }

        void UpdateTotal()
        {
            if (!_scanned || _busy) return;
            long total = Selected;
            TotalText.Text = Util.Size(total);
            StatusText.Text = total > 0
                ? "selected and ready to clean. Open a category to choose exactly what goes."
                : "Nothing selected. Tick a category, or scan again.";
            MainBtn.Content = total > 0 ? "Clean" : "Scan";
        }

        void SetBusy(bool busy, string title = null, string status = null)
        {
            _busy = busy;
            Ring.IsActive = busy;
            MainBtn.IsEnabled = !busy;
            RescanBtn.IsEnabled = !busy;
            List.IsEnabled = !busy;
            if (title != null) TotalText.Text = title;
            if (status != null) StatusText.Text = status;
        }

        public async Task ScanAsync()
        {
            if (_busy) return;
            SetBusy(true, "Scanning…");
            foreach (JunkCategory c in _cats)
            {
                StatusText.Text = "Checking: " + c.Name;
                await Task.Run(() => c.Scan());
            }
            _scanned = true;
            SetBusy(false);
            RescanBtn.Visibility = Visibility.Visible;
            UpdateTotal();
        }

        /// <summary>Used by the Home page's Smart Scan.</summary>
        public async void StartScan() => await ScanAsync();

        async void Rescan_Click(object sender, RoutedEventArgs e) => await ScanAsync();

        async void Main_Click(object sender, RoutedEventArgs e)
        {
            if (_scanned && Selected > 0) await CleanAsync();
            else await ScanAsync();
        }

        async Task CleanAsync()
        {
            List<JunkCategory> selected = _cats.Where(c => c.SelectedBytes > 0).ToList();
            long expected = selected.Sum(c => c.SelectedBytes);
            if (!await Util.Confirm("Clean selected items?",
                $"About {Util.Size(expected)} in {selected.Count} {(selected.Count == 1 ? "category" : "categories")} will be permanently deleted. This can't be undone.", "Clean"))
                return;

            SetBusy(true, "Cleaning…", "Removing selected junk files.");
            long freed = await Task.Run(() => selected.Sum(c => c.Clean()));
            SetBusy(false);

            AppSettings.LastCleanUtc = DateTime.UtcNow;
            AppSettings.LastFreed = freed;
            AppSettings.TotalFreed += freed;
            AppSettings.Save();

            await ScanAsync();
            UpdateDisk();
            TotalText.Text = Util.Size(freed) + " freed";
            StatusText.Text = freed < expected
                ? "Some files were in use or protected and were left in place."
                : "Your PC is clean.";
        }

        void Expand_Click(object sender, RoutedEventArgs e)
        {
            var c = (JunkCategory)((FrameworkElement)sender).Tag;
            c.IsExpanded = !c.IsExpanded;
        }

        async void Elevate_Click(object sender, RoutedEventArgs e)
        {
            if (!Util.RestartElevated())
                await Util.Message("Not restarted", "Administrator access was declined, so PureSweep is still running in limited mode.");
        }
    }
}
