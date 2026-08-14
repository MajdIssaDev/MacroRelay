import 'dart:convert';
import 'dart:io';
import 'dart:math';

class MacroStep {
  MacroStep({
    required this.kind,
    this.code = 0,
    this.down = true,
    this.delayMs = 0,
    this.x,
    this.y,
    this.x2,
    this.y2,
    this.text = '',
    this.enabled = true,
  });

  /// 0 key, 1 mouse, 2 delay, 3 text, 4 wheel, 5 drag
  int kind;
  int code;
  bool down;
  int delayMs;
  int? x;
  int? y;
  int? x2;
  int? y2;
  String text;
  bool enabled;

  bool get hasPos => x != null && y != null;

  MacroStep copy() => MacroStep(
        kind: kind,
        code: code,
        down: down,
        delayMs: delayMs,
        x: x,
        y: y,
        x2: x2,
        y2: y2,
        text: text,
        enabled: enabled,
      );

  String get label {
    switch (kind) {
      case 0:
        return '${down ? 'Key down' : 'Key up'} ${vkName(code)}';
      case 1:
        final btn = ['Left', 'Right', 'Middle', 'X1', 'X2'][code.clamp(0, 4)];
        final pos = hasPos ? ' at ($x,$y)' : '';
        return '${down ? 'Down' : 'Up'} $btn$pos';
      case 2:
        return 'Wait $delayMs ms';
      case 3:
        final t = text.length > 32 ? '${text.substring(0, 32)}…' : text;
        return 'Type "$t"';
      case 4:
        final dir = code >= 0 ? 'up' : 'down';
        final pos = hasPos ? ' at ($x,$y)' : '';
        return 'Wheel $dir$pos';
      case 5:
        final btn = ['Left', 'Right', 'Middle', 'X1', 'X2'][code.clamp(0, 4)];
        return 'Drag $btn ($x,$y) → ($x2,$y2)';
      default:
        return 'Step';
    }
  }

  String get shortLabel {
    switch (kind) {
      case 0:
        return '${vkName(code)}${down ? ' ↓' : ' ↑'}';
      case 1:
        final btn = ['L', 'R', 'M', 'X1', 'X2'][code.clamp(0, 4)];
        final pos = hasPos ? '\n$x,$y' : '';
        return '${down ? '' : '↑ '}$btn$pos';
      case 2:
        return '${delayMs}ms';
      case 3:
        final t = text.length > 8 ? '${text.substring(0, 8)}…' : text;
        return '"$t"';
      case 4:
        return code >= 0 ? 'Wheel↑' : 'Wheel↓';
      case 5:
        return 'Drag\n$x,$y';
      default:
        return '?';
    }
  }

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'code': code,
        'down': down,
        'delayMs': delayMs,
        'x': x,
        'y': y,
        'x2': x2,
        'y2': y2,
        'text': text,
        'enabled': enabled,
      };

  factory MacroStep.fromJson(Map<String, dynamic> json) => MacroStep(
        kind: json['kind'] as int? ?? 0,
        code: json['code'] as int? ?? 0,
        down: json['down'] as bool? ?? true,
        delayMs: json['delayMs'] as int? ?? 0,
        x: json['x'] as int?,
        y: json['y'] as int?,
        x2: json['x2'] as int?,
        y2: json['y2'] as int?,
        text: json['text'] as String? ?? '',
        enabled: json['enabled'] as bool? ?? true,
      );
}

class MacroDef {
  MacroDef({
    String? id,
    this.name = 'New macro',
    this.enabled = true,
    this.intervalMs = 50,
    this.speed = 1.0,
    this.jitter = false,
    this.loopMode = 0,
    this.repeatCount = 1,
    this.durationMs = 10000,
    this.timeLimit = false,
    this.focusTarget = false,
    this.process = '',
    this.title = '',
    this.triggerMode = 0,
    this.playVk = 0,
    this.playMods = 0,
    this.pauseVk = 0,
    this.pauseMods = 0,
    this.stopVk = 0,
    this.stopMods = 0,
    this.tag = 0,
    List<MacroStep>? steps,
  })  : id = id ?? _nid(),
        steps = steps ?? [];

  final String id;
  String name;
  bool enabled;
  int intervalMs;
  double speed;
  bool jitter;
  int loopMode;
  int repeatCount;
  int durationMs;
  bool timeLimit;
  bool focusTarget;
  String process;
  String title;
  /// 0 toggle, 1 hold, 2 run once
  int triggerMode;
  int playVk;
  int playMods;
  int pauseVk;
  int pauseMods;
  int stopVk;
  int stopMods;
  int tag;
  List<MacroStep> steps;
  int nativeId = 0;
  int state = 0;

  String get targetSummary {
    if (!focusTarget && process.isEmpty) return 'No window — plays into whatever is focused';
    final bits = <String>[];
    if (process.isNotEmpty) bits.add(process);
    if (title.isNotEmpty) bits.add('"$title"');
    final name = bits.isEmpty ? 'picked window' : bits.join(' · ');
    return 'Sends to $name without stealing focus';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'enabled': enabled,
        'intervalMs': intervalMs,
        'speed': speed,
        'jitter': jitter,
        'loopMode': loopMode,
        'repeatCount': repeatCount,
        'durationMs': durationMs,
        'timeLimit': timeLimit,
        'focusTarget': focusTarget,
        'process': process,
        'title': title,
        'triggerMode': triggerMode,
        'playVk': playVk,
        'playMods': playMods,
        'pauseVk': pauseVk,
        'pauseMods': pauseMods,
        'stopVk': stopVk,
        'stopMods': stopMods,
        'tag': tag,
        'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory MacroDef.fromJson(Map<String, dynamic> json) => MacroDef(
        id: json['id'] as String?,
        name: json['name'] as String? ?? 'Macro',
        enabled: json['enabled'] as bool? ?? true,
        intervalMs: json['intervalMs'] as int? ?? 50,
        speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
        jitter: json['jitter'] as bool? ?? false,
        loopMode: json['loopMode'] as int? ?? 0,
        repeatCount: json['repeatCount'] as int? ?? 1,
        durationMs: json['durationMs'] as int? ?? 10000,
        timeLimit: json['timeLimit'] as bool? ?? false,
        focusTarget: json['focusTarget'] as bool? ?? false,
        process: json['process'] as String? ?? '',
        title: json['title'] as String? ?? '',
        triggerMode: json['triggerMode'] as int? ?? 0,
        playVk: json['playVk'] as int? ?? 0,
        playMods: json['playMods'] as int? ?? 0,
        pauseVk: json['pauseVk'] as int? ?? 0,
        pauseMods: json['pauseMods'] as int? ?? 0,
        stopVk: json['stopVk'] as int? ?? 0,
        stopMods: json['stopMods'] as int? ?? 0,
        tag: json['tag'] as int? ?? 0,
        steps: (json['steps'] as List<dynamic>? ?? [])
            .map((e) => MacroStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  MacroDef duplicate() => MacroDef(
        name: '$name copy',
        enabled: enabled,
        intervalMs: intervalMs,
        speed: speed,
        jitter: jitter,
        loopMode: loopMode,
        repeatCount: repeatCount,
        durationMs: durationMs,
        timeLimit: timeLimit,
        focusTarget: focusTarget,
        process: process,
        title: title,
        triggerMode: triggerMode,
        playVk: playVk,
        playMods: playMods,
        pauseVk: pauseVk,
        pauseMods: pauseMods,
        stopVk: stopVk,
        stopMods: stopMods,
        tag: tag,
        steps: steps.map((s) => s.copy()).toList(),
      );

  static String _nid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16) +
      Random().nextInt(0xffff).toRadixString(16);
}

const tagColors = <int>[
  0x00000000,
  0xFF3DDC97,
  0xFF5B9DFF,
  0xFFFF8A4C,
  0xFFC084FC,
  0xFFFF5C7A,
];

String bindLabel(int vk, int mods) {
  if (vk <= 0) return 'None';
  final parts = <String>[];
  if (mods & 1 != 0) parts.add('Ctrl');
  if (mods & 2 != 0) parts.add('Shift');
  if (mods & 4 != 0) parts.add('Alt');
  parts.add(vkName(vk));
  return parts.join('+');
}

String vkName(int vk) {
  const named = {
    0x01: 'Mouse L',
    0x02: 'Mouse R',
    0x04: 'Mouse M',
    0x05: 'Mouse X1',
    0x06: 'Mouse X2',
    0x08: 'Backspace',
    0x09: 'Tab',
    0x0D: 'Enter',
    0x10: 'Shift',
    0x11: 'Ctrl',
    0x12: 'Alt',
    0x13: 'Pause',
    0x1B: 'Esc',
    0x20: 'Space',
    0x25: 'Left',
    0x26: 'Up',
    0x27: 'Right',
    0x28: 'Down',
    0x2E: 'Delete',
  };
  if (named.containsKey(vk)) return named[vk]!;
  if (vk >= 0x30 && vk <= 0x39) return String.fromCharCode(vk);
  if (vk >= 0x41 && vk <= 0x5A) return String.fromCharCode(vk);
  if (vk >= 0x70 && vk <= 0x7B) return 'F${vk - 0x6F}';
  return 'VK_${vk.toRadixString(16).toUpperCase()}';
}

int? vkFromName(String name) {
  final n = name.trim();
  if (n.length == 1) {
    final c = n.toUpperCase().codeUnitAt(0);
    if ((c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A)) return c;
  }
  const map = {
    'enter': 0x0D,
    'space': 0x20,
    'esc': 0x1B,
    'escape': 0x1B,
    'tab': 0x09,
    'shift': 0x10,
    'ctrl': 0x11,
    'alt': 0x12,
    'backspace': 0x08,
    'delete': 0x2E,
    'left': 0x25,
    'up': 0x26,
    'right': 0x27,
    'down': 0x28,
  };
  if (map.containsKey(n.toLowerCase())) return map[n.toLowerCase()];
  final f = RegExp(r'^f(\d{1,2})$', caseSensitive: false).firstMatch(n);
  if (f != null) {
    final i = int.parse(f.group(1)!);
    if (i >= 1 && i <= 12) return 0x6F + i;
  }
  return int.tryParse(n);
}

String libraryJson(List<MacroDef> macros) =>
    const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'macros': macros.map((m) => m.toJson()).toList(),
    });

List<MacroDef> parseLibrary(String json) {
  final data = jsonDecode(json) as Map<String, dynamic>;
  final list = data['macros'] as List<dynamic>? ?? [];
  return list.map((e) => MacroDef.fromJson(e as Map<String, dynamic>)).toList();
}

Future<File> libraryFile() async {
  final appdata = Platform.environment['APPDATA'];
  final dir = Directory('${appdata ?? '.'}\\MacroRelay');
  if (!await dir.exists()) await dir.create(recursive: true);
  return File('${dir.path}\\macros.v2.json');
}
