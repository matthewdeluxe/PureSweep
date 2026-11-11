using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class UninstallerPage : UserControl
    {
        List<InstalledApp> _all = new List<InstalledApp>();

        public UninstallerPage()
        {
            InitializeComponent();
            Loaded += async (s, e) => { if (_all.Count == 0) await Reload(); };
        }

        async Task Reload()
        {
            Ring.IsActive = true;
            _all = await Task.Run(() => InstalledApp.Load());
            Ring.IsActive = false;
            ApplyFilter();
        }

        void Filter_Changed(object sender, EventArgs e) { if (IsLoaded) ApplyFilter(); }

        void ApplyFilter()
        {
            string q = Search.Text.Trim();
            IEnumerable<InstalledApp> items = _all;
            if (q != "")
                items = items.Where(a => a.Name.IndexOf(q, StringComparison.CurrentCultureIgnoreCase) >= 0
                                      || (a.Publisher ?? "").IndexOf(q, StringComparison.CurrentCultureIgnoreCase) >= 0);
            if (Sort.SelectedIndex == 1) items = items.OrderByDescending(a => a.SizeBytes);
            else if (Sort.SelectedIndex == 2) items = items.OrderBy(a => a.Publisher ?? "￿", StringComparer.CurrentCultureIgnoreCase);
            List<InstalledApp> list = items.ToList();
            List.ItemsSource = list;
            CountText.Text = $"{list.Count} programs  •  {Util.Size(list.Sum(a => a.SizeBytes))}";
        }

        async void Uninstall_Click(object sender, RoutedEventArgs e)
        {
            var app = (InstalledApp)((Button)sender).Tag;
            if (!await Util.Confirm("Uninstall " + app.Name + "?",
                "This starts the program's own uninstaller. Follow its prompts to finish removing it.", "Uninstall"))
                return;
            try
            {
                Process p = app.StartUninstall();
                Ring.IsActive = true;
                await Task.Run(() => p.WaitForExit());
                await Reload();
            }
            catch (Exception ex)
            {
                Ring.IsActive = false;
                await Util.Message("Couldn't start the uninstaller", ex.Message);
            }
        }
    }
}
