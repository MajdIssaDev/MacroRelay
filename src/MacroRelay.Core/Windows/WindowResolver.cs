using System.Diagnostics;
using System.Text;
using MacroRelay.Core.Models;
using MacroRelay.Core.Native;
using static MacroRelay.Core.Native.NativeMethods;

namespace MacroRelay.Core.Windows;

public sealed class WindowInfo
{
    public IntPtr Handle { get; init; }
    public string Title { get; init; } = "";
    public string ClassName { get; init; } = "";
    public string ProcessName { get; init; } = "";
    public int ProcessId { get; init; }

    public override string ToString() =>
        string.IsNullOrWhiteSpace(Title)
            ? $"{ProcessName} (PID {ProcessId})"
            : $"{Title} — {ProcessName} (PID {ProcessId})";
}

public static class WindowResolver
{
    public static IReadOnlyList<WindowInfo> ListWindows()
    {
        var list = new List<WindowInfo>();
        EnumWindows((hWnd, _) =>
        {
            if (!IsWindowVisible(hWnd) || GetWindowTextLength(hWnd) == 0)
                return true;
            var info = FromHandle(hWnd);
            if (info is not null)
                list.Add(info);
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static WindowInfo? FromHandle(IntPtr hWnd)
    {
        if (hWnd == IntPtr.Zero || !IsWindow(hWnd))
            return null;

        var title = new StringBuilder(512);
        GetWindowText(hWnd, title, title.Capacity);
        var cls = new StringBuilder(256);
        GetClassName(hWnd, cls, cls.Capacity);
        GetWindowThreadProcessId(hWnd, out uint pid);

        string processName = "";
        try
        {
            using var p = Process.GetProcessById((int)pid);
            processName = p.ProcessName;
        }
        catch
        {
            // process may have exited
        }

        return new WindowInfo
        {
            Handle = hWnd,
            Title = title.ToString(),
            ClassName = cls.ToString(),
            ProcessName = processName,
            ProcessId = (int)pid
        };
    }

    public static WindowInfo? FromPoint(int screenX, int screenY)
    {
        var pt = new Point { X = screenX, Y = screenY };
        return FromHandle(WindowFromPoint(pt));
    }

    public static WindowInfo? FromPointExcluding(int screenX, int screenY, IntPtr exclude)
    {
        foreach (var window in ListWindows())
        {
            if (window.Handle == exclude)
                continue;
            GetWindowRect(window.Handle, out var rect);
            if (screenX >= rect.Left && screenX < rect.Right && screenY >= rect.Top && screenY < rect.Bottom)
                return window;
        }
        return FromPoint(screenX, screenY);
    }

    public static WindowInfo? Resolve(WindowTarget target)
    {
        if (target.Mode == PlaybackMode.Foreground)
            return FromHandle(GetForegroundWindow());

        WindowInfo? best = null;
        foreach (var window in ListWindows())
        {
            if (!Matches(window, target))
                continue;
            best = window;
            break;
        }

        return best;
    }

    public static bool Matches(WindowInfo window, WindowTarget target)
    {
        if (!string.IsNullOrWhiteSpace(target.ProcessName) &&
            !string.Equals(window.ProcessName, StripExe(target.ProcessName), StringComparison.OrdinalIgnoreCase))
            return false;
        if (target.ProcessId is int pid and > 0 && window.ProcessId != pid)
            return false;
        if (!string.IsNullOrWhiteSpace(target.TitleContains) &&
            window.Title.IndexOf(target.TitleContains, StringComparison.OrdinalIgnoreCase) < 0)
            return false;
        if (!string.IsNullOrWhiteSpace(target.ClassName) &&
            !string.Equals(window.ClassName, target.ClassName, StringComparison.OrdinalIgnoreCase))
            return false;
        return !string.IsNullOrWhiteSpace(target.ProcessName)
               || !string.IsNullOrWhiteSpace(target.TitleContains)
               || !string.IsNullOrWhiteSpace(target.ClassName)
               || target.ProcessId is > 0;
    }

    public static bool Activate(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd))
            return false;

        if (IsIconic(hwnd))
            ShowWindow(hwnd, SwRestore);
        else
            ShowWindow(hwnd, SwShow);

        var foreground = GetForegroundWindow();
        uint thisThread = GetCurrentThreadId();
        uint foreThread = GetWindowThreadProcessId(foreground, out _);
        if (foreThread != thisThread)
            AttachThreadInput(thisThread, foreThread, true);

        BringWindowToTop(hwnd);
        bool ok = SetForegroundWindow(hwnd);

        if (foreThread != thisThread)
            AttachThreadInput(thisThread, foreThread, false);

        return ok;
    }

    public static (int X, int Y) ToScreen(IntPtr hwnd, int clientX, int clientY)
    {
        var pt = new Point { X = clientX, Y = clientY };
        ClientToScreen(hwnd, ref pt);
        return (pt.X, pt.Y);
    }

    public static (int X, int Y) ToClient(IntPtr hwnd, int screenX, int screenY)
    {
        var pt = new Point { X = screenX, Y = screenY };
        ScreenToClient(hwnd, ref pt);
        return (pt.X, pt.Y);
    }

    public static (int X, int Y) CurrentCursor()
    {
        GetCursorPos(out var pt);
        return (pt.X, pt.Y);
    }

    private static string StripExe(string name) =>
        name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? name[..^4] : name;
}
