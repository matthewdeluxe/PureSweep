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
        bool _scanning;   // a scan the user may stop is running
        bool _stop;       // the user asked that scan to stop
        bool _done;       // just cleaned: show the result until the selection changes or a new scan starts

        public CleanupPage()
        {
            InitializeComponent();
            List.ItemsSource = _cats;
            AdminBar.Visibility = Util.IsAdmin ? Visibility.Collapsed : Visibility.Visible;
            foreach (JunkCategory c in _cats)
                c.PropertyChanged += (s, e) =>
                {
                    if (e.PropertyName != nameof(JunkCategory.SelectedBytes) || _busy) return;
                    _done = false;
                    UpdateTotal();
                };
            UpdateDisk();
        }

        /// <summary>Sets what the round button says. It is the page's only primary action and changes in place.</summary>
        void SetMain(string label, string sub = null, bool enabled = true)
        {
            MainLabel.Text = label;
            MainSub.Text = sub ?? "";
            MainSub.Visibility = sub == null ? Visibility.Collapsed : Visibility.Visible;
            MainBtn.IsEnabled = enabled;
            System.Windows.Automation.AutomationProperties.SetName(MainBtn, sub == null ? label : label + " " + sub);
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
            if (total > 0) SetMain("Clean", Util.Size(total)); else SetMain("Rescan");
            // with nothing selected the round button already rescans, so the link would be a duplicate
            RescanBtn.Visibility = total > 0 ? Visibility.Visible : Visibility.Collapsed;
        }

        void SetBusy(bool busy, string title = null, string status = null)
        {
            _busy = busy;
            Ring.IsActive = busy;
            RescanBtn.IsEnabled = !busy;
            List.IsEnabled = !busy;
            if (title != null) TotalText.Text = title;
            if (status != null) StatusText.Text = status;
        }

        /// <param name="canStop">Let the round button stop the scan. Off for the refresh that follows a clean.</param>
        public async Task ScanAsync(bool canStop = true)
        {
            if (_busy) return;
            _done = false;
            _stop = false;
            _scanning = canStop;
            SetBusy(true, "Scanning…");
            if (canStop) SetMain("Stop");
            foreach (JunkCategory c in _cats)
            {
                if (_stop) break;
                StatusText.Text = "Checking: " + c.Name;
                await Task.Run(() => c.Scan());
            }
            _scanning = false;
            if (_stop)
            {
                // sizes are only partly refreshed, so don't offer to clean from them
                _scanned = false;
                SetBusy(false, "Scan stopped", "Press Scan to start again.");
                SetMain("Scan");
                RescanBtn.Visibility = Visibility.Collapsed;
                return;
            }
            _scanned = true;
            SetBusy(false);
            UpdateTotal();
        }

        /// <summary>Used by the Home page's Smart Scan.</summary>
        public async void StartScan() => await ScanAsync();

        async void Rescan_Click(object sender, RoutedEventArgs e) => await ScanAsync();

        async void Main_Click(object sender, RoutedEventArgs e)
        {
            if (_scanning)
            {
                // takes effect once the category being checked finishes
                _stop = true;
                SetMain("Stopping…", null, false);
            }
            else if (_scanned && !_done && Selected > 0) await CleanAsync();
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
            SetMain("Cleaning…", null, false);
            long freed = await Task.Run(() => selected.Sum(c => c.Clean()));
            SetBusy(false);

            AppSettings.LastCleanUtc = DateTime.UtcNow;
            AppSettings.LastFreed = freed;
            AppSettings.TotalFreed += freed;
            AppSettings.Save();

            await ScanAsync(false);
            UpdateDisk();
            // result state: the button offers a rescan until the user changes the selection
            _done = true;
            TotalText.Text = Util.Size(freed) + " freed";
            StatusText.Text = freed < expected
                ? "Some files were in use or protected and were left in place."
                : "Your PC is clean.";
            SetMain("Rescan");
            RescanBtn.Visibility = Visibility.Collapsed;
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
