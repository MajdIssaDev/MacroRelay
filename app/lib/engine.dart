import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class MrEvent extends Struct {
  @Int32()
  external int kind;
  @Int32()
  external int code;
  @Int32()
  external int down;
  @Int32()
  external int delayMs;
  @Int32()
  external int x;
  @Int32()
  external int y;
  @Int32()
  external int hasPos;
}

typedef _RecordStartC = Int32 Function(Int32);
typedef _RecordStartD = int Function(int);
typedef _VoidC = Void Function();
typedef _VoidD = void Function();
typedef _PollC = Int32 Function(Pointer<MrEvent>, Int32);
typedef _PollD = int Function(Pointer<MrEvent>, int);
typedef _CreateC = Int32 Function();
typedef _CreateD = int Function();
typedef _IdC = Void Function(Int32);
typedef _IdD = void Function(int);
typedef _OptionsC = Void Function(
    Int32, Int32, Double, Int32, Int32, Int32, Int32, Int32);
typedef _OptionsD = void Function(
    int, int, double, int, int, int, int, int);
typedef _TargetC = Void Function(Int32, Pointer<Utf8>, Pointer<Utf8>);
typedef _TargetD = void Function(int, Pointer<Utf8>, Pointer<Utf8>);
typedef _AddKeyC = Void Function(Int32, Int32, Int32);
typedef _AddKeyD = void Function(int, int, int);
typedef _AddMouseC = Void Function(Int32, Int32, Int32, Int32, Int32, Int32);
typedef _AddMouseD = void Function(int, int, int, int, int, int);
typedef _AddDelayC = Void Function(Int32, Int32);
typedef _AddDelayD = void Function(int, int);
typedef _AddTextC = Void Function(Int32, Pointer<Utf8>);
typedef _AddTextD = void Function(int, Pointer<Utf8>);
typedef _AddWheelC = Void Function(Int32, Int32, Int32, Int32, Int32);
typedef _AddWheelD = void Function(int, int, int, int, int);
typedef _AddDragC = Void Function(Int32, Int32, Int32, Int32, Int32, Int32);
typedef _AddDragD = void Function(int, int, int, int, int, int);
typedef _StartC = Int32 Function(Int32);
typedef _StartD = int Function(int);
typedef _StateC = Int32 Function(Int32);
typedef _StateD = int Function(int);
typedef _CountC = Int32 Function();
typedef _CountD = int Function();
typedef _WindowC = Int32 Function(
    Pointer<Utf8>, Int32, Pointer<Utf8>, Int32, Pointer<Int32>);
typedef _WindowD = int Function(
    Pointer<Utf8>, int, Pointer<Utf8>, int, Pointer<Int32>);
typedef _CursorC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Int32>, Pointer<Int32>);
typedef _CursorD = int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Int32>, Pointer<Int32>);
typedef _FlagC = Int32 Function();
typedef _FlagD = int Function();
typedef _HotkeyC = Int32 Function(Pointer<Int32>, Pointer<Int32>);
typedef _HotkeyD = int Function(Pointer<Int32>, Pointer<Int32>);
typedef _HotkeySetC = Void Function(Int32, Int32, Int32, Int32);
typedef _HotkeySetD = void Function(int, int, int, int);
typedef _KeyDownC = Int32 Function(Int32);
typedef _KeyDownD = int Function(int);
typedef _BeepC = Void Function(Int32);
typedef _BeepD = void Function(int);
typedef _PickFileC = Int32 Function(Int32, Pointer<Utf8>, Int32);
typedef _PickFileD = int Function(int, Pointer<Utf8>, int);
typedef _EnableC = Int32 Function(Int32);
typedef _EnableD = int Function(int);
typedef _SetFlagC = Void Function(Int32);
typedef _SetFlagD = void Function(int);
typedef _WinCmdC = Int32 Function(Int32);
typedef _WinCmdD = int Function(int);

class RecordedNative {
  RecordedNative(this.kind, this.code, this.down, this.delayMs);
  final int kind;
  final int code;
  final int down;
  final int delayMs;
}

class NativeEngine {
  NativeEngine._(DynamicLibrary lib)
      : _recordStart = lib.lookupFunction<_RecordStartC, _RecordStartD>('mr_record_start'),
        _recordStop = lib.lookupFunction<_VoidC, _VoidD>('mr_record_stop'),
        _poll = lib.lookupFunction<_PollC, _PollD>('mr_record_poll'),
        _create = lib.lookupFunction<_CreateC, _CreateD>('mr_session_create'),
        _destroy = lib.lookupFunction<_IdC, _IdD>('mr_session_destroy'),
        _clear = lib.lookupFunction<_IdC, _IdD>('mr_session_clear_steps'),
        _options = lib.lookupFunction<_OptionsC, _OptionsD>('mr_session_set_options'),
        _target = lib.lookupFunction<_TargetC, _TargetD>('mr_session_set_target'),
        _addKey = lib.lookupFunction<_AddKeyC, _AddKeyD>('mr_session_add_key'),
        _addMouse = lib.lookupFunction<_AddMouseC, _AddMouseD>('mr_session_add_mouse'),
        _addDelay = lib.lookupFunction<_AddDelayC, _AddDelayD>('mr_session_add_delay'),
        _addText = lib.lookupFunction<_AddTextC, _AddTextD>('mr_session_add_text'),
        _addWheel = lib.lookupFunction<_AddWheelC, _AddWheelD>('mr_session_add_wheel'),
        _addDrag = lib.lookupFunction<_AddDragC, _AddDragD>('mr_session_add_drag'),
        _start = lib.lookupFunction<_StartC, _StartD>('mr_session_start'),
        _pause = lib.lookupFunction<_IdC, _IdD>('mr_session_pause'),
        _stop = lib.lookupFunction<_IdC, _IdD>('mr_session_stop'),
        _stopAll = lib.lookupFunction<_VoidC, _VoidD>('mr_stop_all'),
        _state = lib.lookupFunction<_StateC, _StateD>('mr_session_state'),
        _running = lib.lookupFunction<_CountC, _CountD>('mr_running_count'),
        _window = lib.lookupFunction<_WindowC, _WindowD>('mr_window_at_cursor'),
        _cursor = lib.lookupFunction<_CursorC, _CursorD>('mr_cursor_client'),
        _ctrlShift = lib.lookupFunction<_FlagC, _FlagD>('mr_ctrl_shift_down'),
        _hotkeys = lib.lookupFunction<_HotkeyC, _HotkeyD>('mr_hotkey_poll'),
        _hotkeySet = lib.lookupFunction<_HotkeySetC, _HotkeySetD>('mr_hotkey_set'),
        _keyDown = lib.lookupFunction<_KeyDownC, _KeyDownD>('mr_key_down'),
        _anyKey = lib.lookupFunction<_FlagC, _FlagD>('mr_any_key_down'),
        _beep = lib.lookupFunction<_BeepC, _BeepD>('mr_beep'),
        _pickFile = lib.lookupFunction<_PickFileC, _PickFileD>('mr_pick_file'),
        _startupGet = lib.lookupFunction<_FlagC, _FlagD>('mr_startup_get'),
        _startupSet = lib.lookupFunction<_EnableC, _EnableD>('mr_startup_set'),
        _traySet = lib.lookupFunction<_EnableC, _EnableD>('mr_tray_set'),
        _closeToTray = lib.lookupFunction<_SetFlagC, _SetFlagD>('mr_close_to_tray'),
        _winCmd = lib.lookupFunction<_WinCmdC, _WinCmdD>('mr_window_command');

  final _RecordStartD _recordStart;
  final _VoidD _recordStop;
  final _PollD _poll;
  final _CreateD _create;
  final _IdD _destroy;
  final _IdD _clear;
  final _OptionsD _options;
  final _TargetD _target;
  final _AddKeyD _addKey;
  final _AddMouseD _addMouse;
  final _AddDelayD _addDelay;
  final _AddTextD _addText;
  final _AddWheelD _addWheel;
  final _AddDragD _addDrag;
  final _StartD _start;
  final _IdD _pause;
  final _IdD _stop;
  final _VoidD _stopAll;
  final _StateD _state;
  final _CountD _running;
  final _WindowD _window;
  final _CursorD _cursor;
  final _FlagD _ctrlShift;
  final _HotkeyD _hotkeys;
  final _HotkeySetD _hotkeySet;
  final _KeyDownD _keyDown;
  final _FlagD _anyKey;
  final _BeepD _beep;
  final _PickFileD _pickFile;
  final _FlagD _startupGet;
  final _EnableD _startupSet;
  final _EnableD _traySet;
  final _SetFlagD _closeToTray;
  final _WinCmdD _winCmd;

  static NativeEngine? tryLoad() {
    try {
      final lib = DynamicLibrary.open(
        Platform.isWindows ? 'macro_relay_native.dll' : 'libmacro_relay_native.so',
      );
      return NativeEngine._(lib);
    } catch (_) {
      return null;
    }
  }

  void recordStart({required bool keepDelays}) => _recordStart(keepDelays ? 1 : 0);
  void recordStop() => _recordStop();

  List<RecordedNative> pollRecorded({int max = 64}) {
    final buf = calloc<MrEvent>(max);
    final n = _poll(buf, max);
    final out = <RecordedNative>[];
    for (var i = 0; i < n; i++) {
      final e = buf[i];
      out.add(RecordedNative(e.kind, e.code, e.down, e.delayMs));
    }
    calloc.free(buf);
    return out;
  }

  int createSession() => _create();
  void destroy(int id) => _destroy(id);
  void clear(int id) => _clear(id);

  void setOptions({
    required int id,
    required int intervalMs,
    required double speed,
    required bool jitter,
    required int loopMode,
    required int repeatCount,
    required int durationMs,
    required bool focusTarget,
  }) {
    _options(id, intervalMs, speed, jitter ? 1 : 0, loopMode, repeatCount,
        durationMs, focusTarget ? 2 : 0);
  }

  void setTarget(int id, String process, String title) {
    final p = process.toNativeUtf8();
    final t = title.toNativeUtf8();
    _target(id, p, t);
    malloc.free(p);
    malloc.free(t);
  }

  void addKey(int id, int vk, bool down) => _addKey(id, vk, down ? 1 : 0);
  void addMouse(int id, int button, bool down, {int? x, int? y}) =>
      _addMouse(id, button, down ? 1 : 0, x ?? 0, y ?? 0, (x != null && y != null) ? 1 : 0);
  void addDelay(int id, int ms) => _addDelay(id, ms);
  void addText(int id, String text) {
    final p = text.toNativeUtf8();
    _addText(id, p);
    malloc.free(p);
  }

  void addWheel(int id, int delta, {int? x, int? y}) =>
      _addWheel(id, delta, x ?? 0, y ?? 0, (x != null && y != null) ? 1 : 0);

  void addDrag(int id, int button, int x1, int y1, int x2, int y2) =>
      _addDrag(id, button, x1, y1, x2, y2);

  int start(int id) => _start(id);
  void pause(int id) => _pause(id);
  void stop(int id) => _stop(id);
  void stopAll() => _stopAll();
  int state(int id) => _state(id);
  int runningCount() => _running();

  ({String process, String title, int pid})? windowAtCursor() {
    final proc = calloc<Uint8>(256).cast<Utf8>();
    final title = calloc<Uint8>(512).cast<Utf8>();
    final pid = calloc<Int32>();
    final ok = _window(proc, 256, title, 512, pid);
    final result = ok == 0
        ? null
        : (process: proc.toDartString(), title: title.toDartString(), pid: pid.value);
    calloc.free(proc);
    calloc.free(title);
    calloc.free(pid);
    return result;
  }

  ({int x, int y})? cursorClient({String process = '', String title = ''}) {
    final p = process.toNativeUtf8();
    final t = title.toNativeUtf8();
    final x = calloc<Int32>();
    final y = calloc<Int32>();
    final ok = _cursor(p, t, x, y);
    final result = ok == 0 ? null : (x: x.value, y: y.value);
    malloc.free(p);
    malloc.free(t);
    calloc.free(x);
    calloc.free(y);
    return result;
  }

  bool ctrlShiftDown() => _ctrlShift() != 0;

  ({bool play, bool record}) pollHotkeys() {
    final play = calloc<Int32>();
    final rec = calloc<Int32>();
    _hotkeys(play, rec);
    final result = (play: play.value != 0, record: rec.value != 0);
    calloc.free(play);
    calloc.free(rec);
    return result;
  }

  void hotkeySet({required int play, required int once, required int record, required int panic}) =>
      _hotkeySet(play, once, record, panic);

  bool keyDown(int vk) => vk > 0 && _keyDown(vk) != 0;

  int anyKeyDown() => _anyKey();

  int modifierBits() {
    var bits = 0;
    if (keyDown(0x11)) bits |= 1;
    if (keyDown(0x10)) bits |= 2;
    if (keyDown(0x12)) bits |= 4;
    return bits;
  }

  bool bindDown(int vk, int mods) {
    if (vk <= 0) return false;
    return keyDown(vk) && modifierBits() == mods;
  }

  void beep(int kind) => _beep(kind);

  String? pickFile({required bool save}) {
    final buf = calloc<Uint8>(1024).cast<Utf8>();
    final ok = _pickFile(save ? 1 : 0, buf, 1024);
    final path = ok == 0 ? null : buf.toDartString();
    calloc.free(buf);
    return path;
  }

  bool startupGet() => _startupGet() != 0;
  bool startupSet(bool enable) => _startupSet(enable ? 1 : 0) != 0;
  void traySet(bool enable) => _traySet(enable ? 1 : 0);
  void closeToTray(bool enable) => _closeToTray(enable ? 1 : 0);

  void windowDrag() => _winCmd(0);
  void windowMinimize() => _winCmd(1);
  void windowMaximizeToggle() => _winCmd(2);
  void windowClose() => _winCmd(3);
  void windowHide() => _winCmd(4);
  void windowShow() => _winCmd(5);
}
