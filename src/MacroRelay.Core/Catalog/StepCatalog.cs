using MacroRelay.Core.Input;
using MacroRelay.Core.Models;

namespace MacroRelay.Core.Catalog;

public sealed class StepTemplate
{
    public required string Id { get; init; }
    public required string Category { get; init; }
    public required string Name { get; init; }
    public required string SearchText { get; init; }
    public required Func<MacroStep> Create { get; init; }
}

public static class StepCatalog
{
    public static IReadOnlyList<StepTemplate> All { get; } = Build();

    public static IEnumerable<StepTemplate> Search(string? query)
    {
        if (string.IsNullOrWhiteSpace(query))
            return All;
        var q = query.Trim();
        return All.Where(t =>
            t.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
            t.Category.Contains(q, StringComparison.OrdinalIgnoreCase) ||
            t.SearchText.Contains(q, StringComparison.OrdinalIgnoreCase) ||
            t.Id.Contains(q, StringComparison.OrdinalIgnoreCase));
    }

    public static string Describe(MacroStep step)
    {
        if (!step.Enabled)
            return "(disabled) " + DescribeEnabled(step);
        return DescribeEnabled(step);
    }

    private static string DescribeEnabled(MacroStep step) => step.Type switch
    {
        StepType.Delay => $"Wait {step.DelayMs} ms",
        StepType.ActivateWindow => "Activate target window",
        StepType.Text => step.TextMethod == TextMethod.Paste
            ? $"Paste \"{Truncate(step.Text)}\""
            : $"Type \"{Truncate(step.Text)}\"",
        StepType.Key => $"{step.KeyStroke} {FormatMods(step.Modifiers)}{step.Key}",
        StepType.Mouse => DescribeMouse(step),
        _ => step.Type.ToString()
    };

    private static string DescribeMouse(MacroStep step)
    {
        string pos = step.X is null ? "" : $" at ({step.X},{step.Y}) {step.CoordinateMode}";
        return step.MouseStroke switch
        {
            MouseStroke.Move => $"Move mouse{pos}",
            MouseStroke.Wheel => $"Wheel {step.WheelDelta}{pos}",
            _ => $"{step.MouseButton} {step.MouseStroke}{pos}"
        };
    }

    private static string FormatMods(List<string> mods) =>
        mods.Count == 0 ? "" : string.Join("+", mods) + "+";

    private static string Truncate(string? text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        return text.Length <= 32 ? text : text[..32] + "…";
    }

    private static List<StepTemplate> Build()
    {
        var list = new List<StepTemplate>();
        foreach (var key in KeyCatalog.CommonKeys)
        {
            var k = key;
            list.Add(new StepTemplate
            {
                Id = $"key.tap.{k}",
                Category = "Keyboard",
                Name = $"Tap {k}",
                SearchText = $"key keyboard press {k} ascii",
                Create = () => new MacroStep { Type = StepType.Key, Key = k, KeyStroke = KeyStroke.Tap }
            });
        }
        list.Add(new StepTemplate
        {
            Id = "key.down",
            Category = "Keyboard",
            Name = "Key down…",
            SearchText = "hold key down",
            Create = () => new MacroStep { Type = StepType.Key, Key = "A", KeyStroke = KeyStroke.Down }
        });
        list.Add(new StepTemplate
        {
            Id = "key.up",
            Category = "Keyboard",
            Name = "Key up…",
            SearchText = "release key up",
            Create = () => new MacroStep { Type = StepType.Key, Key = "A", KeyStroke = KeyStroke.Up }
        });

        foreach (var button in Enum.GetValues<MouseButtonKind>())
        {
            var b = button;
            list.Add(new StepTemplate
            {
                Id = $"mouse.click.{b}",
                Category = "Mouse",
                Name = $"{b} click",
                SearchText = $"mouse {b} button click",
                Create = () => new MacroStep
                {
                    Type = StepType.Mouse,
                    MouseButton = b,
                    MouseStroke = MouseStroke.Click,
                    X = 0,
                    Y = 0,
                    CoordinateMode = CoordinateMode.WindowClient
                }
            });
        }
        list.Add(new StepTemplate
        {
            Id = "mouse.move",
            Category = "Mouse",
            Name = "Move mouse",
            SearchText = "cursor position xy",
            Create = () => new MacroStep { Type = StepType.Mouse, MouseStroke = MouseStroke.Move, X = 0, Y = 0, CoordinateMode = CoordinateMode.WindowClient }
        });
        list.Add(new StepTemplate
        {
            Id = "mouse.wheelup",
            Category = "Mouse",
            Name = "Wheel up",
            SearchText = "scroll up",
            Create = () => new MacroStep { Type = StepType.Mouse, MouseStroke = MouseStroke.Wheel, WheelDelta = 120, X = 0, Y = 0 }
        });
        list.Add(new StepTemplate
        {
            Id = "mouse.wheeldown",
            Category = "Mouse",
            Name = "Wheel down",
            SearchText = "scroll down",
            Create = () => new MacroStep { Type = StepType.Mouse, MouseStroke = MouseStroke.Wheel, WheelDelta = -120, X = 0, Y = 0 }
        });

        foreach (var ms in new[] { 10, 50, 100, 250, 500, 1000 })
        {
            var d = ms;
            list.Add(new StepTemplate
            {
                Id = $"delay.{d}",
                Category = "Delay",
                Name = $"Wait {d} ms",
                SearchText = $"sleep delay wait {d} milliseconds",
                Create = () => new MacroStep { Type = StepType.Delay, DelayMs = d }
            });
        }
        list.Add(new StepTemplate
        {
            Id = "delay.custom",
            Category = "Delay",
            Name = "Custom wait…",
            SearchText = "delay milliseconds custom",
            Create = () => new MacroStep { Type = StepType.Delay, DelayMs = 200 }
        });

        list.Add(new StepTemplate
        {
            Id = "text.type",
            Category = "Text",
            Name = "Type text",
            SearchText = "keyboard string ascii type",
            Create = () => new MacroStep { Type = StepType.Text, TextMethod = TextMethod.Type, Text = "" }
        });
        list.Add(new StepTemplate
        {
            Id = "text.paste",
            Category = "Text",
            Name = "Paste text",
            SearchText = "clipboard paste string",
            Create = () => new MacroStep { Type = StepType.Text, TextMethod = TextMethod.Paste, Text = "" }
        });
        list.Add(new StepTemplate
        {
            Id = "window.activate",
            Category = "Window",
            Name = "Activate target window",
            SearchText = "focus bring foreground hwnd",
            Create = () => new MacroStep { Type = StepType.ActivateWindow }
        });
        return list;
    }
}
