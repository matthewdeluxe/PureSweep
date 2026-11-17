using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class CleanupPage : UserControl
    {
        readonly List<JunkCategory> _cats = JunkCatalog.Create();
        bool _scanned, _busy;
        const double CleanShare = 60;   // cleaning fills the progress bar to here; the refresh scan after it fills the rest
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

        /// <summary>Moves the progress bar to a 0-100 value; jump = no glide, for the start of a run.</summary>
        void Progress(double value, bool jump = false)
        {
            if (jump)
            {
                BeginAnimation(ShownProperty, null);
                SetValue(ShownProperty, value);
                ShowProgress(value);   // the callback is skipped when the value hasn't changed
            }
            else
                BeginAnimation(ShownProperty, new DoubleAnimation(value, TimeSpan.FromMilliseconds(450))
                {
                    EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
                });
        }

        // The progress currently drawn. Animated, so the bar and the percentage glide together.
        static readonly DependencyProperty ShownProperty = DependencyProperty.Register("Shown", typeof(double), typeof(CleanupPage),
            new PropertyMetadata(0.0, (d, e) => ((CleanupPage)d).ShowProgress((double)e.NewValue)));

        void ShowProgress(double value)
        {
            WorkFill.Width = WorkTrack.ActualWidth * value / 100;
            WorkPct.Text = Math.Round(value) + "%";
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
            WorkRow.Visibility = busy ? Visibility.Visible : Visibility.Collapsed;
            DiskText.Visibility = DiskBar.Visibility = busy ? Visibility.Collapsed : Visibility.Visible;
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
            SetBusy(true, canStop ? "Scanning…" : "Finishing up…");
            // A normal scan fills the whole bar. The refresh after a clean continues from where cleaning left it.
            double from = canStop ? 0 : CleanShare;
            if (canStop) { SetMain("Stop"); Progress(0, true); }
            for (int i = 0; i < _cats.Count; i++)
            {
                if (_stop) break;
                JunkCategory c = _cats[i];
                StatusText.Text = "Checking: " + c.Name;
                await Task.Run(() => c.Scan());
                Progress(from + (100 - from) * (i + 1) / _cats.Count);
            }
            if (!_stop)
            {
                // a quick scan can end before the bar has visibly moved, so let it glide to full before it disappears
                _scanning = false;   // too late to stop; a click now is ignored because the page is still busy
                Progress(100);
                await Task.Delay(550);
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
                $"About {Util.Size(expected)} will be permanently deleted from: {string.Join(", ", selected.Select(c => c.Name))}. This can't be undone.", "Clean"))
                return;

            SetBusy(true, "Cleaning…", "Removing selected junk files.");
            SetMain("Cleaning…", null, false);
            Progress(0, true);
            long freed = 0;
            for (int i = 0; i < selected.Count; i++)
            {
                JunkCategory c = selected[i];
                StatusText.Text = "Cleaning: " + c.Name;
                freed += await Task.Run(() => c.Clean());
                Progress(CleanShare * (i + 1) / selected.Count);
            }
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
