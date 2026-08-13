# MacroRelay

Lightweight Windows app to record, edit, and play multiple macros at once. Target a specific window, use window-relative mouse coordinates, and keep working while a macro runs.

Windows 10/11 x64.

## Install

1. Open the [Releases](https://github.com/MajdIssaDev/MacroRelay/releases) page.
2. Download **`MacroRelay-win-Setup.exe`** and run it.
3. Or download the portable zip if you do not want an installer.

You can also clone this repository and build from source (see below).

The first launch of an unsigned build may show a SmartScreen warning. That is expected until the installer is code-signed.

## Features

- Multiple macros, including several running at the same time (input is queued so keys do not scramble)
- Record real keyboard/mouse input, with or without delays
- Add steps from a searchable palette (`Ctrl+K`) or a right-click category menu
- Keyboard, mouse, wait, type text, paste text
- Loop forever, repeat N times, or stop after a time limit
- Loop interval, playback speed, and optional timing jitter
- Per-macro hotkeys plus global Start / Pause / Stop / Panic / Record
- Window targeting by process name, title, class, and PID (picker included)
- Mouse X,Y relative to the target window’s client area
- Playback modes: foreground, focus-target then send, or background window messages
- Import / export JSON
- Optional Run as Administrator
- System tray, start with Windows, dark/light/system theme
- Auto-update on launch and **Check for updates** in Settings

## Window targeting (honest limits)

Macros resolve a **window handle** from process name + title/class/PID. Parent process ID (PPID) is not used; launchers often are not the window you want.

| Mode | What it does | Typical result |
| --- | --- | --- |
| Foreground | `SendInput` to whatever is focused | Same idea as a simple AutoHotkey script |
| Focus target | Activates the chosen window, then `SendInput` | Most reliable for apps and many games |
| Background messages | `PostMessage` to that HWND without stealing focus | Some Win32 apps. **Not most games** (DirectInput / Raw Input / anti-cheat) |

There is no kernel driver and no anti-cheat bypass. Game overlays that block background input will not receive it.

## Usage

1. Add a macro and give it a name.
2. Record input, or right-click the step list → category, or press `Ctrl+K` to search.
3. Set loop interval (the old 50 ms auto-presser lives here), speed, and jitter.
4. Optionally pick a target window and choose a playback mode.
5. Press **Start** (or the macro hotkey / **F6** for start-all by default).

Default global shortcuts (change in Settings):

- `F6` start all enabled macros
- `F7` pause all
- `F8` stop all
- `Ctrl+Shift+Escape` panic (stop everything and release held keys)
- `F9` record into the selected macro

## Build from source

Requirements: [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) on Windows.

```powershell
dotnet build MacroRelay.sln -c Release
dotnet run --project src/MacroRelay.App/MacroRelay.App.csproj -c Release
```

Create an installer (Velopack):

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

Output is under `artifacts\`.

## Auto-update

Installed copies check GitHub Releases on startup (can be turned off) and from **Settings → Check for updates**. After you install with `Setup.exe`, later tags published by the release workflow become updates.

Set **GitHub owner** in Settings to match the repository owner if the app did not detect it.

## Data

Macros and settings are stored in `%APPDATA%\MacroRelay\`.

## License

MIT
