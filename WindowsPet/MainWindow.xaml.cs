using System.IO;
using System.Runtime.InteropServices;
using System.Diagnostics;
using System.Net.Http;
using System.Text.Json;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace MiaoXinxin.Windows;

public partial class MainWindow : Window
{
    private static readonly HttpClient UpdateClient = new() { Timeout = TimeSpan.FromSeconds(15) };
    private readonly AssetPack _pack;
    private readonly BehaviorCatalog _catalog;
    private readonly PetSettings _settings = PetSettings.Load();
    private readonly DispatcherTimer _frameTimer = new();
    private readonly DispatcherTimer _movementTimer = new() { Interval = TimeSpan.FromMilliseconds(1000d / 30d) };
    private readonly DispatcherTimer _activityTimer = new();
    private readonly DispatcherTimer _behaviorEndTimer = new();
    private readonly DispatcherTimer _cursorTimer = new() { Interval = TimeSpan.FromMilliseconds(120) };
    private readonly DispatcherTimer _lifeTimer = new() { Interval = TimeSpan.FromMinutes(1) };
    private readonly DispatcherTimer _environmentTimer = new() { Interval = TimeSpan.FromSeconds(2) };
    private readonly List<DesktopToyWindow> _toyWindows = [];
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
    private bool _currentSleeping;
    private bool _suppressed;
    private DateTime _lastToyReaction = DateTime.MinValue;

    public MainWindow(AssetPack pack)
    {
        _pack = pack;
        _catalog = new BehaviorCatalog(pack);
        InitializeComponent();
        Title = pack.Manifest.Name;
        Loaded += OnLoaded;
        Closed += (_, _) =>
        {
            _settings.LastLeft = Left;
            _settings.LastTop = Top;
            if (_settings.LifeSimulationEnabled) _settings.Life.Advance(_currentSleeping);
            _settings.Save();
            foreach (var toy in _toyWindows.ToArray()) toy.Close();
            StopAll();
        };
        MouseLeftButtonDown += OnMouseLeftButtonDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseLeftButtonUp;
        MouseRightButtonUp += (_, _) => OpenBehaviorMenu();
        _frameTimer.Tick += (_, _) => AdvanceFrame();
        _movementTimer.Tick += (_, _) => AdvanceWalk();
        _activityTimer.Tick += (_, _) => BeginRandomActivity();
        _behaviorEndTimer.Tick += (_, _) => FinishTimedBehavior();
        _cursorTimer.Tick += (_, _) => UpdateCursorLook();
        _lifeTimer.Tick += (_, _) => UpdateLife();
        _environmentTimer.Tick += (_, _) => UpdateDesktopEnvironment();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        var work = SystemParameters.WorkArea;
        Left = _settings.LastLeft ?? work.Left + (work.Width - Width) / 2;
        Top = _settings.LastTop ?? work.Bottom - Height;
        DockInsideCurrentDisplay();
        if (!AvailableModes().Contains(_settings.BehaviorMode)) _settings.BehaviorMode = "random";
        ApplyMode(_settings.BehaviorMode);
        _lifeTimer.Start();
        _environmentTimer.Start();
        if (_settings.AutomaticUpdateChecks &&
            (_settings.LastUpdateCheckDate is null || DateTime.Now - _settings.LastUpdateCheckDate > TimeSpan.FromDays(1)))
            _ = CheckForUpdatesAsync(false);
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
        var work = DesktopEnvironment.WorkAreaFor(this);
        Left += _walkDirection * 1.25;
        if (Left <= work.Left) { Left = work.Left; _walkDirection = 1; }
        if (Left + Width >= work.Right) { Left = work.Right - Width; _walkDirection = -1; }
        SetMirrored(_walkDirection < 0);
    }

    private void PlayBehavior(BehaviorDescriptor behavior, bool continuous, Action? completed = null, bool recordLife = true)
    {
        StopAll();
        _frames = _pack.AnimationFrames(behavior.AssetName);
        if (_frames.Count == 0) { completed?.Invoke(); return; }
        _currentSleeping = behavior.IsSleep;
        if (recordLife && _settings.LifeSimulationEnabled && behavior.IsSleep) _settings.Life.Apply("sleep");
        if (recordLife && _settings.LifeSimulationEnabled && behavior.Mode == "eating") _settings.Life.Apply("eat");
        if (recordLife && _settings.LifeSimulationEnabled && behavior.Mode == "drinking") _settings.Life.Apply("drink");
        if (recordLife && _settings.LifeSimulationEnabled) _settings.Save();
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
        var effectiveFps = _settings.ReducedMotion ? Math.Min(fps, 1.5) : fps;
        if (_settings.BatterySaverEnabled && DesktopEnvironment.IsOnBattery) effectiveFps = Math.Min(effectiveFps, 3);
        _frameTimer.Interval = TimeSpan.FromSeconds(1 / Math.Max(.1, effectiveFps));
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
        if (_settings.LifeSimulationEnabled) _settings.Life.Advance(_currentSleeping);
        var hour = _settings.NaturalScheduleEnabled ? DateTime.Now.Hour : 12;
        var life = _settings.LifeSimulationEnabled ? _settings.Life : new PetLifeState();
        var candidates = _catalog.AvailableBehaviors
            .Where(item => _catalog.AutonomousWeight(item, life, hour) > 0)
            .ToArray();
        if (candidates.Length == 0) { ScheduleRandomActivity(TimeSpan.FromSeconds(12)); return; }
        var total = candidates.Sum(item => _catalog.AutonomousWeight(item, life, hour));
        var draw = _random.NextDouble() * total;
        var chosen = candidates[^1];
        foreach (var item in candidates)
        {
            draw -= _catalog.AutonomousWeight(item, life, hour);
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
        if (_settings.LifeSimulationEnabled)
        {
            _settings.Life.Apply("pet");
            _settings.Save();
        }
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
        var life = _settings.Life;
        var status = new System.Windows.Controls.MenuItem
        {
            Header = $"精力 {life.Energy:0}  饱腹 {life.Fullness:0}  水分 {life.Hydration:0}  心情 {life.Mood:0}",
            IsEnabled = false
        };
        menu.Items.Add(status);
        menu.Items.Add(new System.Windows.Controls.Separator());
        var pet = new System.Windows.Controls.MenuItem { Header = $"摸摸{_pack.Manifest.Name}" };
        pet.Click += (_, _) => Pet();
        menu.Items.Add(pet);
        menu.Items.Add(new System.Windows.Controls.Separator());
        AddMode(menu, "随机（自主活动）", "random");
        AddMode(menu, "安静休息", "resting");
        if (_pack.HasAnimation("walk")) AddMode(menu, "散步", "walking");
        foreach (var behavior in _catalog.AvailableBehaviors) AddMode(menu, behavior.Label, behavior.Mode);
        menu.Items.Add(new System.Windows.Controls.Separator());
        if (_settings.DesktopToysEnabled)
        {
            var toys = new System.Windows.Controls.MenuItem { Header = "放置玩具与食物" };
            foreach (var definition in _pack.Manifest.Toys.Where(item => item.Enabled))
            {
                var item = new System.Windows.Controls.MenuItem { Header = ToyLabel(definition) };
                item.Click += (_, _) => PlaceToy(definition);
                toys.Items.Add(item);
            }
            var clear = new System.Windows.Controls.MenuItem { Header = "收起全部" };
            clear.Click += (_, _) => ClearToys();
            toys.Items.Add(new System.Windows.Controls.Separator());
            toys.Items.Add(clear);
            menu.Items.Add(toys);
        }
        AddToggle(menu, "温和养成", _settings.LifeSimulationEnabled, value => _settings.LifeSimulationEnabled = value);
        AddToggle(menu, "自然昼夜作息", _settings.NaturalScheduleEnabled, value => _settings.NaturalScheduleEnabled = value);
        AddToggle(menu, "桌面玩具", _settings.DesktopToysEnabled, value => _settings.DesktopToysEnabled = value);
        AddToggle(menu, "安静模式", _settings.QuietMode, value => _settings.QuietMode = value);
        AddToggle(menu, "减少动态", _settings.ReducedMotion, value => _settings.ReducedMotion = value);
        AddToggle(menu, "电池节能", _settings.BatterySaverEnabled, value => _settings.BatterySaverEnabled = value);
        AddToggle(menu, "全屏时隐藏", _settings.HideDuringFullscreen, value => _settings.HideDuringFullscreen = value);
        AddToggle(menu, "开机启动", _settings.LaunchAtLogin, value =>
        {
            _settings.LaunchAtLogin = value;
            DesktopEnvironment.SetLaunchAtLogin(value);
        });
        AddToggle(menu, "自动检查更新", _settings.AutomaticUpdateChecks, value => _settings.AutomaticUpdateChecks = value);
        var updates = new System.Windows.Controls.MenuItem { Header = "检查更新" };
        updates.Click += async (_, _) => await CheckForUpdatesAsync(true);
        menu.Items.Add(updates);
        menu.Items.Add(new System.Windows.Controls.Separator());
        var quit = new System.Windows.Controls.MenuItem { Header = "退出" };
        quit.Click += (_, _) => Close();
        menu.Items.Add(quit);
        menu.IsOpen = true;
    }

    private void AddToggle(System.Windows.Controls.ContextMenu menu, string label, bool current, Action<bool> changed)
    {
        var item = new System.Windows.Controls.MenuItem { Header = label, IsCheckable = true, IsChecked = current };
        item.Click += (_, _) =>
        {
            changed(item.IsChecked);
            _settings.Save();
            ApplyMode(_settings.BehaviorMode);
        };
        menu.Items.Add(item);
    }

    private static string ToyLabel(ToyDefinition toy) => toy.Label ?? (toy.Kind switch
    {
        "ball" => "小球", "laser" => "激光点", "wand" => "逗宠棒",
        "box" => "纸箱", "food" => "饭碗", "water" => "水碗", _ => toy.Id
    });

    private void PlaceToy(ToyDefinition definition)
    {
        var toy = new DesktopToyWindow(definition.Kind, definition.Label, ReactToToy);
        toy.Closed += (_, _) => _toyWindows.Remove(toy);
        toy.Left = Left + Width + 18;
        toy.Top = Top + Height - toy.Height;
        _toyWindows.Add(toy);
        toy.Show();
    }

    private void ClearToys()
    {
        foreach (var toy in _toyWindows.ToArray()) toy.Close();
        _toyWindows.Clear();
    }

    private void ReactToToy(string kind, Point position)
    {
        if ((DateTime.Now - _lastToyReaction).TotalSeconds < (kind == "laser" ? 1.25 : .25)) return;
        _lastToyReaction = DateTime.Now;
        if (_settings.LifeSimulationEnabled)
        {
            _settings.Life.Apply(kind switch { "food" => "eat", "water" => "drink", _ => "play" }, kind);
            _settings.Save();
        }
        var mode = kind switch { "food" => "eating", "water" => "drinking", _ => "play_toy" };
        var behavior = _catalog.AvailableBehaviors.FirstOrDefault(item => item.Mode == mode);
        if (behavior is not null)
        {
            _resumeMode = _settings.BehaviorMode;
            SetMirrored(position.X < Left + Width / 2);
            PlayBehavior(behavior, false, () => ApplyMode(_resumeMode), recordLife: false);
        }
    }

    private void UpdateLife()
    {
        if (!_settings.LifeSimulationEnabled) return;
        _settings.Life.Advance(_currentSleeping);
        _settings.Save();
    }

    private void UpdateDesktopEnvironment()
    {
        var shouldSuppress = _settings.QuietMode || (_settings.HideDuringFullscreen && DesktopEnvironment.IsForegroundFullscreen());
        if (shouldSuppress == _suppressed) return;
        _suppressed = shouldSuppress;
        if (_suppressed)
        {
            Opacity = 0;
            IsHitTestVisible = false;
            foreach (var toy in _toyWindows) toy.Hide();
        }
        else
        {
            Opacity = 1;
            IsHitTestVisible = true;
            foreach (var toy in _toyWindows) toy.Show();
            DockInsideCurrentDisplay();
        }
    }

    private void DockInsideCurrentDisplay()
    {
        var work = IsLoaded ? DesktopEnvironment.WorkAreaFor(this) : SystemParameters.WorkArea;
        Left = Math.Clamp(Left, work.Left, Math.Max(work.Left, work.Right - Width));
        Top = Math.Clamp(Top, work.Top, Math.Max(work.Top, work.Bottom - Height));
    }

    private async Task CheckForUpdatesAsync(bool showCurrentResult)
    {
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get,
                "https://api.github.com/repos/HExiao-mi/MiaoXinxin-Desktop-Pet/releases/latest");
            request.Headers.UserAgent.ParseAdd("MiaoXinxin-Desktop-Pet");
            using var response = await UpdateClient.SendAsync(request);
            response.EnsureSuccessStatusCode();
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            var root = document.RootElement;
            var tag = root.GetProperty("tag_name").GetString() ?? "v0";
            var page = root.GetProperty("html_url").GetString() ??
                "https://github.com/HExiao-mi/MiaoXinxin-Desktop-Pet/releases";
            _settings.LastUpdateCheckDate = DateTime.Now;
            _settings.Save();
            var current = typeof(MainWindow).Assembly.GetName().Version?.ToString() ?? "0";
            if (IsNewer(tag, current))
            {
                if (MessageBox.Show($"发现新版本 {tag}。打开安装包下载页吗？", "喵心心更新",
                    MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes)
                    Process.Start(new ProcessStartInfo(page) { UseShellExecute = true });
            }
            else if (showCurrentResult)
                MessageBox.Show("当前已经是最新版本。", "喵心心更新", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception error)
        {
            if (showCurrentResult)
                MessageBox.Show(error.Message, "暂时无法检查更新", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static bool IsNewer(string candidate, string current)
    {
        static int[] Parts(string value) => value.TrimStart('v', 'V').Split('.')
            .Select(part => int.TryParse(new string(part.TakeWhile(char.IsDigit).ToArray()), out var number) ? number : 0)
            .ToArray();
        var left = Parts(candidate);
        var right = Parts(current);
        for (var index = 0; index < Math.Max(left.Length, right.Length); index++)
        {
            var lhs = index < left.Length ? left[index] : 0;
            var rhs = index < right.Length ? right[index] : 0;
            if (lhs != rhs) return lhs > rhs;
        }
        return false;
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
        if (_settings.LifeSimulationEnabled && _currentSleeping)
        {
            _settings.Life.Advance(true);
            _settings.Save();
        }
        _frameTimer.Stop();
        _movementTimer.Stop();
        _activityTimer.Stop();
        _behaviorEndTimer.Stop();
        _cursorTimer.Stop();
        _frames = [];
        _walking = false;
        _currentSleeping = false;
        _animationCompleted = null;
        _timedBehaviorCompletion = null;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativePoint { public int X; public int Y; }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out NativePoint point);
}
