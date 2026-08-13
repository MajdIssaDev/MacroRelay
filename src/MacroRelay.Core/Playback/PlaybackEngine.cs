using MacroRelay.Core.Input;
using MacroRelay.Core.Models;
using MacroRelay.Core.Native;
using MacroRelay.Core.Windows;

namespace MacroRelay.Core.Playback;

public sealed class PlaybackEngine : IDisposable
{
    public event Action<Guid, PlaybackState>? StateChanged;

    /// <summary>Optional UI-thread paste. If null, Unicode typing is used instead.</summary>
    public Action<string>? PasteText { get; set; }

    private readonly object _gate = new();
    private readonly Dictionary<Guid, Session> _sessions = [];
    private readonly StuckKeys _stuck = new();
    private readonly Random _rng = new();
    private readonly AutoResetEvent _wake = new(false);
    private CancellationTokenSource? _cts;
    private Task? _loop;

    public IReadOnlyDictionary<Guid, PlaybackState> SnapshotStates()
    {
        lock (_gate)
            return _sessions.ToDictionary(s => s.Key, s => s.Value.State);
    }

    public PlaybackState GetState(Guid id)
    {
        lock (_gate)
            return _sessions.TryGetValue(id, out var s) ? s.State : PlaybackState.Stopped;
    }

    public int RunningCount
    {
        get
        {
            lock (_gate)
                return _sessions.Values.Count(s => s.State == PlaybackState.Running);
        }
    }

    public void Start(MacroDefinition macro)
    {
        ArgumentNullException.ThrowIfNull(macro);
        lock (_gate)
        {
            if (_sessions.TryGetValue(macro.Id, out var existing) && existing.State == PlaybackState.Paused)
            {
                existing.State = PlaybackState.Running;
                existing.Macro = Clone(macro);
                Raise(macro.Id, PlaybackState.Running);
                _wake.Set();
                EnsureLoop();
                return;
            }

            _sessions[macro.Id] = new Session
            {
                Macro = Clone(macro),
                State = PlaybackState.Running,
                StepIndex = 0,
                LoopsDone = 0,
                StartedAt = Environment.TickCount64,
                NextDue = Environment.TickCount64,
                Hwnd = IntPtr.Zero
            };
            Raise(macro.Id, PlaybackState.Running);
            EnsureLoop();
        }
        _wake.Set();
    }

    public void Pause(Guid id)
    {
        lock (_gate)
        {
            if (!_sessions.TryGetValue(id, out var s) || s.State != PlaybackState.Running)
                return;
            s.State = PlaybackState.Paused;
            Raise(id, PlaybackState.Paused);
        }
    }

    public void PauseAll()
    {
        lock (_gate)
        {
            foreach (var s in _sessions.Values.Where(x => x.State == PlaybackState.Running))
            {
                s.State = PlaybackState.Paused;
                Raise(s.Macro.Id, PlaybackState.Paused);
            }
        }
    }

    public void Stop(Guid id)
    {
        lock (_gate)
        {
            if (!_sessions.Remove(id))
                return;
        }
        _stuck.ReleaseAll();
        Raise(id, PlaybackState.Stopped);
        _wake.Set();
    }

    public void StopAll()
    {
        Guid[] ids;
        lock (_gate)
        {
            ids = _sessions.Keys.ToArray();
            _sessions.Clear();
        }
        _stuck.ReleaseAll();
        foreach (var id in ids)
            Raise(id, PlaybackState.Stopped);
        _wake.Set();
    }

    public void Dispose()
    {
        StopAll();
        _cts?.Cancel();
        _wake.Set();
        try { _loop?.Wait(1000); } catch { /* ignored */ }
        _cts?.Dispose();
        _wake.Dispose();
    }

    private void EnsureLoop()
    {
        if (_loop is { IsCompleted: false })
            return;
        _cts?.Dispose();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;
        _loop = Task.Factory.StartNew(() => Run(token), token, TaskCreationOptions.LongRunning, TaskScheduler.Default);
    }

    private void Run(CancellationToken token)
    {
        while (!token.IsCancellationRequested)
        {
            Session? due = null;
            int waitMs = 250;
            long now = Environment.TickCount64;
            lock (_gate)
            {
                if (_sessions.Count == 0)
                    break;

                foreach (var s in _sessions.Values)
                {
                    if (s.State != PlaybackState.Running)
                        continue;
                    long remaining = s.NextDue - now;
                    if (remaining <= 0)
                    {
                        due = s;
                        break;
                    }
                    waitMs = (int)Math.Clamp(Math.Min(waitMs, remaining), 1, 250);
                }
            }

            if (due is null)
            {
                WaitHandle.WaitAny([_wake, token.WaitHandle], waitMs);
                continue;
            }

            try
            {
                Advance(due, now);
            }
            catch
            {
                // keep other macros running
            }
        }
    }

    private void Advance(Session session, long now)
    {
        var macro = session.Macro;
        if (macro.TimeLimitEnabled && now - session.StartedAt >= macro.DurationMs)
        {
            Stop(macro.Id);
            return;
        }

        var steps = macro.Steps.Where(s => s.Enabled).ToList();
        if (steps.Count == 0)
        {
            session.NextDue = now + ScaleDelay(macro, Math.Max(macro.IntervalMs, 1));
            return;
        }

        if (session.StepIndex >= steps.Count)
        {
            session.LoopsDone++;
            if (macro.LoopMode == LoopMode.Count && session.LoopsDone >= Math.Max(1, macro.RepeatCount))
            {
                Stop(macro.Id);
                return;
            }
            session.StepIndex = 0;
            session.NextDue = now + ScaleDelay(macro, Math.Max(macro.IntervalMs, 0));
            session.Hwnd = IntPtr.Zero;
            return;
        }

        var step = steps[session.StepIndex];
        session.StepIndex++;

        if (step.Type == StepType.Delay)
        {
            session.NextDue = now + ScaleDelay(macro, Math.Max(step.DelayMs, 0));
            return;
        }

        PrepareWindow(session);
        Execute(session, step);
        session.NextDue = now;
    }

    private int ScaleDelay(MacroDefinition macro, int ms)
    {
        double speed = macro.Speed <= 0 ? 1 : macro.Speed;
        double value = ms / speed;
        if (macro.JitterPercent > 0)
        {
            double j = macro.JitterPercent / 100.0;
            value *= 1 + ((_rng.NextDouble() * 2) - 1) * j;
        }
        return (int)Math.Clamp(Math.Round(value), 0, 60_000);
    }

    private void PrepareWindow(Session session)
    {
        var target = session.Macro.Target;
        if (target.Mode == PlaybackMode.Foreground)
            return;

        if (session.Hwnd == IntPtr.Zero || !NativeMethods.IsWindow(session.Hwnd))
        {
            var info = WindowResolver.Resolve(target);
            session.Hwnd = info?.Handle ?? IntPtr.Zero;
        }

        if (target.Mode == PlaybackMode.FocusTarget && session.Hwnd != IntPtr.Zero)
        {
            if (NativeMethods.GetForegroundWindow() != session.Hwnd)
                WindowResolver.Activate(session.Hwnd);
        }
    }

    private void Execute(Session session, MacroStep step)
    {
        bool background = session.Macro.Target.Mode == PlaybackMode.BackgroundMessages
                          && session.Hwnd != IntPtr.Zero;

        switch (step.Type)
        {
            case StepType.ActivateWindow:
                if (session.Hwnd != IntPtr.Zero)
                    WindowResolver.Activate(session.Hwnd);
                break;
            case StepType.Key:
                PlayKey(session, step, background);
                break;
            case StepType.Mouse:
                PlayMouse(session, step, background);
                break;
            case StepType.Text:
                PlayText(session, step, background);
                break;
        }
    }

    private void PlayKey(Session session, MacroStep step, bool background)
    {
        if (string.IsNullOrWhiteSpace(step.Key) || !KeyCatalog.TryGetVk(step.Key, out var vk))
            return;

        var mods = ParseMods(step.Modifiers);
        if (step.KeyStroke is KeyStroke.Tap or KeyStroke.Down)
        {
            foreach (var m in mods)
                KeyDown(session, m, background);
            KeyDown(session, vk, background);
        }
        if (step.KeyStroke is KeyStroke.Tap or KeyStroke.Up)
        {
            KeyUp(session, vk, background);
            foreach (var m in Enumerable.Reverse(mods))
                KeyUp(session, m, background);
        }
    }

    private void PlayMouse(Session session, MacroStep step, bool background)
    {
        var (x, y) = ResolvePoint(session, step);
        if (step.MouseStroke == MouseStroke.Move)
        {
            if (background)
                BackgroundMessenger.SendMove(session.Hwnd, x, y);
            else
                InputSender.MoveMouseAbsolute(x, y);
            return;
        }
        if (step.MouseStroke == MouseStroke.Wheel)
        {
            if (background)
                BackgroundMessenger.SendWheel(session.Hwnd, step.WheelDelta, x, y);
            else
            {
                InputSender.MoveMouseAbsolute(x, y);
                InputSender.Scroll(step.WheelDelta == 0 ? 120 : step.WheelDelta);
            }
            return;
        }

        bool down = step.MouseStroke is MouseStroke.Click or MouseStroke.Down;
        bool up = step.MouseStroke is MouseStroke.Click or MouseStroke.Up;
        if (!background)
            InputSender.MoveMouseAbsolute(x, y);
        if (down)
        {
            if (background) BackgroundMessenger.SendMouse(session.Hwnd, step.MouseButton, true, x, y);
            else InputSender.SendMouseButton(step.MouseButton, true);
            _stuck.ButtonDown(step.MouseButton);
        }
        if (up)
        {
            if (background) BackgroundMessenger.SendMouse(session.Hwnd, step.MouseButton, false, x, y);
            else InputSender.SendMouseButton(step.MouseButton, false);
            _stuck.ButtonUp(step.MouseButton);
        }
    }

    private void PlayText(Session session, MacroStep step, bool background)
    {
        var text = step.Text ?? "";
        if (text.Length == 0)
            return;
        if (step.TextMethod == TextMethod.Paste && PasteText is not null && !background)
        {
            PasteText(text);
            return;
        }
        foreach (var ch in text)
        {
            if (background)
            {
                BackgroundMessenger.SendChar(session.Hwnd, ch);
            }
            else
            {
                InputSender.SendUnicodeChar(ch, keyUp: false);
                InputSender.SendUnicodeChar(ch, keyUp: true);
            }
        }
    }

    private (int X, int Y) ResolvePoint(Session session, MacroStep step)
    {
        int x = step.X ?? 0;
        int y = step.Y ?? 0;
        bool windowRelative = step.CoordinateMode == CoordinateMode.WindowClient
                              && session.Hwnd != IntPtr.Zero;
        if (session.Macro.Target.Mode != PlaybackMode.Foreground && session.Hwnd != IntPtr.Zero)
            windowRelative = step.CoordinateMode != CoordinateMode.Screen;

        if (windowRelative)
        {
            if (session.Macro.Target.Mode == PlaybackMode.BackgroundMessages)
                return (x, y);
            return WindowResolver.ToScreen(session.Hwnd, x, y);
        }
        return (x, y);
    }

    private void KeyDown(Session session, ushort vk, bool background)
    {
        if (background) BackgroundMessenger.SendKey(session.Hwnd, vk, keyUp: false);
        else InputSender.SendKey(vk, keyUp: false);
        _stuck.KeyDown(vk);
    }

    private void KeyUp(Session session, ushort vk, bool background)
    {
        if (background) BackgroundMessenger.SendKey(session.Hwnd, vk, keyUp: true);
        else InputSender.SendKey(vk, keyUp: true);
        _stuck.KeyUp(vk);
    }

    private static List<ushort> ParseMods(List<string>? modifiers)
    {
        var list = new List<ushort>();
        if (modifiers is null) return list;
        foreach (var name in modifiers)
        {
            if (KeyCatalog.TryGetVk(name, out var vk))
                list.Add(vk);
        }
        return list;
    }

    private void Raise(Guid id, PlaybackState state) => StateChanged?.Invoke(id, state);

    private static MacroDefinition Clone(MacroDefinition m)
    {
        var json = System.Text.Json.JsonSerializer.Serialize(m, Storage.JsonStore.Options);
        return System.Text.Json.JsonSerializer.Deserialize<MacroDefinition>(json, Storage.JsonStore.Options) ?? m;
    }

    private sealed class Session
    {
        public required MacroDefinition Macro { get; set; }
        public PlaybackState State { get; set; }
        public int StepIndex { get; set; }
        public int LoopsDone { get; set; }
        public long StartedAt { get; set; }
        public long NextDue { get; set; }
        public IntPtr Hwnd { get; set; }
    }
}
