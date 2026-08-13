namespace MacroRelay.Core.Input;

public static class KeyCatalog
{
    public static readonly IReadOnlyDictionary<string, ushort> VirtualKeys = CreateMap();

    public static readonly IReadOnlyList<string> CommonKeys =
    [
        "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
        "0","1","2","3","4","5","6","7","8","9",
        "F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12",
        "Enter","Space","Tab","Escape","Backspace","Delete","Insert","Home","End","PageUp","PageDown",
        "Up","Down","Left","Right",
        "LeftShift","RightShift","LeftCtrl","RightCtrl","LeftAlt","RightAlt","LWin","RWin",
        "CapsLock","NumLock","ScrollLock",
        "Numpad0","Numpad1","Numpad2","Numpad3","Numpad4","Numpad5","Numpad6","Numpad7","Numpad8","Numpad9",
        "NumpadAdd","NumpadSubtract","NumpadMultiply","NumpadDivide","NumpadDecimal","NumpadEnter",
        "OemMinus","OemPlus","OemOpenBrackets","OemCloseBrackets","OemSemicolon","OemQuotes","OemComma","OemPeriod","OemQuestion","OemPipe","OemTilde"
    ];

    public static readonly HashSet<ushort> ExtendedKeys =
    [
        0x21, 0x22, 0x23, 0x24, 0x2D, 0x2E, // page/home/end/ins/del
        0x25, 0x26, 0x27, 0x28,             // arrows
        0xA3, 0xA5, 0x5C,                   // RCtrl RAlt RWin
        0x6F, 0x0D                          // divide, enter (enter only when numpad flagged separately)
    ];

    public static bool TryGetVk(string name, out ushort vk) => VirtualKeys.TryGetValue(name, out vk);

    public static string? NameFromVk(uint vk)
    {
        foreach (var pair in VirtualKeys)
        {
            if (pair.Value == vk)
                return pair.Key;
        }

        return vk is >= 0x30 and <= 0x39 or >= 0x41 and <= 0x5A
            ? ((char)vk).ToString()
            : $"VK_{vk:X2}";
    }

    public static bool IsExtended(ushort vk) =>
        vk is 0x21 or 0x22 or 0x23 or 0x24 or 0x25 or 0x26 or 0x27 or 0x28
            or 0x2D or 0x2E or 0xA3 or 0xA5 or 0x5B or 0x5C or 0x6F;

    private static Dictionary<string, ushort> CreateMap()
    {
        var map = new Dictionary<string, ushort>(StringComparer.OrdinalIgnoreCase);

        for (char c = 'A'; c <= 'Z'; c++)
            map[c.ToString()] = c;
        for (char c = '0'; c <= '9'; c++)
            map[c.ToString()] = c;

        for (ushort i = 1; i <= 12; i++)
            map[$"F{i}"] = (ushort)(0x70 + i - 1);

        map["Enter"] = 0x0D;
        map["Space"] = 0x20;
        map["Tab"] = 0x09;
        map["Escape"] = 0x1B;
        map["Esc"] = 0x1B;
        map["Backspace"] = 0x08;
        map["Delete"] = 0x2E;
        map["Insert"] = 0x2D;
        map["Home"] = 0x24;
        map["End"] = 0x23;
        map["PageUp"] = 0x21;
        map["PageDown"] = 0x22;
        map["Up"] = 0x26;
        map["Down"] = 0x28;
        map["Left"] = 0x25;
        map["Right"] = 0x27;
        map["LeftShift"] = 0xA0;
        map["RightShift"] = 0xA1;
        map["Shift"] = 0x10;
        map["LeftCtrl"] = 0xA2;
        map["RightCtrl"] = 0xA3;
        map["Ctrl"] = 0x11;
        map["LeftAlt"] = 0xA4;
        map["RightAlt"] = 0xA5;
        map["Alt"] = 0x12;
        map["LWin"] = 0x5B;
        map["RWin"] = 0x5C;
        map["CapsLock"] = 0x14;
        map["NumLock"] = 0x90;
        map["ScrollLock"] = 0x91;
        map["Numpad0"] = 0x60;
        map["Numpad1"] = 0x61;
        map["Numpad2"] = 0x62;
        map["Numpad3"] = 0x63;
        map["Numpad4"] = 0x64;
        map["Numpad5"] = 0x65;
        map["Numpad6"] = 0x66;
        map["Numpad7"] = 0x67;
        map["Numpad8"] = 0x68;
        map["Numpad9"] = 0x69;
        map["NumpadMultiply"] = 0x6A;
        map["NumpadAdd"] = 0x6B;
        map["NumpadSubtract"] = 0x6D;
        map["NumpadDecimal"] = 0x6E;
        map["NumpadDivide"] = 0x6F;
        map["NumpadEnter"] = 0x0D;
        map["OemMinus"] = 0xBD;
        map["OemPlus"] = 0xBB;
        map["OemOpenBrackets"] = 0xDB;
        map["OemCloseBrackets"] = 0xDD;
        map["OemSemicolon"] = 0xBA;
        map["OemQuotes"] = 0xDE;
        map["OemComma"] = 0xBC;
        map["OemPeriod"] = 0xBE;
        map["OemQuestion"] = 0xBF;
        map["OemPipe"] = 0xDC;
        map["OemTilde"] = 0xC0;
        return map;
    }
}
