using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using ModernWpf;
using ModernWpf.Controls;
using PureSweep.Core;
using PureSweep.Pages;

namespace PureSweep
{
    public partial class MainWindow : Window
    {
        /// <summary>A sidebar entry and its colours: a dark-to-light background gradient and a bright accent.</summary>
        sealed class PageInfo
        {
            public string Tag, Title, Glyph, Section;
            public Color[] Palette;
            public Color Accent;
        }

        static Color C(uint rgb) => Color.FromRgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

        // Same colours as the macOS version (Hibernation uses the Snapshots colours).
        static readonly PageInfo[] Pages =
        {
            new PageInfo { Tag = "home", Title = "Home", Glyph = "", Palette = new[] { C(0x1A1440), C(0x3B1D7A), C(0x6B2FA8) }, Accent = C(0xC79BFF) },
            new PageInfo { Tag = "cleanup", Title = "Cleanup", Glyph = "", Section = "CLEANUP", Palette = new[] { C(0x062A3F), C(0x0B5372), C(0x1293A8) }, Accent = C(0x5CE1E6) },
            new PageInfo { Tag = "hibernation", Title = "Hibernation", Glyph = "", Section = "CLEANUP", Palette = new[] { C(0x111633), C(0x23307A), C(0x3F52C4) }, Accent = C(0x9DB0FF) },
            new PageInfo { Tag = "uninstaller", Title = "Uninstaller", Glyph = "", Section = "PROGRAMS", Palette = new[] { C(0x2A0716), C(0x6E1236), C(0xB0305A) }, Accent = C(0xFF8FB0) },
            new PageInfo { Tag = "startup", Title = "Startup", Glyph = "", Section = "PROGRAMS", Palette = new[] { C(0x03241F), C(0x0A5546), C(0x13917A) }, Accent = C(0x6FF0C8) },
            new PageInfo { Tag = "shredder", Title = "Shredder", Glyph = "", Section = "FILES", Palette = new[] { C(0x111214), C(0x2A2D35), C(0x4A505E) }, Accent = C(0xC9D1E0) },
            new PageInfo { Tag = "settings", Title = "Settings", Glyph = "", Section = "BOTTOM", Palette = new[] { C(0x0E1820), C(0x22313F), C(0x3D5566) }, Accent = C(0x9CC8E8) },
        };

        readonly Dictionary<string, UserControl> _pages = new Dictionary<string, UserControl>();
        readonly Dictionary<string, RadioButton> _nav = new Dictionary<string, RadioButton>();
        readonly LinearGradientBrush _bg;      // three stops, animated per page
        readonly RadialGradientBrush _glow;    // first stop is the accent glow
        bool _first = true;

        public MainWindow()
        {
            InitializeComponent();
            if (Util.IsAdmin) { Title = "PureSweep (Administrator)"; AdminText.Visibility = Visibility.Visible; }

            // bottom-left to top-right, like the macOS window
            // The stops are animated through the brushes' own collections, so they must not be frozen.
            _bg = new LinearGradientBrush { StartPoint = new Point(0, 1), EndPoint = new Point(1, 0) };
            foreach (double offset in new[] { 0, 0.55, 1 }) _bg.GradientStops.Add(new GradientStop(Colors.Black, offset));
            _glow = new RadialGradientBrush { Center = new Point(0.68, 0.32), GradientOrigin = new Point(0.68, 0.32), RadiusX = 0.55, RadiusY = 0.75 };
            _glow.GradientStops.Add(new GradientStop(Colors.Transparent, 0));
            _glow.GradientStops.Add(new GradientStop(Colors.Transparent, 1));
            BgGradient.Fill = _bg;
            BgGlow.Fill = _glow;

            BuildNav();
            Loaded += (s, e) => Go("home");
        }

        void BuildNav()
        {
            string section = null;
            foreach (PageInfo p in Pages)
            {
                bool bottom = p.Section == "BOTTOM";
                if (!bottom && p.Section != section && p.Section != null)
                    NavList.Children.Add(new TextBlock { Text = p.Section, Style = (Style)FindResource("NavSection") });
                section = p.Section;

                var tile = new Border
                {
                    Width = 24, Height = 24, CornerRadius = new CornerRadius(7),
                    Background = new LinearGradientBrush(Color.FromArgb(0xE6, p.Accent.R, p.Accent.G, p.Accent.B), p.Palette[2], 90),
                    Child = new FontIcon { Glyph = p.Glyph, FontSize = 12, Foreground = Brushes.White }
                };
                var item = new RadioButton
                {
                    Style = (Style)FindResource("NavItem"),
                    Tag = p.Tag,
                    Content = new StackPanel
                    {
                        Orientation = Orientation.Horizontal,
                        Children = { tile, new TextBlock { Text = p.Title, FontSize = 14, Margin = new Thickness(10, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center } }
                    }
                };
                System.Windows.Automation.AutomationProperties.SetName(item, p.Title);
                item.Checked += (s, e) => Show((string)((RadioButton)s).Tag);
                _nav[p.Tag] = item;
                (bottom ? BottomNav : NavList).Children.Add(item);
            }
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
            if (_nav.TryGetValue(tag, out RadioButton item))
            {
                if (item.IsChecked == true) Show(tag);
                else item.IsChecked = true;   // raises Checked, which shows the page
            }
        }

        public void SmartScan()
        {
            Go("cleanup");
            ((CleanupPage)Page("cleanup")).StartScan();
        }

        void Show(string tag)
        {
            PageInfo info = Pages.First(p => p.Tag == tag);
            Recolour(info);
            Host.Content = Page(tag);
            Host.BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220)));
        }

        /// <summary>Glides the background to the page's colours and makes its accent the app accent.</summary>
        void Recolour(PageInfo info)
        {
            var time = TimeSpan.FromMilliseconds(_first ? 0 : 500);
            _first = false;
            for (int i = 0; i < 3; i++)
                _bg.GradientStops[i].BeginAnimation(GradientStop.ColorProperty, new ColorAnimation(info.Palette[i], time));
            _glow.GradientStops[0].BeginAnimation(GradientStop.ColorProperty,
                new ColorAnimation(Color.FromArgb(0x5C, info.Accent.R, info.Accent.G, info.Accent.B), time));
            LogoIcon.Foreground = new SolidColorBrush(info.Accent);
            ThemeManager.Current.AccentColor = info.Accent;
        }
    }
}
