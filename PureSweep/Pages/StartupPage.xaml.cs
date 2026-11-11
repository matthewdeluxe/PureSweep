using System;
using System.Collections.Generic;
using System.Linq;
using System.Security;
using System.Windows;
using System.Windows.Controls;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class StartupPage : UserControl
    {
        List<StartupItem> _items;

        public StartupPage()
        {
            InitializeComponent();
            Reload();
        }

        void Reload()
        {
            _items = StartupItem.Load();
            List.ItemsSource = _items;
            UpdateSummary();
        }

        void UpdateSummary() =>
            Banner.Subtitle = $"{_items.Count(i => i.IsEnabled)} of {_items.Count} programs launch when you sign in. Disabling one is reversible.";

        void Refresh_Click(object sender, RoutedEventArgs e) => Reload();

        async void Toggle_Click(object sender, RoutedEventArgs e)
        {
            var item = (StartupItem)((Button)sender).Tag;
            try
            {
                item.Toggle();
                UpdateSummary();
            }
            catch (Exception ex) when (ex is UnauthorizedAccessException || ex is SecurityException)
            {
                await Util.Message("Administrator rights needed",
                    "This item starts for all users, so changing it needs administrator rights. Use \"Restart as administrator\" on the Cleanup page, then try again.");
            }
        }
    }
}
