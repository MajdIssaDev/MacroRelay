import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class SettingsStore {
  static Future<File> file() async {
    final dir = Directory('${Platform.environment['APPDATA'] ?? '.'}\\MacroRelay');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}\\settings.json');
  }

  static Future<Map<String, dynamic>> read() async {
    try {
      final f = await file();
      if (await f.exists()) {
        return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  static Future<void> patch(Map<String, dynamic> patch) async {
    final data = await read();
    data.addAll(patch);
    final f = await file();
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }
}

class AppSettings extends ChangeNotifier {
  int playVk = 0x75; // F6
  int playMods = 0;
  int onceVk = 0x76; // F7
  int onceMods = 0;
  int recordVk = 0x78; // F9
  int recordMods = 0;
  int panicVk = 0x7B; // F12
  int panicMods = 0;
  bool closeToTray = false;
  bool audioCues = false;
  bool runOnStartup = false;

  Future<void> load() async {
    try {
      final data = await SettingsStore.read();
      playVk = data['playVk'] as int? ?? playVk;
      playMods = data['playMods'] as int? ?? playMods;
      onceVk = data['onceVk'] as int? ?? onceVk;
      onceMods = data['onceMods'] as int? ?? onceMods;
      recordVk = data['recordVk'] as int? ?? recordVk;
      recordMods = data['recordMods'] as int? ?? recordMods;
      panicVk = data['panicVk'] as int? ?? panicVk;
      panicMods = data['panicMods'] as int? ?? panicMods;
      closeToTray = data['closeToTray'] as bool? ?? closeToTray;
      audioCues = data['audioCues'] as bool? ?? audioCues;
      runOnStartup = data['runOnStartup'] as bool? ?? runOnStartup;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> save() async {
    await SettingsStore.patch({
      'playVk': playVk,
      'playMods': playMods,
      'onceVk': onceVk,
      'onceMods': onceMods,
      'recordVk': recordVk,
      'recordMods': recordMods,
      'panicVk': panicVk,
      'panicMods': panicMods,
      'closeToTray': closeToTray,
      'audioCues': audioCues,
      'runOnStartup': runOnStartup,
    });
    notifyListeners();
  }
}
