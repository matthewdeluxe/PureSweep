using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace PureSweep.Controls
{
    /// <summary>A circular 0-100 gauge: a faint full track with a coloured arc drawn clockwise from 12 o'clock.</summary>
    public class RingGauge : FrameworkElement
    {
        public static readonly DependencyProperty ValueProperty = DependencyProperty.Register(nameof(Value), typeof(double), typeof(RingGauge),
            new FrameworkPropertyMetadata(0.0, FrameworkPropertyMetadataOptions.AffectsRender));
        public static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(nameof(Stroke), typeof(Brush), typeof(RingGauge),
            new FrameworkPropertyMetadata(Brushes.DodgerBlue, FrameworkPropertyMetadataOptions.AffectsRender));
        public static readonly DependencyProperty ThicknessProperty = DependencyProperty.Register(nameof(Thickness), typeof(double), typeof(RingGauge),
            new FrameworkPropertyMetadata(12.0, FrameworkPropertyMetadataOptions.AffectsRender));

        public double Value { get => (double)GetValue(ValueProperty); set => SetValue(ValueProperty, value); }
        public Brush Stroke { get => (Brush)GetValue(StrokeProperty); set => SetValue(StrokeProperty, value); }
        public double Thickness { get => (double)GetValue(ThicknessProperty); set => SetValue(ThicknessProperty, value); }

        static readonly Brush Track = Frozen(Color.FromArgb(0x1F, 0xFF, 0xFF, 0xFF));   // faint white, for the dark gradient
        static Brush Frozen(Color c) { var b = new SolidColorBrush(c); b.Freeze(); return b; }

        /// <summary>Glides the needle to a new value instead of jumping.</summary>
        public void AnimateTo(double value)
        {
            BeginAnimation(ValueProperty, new DoubleAnimation(value, TimeSpan.FromMilliseconds(450))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
            });
        }

        protected override void OnRender(DrawingContext dc)
        {
            double size = Math.Min(ActualWidth, ActualHeight);
            double r = (size - Thickness) / 2;
            if (r <= 0) return;
            var c = new Point(ActualWidth / 2, ActualHeight / 2);
            dc.DrawEllipse(null, new Pen(Track, Thickness), c, r, r);

            double v = Math.Max(0, Math.Min(99.99, Value));
            if (v < 0.2) return;
            double a = v / 100 * 2 * Math.PI;
            var end = new Point(c.X + r * Math.Sin(a), c.Y - r * Math.Cos(a));
            var g = new StreamGeometry();
            using (StreamGeometryContext ctx = g.Open())
            {
                ctx.BeginFigure(new Point(c.X, c.Y - r), false, false);
                ctx.ArcTo(end, new Size(r, r), 0, a > Math.PI, SweepDirection.Clockwise, true, false);
            }
            dc.DrawGeometry(null, new Pen(Stroke, Thickness) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round }, g);
        }
    }
}
