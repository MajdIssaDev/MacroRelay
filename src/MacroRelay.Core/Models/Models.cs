namespace MacroRelay.Core.Models;

public sealed class WindowTarget
{
    public PlaybackMode Mode { get; set; } = PlaybackMode.Foreground;
    public string? ProcessName { get; set; }
    public string? TitleContains { get; set; }
    public string? ClassName { get; set; }
    public int? ProcessId { get; set; }
}

public sealed class MacroStep
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public StepType Type { get; set; }
    public bool Enabled { get; set; } = true;

    public KeyStroke KeyStroke { get; set; } = KeyStroke.Tap;
    public string? Key { get; set; }
    public List<string> Modifiers { get; set; } = [];

    public MouseButtonKind MouseButton { get; set; } = MouseButtonKind.Left;
    public MouseStroke MouseStroke { get; set; } = MouseStroke.Click;
    public int? X { get; set; }
    public int? Y { get; set; }
    public CoordinateMode CoordinateMode { get; set; } = CoordinateMode.WindowClient;
    public int WheelDelta { get; set; }

    public int DelayMs { get; set; }

    public string? Text { get; set; }
    public TextMethod TextMethod { get; set; } = TextMethod.Type;
}

public sealed class MacroDefinition
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "New macro";
    public bool Enabled { get; set; } = true;
    public string? Hotkey { get; set; }
    public LoopMode LoopMode { get; set; } = LoopMode.Infinite;
    public int RepeatCount { get; set; } = 1;
    public int DurationMs { get; set; } = 10_000;
    public bool TimeLimitEnabled { get; set; }
    public int IntervalMs { get; set; } = 50;
    public double Speed { get; set; } = 1.0;
    public int JitterPercent { get; set; }
    public WindowTarget Target { get; set; } = new();
    public List<MacroStep> Steps { get; set; } = [];
}

public sealed class MacroLibrary
{
    public int Version { get; set; } = 1;
    public List<MacroDefinition> Macros { get; set; } = [];
}

public sealed class AppSettings
{
    public string Theme { get; set; } = "Dark";
    public bool CloseToTray { get; set; } = true;
    public bool StartMinimized { get; set; }
    public bool StartWithWindows { get; set; }
    public bool CheckUpdatesOnLaunch { get; set; } = true;
    public int DefaultIntervalMs { get; set; } = 50;
    public double DefaultSpeed { get; set; } = 1.0;
    public int DefaultJitterPercent { get; set; }
    public string HotkeyStartAll { get; set; } = "F6";
    public string HotkeyPauseAll { get; set; } = "F7";
    public string HotkeyStopAll { get; set; } = "F8";
    public string HotkeyPanic { get; set; } = "Ctrl+Shift+Escape";
    public string HotkeyRecord { get; set; } = "F9";
    public string GitHubOwner { get; set; } = "MajdIssaDev";
    public string GitHubRepo { get; set; } = "MacroRelay";
}
