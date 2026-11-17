using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class ShredderPage : UserControl
    {
        readonly ObservableCollection<string> _items = new ObservableCollection<string>();

        public ShredderPage()
        {
            InitializeComponent();
            List.ItemsSource = _items;
            _items.CollectionChanged += (s, e) =>
            {
                Empty.Visibility = _items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
                ShredBtn.IsEnabled = _items.Count > 0;
            };
        }

        void Add(IEnumerable<string> paths)
        {
            foreach (string p in paths)
                if (!_items.Contains(p, StringComparer.OrdinalIgnoreCase)) _items.Add(p);
            Status.Text = "";
        }

        void Zone_DragOver(object sender, DragEventArgs e)
        {
            e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
            e.Handled = true;
        }

        void Zone_Drop(object sender, DragEventArgs e)
        {
            if (e.Data.GetData(DataFormats.FileDrop) is string[] paths) Add(paths);
        }

        void AddFiles_Click(object sender, RoutedEventArgs e)
        {
            var dlg = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "Choose files to shred" };
            if (dlg.ShowDialog() == true) Add(dlg.FileNames);
        }

        void AddFolder_Click(object sender, RoutedEventArgs e)
        {
            using (var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = "Choose a folder to shred", ShowNewFolderButton = false })
                if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK) Add(new[] { dlg.SelectedPath });
        }

        void Remove_Click(object sender, RoutedEventArgs e) => _items.Remove((string)((Button)sender).Tag);

        async void Shred_Click(object sender, RoutedEventArgs e)
        {
            if (!await Util.Confirm("Shred " + _items.Count + (_items.Count == 1 ? " item?" : " items?"),
                "The selected files and everything inside the selected folders will be overwritten and deleted. This can't be undone, and nothing goes to the Recycle Bin.\n\n"
                + string.Join("\n", _items.Take(5)) + (_items.Count > 5 ? "\n...and " + (_items.Count - 5) + " more" : ""), "Shred"))
                return;

            int passes = int.Parse((string)((ComboBoxItem)Passes.SelectedItem).Tag);
            List<string> targets = _items.ToList();
            IsEnabled = false;
            Status.Text = "Shredding…";

            int files = 0;
            var failed = new List<string>();
            await Task.Run(() =>
            {
                foreach (string t in targets)
                {
                    try { files += Shredder.Shred(t, passes); }
                    catch (Exception ex) { failed.Add(t + " — " + ex.Message); }
                }
            });

            IsEnabled = true;
            foreach (string t in targets.Where(t => !failed.Any(f => f.StartsWith(t + " — ")))) _items.Remove(t);
            Status.Text = $"{files} files shredded" + (failed.Count > 0 ? $", {failed.Count} items failed" : "") + ".";
            if (failed.Count > 0)
                await Util.Message("Some items couldn't be shredded", string.Join("\n", failed.Take(8)));
        }
    }
}
