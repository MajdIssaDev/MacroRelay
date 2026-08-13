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
        _start = lib.lookupFunction<_StartC, _StartD>('mr_session_start'),
        _pause = lib.lookupFunction<_IdC, _IdD>('mr_session_pause'),
        _stop = lib.lookupFunction<_IdC, _IdD>('mr_session_stop'),
        _stopAll = lib.lookupFunction<_VoidC, _VoidD>('mr_stop_all'),
        _state = lib.lookupFunction<_StateC, _StateD>('mr_session_state'),
        _running = lib.lookupFunction<_CountC, _CountD>('mr_running_count'),
        _window = lib.lookupFunction<_WindowC, _WindowD>('mr_window_at_cursor'),
        _cursor = lib.lookupFunction<_CursorC, _CursorD>('mr_cursor_client'),
        _ctrlShift = lib.lookupFunction<_FlagC, _FlagD>('mr_ctrl_shift_down');

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
  final _StartD _start;
  final _IdD _pause;
  final _IdD _stop;
  final _VoidD _stopAll;
  final _StateD _state;
  final _CountD _running;
  final _WindowD _window;
  final _CursorD _cursor;
  final _FlagD _ctrlShift;

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
}
