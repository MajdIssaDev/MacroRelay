# MacroRelay

Lightweight Windows macro recorder and player. Flutter desktop UI over a C++ engine that uses low-level hooks and `SendInput`.

Windows 10/11 x64.

## Install

1. Open [Releases](https://github.com/MajdIssaDev/MacroRelay/releases).
2. Download **MacroRelay-win-Setup.exe** (or the portable zip).
3. Unsigned builds may show SmartScreen — **More info → Run anyway**.

From source:

```powershell
cd app
flutter pub get
flutter run -d windows
```

## Recording (no path bloat)

The native hook **ignores `WM_MOUSEMOVE` and wheel data**. It only stores:

- keyboard key down / up
- mouse button down / up (left, right, middle, X1, X2)

Clicks do **not** record a travel path. If you need a click at a point, right-click the sequence and insert **Mouse click at X,Y** (client coordinates relative to the target window).

Optional **Keep delays** stores waits between those state changes only.

## Playback and window targeting

| Mode | Behavior |
| --- | --- |
| Foreground | `SendInput` goes to whatever is focused |
| Focus target | Activates the chosen process/title, then `SendInput` |

Mouse X,Y with a target window are **client-relative** (`ClientToScreen` at play time).

### What this will not do

Modern games (GTA V and similar) often read **DirectInput / Raw Input** and ignore posted Windows messages. Sending input while you use another app, without focusing the game, requires either **injecting a DLL into the game** or a **kernel/virtual HID driver**. MacroRelay does **not** implement those:

- injecting into other processes is a cheat/malware technique
- filter drivers that spoof hardware to a specific PID are out of scope

Use **Focus target** and keep the game in the foreground for titles like that.

The C++ library lives in `native/` and is loaded by Flutter via FFI (`macro_relay_native.dll`).

## UI

Dark “ops” dashboard:

- multiple macros in the sidebar
- repeat: infinite / count / time limit
- speed multiplier dropdown
- humanized jitter toggle
- right-click (or Ctrl+K) to insert text, keys, or clicks at X,Y
- Start / Pause / Stop / Record
- **Check for updates** (downloads and installs the latest GitHub Release automatically)

## Layout

```
app/        Flutter Windows frontend (FFI)
native/     C++ engine (hooks + SendInput)
src/        Legacy WPF app (same recording filter applied)
```

## Auto-update

Installed copies (Setup.exe / Velopack) check GitHub Releases on launch. If a newer version exists, MacroRelay downloads the package and applies it with `Update.exe`, then restarts. **Check for updates** in the status bar does the same check on demand. Debug / unpackaged builds skip silent install; the button still downloads Setup.exe and runs it.

## Build installer

```powershell
flutter build windows --release
# output: app\build\windows\x64\runner\Release\MacroRelay.exe
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

## License

MIT
