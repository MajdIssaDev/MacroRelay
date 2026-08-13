using System.Windows;
using System.Windows.Interop;
using MacroRelay.Core.Input;
using MacroRelay.Core.Native;

namespace MacroRelay.App.Services;

public sealed class HotkeyService : IDisposable
{
    private HwndSource? _source;
    private IntPtr _hwnd;
    private readonly Dictionary<int, Action> _actions = [];
    private int _nextId = 1;

    public HashSet<string> RegisteredKeys { get; } = new(StringComparer.OrdinalIgnoreCase);

    public void Attach(Window window)
    {
        var helper = new WindowInteropHelper(window);
        _hwnd = helper.EnsureHandle();
        _source = HwndSource.FromHwnd(_hwnd);
        _source?.AddHook(WndProc);
    }

    public void Clear()
    {
        foreach (var id in _actions.Keys.ToArray())
            NativeMethods.UnregisterHotKey(_hwnd, id);
        _actions.Clear();
        RegisteredKeys.Clear();
        _nextId = 1;
    }

    public bool TryRegister(string? gesture, Action action)
    {
        if (!ParsedHotkey.TryParse(gesture, out var parsed))
            return false;
        int id = _nextId++;
        if (!NativeMethods.RegisterHotKey(_hwnd, id, parsed.Modifiers, parsed.VirtualKey))
            return false;
        _actions[id] = action;
        RegisteredKeys.Add(parsed.Display);
        var keyPart = gesture!.Split('+')[^1].Trim();
        RegisteredKeys.Add(keyPart);
        return true;
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == NativeMethods.WmHotkey && _actions.TryGetValue(wParam.ToInt32(), out var action))
        {
            action();
            handled = true;
        }
        if (msg == NativeBroadcast.WmShowMacroRelay)
        {
            if (System.Windows.Application.Current.MainWindow is { } w)
            {
                w.Show();
                w.WindowState = WindowState.Normal;
                w.Activate();
            }
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        Clear();
        _source?.RemoveHook(WndProc);
        _source?.Dispose();
    }
}
