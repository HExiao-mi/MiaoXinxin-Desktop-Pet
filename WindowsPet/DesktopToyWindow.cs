using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace MiaoXinxin.Windows;

public sealed class DesktopToyWindow : Window
{
    private readonly string _kind;
    private readonly Action<string, Point> _onUsed;
    private readonly DispatcherTimer? _laserTimer;
    private Point _mouseDown;
    private bool _dragging;

    public DesktopToyWindow(string kind, string? label, Action<string, Point> onUsed)
    {
        _kind = kind;
        _onUsed = onUsed;
        Title = label ?? kind;
        Width = kind == "box" ? 82 : 58;
        Height = kind == "box" ? 66 : 58;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ResizeMode = ResizeMode.NoResize;
        Content = BuildVisual(kind);
        MouseLeftButtonDown += OnDown;
        MouseMove += OnMove;
        MouseLeftButtonUp += OnUp;

        if (kind == "laser")
        {
            IsHitTestVisible = false;
            _laserTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
            _laserTimer.Tick += (_, _) => FollowCursor();
            _laserTimer.Start();
        }
        Closed += (_, _) => _laserTimer?.Stop();
    }

    private static UIElement BuildVisual(string kind)
    {
        if (kind == "ball")
            return new Ellipse { Width = 34, Height = 34, Fill = Brushes.DodgerBlue, Stroke = Brushes.White, StrokeThickness = 3 };
        if (kind == "laser")
            return new Ellipse { Width = 14, Height = 14, Fill = Brushes.Red, Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Red, BlurRadius = 14, ShadowDepth = 0 } };
        var emoji = kind switch { "wand" => "🪶", "box" => "📦", "food" => "🍚", "water" => "💧", _ => "🧸" };
        return new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(205, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(90, 0, 0, 0)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(14),
            Child = new TextBlock { Text = emoji, FontSize = kind == "box" ? 38 : 31, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }
        };
    }

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        _mouseDown = e.GetPosition(this);
        _dragging = false;
        CaptureMouse();
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(this);
        if (!_dragging && (point - _mouseDown).Length > 4) _dragging = true;
        if (!_dragging) return;
        var screen = PointToScreen(point);
        Left = screen.X - _mouseDown.X;
        Top = screen.Y - _mouseDown.Y;
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        _onUsed(_kind, new Point(Left + Width / 2, Top + Height / 2));
        _dragging = false;
    }

    private void FollowCursor()
    {
        if (!GetCursorPos(out var point)) return;
        Left = point.X - Width / 2;
        Top = point.Y - Height / 2;
        _onUsed(_kind, new Point(Left + Width / 2, Top + Height / 2));
    }

    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X; public int Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
}
