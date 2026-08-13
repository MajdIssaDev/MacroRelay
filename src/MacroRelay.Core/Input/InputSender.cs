using MacroRelay.Core.Models;
using MacroRelay.Core.Native;
using static MacroRelay.Core.Native.NativeMethods;

namespace MacroRelay.Core.Input;

public sealed class StuckKeys
{
    private readonly HashSet<ushort> _keys = [];
    private readonly HashSet<MouseButtonKind> _buttons = [];
    private readonly object _gate = new();

    public void KeyDown(ushort vk)
    {
        lock (_gate) _keys.Add(vk);
    }

    public void KeyUp(ushort vk)
    {
        lock (_gate) _keys.Remove(vk);
    }

    public void ButtonDown(MouseButtonKind button)
    {
        lock (_gate) _buttons.Add(button);
    }

    public void ButtonUp(MouseButtonKind button)
    {
        lock (_gate) _buttons.Remove(button);
    }

    public void ReleaseAll()
    {
        ushort[] keys;
        MouseButtonKind[] buttons;
        lock (_gate)
        {
            keys = [.. _keys];
            buttons = [.. _buttons];
            _keys.Clear();
            _buttons.Clear();
        }

        foreach (var vk in keys)
            InputSender.SendKey(vk, keyUp: true);
        foreach (var button in buttons)
            InputSender.SendMouseButton(button, down: false);
    }
}

public static class InputSender
{
    public static void SendKey(ushort vk, bool keyUp)
    {
        var scan = (ushort)MapVirtualKey(vk, MapvkVkToVsc);
        uint flags = keyUp ? KeyeventfKeyup : 0;
        if (KeyCatalog.IsExtended(vk))
            flags |= KeyeventfExtendedkey;

        var input = new InputPacket
        {
            Type = InputKeyboard,
            Data = new InputUnion
            {
                Keyboard = new KeyboardInput
                {
                    Vk = vk,
                    Scan = scan,
                    Flags = flags,
                    ExtraInfo = GetMessageExtraInfo()
                }
            }
        };
        SendInput(1, [input], System.Runtime.InteropServices.Marshal.SizeOf<InputPacket>());
    }

    public static void SendUnicodeChar(char ch, bool keyUp)
    {
        var input = new InputPacket
        {
            Type = InputKeyboard,
            Data = new InputUnion
            {
                Keyboard = new KeyboardInput
                {
                    Vk = 0,
                    Scan = ch,
                    Flags = KeyeventfUnicode | (keyUp ? KeyeventfKeyup : 0),
                    ExtraInfo = GetMessageExtraInfo()
                }
            }
        };
        SendInput(1, [input], System.Runtime.InteropServices.Marshal.SizeOf<InputPacket>());
    }

    public static void SendMouseButton(MouseButtonKind button, bool down, uint xButton = 0)
    {
        uint flags = button switch
        {
            MouseButtonKind.Left => down ? MouseeventfLeftdown : MouseeventfLeftup,
            MouseButtonKind.Right => down ? MouseeventfRightdown : MouseeventfRightup,
            MouseButtonKind.Middle => down ? MouseeventfMiddledown : MouseeventfMiddleup,
            MouseButtonKind.X1 or MouseButtonKind.X2 => down ? MouseeventfXdown : MouseeventfXup,
            _ => 0
        };
        uint data = button switch
        {
            MouseButtonKind.X1 => Xbutton1,
            MouseButtonKind.X2 => Xbutton2,
            _ => xButton
        };
        var input = new InputPacket
        {
            Type = InputMouse,
            Data = new InputUnion
            {
                Mouse = new MouseInput
                {
                    Flags = flags,
                    MouseData = data,
                    ExtraInfo = GetMessageExtraInfo()
                }
            }
        };
        SendInput(1, [input], System.Runtime.InteropServices.Marshal.SizeOf<InputPacket>());
    }

    public static void MoveMouseAbsolute(int screenX, int screenY)
    {
        int vx = (int)Math.Round(screenX * 65535.0 / Math.Max(GetSystemMetrics(0) - 1, 1));
        int vy = (int)Math.Round(screenY * 65535.0 / Math.Max(GetSystemMetrics(1) - 1, 1));
        var input = new InputPacket
        {
            Type = InputMouse,
            Data = new InputUnion
            {
                Mouse = new MouseInput
                {
                    Dx = vx,
                    Dy = vy,
                    Flags = MouseeventfMove | MouseeventfAbsolute | MouseeventfVirtualdesk,
                    ExtraInfo = GetMessageExtraInfo()
                }
            }
        };
        SendInput(1, [input], System.Runtime.InteropServices.Marshal.SizeOf<InputPacket>());
    }

    public static void Scroll(int delta)
    {
        var input = new InputPacket
        {
            Type = InputMouse,
            Data = new InputUnion
            {
                Mouse = new MouseInput
                {
                    MouseData = unchecked((uint)delta),
                    Flags = MouseeventfWheel,
                    ExtraInfo = GetMessageExtraInfo()
                }
            }
        };
        SendInput(1, [input], System.Runtime.InteropServices.Marshal.SizeOf<InputPacket>());
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern int GetSystemMetrics(int nIndex);
}

public static class BackgroundMessenger
{
    public static void SendKey(IntPtr hwnd, ushort vk, bool keyUp)
    {
        var msg = keyUp ? (uint)WmKeyup : (uint)WmKeydown;
        var scan = MapVirtualKey(vk, MapvkVkToVsc);
        uint lParam = 1u | (scan << 16);
        if (keyUp)
            lParam |= 1u << 30 | 1u << 31;
        if (KeyCatalog.IsExtended(vk))
            lParam |= 1u << 24;
        PostMessage(hwnd, msg, (IntPtr)vk, (IntPtr)lParam);
    }

    public static void SendChar(IntPtr hwnd, char ch) =>
        PostMessage(hwnd, WmChar, (IntPtr)ch, IntPtr.Zero);

    public static void SendMouse(IntPtr hwnd, MouseButtonKind button, bool down, int clientX, int clientY)
    {
        uint msg = (button, down) switch
        {
            (MouseButtonKind.Left, true) => WmLbuttondown,
            (MouseButtonKind.Left, false) => WmLbuttonup,
            (MouseButtonKind.Right, true) => WmRbuttondown,
            (MouseButtonKind.Right, false) => WmRbuttonup,
            (MouseButtonKind.Middle, true) => WmMbuttondown,
            (MouseButtonKind.Middle, false) => WmMbuttonup,
            (MouseButtonKind.X1 or MouseButtonKind.X2, true) => WmXbuttondown,
            (MouseButtonKind.X1 or MouseButtonKind.X2, false) => WmXbuttonup,
            _ => WmLbuttondown
        };
        IntPtr wParam = button switch
        {
            MouseButtonKind.X1 => (IntPtr)(Xbutton1 << 16),
            MouseButtonKind.X2 => (IntPtr)(Xbutton2 << 16),
            _ => IntPtr.Zero
        };
        PostMessage(hwnd, msg, wParam, MakeLParam(clientX, clientY));
    }

    public static void SendMove(IntPtr hwnd, int clientX, int clientY) =>
        PostMessage(hwnd, WmMousemove, IntPtr.Zero, MakeLParam(clientX, clientY));

    public static void SendWheel(IntPtr hwnd, int delta, int clientX, int clientY) =>
        PostMessage(hwnd, WmMousewheel, (IntPtr)(delta << 16), MakeLParam(clientX, clientY));
}
