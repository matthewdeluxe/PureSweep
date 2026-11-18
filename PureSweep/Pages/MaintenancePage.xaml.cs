using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using ModernWpf.Controls;
using PureSweep.Core;

namespace PureSweep.Pages
{
    public partial class MaintenancePage : UserControl
    {
        public MaintenancePage()
        {
            InitializeComponent();
            foreach (MaintenanceTask t in MaintenanceTask.All) Rows.Children.Add(BuildRow(t));
        }

        UIElement BuildRow(MaintenanceTask t)
        {
            var icon = new Border
            {
                Width = 40, Height = 40, CornerRadius = new CornerRadius(10), VerticalAlignment = VerticalAlignment.Center,
                Background = new SolidColorBrush(Color.FromArgb(0x1A, 255, 255, 255))
            };
            var glyph = new FontIcon { Glyph = t.Glyph, FontSize = 18 };
            glyph.SetResourceReference(Control.ForegroundProperty, "SystemControlHighlightAccentBrush");
            icon.Child = glyph;

            var title = new StackPanel { Orientation = Orientation.Horizontal };
            title.Children.Add(new TextBlock { Text = t.Title, FontWeight = FontWeights.SemiBold, Foreground = Brushes.White });
            if (t.NeedsAdmin && !Util.IsAdmin)
                title.Children.Add(new Border
                {
                    Margin = new Thickness(8, 0, 0, 0), Padding = new Thickness(7, 1, 7, 2), CornerRadius = new CornerRadius(9),
                    Background = new SolidColorBrush(Color.FromArgb(0x38, 0xFF, 0xB3, 0x47)), VerticalAlignment = VerticalAlignment.Center,
                    Child = new TextBlock { Text = "Needs administrator", FontSize = 11, FontWeight = FontWeights.SemiBold, Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0xB3, 0x47)) }
                });

            var status = new TextBlock { Style = (Style)FindResource("MutedCaption"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 4, 0, 0), Visibility = Visibility.Collapsed };
            var text = new StackPanel { Margin = new Thickness(14, 0, 12, 0), VerticalAlignment = VerticalAlignment.Center };
            text.Children.Add(title);
            text.Children.Add(new TextBlock { Text = t.Detail, Style = (Style)FindResource("MutedCaption"), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 0) });
            text.Children.Add(status);

            var ring = new ProgressRing { IsActive = false, Width = 22, Height = 22, Visibility = Visibility.Collapsed, Margin = new Thickness(20, 0, 20, 0) };
            var run = new Button { Content = "Run", Style = (Style)FindResource("Push3D"), MinWidth = 72, VerticalAlignment = VerticalAlignment.Center };
            System.Windows.Automation.AutomationProperties.SetName(run, "Run " + t.Title);
            run.Click += async (s, e) =>
            {
                if (t.Confirm != null && !await Util.Confirm(t.Title + "?", t.Confirm, "Run")) return;
                run.Visibility = Visibility.Collapsed;
                ring.Visibility = Visibility.Visible; ring.IsActive = true;
                status.Visibility = Visibility.Collapsed;
                string error = await t.Run();
                ring.IsActive = false; ring.Visibility = Visibility.Collapsed;
                run.Visibility = Visibility.Visible;
                if (error == "") return;   // UAC prompt declined
                status.Visibility = Visibility.Visible;
                if (error == null)
                {
                    status.Text = $"Done at {DateTime.Now:t}." + (t.DoneNote != null ? " " + t.DoneNote : "");
                    status.SetResourceReference(TextBlock.ForegroundProperty, "SystemControlHighlightAccentBrush");
                }
                else
                {
                    status.Text = error;
                    status.Foreground = new SolidColorBrush(Color.FromRgb(0xFF, 0xB3, 0x47));
                }
            };

            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            Grid.SetColumn(text, 1);
            Grid.SetColumn(run, 2);
            Grid.SetColumn(ring, 2);
            grid.Children.Add(icon);
            grid.Children.Add(text);
            grid.Children.Add(run);
            grid.Children.Add(ring);

            return new Border { Style = (Style)FindResource("Card"), Padding = new Thickness(16, 14, 16, 14), Margin = new Thickness(0, 0, 0, 10), Child = grid };
        }
    }
}
