using MacroRelay.Core.Native;

namespace MacroRelay.Core.Input;

public readonly record struct ParsedHotkey(uint Modifiers, ushort VirtualKey, string Display)
{
    public static bool TryParse(string? text, out ParsedHotkey hotkey)
    {
        hotkey = default;
        if (string.IsNullOrWhiteSpace(text))
            return false;

        var parts = text.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0)
            return false;

        uint mods = NativeMethods.ModNorepeat;
        string keyName = parts[^1];
        for (int i = 0; i < parts.Length - 1; i++)
        {
            switch (parts[i].ToLowerInvariant())
            {
                case "ctrl":
                case "control":
                    mods |= NativeMethods.ModControl;
                    break;
                case "shift":
                    mods |= NativeMethods.ModShift;
                    break;
                case "alt":
                    mods |= NativeMethods.ModAlt;
                    break;
                case "win":
                case "windows":
                    mods |= NativeMethods.ModWin;
                    break;
                default:
                    return false;
            }
        }

        if (!KeyCatalog.TryGetVk(keyName, out var vk))
            return false;

        hotkey = new ParsedHotkey(mods, vk, Format(mods, keyName));
        return true;
    }

    private static string Format(uint mods, string key)
    {
        var bits = new List<string>();
        if ((mods & NativeMethods.ModControl) != 0) bits.Add("Ctrl");
        if ((mods & NativeMethods.ModShift) != 0) bits.Add("Shift");
        if ((mods & NativeMethods.ModAlt) != 0) bits.Add("Alt");
        if ((mods & NativeMethods.ModWin) != 0) bits.Add("Win");
        bits.Add(key);
        return string.Join("+", bits);
    }
}
