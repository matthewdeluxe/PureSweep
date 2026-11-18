using System.Windows;
using System.Windows.Controls;

namespace PureSweep.Controls
{
    /// <summary>
    /// Large glowing circle with a glyph, used on a page's start screen. IsSpinning adds a rotating arc while work runs.
    /// Colours follow the current page's accent (SystemAccentColor). The template is in App.xaml.
    /// </summary>
    public class Emblem : Control
    {
        public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(nameof(Glyph), typeof(string), typeof(Emblem));
        public static readonly DependencyProperty IsSpinningProperty = DependencyProperty.Register(nameof(IsSpinning), typeof(bool), typeof(Emblem));

        public string Glyph { get => (string)GetValue(GlyphProperty); set => SetValue(GlyphProperty, value); }
        public bool IsSpinning { get => (bool)GetValue(IsSpinningProperty); set => SetValue(IsSpinningProperty, value); }

        public Emblem() { Focusable = false; IsHitTestVisible = false; }
    }
}
