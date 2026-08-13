namespace MacroRelay.Core.Models;

public enum LoopMode
{
    Infinite,
    Count,
    Duration
}

public enum PlaybackMode
{
    Foreground,
    FocusTarget,
    BackgroundMessages
}

public enum CoordinateMode
{
    Screen,
    WindowClient
}

public enum StepType
{
    Key,
    Mouse,
    Delay,
    Text,
    ActivateWindow
}

public enum KeyStroke
{
    Tap,
    Down,
    Up
}

public enum MouseButtonKind
{
    Left,
    Right,
    Middle,
    X1,
    X2
}

public enum MouseStroke
{
    Click,
    Down,
    Up,
    Move,
    Wheel
}

public enum TextMethod
{
    Type,
    Paste
}

public enum PlaybackState
{
    Stopped,
    Running,
    Paused
}
