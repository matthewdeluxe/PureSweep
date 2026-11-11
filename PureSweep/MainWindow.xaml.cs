using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using ModernWpf.Controls;
using PureSweep.Core;
using PureSweep.Pages;

namespace PureSweep
{
    public partial class MainWindow : Window
    {
        readonly Dictionary<string, UserControl> _pages = new Dictionary<string, UserControl>();

        public MainWindow()
        {
            InitializeComponent();
            if (Util.IsAdmin) Title = "PureSweep (Administrator)";
            Loaded += (s, e) => Nav.SelectedItem = Nav.MenuItems[0];
        }

        UserControl Page(string tag)
        {
            if (!_pages.TryGetValue(tag, out UserControl page))
            {
                switch (tag)
                {
                    case "home": page = new HomePage(); break;
                    case "cleanup": page = new CleanupPage(); break;
                    case "uninstaller": page = new UninstallerPage(); break;
                    case "startup": page = new StartupPage(); break;
                    case "hibernation": page = new HibernationPage(); break;
                    case "shredder": page = new ShredderPage(); break;
                    default: page = new SettingsPage(); break;
                }
                _pages[tag] = page;
            }
            return page;
        }

        /// <summary>Switches to a page by its tag, keeping the sidebar selection in step.</summary>
        public void Go(string tag)
        {
            object item = Nav.MenuItems.OfType<NavigationViewItem>().FirstOrDefault(i => (string)i.Tag == tag);
            if (item != null) Nav.SelectedItem = item;
        }

        public void SmartScan()
        {
            Go("cleanup");
            ((CleanupPage)Page("cleanup")).StartScan();
        }

        void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            string tag = args.IsSettingsSelected ? "settings" : (args.SelectedItem as NavigationViewItem)?.Tag as string;
            if (tag != null) Host.Content = Page(tag);
        }
    }
}
