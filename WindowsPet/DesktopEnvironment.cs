using Microsoft.Win32;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media;
using Point = System.Windows.Point;

namespace MiaoXinxin.Windows;

internal static class DesktopEnvironment
{
    public static Rect WorkAreaFor(Window window)
    {
        var dpi = VisualTreeHelper.GetDpi(window);
        var center = window.PointToScreen(new Point(window.ActualWidth / 2, window.ActualHeight / 2));
        var screen = System.Windows.Forms.Screen.FromPoint(
            new System.Drawing.Point((int)center.X, (int)center.Y)
        );
        var area = screen.WorkingArea;
        return new Rect(area.Left / dpi.DpiScaleX, area.Top / dpi.DpiScaleY,
            area.Width / dpi.DpiScaleX, area.Height / dpi.DpiScaleY);
    }

    public static bool IsForegroundFullscreen()
    {
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero || !GetWindowRect(foreground, out var windowRect)) return false;
        var monitor = MonitorFromWindow(foreground, 2);
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info)) return false;
        const int tolerance = 3;
        return Math.Abs(windowRect.Left - info.Monitor.Left) <= tolerance
            && Math.Abs(windowRect.Top - info.Monitor.Top) <= tolerance
            && Math.Abs(windowRect.Right - info.Monitor.Right) <= tolerance
            && Math.Abs(windowRect.Bottom - info.Monitor.Bottom) <= tolerance;
    }

    public static bool IsOnBattery =>
        System.Windows.Forms.SystemInformation.PowerStatus.PowerLineStatus ==
        System.Windows.Forms.PowerLineStatus.Offline;

    public static void SetLaunchAtLogin(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run");
        if (enabled)
        {
            var executable = Environment.ProcessPath ?? Process.GetCurrentProcess().MainModule?.FileName;
            if (!string.IsNullOrWhiteSpace(executable)) key.SetValue("MiaoXinxinDesktopPet", $"\"{executable}\"");
        }
        else key.DeleteValue("MiaoXinxinDesktopPet", false);
    }

    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MonitorInfo { public int Size; public NativeRect Monitor; public NativeRect Work; public uint Flags; }

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr handle, out NativeRect rect);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr handle, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Auto)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
}
