using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class SettingsPage : UserControl
    {
        static readonly string[][] Accents =
        {
            new[] { "", "Windows accent" },
            new[] { "#0078D4", "Blue" },
            new[] { "#8764B8", "Violet" },
            new[] { "#E3008C", "Magenta" },
            new[] { "#E81123", "Red" },
            new[] { "#F7630C", "Orange" },
            new[] { "#10893E", "Green" },
            new[] { "#038387", "Teal" },
            new[] { "#69797E", "Slate" },
        };

        readonly bool _ready;

        public SettingsPage()
        {
            InitializeComponent();
            (AppSettings.Theme == 1 ? ThemeLight : AppSettings.Theme == 2 ? ThemeDark : ThemeSystem).IsChecked = true;
            KeepRecent.IsOn = AppSettings.KeepRecentTemp;
            BuildSwatches();
            _ready = true;
        }

        void BuildSwatches()
        {
            Swatches.Children.Clear();
            foreach (string[] a in Accents)
            {
                bool selected = string.Equals(a[0], AppSettings.Accent, StringComparison.OrdinalIgnoreCase);
                FrameworkElement content;
                if (a[0] == "")
                    content = new TextBlock { Text = "Windows", Margin = new Thickness(6, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
                else
                    content = new Rectangle
                    {
                        Width = 28, Height = 28, RadiusX = 4, RadiusY = 4,
                        Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString(a[0]))
                    };

                var b = new Button
                {
                    Content = content,
                    ToolTip = a[1],
                    Tag = a[0],
                    Padding = new Thickness(4),
                    MinHeight = 40,
                    Margin = new Thickness(0, 0, 8, 8),
                    BorderThickness = new Thickness(2)
                };
                if (selected) b.SetResourceReference(BorderBrushProperty, "SystemControlForegroundBaseHighBrush");
                b.Click += (s, e) =>
                {
                    AppSettings.Accent = (string)((Button)s).Tag;
                    AppSettings.Apply();
                    AppSettings.Save();
                    BuildSwatches();
                };
                Swatches.Children.Add(b);
            }
        }

        void Theme_Checked(object sender, RoutedEventArgs e)
        {
            if (!_ready) return;
            AppSettings.Theme = int.Parse((string)((RadioButton)sender).Tag);
            AppSettings.Apply();
            AppSettings.Save();
        }

        void KeepRecent_Toggled(object sender, RoutedEventArgs e)
        {
            if (!_ready) return;
            AppSettings.KeepRecentTemp = KeepRecent.IsOn;
            AppSettings.Save();
        }
    }
}
