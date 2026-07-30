using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace MiaoXinxin.Windows;

public partial class MainWindow : Window
{
    private readonly AssetPack _pack;
    private readonly BehaviorCatalog _catalog;
    private readonly PetSettings _settings = PetSettings.Load();
    private readonly DispatcherTimer _frameTimer = new();
    private readonly DispatcherTimer _movementTimer = new() { Interval = TimeSpan.FromMilliseconds(1000d / 30d) };
    private readonly DispatcherTimer _activityTimer = new();
    private readonly DispatcherTimer _behaviorEndTimer = new();
    private readonly DispatcherTimer _cursorTimer = new() { Interval = TimeSpan.FromMilliseconds(120) };
    private readonly Random _random = new();
    private IReadOnlyList<string> _frames = [];
    private int _frameIndex;
    private int _remainingLoops;
    private bool _loopsForever;
    private bool _walking;
    private double _walkDirection = 1;
    private Point? _mouseDown;
    private bool _dragging;
    private string _resumeMode = "random";

    public MainWindow(AssetPack pack)
    {
        _pack = pack;
        _catalog = new BehaviorCatalog(pack);
        InitializeComponent();
        Title = pack.Manifest.Name;
        Loaded += OnLoaded;
        Closed += (_, _) => StopAll();
        MouseLeftButtonDown += OnMouseLeftButtonDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseLeftButtonUp;
        MouseRightButtonUp += (_, _) => OpenBehaviorMenu();
        _frameTimer.Tick += (_, _) => AdvanceFrame();
        _movementTimer.Tick += (_, _) => AdvanceWalk();
        _activityTimer.Tick += (_, _) => BeginRandomActivity();
        _behaviorEndTimer.Tick += (_, _) => FinishTimedBehavior();
        _cursorTimer.Tick += (_, _) => UpdateCursorLook();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var work = SystemParameters.WorkArea;
        Left = work.Left + (work.Width - Width) / 2;
        Top = work.Bottom - Height;
        if (!AvailableModes().Contains(_settings.BehaviorMode)) _settings.BehaviorMode = "random";
        ApplyMode(_settings.BehaviorMode);
    }

    private IReadOnlyList<string> AvailableModes()
    {
        var modes = new List<string> { "random", "resting" };
        if (_pack.HasAnimation("walk")) modes.Add("walking");
        modes.AddRange(_catalog.AvailableBehaviors.Select(item => item.Mode));
        return modes;
    }

    private void ApplyMode(string mode)
    {
        StopAll();
        switch (mode)
        {
            case "random":
                ShowRandomRestingPose();
                _cursorTimer.Start();
                ScheduleRandomActivity(TimeSpan.FromSeconds(4));
                break;
            case "resting":
                ShowRandomRestingPose();
                _cursorTimer.Start();
                break;
            case "walking":
                StartWalking();
                break;
            default:
                var behavior = _catalog.AvailableBehaviors.FirstOrDefault(item => item.Mode == mode);
                if (behavior is null) ApplyMode("resting");
                else PlayBehavior(behavior, true);
                break;
        }
    }

    private void StartWalking()
    {
        _frames = _pack.AnimationFrames("walk");
        if (_frames.Count == 0) { ApplyMode("resting"); return; }
        _walking = true;
        _walkDirection = _random.Next(2) == 0 ? -1 : 1;
        PetImage.RenderTransformOrigin = new Point(.5, .5);
        SetMirrored(_walkDirection < 0);
        StartFrames(_pack.Manifest.Animations.Walk.Fps, true, int.MaxValue);
        _movementTimer.Start();
    }

    private void AdvanceWalk()
    {
        if (!_walking) return;
        var work = SystemParameters.WorkArea;
        Left += _walkDirection * 1.25;
        if (Left <= work.Left) { Left = work.Left; _walkDirection = 1; }
        if (Left + Width >= work.Right) { Left = work.Right - Width; _walkDirection = -1; }
        SetMirrored(_walkDirection < 0);
    }

    private void PlayBehavior(BehaviorDescriptor behavior, bool continuous, Action? completed = null)
    {
        StopAll();
        _frames = _pack.AnimationFrames(behavior.AssetName);
        if (_frames.Count == 0) { completed?.Invoke(); return; }
        StartFrames(behavior.Fps, continuous || behavior.IsSleep, behavior.PlaybackLoops, completed);
        if (behavior.IsSleep && !continuous)
        {
            _timedBehaviorCompletion = completed;
            _behaviorEndTimer.Interval = TimeSpan.FromSeconds(16 + _random.NextDouble() * 12);
            _behaviorEndTimer.Start();
        }
    }

    private Action? _animationCompleted;
    private Action? _timedBehaviorCompletion;

    private void FinishTimedBehavior()
    {
        var completed = _timedBehaviorCompletion;
        StopAll();
        completed?.Invoke();
    }

    private void StartFrames(double fps, bool forever, int loops, Action? completed = null)
    {
        _frameIndex = 0;
        _remainingLoops = Math.Max(1, loops);
        _loopsForever = forever;
        _animationCompleted = completed;
        ShowFrame(_frames[0]);
        _frameTimer.Interval = TimeSpan.FromSeconds(1 / Math.Max(.1, fps));
        _frameTimer.Start();
    }

    private void AdvanceFrame()
    {
        if (_frames.Count == 0) return;
        _frameIndex++;
        if (_frameIndex >= _frames.Count)
        {
            _frameIndex = 0;
            if (!_loopsForever && --_remainingLoops <= 0)
            {
                var completed = _animationCompleted;
                StopAll();
                completed?.Invoke();
                return;
            }
        }
        ShowFrame(_frames[_frameIndex]);
    }

    private void BeginRandomActivity()
    {
        _activityTimer.Stop();
        _behaviorEndTimer.Stop();
        if (_pack.HasAnimation("walk") && _random.NextDouble() < .18)
        {
            StopAll();
            StartWalking();
            _timedBehaviorCompletion = ResumeAfterRandomActivity;
            _behaviorEndTimer.Interval = TimeSpan.FromSeconds(8 + _random.NextDouble() * 8);
            _behaviorEndTimer.Start();
            return;
        }
        var candidates = _catalog.AvailableBehaviors.Where(item => item.AutonomousWeight > 0).ToArray();
        if (candidates.Length == 0) { ScheduleRandomActivity(TimeSpan.FromSeconds(12)); return; }
        var total = candidates.Sum(item => item.AutonomousWeight);
        var draw = _random.NextDouble() * total;
        var chosen = candidates[^1];
        foreach (var item in candidates)
        {
            draw -= item.AutonomousWeight;
            if (draw < 0) { chosen = item; break; }
        }
        PlayBehavior(chosen, false, ResumeAfterRandomActivity);
    }

    private void ResumeAfterRandomActivity()
    {
        if (_settings.BehaviorMode != "random") { ApplyMode(_settings.BehaviorMode); return; }
        ShowRandomRestingPose();
        _cursorTimer.Start();
        ScheduleRandomActivity(TimeSpan.FromSeconds(7 + _random.NextDouble() * 11));
    }

    private void ScheduleRandomActivity(TimeSpan delay)
    {
        _activityTimer.Stop();
        _activityTimer.Interval = delay;
        _activityTimer.Start();
    }

    private void Pet()
    {
        var response = _catalog.PetResponse;
        if (response is null) return;
        _resumeMode = _settings.BehaviorMode;
        PlayBehavior(response, false, () => ApplyMode(_resumeMode));
    }

    private void ShowRandomRestingPose()
    {
        var frames = _pack.PoseFrames(_pack.Manifest.Poses.Resting);
        if (frames.Count == 0) frames = _pack.PoseFrames(_pack.Manifest.Poses.Dialogue);
        if (frames.Count > 0) ShowFrame(frames[_random.Next(frames.Count)]);
        SetMirrored(_random.Next(2) == 0);
    }

    private void UpdateCursorLook()
    {
        if (!_pack.HasAnimation("look") || _frames.Count > 0) return;
        if (!GetCursorPos(out var point)) return;
        var centerX = Left + Width / 2;
        var centerY = Top + Height / 2;
        var dx = point.X - centerX;
        var dy = point.Y - centerY;
        var distance = Math.Sqrt(dx * dx + dy * dy);
        if (distance > 520) return;
        var look = _pack.AnimationFrames("look");
        var index = distance < 45 ? 1 : dy < -45 && Math.Abs(dy) > Math.Abs(dx) * .7 ? 3 : dx < 0 ? 0 : 2;
        if (index < look.Count) ShowFrame(look[index]);
    }

    private void OpenBehaviorMenu()
    {
        var menu = new System.Windows.Controls.ContextMenu();
        var pet = new System.Windows.Controls.MenuItem { Header = $"摸摸{_pack.Manifest.Name}" };
        pet.Click += (_, _) => Pet();
        menu.Items.Add(pet);
        menu.Items.Add(new System.Windows.Controls.Separator());
        AddMode(menu, "随机（自主活动）", "random");
        AddMode(menu, "安静休息", "resting");
        if (_pack.HasAnimation("walk")) AddMode(menu, "散步", "walking");
        foreach (var behavior in _catalog.AvailableBehaviors) AddMode(menu, behavior.Label, behavior.Mode);
        menu.Items.Add(new System.Windows.Controls.Separator());
        var quit = new System.Windows.Controls.MenuItem { Header = "退出" };
        quit.Click += (_, _) => Close();
        menu.Items.Add(quit);
        menu.IsOpen = true;
    }

    private void AddMode(System.Windows.Controls.ContextMenu menu, string label, string mode)
    {
        var item = new System.Windows.Controls.MenuItem { Header = label, IsCheckable = true, IsChecked = _settings.BehaviorMode == mode };
        item.Click += (_, _) =>
        {
            _settings.BehaviorMode = mode;
            _settings.Save();
            ApplyMode(mode);
        };
        menu.Items.Add(item);
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _mouseDown = e.GetPosition(this);
        _dragging = false;
        CaptureMouse();
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (_mouseDown is null || e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(this);
        if (!_dragging && (point - _mouseDown.Value).Length > 10) _dragging = true;
        if (!_dragging) return;
        var screen = PointToScreen(point);
        Left = screen.X - _mouseDown.Value.X;
        Top = screen.Y - _mouseDown.Value.Y;
    }

    private void OnMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        if (!_dragging && _mouseDown is not null) Pet();
        _mouseDown = null;
        _dragging = false;
    }

    private void ShowFrame(string file)
    {
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.UriSource = new Uri(Path.GetFullPath(file));
        bitmap.EndInit();
        bitmap.Freeze();
        PetImage.Source = bitmap;
    }

    private void SetMirrored(bool mirrored) =>
        PetImage.RenderTransform = new ScaleTransform(mirrored ? -1 : 1, 1);

    private void StopAll()
    {
        _frameTimer.Stop();
        _movementTimer.Stop();
        _activityTimer.Stop();
        _behaviorEndTimer.Stop();
        _cursorTimer.Stop();
        _frames = [];
        _walking = false;
        _animationCompleted = null;
        _timedBehaviorCompletion = null;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint { public int X; public int Y; }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out NativePoint point);
}
