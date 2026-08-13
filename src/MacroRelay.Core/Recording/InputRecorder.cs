using System.Runtime.InteropServices;
using MacroRelay.Core.Input;
using MacroRelay.Core.Models;
using MacroRelay.Core.Native;
using static MacroRelay.Core.Native.NativeMethods;

namespace MacroRelay.Core.Recording;

public sealed class RecordedEvent
{
    public required MacroStep Step { get; init; }
    public int DelayBeforeMs { get; init; }
}

public sealed class InputRecorder : IDisposable
{
    public bool KeepDelays { get; set; } = true;
    public HashSet<string> IgnoreKeys { get; } = new(StringComparer.OrdinalIgnoreCase);

    public event Action<MacroStep>? StepCaptured;

    private IntPtr _kbHook;
    private IntPtr _mouseHook;
    private HookProc? _kbProc;
    private HookProc? _mouseProc;
    private long _lastTicks;
    private bool _started;
    private readonly object _gate = new();

    public bool IsRecording { get; private set; }

    public void Start()
    {
        lock (_gate)
        {
            if (IsRecording)
                return;
            _kbProc = KeyboardHook;
            _mouseProc = MouseHook;
            _lastTicks = Environment.TickCount64;
            var module = GetModuleHandle(null);
            _kbHook = SetWindowsHookEx(WhKeyboardLl, _kbProc, module, 0);
            _mouseHook = SetWindowsHookEx(WhMouseLl, _mouseProc, module, 0);
            IsRecording = true;
            _started = false;
        }
    }

    public void Stop()
    {
        lock (_gate)
        {
            if (!IsRecording)
                return;
            if (_kbHook != IntPtr.Zero) UnhookWindowsHookEx(_kbHook);
            if (_mouseHook != IntPtr.Zero) UnhookWindowsHookEx(_mouseHook);
            _kbHook = IntPtr.Zero;
            _mouseHook = IntPtr.Zero;
            _kbProc = null;
            _mouseProc = null;
            IsRecording = false;
        }
    }

    public void Dispose() => Stop();

    private int ConsumeDelay()
    {
        long now = Environment.TickCount64;
        int delay = (int)Math.Clamp(now - _lastTicks, 0, 60_000);
        _lastTicks = now;
        if (!_started)
        {
            _started = true;
            return 0;
        }
        return KeepDelays ? delay : 0;
    }

    private IntPtr KeyboardHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);
            int msg = wParam.ToInt32();
            bool down = msg is WmKeydown or WmSyskeydown;
            bool up = msg is WmKeyup or WmSyskeyup;
            if (down || up)
            {
                string? name = KeyCatalog.NameFromVk(data.VkCode);
                if (name is not null && !IgnoreKeys.Contains(name) && !IgnoreKeys.Contains($"VK_{data.VkCode:X2}"))
                {
                    int delay = ConsumeDelay();
                    var step = new MacroStep
                    {
                        Type = StepType.Key,
                        Key = name,
                        KeyStroke = down ? KeyStroke.Down : KeyStroke.Up
                    };
                    Emit(delay, step);
                }
            }
        }
        return CallNextHookEx(_kbHook, nCode, wParam, lParam);
    }

    private IntPtr MouseHook(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var data = Marshal.PtrToStructure<MsllHookStruct>(lParam);
            int msg = wParam.ToInt32();
            switch (msg)
            {
                case WmLbuttondown:
                case WmLbuttonup:
                case WmRbuttondown:
                case WmRbuttonup:
                case WmMbuttondown:
                case WmMbuttonup:
                case WmXbuttondown:
                case WmXbuttonup:
                    EmitMouseButton(msg, data);
                    break;
                // Ignore WM_MOUSEMOVE / WM_MOUSEWHEEL — clicks get X,Y only if the user sets them.
            }
        }
        return CallNextHookEx(_mouseHook, nCode, wParam, lParam);
    }

    private void EmitMouseButton(int msg, MsllHookStruct data)
    {
        var (button, down) = msg switch
        {
            WmLbuttondown => (MouseButtonKind.Left, true),
            WmLbuttonup => (MouseButtonKind.Left, false),
            WmRbuttondown => (MouseButtonKind.Right, true),
            WmRbuttonup => (MouseButtonKind.Right, false),
            WmMbuttondown => (MouseButtonKind.Middle, true),
            WmMbuttonup => (MouseButtonKind.Middle, false),
            WmXbuttondown => ((((data.MouseData >> 16) & 0xFFFF) == 2) ? MouseButtonKind.X2 : MouseButtonKind.X1, true),
            WmXbuttonup => ((((data.MouseData >> 16) & 0xFFFF) == 2) ? MouseButtonKind.X2 : MouseButtonKind.X1, false),
            _ => (MouseButtonKind.Left, true)
        };
        int delay = ConsumeDelay();
        var step = new MacroStep
        {
            Type = StepType.Mouse,
            MouseButton = button,
            MouseStroke = down ? MouseStroke.Down : MouseStroke.Up
        };
        Emit(delay, step);
    }

    private void Emit(int delay, MacroStep step)
    {
        if (delay > 0 && KeepDelays)
        {
            StepCaptured?.Invoke(new MacroStep
            {
                Type = StepType.Delay,
                DelayMs = delay
            });
        }
        StepCaptured?.Invoke(step);
    }
}
