using System;
using System.Windows;
using System.Windows.Controls;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class SettingsPage : UserControl
    {
        readonly bool _ready;

        public SettingsPage()
        {
            InitializeComponent();
            KeepRecent.IsOn = AppSettings.KeepRecentTemp;
            Loaded += (s, e) => ShowHistory();
            _ready = true;
        }

        void ShowHistory()
        {
            LastText.Text = AppSettings.LastCleanUtc is DateTime last
                ? $"Last cleanup: {Util.Size(AppSettings.LastFreed)} freed on {last.ToLocalTime():g}"
                : "Last cleanup: never";
            TotalText.Text = $"Reclaimed in total: {Util.Size(AppSettings.TotalFreed)}";
        }

        void KeepRecent_Toggled(object sender, RoutedEventArgs e)
        {
            if (!_ready) return;
            AppSettings.KeepRecentTemp = KeepRecent.IsOn;
            AppSettings.Save();
        }
    }
}
