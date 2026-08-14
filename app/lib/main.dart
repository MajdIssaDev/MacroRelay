import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chrome.dart';
import 'engine.dart';
import 'keybinds.dart';
import 'menus.dart';
import 'models.dart';
import 'settings.dart';
import 'theme.dart';
import 'tutorial.dart';
import 'updater.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MacroRelayApp());
}

class MacroRelayApp extends StatefulWidget {
  const MacroRelayApp({super.key});
  @override
  State<MacroRelayApp> createState() => _MacroRelayAppState();
}

class _MacroRelayAppState extends State<MacroRelayApp> {
  final themes = ThemeController();

  @override
  void dispose() {
    themes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppTheme(
      controller: themes,
      child: AnimatedBuilder(
        animation: themes,
        builder: (context, _) {
          final p = themes.palette;
          return MaterialApp(
            title: 'MacroRelay',
            debugShowCheckedModeBanner: false,
            theme: themeFrom(p),
            home: const DashboardPage(),
          );
        },
      ),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final engine = NativeEngine.tryLoad();
  final settings = AppSettings();
  final macros = <MacroDef>[];
  MacroDef? selected;
  final selectedIndices = <int>{};
  int? selectionAnchor;
  int? insertCursor;
  int? recordInsertAt;
  bool _reordering = false;
  bool keepDelays = true;
  bool recording = false;
  bool nameHover = false;
  bool _hotkeysPaused = false;
  int _editorTab = 0;
  String status = 'Ready';
  String updateStatus = '';
  bool _updating = false;
  Timer? _poll;
  Timer? _stateTimer;
  final sequenceFocus = FocusNode();
  final nameFocus = FocusNode();
  late final TextEditingController nameCtrl;
  bool editingName = false;
  bool _globalPlayWas = false;
  bool _globalOnceWas = false;
  bool _recordWas = false;
  bool _panicWas = false;
  final _playWas = <String, bool>{};
  final _pauseWas = <String, bool>{};
  final _stopWas = <String, bool>{};
  final _holdOn = <String, bool>{};
  final headerKey = GlobalKey();
  final recordKey = GlobalKey();
  final themeKey = GlobalKey();
  final infoKey = GlobalKey();
  final nameKey = GlobalKey();
  final startKey = GlobalKey();
  final targetKey = GlobalKey();
  final sequenceKey = GlobalKey();
  final insertKey = GlobalKey();
  final keybindsKey = GlobalKey();
  final settingsKey = GlobalKey();
  final sidebarKey = GlobalKey();

  Palette get c => AppTheme.of(context);

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController();
    nameFocus.addListener(() {
      if (!nameFocus.hasFocus && editingName) _commitName();
    });
    _load();
    _stateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _pollHotkeys();
      _refreshStates();
    });
    _checkUpdates(silent: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _stateTimer?.cancel();
    sequenceFocus.dispose();
    nameFocus.dispose();
    nameCtrl.dispose();
    engine?.stopAll();
    super.dispose();
  }

  Future<void> _load() async {
    await settings.load();
    try {
      final file = await libraryFile();
      if (await file.exists()) {
        macros
          ..clear()
          ..addAll(parseLibrary(await file.readAsString()));
      }
    } catch (_) {}
    selected = macros.isEmpty ? null : macros.first;
    nameCtrl.text = selected?.name ?? '';
    _applyEngineSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyEngineSettings();
      if (Platform.executableArguments.contains('--tray')) {
        engine?.traySet(true);
        engine?.windowHide();
      }
    });
    setState(() {});
  }

  void _applyEngineSettings() {
    final e = engine;
    if (e == null) return;
    e.hotkeySet(
      play: settings.playVk,
      once: settings.onceVk,
      record: settings.recordVk,
      panic: settings.panicVk,
    );
    e.closeToTray(settings.closeToTray);
    e.traySet(settings.closeToTray || settings.runOnStartup);
    settings.runOnStartup = e.startupGet();
    _syncBindEdges();
  }

  void _syncBindEdges() {
    final e = engine;
    if (e == null) return;
    _globalPlayWas = e.bindDown(settings.playVk, settings.playMods);
    _globalOnceWas = e.bindDown(settings.onceVk, settings.onceMods);
    _recordWas = e.bindDown(settings.recordVk, settings.recordMods);
    _panicWas = e.bindDown(settings.panicVk, settings.panicMods);
    for (final m in macros) {
      if (m.playVk > 0) _playWas[m.id] = e.bindDown(m.playVk, m.playMods);
      if (m.pauseVk > 0) _pauseWas[m.id] = e.bindDown(m.pauseVk, m.pauseMods);
      if (m.stopVk > 0) _stopWas[m.id] = e.bindDown(m.stopVk, m.stopMods);
    }
  }

  Future<void> _save() async {
    final file = await libraryFile();
    await file.writeAsString(libraryJson(macros));
  }

  void _commitName() {
    final m = selected;
    editingName = false;
    if (m == null) return;
    final v = nameCtrl.text.trim();
    if (v.isNotEmpty && v != m.name) {
      m.name = v;
      _save();
    } else {
      nameCtrl.text = m.name;
    }
    setState(() {});
  }

  void _startTutorial() {
    showTutorial(context, [
      TutorialStep(
        title: 'Welcome to MacroRelay',
        body: 'Record keys and clicks, then play them into a picked window without stealing focus. Use Previous / Next to walk through the controls.',
        anchor: headerKey,
      ),
      TutorialStep(
        title: 'Themes',
        body: 'Tap a color dot to switch palettes. Ops, Cobalt, Ember, Orchid, and Frost are saved for next launch.',
        anchor: themeKey,
      ),
      TutorialStep(
        title: 'Keybinds',
        body: 'Open Keybinds to change Start, Run once, Record, and Panic stop. Defaults are F6, F7, F9, and F12. Combos like Ctrl+Shift+1 work. Each macro can also have its own Start, Pause, and Stop, and a trigger: Toggle, Hold down, or Run once.',
        anchor: keybindsKey,
      ),
      TutorialStep(
        title: 'Settings',
        body: 'Run on Windows startup (opens in the tray), close to tray so macros keep running, and optional beeps on start, pause, and stop. Export or import the whole library as JSON here.',
        anchor: settingsKey,
      ),
      TutorialStep(
        title: 'Record',
        body: 'The record key (default F9) starts and stops recording. Mouse travel is ignored. Clicks on MacroRelay itself are not captured.',
        anchor: recordKey,
      ),
      TutorialStep(
        title: 'Macros',
        body: 'Use + to add a macro. The upload icon imports JSON. Right-click a card to export, copy JSON, duplicate, or delete it.',
        anchor: sidebarKey,
      ),
      TutorialStep(
        title: 'Macro name',
        body: 'Click the name to edit it in place. No popup. Keep it short; this box stays on the left of Start.',
        anchor: nameKey,
      ),
      TutorialStep(
        title: 'Play',
        body: 'Start uses Repeat (infinite, count, or time). Run once plays the sequence a single time, then stops. Trigger Hold down loops only while the start key is held. Panic stop (F12) ends every running macro.',
        anchor: startKey,
      ),
      TutorialStep(
        title: 'Window target',
        body: 'Pick window sends posted keys and clicks to that app without focusing it. DirectInput games may still ignore posted messages.',
        anchor: targetKey,
      ),
      TutorialStep(
        title: 'Sequence',
        body: 'Click a square to select it. Ctrl+click adds more, Shift+click selects the range. Hold a square to drag the selection. Duplicate clones the selection. Move left / Move right shifts the selected steps. Right-click an arrow or the + slot to insert or record there.',
        anchor: sequenceKey,
      ),
      TutorialStep(
        title: 'Insert step',
        body: 'Insert text, keys, waits, mouse wheel, or click-and-drag. Capture click X,Y with the crosshair, then click the target window — or use Control+Shift. That click does not move your cursor.',
        anchor: insertKey,
      ),
    ]);
  }

  void _refreshStates() {
    final e = engine;
    if (e == null) return;
    var changed = false;
    for (final m in macros) {
      if (m.nativeId == 0) continue;
      final s = e.state(m.nativeId);
      if (s != m.state) {
        m.state = s;
        changed = true;
      }
    }
    if (changed) setState(() {});
  }

  Future<void> _checkUpdates({bool silent = false}) async {
    if (_updating) return;
    _updating = true;
    if (!silent) setState(() => updateStatus = 'Checking updates…');
    try {
      final result = await Updater.checkAndApply(
        onStatus: (s) {
          if (mounted) setState(() => updateStatus = s);
        },
        onBeforeApply: () async {
          engine?.stopAll();
        },
        apply: true,
        allowSetupInstall: !silent,
      );
      if (!mounted) return;
      switch (result.kind) {
        case UpdateKind.upToDate:
          setState(() => updateStatus = silent ? '' : result.message);
        case UpdateKind.skipped:
          setState(() => updateStatus = silent ? '' : result.message);
        case UpdateKind.failed:
          setState(() => updateStatus = silent ? '' : result.message);
      }
    } catch (_) {
      if (mounted) setState(() => updateStatus = silent ? '' : 'Update check failed');
    } finally {
      _updating = false;
    }
  }

  void _ensureNative(MacroDef m, {int? loopMode}) {
    final e = engine;
    if (e == null) return;
    if (m.nativeId == 0) m.nativeId = e.createSession();
    e.stop(m.nativeId);
    e.clear(m.nativeId);
    final mode = loopMode ?? (m.timeLimit ? 2 : m.loopMode);
    e.setOptions(
      id: m.nativeId,
      intervalMs: m.intervalMs,
      speed: m.speed,
      jitter: m.jitter,
      loopMode: mode,
      repeatCount: m.repeatCount,
      durationMs: m.durationMs,
      focusTarget: m.focusTarget || m.process.isNotEmpty,
    );
    e.setTarget(m.nativeId, m.process, m.title);
    for (final step in m.steps.where((s) => s.enabled)) {
      switch (step.kind) {
        case 0:
          e.addKey(m.nativeId, step.code, step.down);
        case 1:
          e.addMouse(m.nativeId, step.code, step.down, x: step.x, y: step.y);
        case 2:
          e.addDelay(m.nativeId, step.delayMs);
        case 3:
          e.addText(m.nativeId, step.text);
        case 4:
          e.addWheel(m.nativeId, step.code, x: step.x, y: step.y);
        case 5:
          e.addDrag(m.nativeId, step.code, step.x ?? 0, step.y ?? 0, step.x2 ?? 0, step.y2 ?? 0);
      }
    }
  }

  void _cue(int kind) {
    if (settings.audioCues) engine?.beep(kind);
  }

  void _play(MacroDef m, {int? loopMode}) {
    if (engine == null) {
      setState(() => status = 'Native engine not loaded.');
      return;
    }
    if (m.steps.where((s) => s.enabled).isEmpty) {
      setState(() => status = 'Add steps, or record, first.');
      return;
    }
    _ensureNative(m, loopMode: loopMode);
    engine!.start(m.nativeId);
    _cue(0);
    setState(() => status = loopMode == 3 ? 'Playing ${m.name} once' : 'Playing ${m.name}');
  }

  void _playOnce(MacroDef m) {
    if (recording) return;
    _play(m, loopMode: 3);
  }

  void _togglePlay() {
    final m = selected;
    if (m == null || recording) return;
    _togglePlayMacro(m);
  }

  void _togglePlayMacro(MacroDef m) {
    final running = m.nativeId != 0 && (engine?.state(m.nativeId) ?? m.state) != 0;
    if (running) {
      _stopMacro(m);
      return;
    }
    _play(m);
  }

  void _pauseMacro(MacroDef m) {
    if (m.nativeId != 0) engine?.pause(m.nativeId);
    _cue(1);
    setState(() {});
  }

  void _stopMacro(MacroDef m) {
    if (m.nativeId != 0) engine?.stop(m.nativeId);
    _holdOn[m.id] = false;
    _cue(2);
    setState(() => status = 'Stopped');
  }

  bool _took(bool now, bool was) => now && !was;

  void _handleTrigger(MacroDef m, bool down, bool was) {
    if (recording) return;
    if (m.triggerMode == 1) {
      if (down && !(_holdOn[m.id] ?? false)) {
        final running = m.nativeId != 0 && (engine?.state(m.nativeId) ?? m.state) != 0;
        if (!running) _play(m, loopMode: 0);
        _holdOn[m.id] = true;
      } else if (!down && (_holdOn[m.id] ?? false)) {
        _stopMacro(m);
      }
      return;
    }
    if (_took(down, was)) {
      if (m.triggerMode == 2) {
        _playOnce(m);
      } else {
        _togglePlayMacro(m);
      }
    }
  }

  void _pollHotkeys() {
    final e = engine;
    if (e == null || _hotkeysPaused) return;

    final recordNow = e.bindDown(settings.recordVk, settings.recordMods);
    if (_took(recordNow, _recordWas)) _toggleRecord();
    _recordWas = recordNow;

    final panicNow = e.bindDown(settings.panicVk, settings.panicMods);
    if (_took(panicNow, _panicWas)) {
      e.stopAll();
      _holdOn.clear();
      _cue(2);
      setState(() => status = 'Panic stop');
    }
    _panicWas = panicNow;

    var consumedPlay = false;
    var consumedOnce = false;

    for (final m in macros) {
      if (m.pauseVk > 0) {
        final down = e.bindDown(m.pauseVk, m.pauseMods);
        if (_took(down, _pauseWas[m.id] ?? false)) _pauseMacro(m);
        _pauseWas[m.id] = down;
      }
      if (m.stopVk > 0) {
        final down = e.bindDown(m.stopVk, m.stopMods);
        if (_took(down, _stopWas[m.id] ?? false)) _stopMacro(m);
        _stopWas[m.id] = down;
      }
      if (m.playVk > 0) {
        final down = e.bindDown(m.playVk, m.playMods);
        _handleTrigger(m, down, _playWas[m.id] ?? false);
        _playWas[m.id] = down;
        if (m.playVk == settings.playVk && m.playMods == settings.playMods) consumedPlay = true;
        if (m.playVk == settings.onceVk && m.playMods == settings.onceMods) consumedOnce = true;
      }
    }

    final sel = selected;
    final playNow = e.bindDown(settings.playVk, settings.playMods);
    if (!consumedPlay && sel != null && sel.playVk == 0) {
      _handleTrigger(sel, playNow, _globalPlayWas);
    }
    _globalPlayWas = playNow;

    final onceNow = e.bindDown(settings.onceVk, settings.onceMods);
    if (!consumedOnce && _took(onceNow, _globalOnceWas) && sel != null && !recording) {
      _playOnce(sel);
    }
    _globalOnceWas = onceNow;
  }

  void _insert(MacroStep step) {
    final m = selected;
    if (m == null) return;
    final i = insertCursor ??
        (selectedIndices.isEmpty ? m.steps.length : (selectedIndices.reduce(math.max) + 1));
    final at = i.clamp(0, m.steps.length);
    m.steps.insert(at, step);
    if (insertCursor != null) insertCursor = at + 1;
    selectedIndices
      ..clear()
      ..add(at);
    selectionAnchor = at;
    _save();
    setState(() {});
  }

  void _selectIndex(int i, {required bool ctrl, required bool shift}) {
    sequenceFocus.requestFocus();
    if (shift && selectionAnchor != null) {
      final from = math.min(selectionAnchor!, i);
      final to = math.max(selectionAnchor!, i);
      selectedIndices
        ..clear()
        ..addAll([for (var k = from; k <= to; k++) k]);
    } else if (ctrl) {
      if (!selectedIndices.remove(i)) selectedIndices.add(i);
      selectionAnchor = i;
    } else {
      selectedIndices
        ..clear()
        ..add(i);
      selectionAnchor = i;
    }
    setState(() {});
  }

  void _moveSelectedTo(int dest) {
    final m = selected;
    if (m == null || selectedIndices.isEmpty) return;
    final order = selectedIndices.toList()..sort();
    final contiguous = order.last - order.first + 1 == order.length;
    if (contiguous && dest >= order.first && dest <= order.last + 1) return;
    final moving = [for (final i in order) m.steps[i]];
    var insertAt = dest;
    for (final i in order.reversed) {
      m.steps.removeAt(i);
      if (i < insertAt) insertAt--;
    }
    insertAt = insertAt.clamp(0, m.steps.length);
    m.steps.insertAll(insertAt, moving);
    selectedIndices
      ..clear()
      ..addAll([for (var k = 0; k < moving.length; k++) insertAt + k]);
    selectionAnchor = insertAt;
    _save();
    setState(() {});
  }

  void _deleteMacro(MacroDef m) {
    if (recording && selected?.id == m.id) _toggleRecord();
    if (m.nativeId != 0) {
      engine?.stop(m.nativeId);
      engine?.destroy(m.nativeId);
    }
    macros.removeWhere((e) => e.id == m.id);
    if (selected?.id == m.id) {
      selected = macros.isEmpty ? null : macros.first;
      selectedIndices.clear();
      selectionAnchor = null;
      editingName = false;
      nameHover = false;
      nameCtrl.text = selected?.name ?? '';
    }
    _save();
    setState(() {});
  }

  void _deleteSelected() {
    final m = selected;
    if (m == null || selectedIndices.isEmpty) return;
    final order = selectedIndices.toList()..sort((a, b) => b.compareTo(a));
    for (final i in order) {
      if (i >= 0 && i < m.steps.length) m.steps.removeAt(i);
    }
    selectedIndices.clear();
    selectionAnchor = null;
    _save();
    setState(() {});
  }

  void _duplicateSelected() {
    final m = selected;
    if (m == null || selectedIndices.isEmpty) return;
    final order = selectedIndices.toList()..sort();
    final copies = [for (final i in order) m.steps[i].copy()];
    final at = order.last + 1;
    m.steps.insertAll(at, copies);
    selectedIndices
      ..clear()
      ..addAll([for (var k = 0; k < copies.length; k++) at + k]);
    selectionAnchor = at;
    _save();
    setState(() {});
  }

  void _nudgeSelected(int dir) {
    final m = selected;
    if (m == null || selectedIndices.isEmpty) return;
    final order = selectedIndices.toList()..sort();
    if (dir < 0) {
      _moveSelectedTo(order.first - 1);
    } else {
      _moveSelectedTo(order.last + 2);
    }
  }

  void _duplicateMacro(MacroDef m) {
    final copy = m.duplicate();
    macros.insert(macros.indexOf(m) + 1, copy);
    selected = copy;
    selectedIndices.clear();
    selectionAnchor = null;
    nameCtrl.text = copy.name;
    _save();
    setState(() {});
  }

  Future<void> _exportJson(List<MacroDef> list, {String? label}) async {
    final path = engine?.pickFile(save: true);
    if (path == null || path.isEmpty) return;
    await File(path).writeAsString(libraryJson(list));
    setState(() => status = 'Exported ${label ?? '${list.length} macros'}');
  }

  Future<void> _importJson() async {
    final path = engine?.pickFile(save: false);
    if (path == null || path.isEmpty) return;
    try {
      final incoming = parseLibrary(await File(path).readAsString());
      for (final m in incoming) {
        final copy = m.duplicate();
        copy.name = m.name;
        macros.add(copy);
      }
      selected ??= macros.isEmpty ? null : macros.last;
      nameCtrl.text = selected?.name ?? '';
      _save();
      setState(() => status = 'Imported ${incoming.length} macros');
    } catch (_) {
      setState(() => status = 'Import failed');
    }
  }

  Future<void> _copyMacroJson(MacroDef m) async {
    await Clipboard.setData(ClipboardData(text: libraryJson([m])));
    setState(() => status = 'Copied ${m.name} JSON');
  }

  Future<void> _showKeybinds() async {
    _hotkeysPaused = true;
    await showKeybindsDialog(
      context: context,
      engine: engine,
      settings: settings,
      macro: selected,
      onChanged: () {
        _applyEngineSettings();
        _save();
        setState(() {});
      },
    );
    _hotkeysPaused = false;
    _applyEngineSettings();
  }

  Future<void> _showSettings() async {
    _hotkeysPaused = true;
    await showAppSettingsDialog(
      context: context,
      engine: engine,
      settings: settings,
      onExportLibrary: () => _exportJson(macros, label: 'library'),
      onImportLibrary: _importJson,
      onChanged: () {
        _applyEngineSettings();
        setState(() {});
      },
    );
    _hotkeysPaused = false;
    _applyEngineSettings();
  }

  Future<void> _macroCardMenu(Offset pos, MacroDef m) async {
    final choice = await showAppMenu<String>(
      context: context,
      position: pos,
      items: const [
        MenuChoice('export', 'Export as JSON'),
        MenuChoice('copy', 'Copy JSON'),
        MenuChoice('dup', 'Duplicate'),
        MenuChoice('delete', 'Delete'),
      ],
    );
    if (choice == null) return;
    switch (choice) {
      case 'export':
        await _exportJson([m], label: m.name);
      case 'copy':
        await _copyMacroJson(m);
      case 'dup':
        _duplicateMacro(m);
      case 'delete':
        _deleteMacro(m);
    }
  }

  void _toggleRecord({int? insertAt}) {
    final e = engine;
    final m = selected;
    if (e == null || m == null) return;
    if (recording) {
      e.recordStop();
      _poll?.cancel();
      _ingestRecorded(m);
      recording = false;
      recordInsertAt = null;
      status = 'Recording stopped';
      _save();
      setState(() {});
      return;
    }
    recordInsertAt = insertAt;
    e.recordStart(keepDelays: keepDelays);
    recording = true;
    final where = insertAt == null ? '' : ' · insert at ${(insertAt + 1).toString().padLeft(2, '0')}';
    final prefix = keepDelays ? 'Recording (delays on)' : 'Recording (delays off)';
    status = '$prefix$where  ${bindLabel(settings.recordVk, settings.recordMods)} stop';
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      _ingestRecorded(m);
      setState(() {});
    });
    setState(() {});
  }

  void _ingestRecorded(MacroDef m) {
    final e = engine;
    if (e == null) return;
    for (final ev in e.pollRecorded()) {
      void put(MacroStep step) {
        final at = recordInsertAt;
        if (at == null) {
          m.steps.add(step);
        } else {
          m.steps.insert(at.clamp(0, m.steps.length), step);
          recordInsertAt = at + 1;
        }
      }

      if (ev.delayMs > 0 && keepDelays) {
        put(MacroStep(kind: 2, delayMs: ev.delayMs));
      }
      put(MacroStep(kind: ev.kind, code: ev.code, down: ev.down == 1));
    }
  }

  Future<void> _pickWindow() async {
    final e = engine;
    final m = selected;
    if (e == null || m == null) return;
    setState(() => status = 'Hover the target app, then click it (2s)…');
    await Future<void>.delayed(const Duration(seconds: 2));
    final info = e.windowAtCursor();
    if (info == null) return;
    m
      ..process = info.process
      ..title = info.title
      ..focusTarget = true;
    _save();
    setState(() => status = 'Target ${info.process} — input goes there without focusing it');
  }

  @override
  Widget build(BuildContext context) {
    final m = selected;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _AddIntent(),
        SingleActivator(LogicalKeyboardKey.delete): _DeleteIntent(),
      },
      child: Actions(
        actions: {
          _AddIntent: CallbackAction<_AddIntent>(onInvoke: (_) {
            _showInsertMenu(context);
            return null;
          }),
          _DeleteIntent: CallbackAction<_DeleteIntent>(onInvoke: (_) {
            _deleteSelected();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Column(
              children: [
                AppHeader(
                  engine: engine,
                  recording: recording,
                  recordLabel: bindLabel(settings.recordVk, settings.recordMods),
                  onRecord: () => _toggleRecord(),
                  onStartAll: () {
                    for (final m in macros.where((e) => e.enabled)) {
                      _play(m);
                    }
                  },
                  onPauseAll: () {
                    for (final m in macros) {
                      if (m.nativeId != 0) engine?.pause(m.nativeId);
                    }
                    _cue(1);
                  },
                  onStopAll: () {
                    engine?.stopAll();
                    _holdOn.clear();
                    _cue(2);
                    setState(() => status = 'Stopped');
                  },
                  onKeybinds: _showKeybinds,
                  onSettings: _showSettings,
                  onInfo: _startTutorial,
                  headerKey: headerKey,
                  recordKey: recordKey,
                  themeKey: themeKey,
                  infoKey: infoKey,
                  keybindsKey: keybindsKey,
                  settingsKey: settingsKey,
                ),
                Expanded(
                  child: Row(
                    children: [
                      _sidebar(),
                      Container(width: 1, color: c.line),
                      Expanded(child: m == null ? _empty() : _editor(m)),
                    ],
                  ),
                ),
                _statusBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sidebar() {
    return SizedBox(
      width: 280,
      child: ColoredBox(
        color: c.panel,
        child: Column(
          children: [
            Padding(
              key: sidebarKey,
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              child: Row(
                children: [
                  const Text('Macros', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Import JSON',
                    onPressed: _importJson,
                    icon: Icon(Icons.file_upload_outlined, color: c.accent),
                  ),
                  IconButton(
                    tooltip: 'Add macro',
                    onPressed: () {
                      final m = MacroDef(name: 'Macro ${macros.length + 1}');
                      macros.add(m);
                      selected = m;
                      selectedIndices.clear();
                      selectionAnchor = null;
                      nameHover = false;
                      editingName = false;
                      nameCtrl.text = m.name;
                      _save();
                      setState(() {});
                    },
                    icon: Icon(Icons.add, color: c.accent),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: macros.length,
                itemBuilder: (context, i) {
                  final m = macros[i];
                  final on = selected?.id == m.id;
                  return GestureDetector(
                    onSecondaryTapDown: (d) => _macroCardMenu(d.globalPosition, m),
                    child: InkWell(
                    onTap: () => setState(() {
                      selected = m;
                      selectedIndices.clear();
                      selectionAnchor = null;
                      nameHover = false;
                      editingName = false;
                      nameCtrl.text = m.name;
                    }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: on ? c.accentDim : c.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: on ? c.accent : c.line),
                      ),
                      child: Row(
                        children: [
                          Switch(
                            value: m.enabled,
                            activeThumbColor: c.accent,
                            onChanged: (v) {
                              m.enabled = v;
                              _save();
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(m.name, overflow: TextOverflow.ellipsis),
                                Text(
                                  m.state == 1
                                      ? 'Running'
                                      : m.state == 2
                                          ? 'Paused'
                                          : 'Stopped',
                                  style: TextStyle(color: c.muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete macro',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _deleteMacro(m),
                            icon: Icon(Icons.delete_outline, color: c.danger, size: 20),
                          ),
                        ],
                      ),
                    ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _editor(MacroDef m) {
    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              KeyedSubtree(
                key: nameKey,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: MouseRegion(
                    onEnter: (_) => setState(() => nameHover = true),
                    onExit: (_) => setState(() => nameHover = false),
                    cursor: SystemMouseCursors.text,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: (nameHover || editingName) ? c.accentDim : c.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (nameHover || editingName) ? c.accent : c.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: editingName
                                ? TextField(
                                    controller: nameCtrl,
                                    focusNode: nameFocus,
                                    autofocus: true,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    onSubmitted: (_) => _commitName(),
                                  )
                                : GestureDetector(
                                    onTap: () {
                                      setState(() => editingName = true);
                                      nameCtrl.text = m.name;
                                      nameCtrl.selection = TextSelection(baseOffset: 0, extentOffset: nameCtrl.text.length);
                                      WidgetsBinding.instance.addPostFrameCallback((_) => nameFocus.requestFocus());
                                    },
                                    child: Text(
                                      m.name,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.edit_outlined, size: 16, color: (nameHover || editingName) ? c.accent : c.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              KeyedSubtree(
                key: startKey,
                child: FilledButton(
                  onPressed: _togglePlay,
                  child: Text(
                    (m.state == 1 || m.state == 2)
                        ? 'Stop (${bindLabel(m.playVk > 0 ? m.playVk : settings.playVk, m.playVk > 0 ? m.playMods : settings.playMods)})'
                        : 'Start (${bindLabel(m.playVk > 0 ? m.playVk : settings.playVk, m.playVk > 0 ? m.playMods : settings.playMods)})',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => _playOnce(m),
                child: Text('Run once (${bindLabel(settings.onceVk, settings.onceMods)})'),
              ),
              const SizedBox(width: 8),
              _ghost('Pause', () => _pauseMacro(m)),
              _ghost('Stop', () => _stopMacro(m), color: c.danger),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _menuChip(
                label: 'Repeat',
                value: m.loopMode == 1
                    ? 'Count'
                    : m.loopMode == 2
                        ? 'Time limit'
                        : 'Infinite',
                items: const [
                  MenuChoice(0, 'Infinite'),
                  MenuChoice(1, 'Count'),
                  MenuChoice(2, 'Time limit'),
                ],
                onPicked: (int v) {
                  m.loopMode = v;
                  m.timeLimit = v == 2;
                  _save();
                  setState(() {});
                },
              ),
              _menuChip(
                label: 'Trigger',
                value: m.triggerMode == 1
                    ? 'Hold'
                    : m.triggerMode == 2
                        ? 'Once'
                        : 'Toggle',
                items: const [
                  MenuChoice(0, 'Toggle'),
                  MenuChoice(1, 'Hold down'),
                  MenuChoice(2, 'Run once'),
                ],
                onPicked: (int v) {
                  m.triggerMode = v;
                  _save();
                  setState(() {});
                },
              ),
              if (m.loopMode == 1)
                _numField('Count', m.repeatCount, (v) {
                  m.repeatCount = v;
                  _save();
                }),
              if (m.loopMode == 2 || m.timeLimit)
                _numField('Limit ms', m.durationMs, (v) {
                  m.durationMs = v;
                  m.timeLimit = true;
                  _save();
                }),
              _numField('Interval ms', m.intervalMs, (v) {
                m.intervalMs = v;
                _save();
              }),
              _menuChip(
                label: 'Speed',
                value: '${m.speed}x',
                items: const [
                  MenuChoice(0.5, '0.5x'),
                  MenuChoice(1.0, '1x'),
                  MenuChoice(1.5, '1.5x'),
                  MenuChoice(2.0, '2x'),
                  MenuChoice(3.0, '3x'),
                ],
                onPicked: (double v) {
                  m.speed = v;
                  _save();
                  setState(() {});
                },
              ),
              FilterChip(
                label: const Text('Humanized jitter'),
                selected: m.jitter,
                selectedColor: c.accentDim,
                checkmarkColor: c.accent,
                onSelected: (v) {
                  m.jitter = v;
                  _save();
                  setState(() {});
                },
              ),
              FilterChip(
                label: const Text('Keep delays'),
                selected: keepDelays,
                selectedColor: c.accentDim,
                checkmarkColor: c.accent,
                onSelected: (v) => setState(() => keepDelays = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            key: targetKey,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Window target', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(m.targetSummary, style: TextStyle(color: c.muted)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _ghost('Pick window', _pickWindow),
                    _ghost('Clear', () {
                      m
                        ..process = ''
                        ..title = ''
                        ..focusTarget = false;
                      _save();
                      setState(() {});
                    }),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Picked windows receive posted key/click messages and stay in the background. '
                  'You can keep using other apps. Some games ignore this (DirectInput / Raw Input).',
                  style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _editorTabBtn('Sequence', 0),
              const SizedBox(width: 8),
              _editorTabBtn('Keybinds', 1),
            ],
          ),
          const SizedBox(height: 12),
          if (_editorTab == 1) _macroKeybinds(m) else ...[
          Row(
            key: sequenceKey,
            children: [
              const Text('Sequence', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(width: 12),
              if (selectedIndices.isNotEmpty)
                Text('${selectedIndices.length} selected', style: TextStyle(color: c.muted, fontSize: 12)),
              const Spacer(),
              KeyedSubtree(
                key: insertKey,
                child: Builder(
                  builder: (ctx) => TextButton(
                    onPressed: () => _showInsertMenu(ctx, offset: buttonMenuOrigin(ctx)),
                    child: Text('Insert step', style: TextStyle(color: c.text)),
                  ),
                ),
              ),
              _ghost('Select all', () {
                selectedIndices
                  ..clear()
                  ..addAll(List.generate(m.steps.length, (i) => i));
                selectionAnchor = m.steps.isEmpty ? null : 0;
                setState(() {});
              }),
              _ghost('Duplicate', _duplicateSelected),
              _ghost('Move left', () => _nudgeSelected(-1)),
              _ghost('Move right', () => _nudgeSelected(1)),
              _ghost('Delete', _deleteSelected, color: c.danger),
            ],
          ),
          const SizedBox(height: 12),
          _sequenceBoard(m),
          ],
        ],
      ),
    );
  }

  Widget _editorTabBtn(String label, int index) {
    final on = _editorTab == index;
    return TextButton(
      onPressed: () => setState(() => _editorTab = index),
      style: TextButton.styleFrom(
        backgroundColor: on ? c.accentDim : Colors.transparent,
        foregroundColor: on ? c.accent : c.muted,
      ),
      child: Text(label),
    );
  }

  Widget _macroKeybinds(MacroDef m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Per-macro binds. Empty means the global Keybinds tab is used.',
            style: TextStyle(color: c.muted, fontSize: 12)),
        const SizedBox(height: 12),
        BindCaptureTile(
          label: 'Start',
          vk: m.playVk,
          mods: m.playMods,
          engine: engine,
          allowClear: true,
          onChanged: (vk, mods) {
            m.playVk = vk;
            m.playMods = mods;
            _syncBindEdges();
            _save();
            setState(() {});
          },
        ),
        BindCaptureTile(
          label: 'Pause',
          vk: m.pauseVk,
          mods: m.pauseMods,
          engine: engine,
          allowClear: true,
          onChanged: (vk, mods) {
            m.pauseVk = vk;
            m.pauseMods = mods;
            _syncBindEdges();
            _save();
            setState(() {});
          },
        ),
        BindCaptureTile(
          label: 'Stop',
          vk: m.stopVk,
          mods: m.stopMods,
          engine: engine,
          allowClear: true,
          onChanged: (vk, mods) {
            m.stopVk = vk;
            m.stopMods = mods;
            _syncBindEdges();
            _save();
            setState(() {});
          },
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _showKeybinds,
          child: Text('Open keybinds dialog', style: TextStyle(color: c.accent)),
        ),
      ],
    );
  }

  Widget _statusBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: c.panel,
      child: Row(
        children: [
          Text(status, style: TextStyle(color: c.muted, fontSize: 12)),
          const Spacer(),
          TextButton(
            onPressed: _updating ? null : () => _checkUpdates(),
            child: Text(updateStatus.isEmpty ? 'Check for updates' : updateStatus,
                style: TextStyle(fontSize: 12, color: c.accent)),
          ),
          const SizedBox(width: 12),
          Text(engine == null ? 'engine offline' : 'native ${engine != null ? 'ready' : ''}',
              style: TextStyle(color: engine == null ? c.danger : c.muted, fontSize: 12)),
          const SizedBox(width: 12),
          Text('v${Updater.current}', style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Text(
          'You have no macros, click + to add a macro',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.muted, fontSize: 16, height: 1.5),
        ),
      );

  Widget _ghost(String label, VoidCallback onTap, {Color? color}) {
    return TextButton(
      onPressed: onTap,
      child: Text(label, style: TextStyle(color: color ?? c.text)),
    );
  }

  Widget _numField(String label, int value, ValueChanged<int> onChanged) {
    return SizedBox(
      width: 140,
      child: TextField(
        controller: TextEditingController(text: '$value'),
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: c.muted, fontSize: 12),
          filled: true,
          fillColor: c.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onSubmitted: (v) => onChanged(int.tryParse(v) ?? value),
      ),
    );
  }

  Widget _menuChip<T>({
    required String label,
    required String value,
    required List<MenuChoice<T>> items,
    required ValueChanged<T> onPicked,
  }) {
    return Builder(
      builder: (ctx) {
        return InkWell(
          onTap: () async {
            final picked = await showAppMenu<T>(
              context: ctx,
              position: buttonMenuOrigin(ctx),
              items: items,
            );
            if (picked != null) onPicked(picked);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(color: c.muted, fontSize: 12)),
              const SizedBox(width: 8),
              Text(value, style: TextStyle(color: c.text, fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 16, color: c.muted),
            ]),
          ),
        );
      },
    );
  }

  Widget _sequenceBoard(MacroDef m) {
    return Focus(
      focusNode: sequenceFocus,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_reordering) return;
          sequenceFocus.requestFocus();
          if (selectedIndices.isEmpty) return;
          selectedIndices.clear();
          selectionAnchor = null;
          setState(() {});
        },
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: m.steps.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _gapSlot(0, terminal: true),
                    const SizedBox(height: 10),
                    Text(
                      'Right-click the + slot to insert or record here. Hold a square to drag.\n'
                      'Ctrl+click adds to the selection, Shift+click selects the range between two squares.',
                      style: TextStyle(color: c.muted, height: 1.5),
                    ),
                  ],
                )
              : Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 0,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < m.steps.length; i++) ...[
                      _gapSlot(i),
                      _stepSquare(m, i),
                    ],
                    _gapSlot(m.steps.length, terminal: true),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _gapSlot(int insertAt, {bool terminal = false}) {
    return DragTarget<int>(
      onWillAcceptWithDetails: (_) => !recording && selectedIndices.isNotEmpty,
      onAcceptWithDetails: (_) => _moveSelectedTo(insertAt),
      builder: (context, cand, _) {
        final hot = cand.isNotEmpty;
        if (terminal) {
          final plus = AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hot ? c.accentDim : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: hot ? c.accent : c.line),
            ),
            child: Column(
              children: [
                Text(
                  'end',
                  style: TextStyle(color: hot ? c.accent : c.muted, fontSize: 11),
                ),
                Expanded(
                  child: Center(
                    child: Icon(Icons.add, color: hot ? c.accent : c.muted),
                  ),
                ),
              ],
            ),
          );
          return Tooltip(
            message: 'Drop here · right-click to insert or record at the end',
            child: GestureDetector(
              onSecondaryTapDown: (d) => _showGapMenu(d.globalPosition, insertAt),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (insertAt > 0)
                    SizedBox(
                      width: hot ? 32 : 24,
                      height: 96,
                      child: Icon(
                        Icons.arrow_forward,
                        color: hot ? c.accent : c.muted,
                        size: 18,
                      ),
                    ),
                  plus,
                ],
              ),
            ),
          );
        }
        return Tooltip(
          message: 'Drop here · right-click to insert or record',
          child: GestureDetector(
            onSecondaryTapDown: (d) => _showGapMenu(d.globalPosition, insertAt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: hot ? 32 : 24,
              height: 96,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: hot ? c.accentDim : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                insertAt == 0 ? Icons.chevron_right : Icons.arrow_forward,
                color: hot ? c.accent : c.muted,
                size: 18,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showGapMenu(Offset pos, int at) async {
    final choice = await showAppMenu<String>(
      context: context,
      position: pos,
      items: const [
        MenuChoice('insert', 'Insert step…'),
        MenuChoice('record', 'Record here'),
      ],
    );
    if (!mounted || choice == null) return;
    if (choice == 'insert') {
      insertCursor = at;
      await _showInsertMenu(context, offset: pos);
    } else if (choice == 'record') {
      if (recording) {
        _toggleRecord();
      } else {
        _toggleRecord(insertAt: at);
      }
    }
  }

  Future<void> _showInsertMenu(BuildContext context, {Offset? offset}) async {
    try {
      final pos = offset ??
          Offset(MediaQuery.sizeOf(context).width * 0.45, MediaQuery.sizeOf(context).height * 0.28);
      final choice = await showAppMenu<String>(
        context: context,
        position: pos,
        items: const [
          MenuChoice('text', 'Type ASCII / text…'),
          MenuChoice('key', 'Keyboard tap…'),
          MenuChoice('click', 'Mouse click at X,Y…'),
          MenuChoice('wheel', 'Mouse wheel…'),
          MenuChoice('drag', 'Click-and-drag…'),
          MenuChoice('lclick', 'Left click (cursor)'),
          MenuChoice('rclick', 'Right click (cursor)'),
          MenuChoice('delay', 'Wait…'),
        ],
      );
      if (choice == null || !mounted) return;
      MacroStep? step;
      switch (choice) {
        case 'text':
          final t = await _prompt('Text to type', '');
          if (t != null) step = MacroStep(kind: 3, text: t);
        case 'key':
          final t = await _prompt('Key (A, Enter, F6…)', 'A');
          final vk = t == null ? null : vkFromName(t);
          if (vk != null) {
            _insert(MacroStep(kind: 0, code: vk, down: true));
            _insert(MacroStep(kind: 0, code: vk, down: false));
            return;
          }
        case 'click':
          final cap = await _promptClickXy();
          if (cap != null) {
            final macro = selected;
            if (macro != null && cap.process.isNotEmpty) {
              macro
                ..process = cap.process
                ..title = cap.title
                ..focusTarget = true;
            }
            _insert(MacroStep(kind: 1, code: 0, down: true, x: cap.x, y: cap.y));
            _insert(MacroStep(kind: 1, code: 0, down: false, x: cap.x, y: cap.y));
            return;
          }
        case 'wheel':
          final wheel = await _promptWheel();
          if (wheel != null) step = wheel;
        case 'drag':
          final drag = await _promptDrag();
          if (drag != null) step = drag;
        case 'lclick':
          _insert(MacroStep(kind: 1, code: 0, down: true));
          _insert(MacroStep(kind: 1, code: 0, down: false));
          return;
        case 'rclick':
          _insert(MacroStep(kind: 1, code: 1, down: true));
          _insert(MacroStep(kind: 1, code: 1, down: false));
          return;
        case 'delay':
          final t = await _prompt('Milliseconds', '50');
          final ms = int.tryParse(t ?? '');
          if (ms != null) step = MacroStep(kind: 2, delayMs: ms);
      }
      if (step != null) _insert(step);
    } finally {
      insertCursor = null;
    }
  }

  Widget _stepFace(MacroDef m, int i) {
    final step = m.steps[i];
    final on = selectedIndices.contains(i);
    final parts = step.shortLabel.split('\n');
    final glyph = parts.first;
    final detail = parts.length > 1 ? parts.sublist(1).join('\n') : '';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 96,
      height: 96,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: on ? c.accentDim : c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? c.accent : c.line, width: on ? 2 : 1),
      ),
      child: Column(
        children: [
          Text(
            '${i + 1}'.padLeft(2, '0'),
            style: TextStyle(color: c.muted, fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    glyph,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      color: step.enabled ? c.text : c.muted,
                    ),
                  ),
                  if (detail.isNotEmpty)
                    Text(
                      detail,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.muted, height: 1.2),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepSquare(MacroDef m, int i) {
    final count = selectedIndices.length;
    return Draggable<int>(
      data: i,
      maxSimultaneousDrags: recording ? 0 : 1,
      onDragStarted: () {
        _reordering = true;
        sequenceFocus.requestFocus();
        if (!selectedIndices.contains(i)) {
          selectedIndices
            ..clear()
            ..add(i);
          selectionAnchor = i;
          setState(() {});
        }
      },
      onDragEnd: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _reordering = false;
        });
      },
      feedback: Material(
        color: Colors.transparent,
        elevation: 8,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 96,
          height: 96,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _stepFace(m, i),
              if (count > 1)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: c.light ? Colors.white : c.bg,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _stepFace(m, i)),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (_) => !recording && selectedIndices.isNotEmpty,
        onAcceptWithDetails: (_) => _moveSelectedTo(i),
        builder: (context, cand, _) {
          final hot = cand.isNotEmpty;
          return Tooltip(
            message: '${m.steps[i].label}\nClick to select · Ctrl/Shift · hold to drag',
            child: GestureDetector(
              onTap: () {
                final keys = HardwareKeyboard.instance;
                _selectIndex(i, ctrl: keys.isControlPressed, shift: keys.isShiftPressed);
              },
              onSecondaryTapDown: (d) => _showGapMenu(d.globalPosition, i + 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    if (hot) BoxShadow(color: c.accent.withValues(alpha: 0.45), blurRadius: 10),
                  ],
                ),
                child: _stepFace(m, i),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<_CapturedClick?> _promptClickXy() async {
    return showDialog<_CapturedClick>(
      context: context,
      builder: (ctx) => _ClickXyDialog(engine: engine),
    );
  }

  Future<MacroStep?> _promptWheel() async {
    return showDialog<MacroStep>(
      context: context,
      builder: (ctx) => _WheelDialog(engine: engine),
    );
  }

  Future<MacroStep?> _promptDrag() async {
    return showDialog<MacroStep>(
      context: context,
      builder: (ctx) => _DragDialog(engine: engine),
    );
  }

  Future<String?> _prompt(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Insert')),
        ],
      ),
    );
  }
}

class _AddIntent extends Intent {
  const _AddIntent();
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _CapturedClick {
  const _CapturedClick(this.x, this.y, {this.process = '', this.title = ''});
  final int x;
  final int y;
  final String process;
  final String title;
}

class _ClickXyDialog extends StatefulWidget {
  const _ClickXyDialog({this.engine});
  final NativeEngine? engine;

  @override
  State<_ClickXyDialog> createState() => _ClickXyDialogState();
}

class _ClickXyDialogState extends State<_ClickXyDialog> {
  late final TextEditingController _ctrl;
  Timer? _poll;
  bool capturing = false;
  bool armed = false;
  String hint = '';
  Palette get c => AppTheme.of(context);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '0,0');
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _startClickPick() {
    if (widget.engine == null) {
      setState(() => hint = 'Native engine is offline.');
      return;
    }
    _poll?.cancel();
    setState(() {
      capturing = true;
      armed = false;
      hint = 'Click the target window.';
    });
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final e = widget.engine;
      if (e == null || !capturing) return;
      if (!armed) {
        if (!e.keyDown(0x01)) armed = true;
        return;
      }
      if (!e.keyDown(0x01)) return;
      final win = e.windowAtCursor();
      if (win != null && win.process.toLowerCase() == 'macrorelay') return;
      _finishCapture(e, win);
    });
  }

  void _startCapture() {
    if (widget.engine == null) {
      setState(() => hint = 'Native engine is offline.');
      return;
    }
    _poll?.cancel();
    setState(() {
      capturing = true;
      armed = false;
      hint = 'Hover the app, then press Control+Shift.';
    });
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final e = widget.engine;
      if (e == null || !capturing) return;
      final down = e.ctrlShiftDown();
      if (!down) {
        armed = true;
        return;
      }
      if (!armed) return;
      final win = e.windowAtCursor();
      if (win != null && win.process.toLowerCase() == 'macrorelay') return;
      _finishCapture(e, win);
    });
  }

  void _finishCapture(NativeEngine e, ({String process, String title, int pid})? win) {
    _poll?.cancel();
    capturing = false;
    final pos = e.cursorClient();
    if (pos == null || !mounted) {
      setState(() {
        capturing = false;
        hint = 'Could not read that window. Try again.';
      });
      return;
    }
    Navigator.pop(
      context,
      _CapturedClick(pos.x, pos.y, process: win?.process ?? '', title: win?.title ?? ''),
    );
  }

  _CapturedClick? _fromTyped() {
    final parts = _ctrl.text.split(',');
    if (parts.length != 2) return null;
    final x = int.tryParse(parts[0].trim());
    final y = int.tryParse(parts[1].trim());
    if (x == null || y == null) return null;
    return _CapturedClick(x, y);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: c.card,
      title: const Text('Click at X,Y'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Type client coordinates', style: TextStyle(color: c.muted, fontSize: 12)),
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '120,80',
                suffixIcon: IconButton(
                  tooltip: 'Click a point in the target window',
                  onPressed: capturing ? null : _startClickPick,
                  icon: Icon(Icons.center_focus_strong, color: c.accent),
                ),
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: capturing ? null : _startCapture,
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: capturing ? c.accentDim : c.panel,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: capturing ? c.accent : c.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.ads_click, size: 18, color: c.accent),
                        const SizedBox(width: 8),
                        const Text('Capture with Control+Shift', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      capturing
                          ? (hint.isEmpty ? 'Hover the app, then press Control+Shift.' : hint)
                          : 'Click here, move to the target window, hover the spot, then press Control+Shift. '
                              'Saves X,Y relative to that app.',
                      style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = _fromTyped();
            if (v != null) Navigator.pop(context, v);
          },
          child: const Text('Insert'),
        ),
      ],
    );
  }
}

({int x, int y})? _parseXy(String text) {
  final parts = text.split(',');
  if (parts.length != 2) return null;
  final x = int.tryParse(parts[0].trim());
  final y = int.tryParse(parts[1].trim());
  if (x == null || y == null) return null;
  return (x: x, y: y);
}

class _XyPickField extends StatefulWidget {
  const _XyPickField({required this.controller, required this.engine, this.label = 'X,Y'});
  final TextEditingController controller;
  final NativeEngine? engine;
  final String label;

  @override
  State<_XyPickField> createState() => _XyPickFieldState();
}

class _XyPickFieldState extends State<_XyPickField> {
  Timer? _poll;
  bool capturing = false;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _pick() {
    final e = widget.engine;
    if (e == null) return;
    _poll?.cancel();
    setState(() => capturing = true);
    var armed = false;
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!capturing) return;
      if (!armed) {
        if (!e.keyDown(0x01)) armed = true;
        return;
      }
      if (!e.keyDown(0x01)) return;
      final win = e.windowAtCursor();
      if (win != null && win.process.toLowerCase() == 'macrorelay') return;
      final pos = e.cursorClient();
      if (pos == null) return;
      widget.controller.text = '${pos.x},${pos.y}';
      _poll?.cancel();
      if (mounted) setState(() => capturing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    return TextField(
      controller: widget.controller,
      decoration: InputDecoration(
        labelText: capturing ? 'Click the target window…' : widget.label,
        suffixIcon: IconButton(
          tooltip: 'Pick on screen',
          onPressed: capturing ? null : _pick,
          icon: Icon(Icons.center_focus_strong, color: p.accent),
        ),
      ),
    );
  }
}

class _WheelDialog extends StatefulWidget {
  const _WheelDialog({this.engine});
  final NativeEngine? engine;

  @override
  State<_WheelDialog> createState() => _WheelDialogState();
}

class _WheelDialogState extends State<_WheelDialog> {
  bool up = true;
  final xy = TextEditingController();

  @override
  void dispose() {
    xy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    return AlertDialog(
      backgroundColor: p.card,
      title: const Text('Mouse wheel'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Up'),
                  selected: up,
                  onSelected: (_) => setState(() => up = true),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Down'),
                  selected: !up,
                  onSelected: (_) => setState(() => up = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _XyPickField(controller: xy, engine: widget.engine, label: 'X,Y (optional)'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final pos = _parseXy(xy.text);
            Navigator.pop(
              context,
              MacroStep(kind: 4, code: up ? 120 : -120, x: pos?.x, y: pos?.y),
            );
          },
          child: const Text('Insert'),
        ),
      ],
    );
  }
}

class _DragDialog extends StatefulWidget {
  const _DragDialog({this.engine});
  final NativeEngine? engine;

  @override
  State<_DragDialog> createState() => _DragDialogState();
}

class _DragDialogState extends State<_DragDialog> {
  final from = TextEditingController(text: '0,0');
  final to = TextEditingController(text: '100,100');
  int button = 0;

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    return AlertDialog(
      backgroundColor: p.card,
      title: const Text('Click-and-drag'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final item in const [(0, 'Left'), (1, 'Right'), (2, 'Middle')])
                    ChoiceChip(
                      label: Text(item.$2),
                      selected: button == item.$1,
                      onSelected: (_) => setState(() => button = item.$1),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _XyPickField(controller: from, engine: widget.engine, label: 'From X,Y'),
            const SizedBox(height: 12),
            _XyPickField(controller: to, engine: widget.engine, label: 'To X,Y'),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final a = _parseXy(from.text);
            final b = _parseXy(to.text);
            if (a == null || b == null) return;
            Navigator.pop(
              context,
              MacroStep(kind: 5, code: button, x: a.x, y: a.y, x2: b.x, y2: b.y),
            );
          },
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
