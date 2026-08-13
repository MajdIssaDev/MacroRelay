import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'models.dart';
import 'updater.dart';

const _bg = Color(0xFF070A0D);
const _panel = Color(0xFF10161D);
const _card = Color(0xFF161E27);
const _line = Color(0xFF243040);
const _accent = Color(0xFF3DDC97);
const _accentDim = Color(0xFF1B3D30);
const _text = Color(0xFFE8EEF4);
const _muted = Color(0xFF8A9AAB);
const _danger = Color(0xFFFF5C7A);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MacroRelayApp());
}

class MacroRelayApp extends StatelessWidget {
  const MacroRelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MacroRelay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          surface: _panel,
        ),
        fontFamily: 'Segoe UI',
      ),
      home: const DashboardPage(),
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
  final macros = <MacroDef>[];
  MacroDef? selected;
  MacroStep? selectedStep;
  bool keepDelays = true;
  bool recording = false;
  String status = 'Ready';
  String updateStatus = '';
  Timer? _poll;
  Timer? _stateTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _stateTimer = Timer.periodic(const Duration(milliseconds: 250), (_) => _refreshStates());
    _checkUpdates(silent: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _stateTimer?.cancel();
    engine?.stopAll();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = await libraryFile();
      if (await file.exists()) {
        macros
          ..clear()
          ..addAll(parseLibrary(await file.readAsString()));
      }
    } catch (_) {}
    if (macros.isEmpty) {
      macros.add(MacroDef(name: 'Macro 1'));
    }
    selected = macros.first;
    setState(() {});
  }

  Future<void> _save() async {
    final file = await libraryFile();
    await file.writeAsString(libraryJson(macros));
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
    setState(() => updateStatus = 'Checking updates…');
    try {
      final info = await Updater.check();
      if (info == null) {
        setState(() => updateStatus = silent ? '' : 'Up to date (${Updater.current})');
        return;
      }
      setState(() => updateStatus = 'Update ${info.latest} available');
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _card,
          title: Text('MacroRelay ${info.latest}'),
          content: Text('A new version is on GitHub Releases.\n\n${info.body}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Later')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Open release')),
          ],
        ),
      );
      if (go == true) {
        await Process.run('cmd', ['/c', 'start', '', info.url]);
      }
    } catch (err) {
      setState(() => updateStatus = silent ? '' : 'Update check failed');
    }
  }

  void _ensureNative(MacroDef m) {
    final e = engine;
    if (e == null) return;
    if (m.nativeId == 0) m.nativeId = e.createSession();
    e.clear(m.nativeId);
    e.setOptions(
      id: m.nativeId,
      intervalMs: m.intervalMs,
      speed: m.speed,
      jitter: m.jitter,
      loopMode: m.timeLimit ? 2 : m.loopMode,
      repeatCount: m.repeatCount,
      durationMs: m.durationMs,
      focusTarget: m.focusTarget,
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
      }
    }
  }

  void _play(MacroDef m) {
    if (engine == null) {
      setState(() => status = 'Native engine not loaded.');
      return;
    }
    if (m.steps.where((s) => s.enabled).isEmpty) {
      setState(() => status = 'Add steps, or record, first.');
      return;
    }
    _ensureNative(m);
    engine!.start(m.nativeId);
    setState(() => status = 'Playing ${m.name}');
  }

  void _insert(MacroStep step) {
    final m = selected;
    if (m == null) return;
    final i = selectedStep == null ? m.steps.length : m.steps.indexOf(selectedStep!) + 1;
    m.steps.insert(i.clamp(0, m.steps.length), step);
    selectedStep = step;
    _save();
    setState(() {});
  }

  void _toggleRecord() {
    final e = engine;
    final m = selected;
    if (e == null || m == null) return;
    if (recording) {
      e.recordStop();
      _poll?.cancel();
      recording = false;
      status = 'Recording stopped';
      _save();
      setState(() {});
      return;
    }
    e.recordStart(keepDelays: keepDelays);
    recording = true;
    status = keepDelays ? 'Recording (delays on)' : 'Recording (delays off)';
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      for (final ev in e.pollRecorded()) {
        if (ev.delayMs > 0 && keepDelays) {
          m.steps.add(MacroStep(kind: 2, delayMs: ev.delayMs));
        }
        m.steps.add(MacroStep(kind: ev.kind, code: ev.code, down: ev.down == 1));
      }
      setState(() {});
    });
    setState(() {});
  }

  Future<void> _pickWindow() async {
    final e = engine;
    final m = selected;
    if (e == null || m == null) return;
    setState(() => status = 'Click a window in 2 seconds…');
    await Future<void>.delayed(const Duration(seconds: 2));
    final info = e.windowAtCursor();
    if (info == null) return;
    m
      ..process = info.process
      ..title = info.title
      ..focusTarget = true;
    _save();
    setState(() => status = 'Target: ${info.process} — ${info.title}');
  }

  @override
  Widget build(BuildContext context) {
    final m = selected;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _AddIntent(),
      },
      child: Actions(
        actions: {
          _AddIntent: CallbackAction<_AddIntent>(onInvoke: (_) {
            _showInsertMenu(context);
            return null;
          }),
        },
        child: Scaffold(
          body: Column(
            children: [
              _topBar(),
              Expanded(
                child: Row(
                  children: [
                    _sidebar(),
                    Container(width: 1, color: _line),
                    Expanded(child: m == null ? _empty() : _editor(m)),
                  ],
                ),
              ),
              _statusBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          const Text('MACRORELAY',
              style: TextStyle(letterSpacing: 3, fontWeight: FontWeight.w700, fontSize: 13)),
          const Spacer(),
          _ghost('Start all', () {
            for (final m in macros.where((e) => e.enabled)) {
              _play(m);
            }
          }),
          _ghost('Pause all', () {
            for (final m in macros) {
              if (m.nativeId != 0) engine?.pause(m.nativeId);
            }
          }),
          _ghost('Stop all', () {
            engine?.stopAll();
            setState(() => status = 'Stopped');
          }, color: _danger),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _toggleRecord,
            style: FilledButton.styleFrom(
              backgroundColor: recording ? _danger : _accent,
              foregroundColor: Colors.black,
            ),
            child: Text(recording ? 'Stop rec' : 'Record'),
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    return SizedBox(
      width: 280,
      child: ColoredBox(
        color: _panel,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              child: Row(
                children: [
                  const Text('Macros', style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Add macro',
                    onPressed: () {
                      final m = MacroDef(name: 'Macro ${macros.length + 1}');
                      macros.add(m);
                      selected = m;
                      _save();
                      setState(() {});
                    },
                    icon: const Icon(Icons.add, color: _accent),
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
                  return InkWell(
                    onTap: () => setState(() {
                      selected = m;
                      selectedStep = null;
                    }),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: on ? _accentDim : _card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: on ? _accent : _line),
                      ),
                      child: Row(
                        children: [
                          Switch(
                            value: m.enabled,
                            activeThumbColor: _accent,
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
                                  style: const TextStyle(color: _muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
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
      color: _bg,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final v = await _prompt('Macro name', m.name);
                    if (v != null && v.trim().isNotEmpty) {
                      m.name = v.trim();
                      _save();
                      setState(() {});
                    }
                  },
                  child: Text(m.name,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                ),
              ),
              FilledButton(onPressed: () => _play(m), child: const Text('Start')),
              const SizedBox(width: 8),
              _ghost('Pause', () {
                if (m.nativeId != 0) engine?.pause(m.nativeId);
              }),
              _ghost('Stop', () {
                if (m.nativeId != 0) engine?.stop(m.nativeId);
              }, color: _danger),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _chipField(
                'Repeat',
                DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: m.loopMode,
                    dropdownColor: _card,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Infinite')),
                      DropdownMenuItem(value: 1, child: Text('Count')),
                      DropdownMenuItem(value: 2, child: Text('Time limit')),
                    ],
                    onChanged: (v) {
                      m.loopMode = v ?? 0;
                      m.timeLimit = m.loopMode == 2;
                      _save();
                      setState(() {});
                    },
                  ),
                ),
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
              _chipField(
                'Speed',
                DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    value: const [0.5, 1.0, 1.5, 2.0, 3.0].contains(m.speed) ? m.speed : 1.0,
                    dropdownColor: _card,
                    items: const [
                      DropdownMenuItem(value: 0.5, child: Text('0.5x')),
                      DropdownMenuItem(value: 1.0, child: Text('1x')),
                      DropdownMenuItem(value: 1.5, child: Text('1.5x')),
                      DropdownMenuItem(value: 2.0, child: Text('2x')),
                      DropdownMenuItem(value: 3.0, child: Text('3x')),
                    ],
                    onChanged: (v) {
                      m.speed = v ?? 1;
                      _save();
                      setState(() {});
                    },
                  ),
                ),
              ),
              FilterChip(
                label: const Text('Humanized jitter'),
                selected: m.jitter,
                selectedColor: _accentDim,
                checkmarkColor: _accent,
                onSelected: (v) {
                  m.jitter = v;
                  _save();
                  setState(() {});
                },
              ),
              FilterChip(
                label: const Text('Keep delays'),
                selected: keepDelays,
                selectedColor: _accentDim,
                checkmarkColor: _accent,
                onSelected: (v) => setState(() => keepDelays = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Window target', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(m.targetSummary, style: const TextStyle(color: _muted)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    _ghost(m.focusTarget ? 'Focus target' : 'Foreground', () {
                      m.focusTarget = !m.focusTarget;
                      _save();
                      setState(() {});
                    }),
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
                const Text(
                  'Focus target activates the window, then sends hardware-style SendInput. '
                  'Games using DirectInput/Raw Input still need that window focused — '
                  'MacroRelay does not inject into other processes or install input drivers.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Sequence', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const Spacer(),
              _ghost('Insert step', () => _showInsertMenu(context)),
              _ghost('Delete', () {
                if (selectedStep == null) return;
                m.steps.remove(selectedStep);
                selectedStep = null;
                _save();
                setState(() {});
              }, color: _danger),
            ],
          ),
          const SizedBox(height: 8),
          ...m.steps.asMap().entries.map((e) {
            final step = e.value;
            final on = selectedStep == step;
            return GestureDetector(
              onTap: () => setState(() => selectedStep = step),
              onSecondaryTapDown: (d) => _showInsertMenu(context, offset: d.globalPosition, replace: step),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: on ? _accentDim : _card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: on ? _accent : _line),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: step.enabled,
                      activeColor: _accent,
                      onChanged: (v) {
                        step.enabled = v ?? true;
                        _save();
                        setState(() {});
                      },
                    ),
                    Text('${e.key + 1}'.padLeft(2, '0'),
                        style: const TextStyle(color: _muted, fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(width: 12),
                    Expanded(child: Text(step.label)),
                  ],
                ),
              ),
            );
          }),
          if (m.steps.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: Text(
                'Right-click here to insert a key, click, or text step.\nRecord to capture down/up only — mouse travel is ignored.',
                style: TextStyle(color: _muted, height: 1.5),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusBar() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: _panel,
      child: Row(
        children: [
          Text(status, style: const TextStyle(color: _muted, fontSize: 12)),
          const Spacer(),
          TextButton(
            onPressed: () => _checkUpdates(),
            child: Text(updateStatus.isEmpty ? 'Check for updates' : updateStatus,
                style: const TextStyle(fontSize: 12, color: _accent)),
          ),
          const SizedBox(width: 12),
          Text(engine == null ? 'engine offline' : 'native ${engine != null ? 'ready' : ''}',
              style: TextStyle(color: engine == null ? _danger : _muted, fontSize: 12)),
          const SizedBox(width: 12),
          const Text('v${Updater.current}', style: TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _empty() => const Center(child: Text('Add a macro to begin', style: TextStyle(color: _muted)));

  Widget _ghost(String label, VoidCallback onTap, {Color color = _text}) {
    return TextButton(
      onPressed: onTap,
      child: Text(label, style: TextStyle(color: color)),
    );
  }

  Widget _chipField(String label, Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(width: 8),
        child,
      ]),
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
          labelStyle: const TextStyle(color: _muted, fontSize: 12),
          filled: true,
          fillColor: _card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onSubmitted: (v) => onChanged(int.tryParse(v) ?? value),
      ),
    );
  }

  Future<void> _showInsertMenu(BuildContext context, {Offset? offset, MacroStep? replace}) async {
    final pos = offset ?? const Offset(400, 300);
    final choice = await showMenu<String>(
      context: context,
      color: _card,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
      items: const [
        PopupMenuItem(value: 'text', child: Text('Type ASCII / text…')),
        PopupMenuItem(value: 'key', child: Text('Keyboard tap…')),
        PopupMenuItem(value: 'click', child: Text('Mouse click at X,Y…')),
        PopupMenuItem(value: 'lclick', child: Text('Left click (cursor)')),
        PopupMenuItem(value: 'rclick', child: Text('Right click (cursor)')),
        PopupMenuItem(value: 'delay', child: Text('Wait…')),
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
        final xy = await _prompt('Client X,Y (example 120,80)', '0,0');
        final parts = xy?.split(',');
        if (parts != null && parts.length == 2) {
          final x = int.tryParse(parts[0].trim());
          final y = int.tryParse(parts[1].trim());
          if (x != null && y != null) {
            _insert(MacroStep(kind: 1, code: 0, down: true, x: x, y: y));
            _insert(MacroStep(kind: 1, code: 0, down: false, x: x, y: y));
            return;
          }
        }
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
  }

  Future<String?> _prompt(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
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
