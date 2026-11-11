using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace PureSweep.Controls
{
    /// <summary>
    /// Coloured page banner: icon, title, subtitle and an optional action on the right (the control's Content).
    /// Set From/To for a fixed gradient; leave them unset to follow the app's accent colour.
    /// </summary>
    public class Hero : ContentControl
    {
        public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(nameof(Title), typeof(string), typeof(Hero));
        public static readonly DependencyProperty SubtitleProperty = DependencyProperty.Register(nameof(Subtitle), typeof(string), typeof(Hero));
        public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(nameof(Glyph), typeof(string), typeof(Hero));
        public static readonly DependencyProperty FillProperty = DependencyProperty.Register(nameof(Fill), typeof(Brush), typeof(Hero));
        public static readonly DependencyProperty FromProperty = DependencyProperty.Register(nameof(From), typeof(Color), typeof(Hero), new PropertyMetadata(Colors.Transparent, OnColors));
        public static readonly DependencyProperty ToProperty = DependencyProperty.Register(nameof(To), typeof(Color), typeof(Hero), new PropertyMetadata(Colors.Transparent, OnColors));

        public string Title { get => (string)GetValue(TitleProperty); set => SetValue(TitleProperty, value); }
        public string Subtitle { get => (string)GetValue(SubtitleProperty); set => SetValue(SubtitleProperty, value); }
        public string Glyph { get => (string)GetValue(GlyphProperty); set => SetValue(GlyphProperty, value); }
        public Brush Fill { get => (Brush)GetValue(FillProperty); set => SetValue(FillProperty, value); }
        public Color From { get => (Color)GetValue(FromProperty); set => SetValue(FromProperty, value); }
        public Color To { get => (Color)GetValue(ToProperty); set => SetValue(ToProperty, value); }

        public Hero() { Focusable = false; }

        static void OnColors(DependencyObject d, DependencyPropertyChangedEventArgs e)
        {
            var h = (Hero)d;
            var brush = new LinearGradientBrush(h.From, h.To, new Point(0, 0), new Point(1, 1));
            brush.Freeze();
            h.Fill = brush;
        }
    }
}
