import 'dart:async';

import 'package:flutter/material.dart';

import 'engine.dart';
import 'models.dart';
import 'settings.dart';
import 'theme.dart';

class BindCaptureTile extends StatefulWidget {
  const BindCaptureTile({
    super.key,
    required this.label,
    required this.vk,
    required this.mods,
    required this.engine,
    required this.onChanged,
    this.allowClear = false,
  });

  final String label;
  final int vk;
  final int mods;
  final NativeEngine? engine;
  final void Function(int vk, int mods) onChanged;
  final bool allowClear;

  @override
  State<BindCaptureTile> createState() => _BindCaptureTileState();
}

class _BindCaptureTileState extends State<BindCaptureTile> {
  bool capturing = false;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _start() {
    final e = widget.engine;
    if (e == null) return;
    _poll?.cancel();
    setState(() => capturing = true);
    var armed = false;
    _poll = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!capturing) return;
      final vk = e.anyKeyDown();
      if (!armed) {
        if (vk == 0) armed = true;
        return;
      }
      if (vk == 0x1B) {
        _stop();
        return;
      }
      if (vk == 0) return;
      final mods = e.modifierBits();
      widget.onChanged(vk, mods);
      _stop();
    });
  }

  void _stop() {
    _poll?.cancel();
    if (mounted) setState(() => capturing = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(widget.label, style: TextStyle(color: p.text)),
          ),
          Expanded(
            child: OutlinedButton(
              onPressed: capturing ? null : _start,
              child: Text(
                capturing ? 'Press a key…' : bindLabel(widget.vk, widget.mods),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (widget.allowClear)
            IconButton(
              tooltip: 'Clear',
              onPressed: () => widget.onChanged(0, 0),
              icon: Icon(Icons.clear, size: 18, color: p.muted),
            ),
        ],
      ),
    );
  }
}

Future<void> showKeybindsDialog({
  required BuildContext context,
  required NativeEngine? engine,
  required AppSettings settings,
  required MacroDef? macro,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => DefaultTabController(
      length: macro == null ? 1 : 2,
      child: AlertDialog(
        backgroundColor: AppTheme.of(context).card,
        title: const Text('Keybinds'),
        content: SizedBox(
          width: 460,
          height: 420,
          child: Column(
            children: [
              TabBar(
                labelColor: AppTheme.of(context).accent,
                unselectedLabelColor: AppTheme.of(context).muted,
                tabs: [
                  const Tab(text: 'Global'),
                  if (macro != null) const Tab(text: 'This macro'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _GlobalBinds(engine: engine, settings: settings, onChanged: onChanged),
                    if (macro != null)
                      _MacroBinds(engine: engine, macro: macro, onChanged: onChanged),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ),
    ),
  );
}

class _GlobalBinds extends StatefulWidget {
  const _GlobalBinds({required this.engine, required this.settings, required this.onChanged});
  final NativeEngine? engine;
  final AppSettings settings;
  final VoidCallback onChanged;

  @override
  State<_GlobalBinds> createState() => _GlobalBindsState();
}

class _GlobalBindsState extends State<_GlobalBinds> {
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    final settings = widget.settings;
    final engine = widget.engine;
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        Text('These apply to the selected macro unless it has its own bind.',
            style: TextStyle(color: p.muted, fontSize: 12)),
        const SizedBox(height: 12),
        BindCaptureTile(
          label: 'Start / toggle',
          vk: settings.playVk,
          mods: settings.playMods,
          engine: engine,
          onChanged: (vk, mods) {
            setState(() {
              settings.playVk = vk;
              settings.playMods = mods;
            });
            settings.save();
            widget.onChanged();
          },
        ),
        BindCaptureTile(
          label: 'Run once',
          vk: settings.onceVk,
          mods: settings.onceMods,
          engine: engine,
          onChanged: (vk, mods) {
            setState(() {
              settings.onceVk = vk;
              settings.onceMods = mods;
            });
            settings.save();
            widget.onChanged();
          },
        ),
        BindCaptureTile(
          label: 'Record',
          vk: settings.recordVk,
          mods: settings.recordMods,
          engine: engine,
          onChanged: (vk, mods) {
            setState(() {
              settings.recordVk = vk;
              settings.recordMods = mods;
            });
            settings.save();
            widget.onChanged();
          },
        ),
        BindCaptureTile(
          label: 'Panic stop',
          vk: settings.panicVk,
          mods: settings.panicMods,
          engine: engine,
          onChanged: (vk, mods) {
            setState(() {
              settings.panicVk = vk;
              settings.panicMods = mods;
            });
            settings.save();
            widget.onChanged();
          },
        ),
      ],
    );
  }
}

class _MacroBinds extends StatefulWidget {
  const _MacroBinds({required this.engine, required this.macro, required this.onChanged});
  final NativeEngine? engine;
  final MacroDef macro;
  final VoidCallback onChanged;

  @override
  State<_MacroBinds> createState() => _MacroBindsState();
}

class _MacroBindsState extends State<_MacroBinds> {
  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    final macro = widget.macro;
    final engine = widget.engine;
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        Text('Leave empty to use the global binds. Hold-down loops while the start key is held.',
            style: TextStyle(color: p.muted, fontSize: 12)),
        const SizedBox(height: 12),
        Text('Trigger', style: TextStyle(color: p.muted, fontSize: 12)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final item in const [
              (0, 'Toggle'),
              (1, 'Hold down'),
              (2, 'Run once'),
            ])
              ChoiceChip(
                label: Text(item.$2),
                selected: macro.triggerMode == item.$1,
                onSelected: (_) {
                  setState(() => macro.triggerMode = item.$1);
                  widget.onChanged();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        BindCaptureTile(
          label: 'Start',
          vk: macro.playVk,
          mods: macro.playMods,
          engine: engine,
          allowClear: true,
          onChanged: (vk, mods) {
            setState(() {
              macro.playVk = vk;
              macro.playMods = mods;
            });
            widget.onChanged();
          },
        ),
        BindCaptureTile(
          label: 'Pause',
          vk: macro.pauseVk,
          mods: macro.pauseMods,
          engine: engine,
          allowClear: true,
          onChanged: (vk, mods) {
            setState(() {
              macro.pauseVk = vk;
              macro.pauseMods = mods;
            });
            widget.onChanged();
          },
        ),
        BindCaptureTile(
          label: 'Stop',
          vk: macro.stopVk,
          mods: macro.stopMods,
          engine: engine,
          allowClear: true,
          onChanged: (vk, mods) {
            setState(() {
              macro.stopVk = vk;
              macro.stopMods = mods;
            });
            widget.onChanged();
          },
        ),
      ],
    );
  }
}

Future<void> showAppSettingsDialog({
  required BuildContext context,
  required NativeEngine? engine,
  required AppSettings settings,
  required VoidCallback onExportLibrary,
  required VoidCallback onImportLibrary,
  required VoidCallback onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final p = AppTheme.of(ctx);
          return AlertDialog(
            backgroundColor: p.card,
            title: const Text('Settings'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Run on Windows startup'),
                    subtitle: Text('Launches in the tray', style: TextStyle(color: p.muted, fontSize: 12)),
                    value: settings.runOnStartup,
                    onChanged: (v) {
                      settings.runOnStartup = v;
                      engine?.startupSet(v);
                      settings.save();
                      setLocal(() {});
                      onChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Close to tray'),
                    subtitle: Text('X hides the window instead of quitting',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                    value: settings.closeToTray,
                    onChanged: (v) {
                      settings.closeToTray = v;
                      engine?.closeToTray(v);
                      engine?.traySet(v || settings.runOnStartup);
                      settings.save();
                      setLocal(() {});
                      onChanged();
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Audio cues'),
                    subtitle: Text('Beeps on start, pause, and stop',
                        style: TextStyle(color: p.muted, fontSize: 12)),
                    value: settings.audioCues,
                    onChanged: (v) {
                      settings.audioCues = v;
                      settings.save();
                      setLocal(() {});
                      onChanged();
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Library', style: TextStyle(color: p.muted, fontSize: 12)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onExportLibrary,
                          child: const Text('Export JSON'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onImportLibrary,
                          child: const Text('Import JSON'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
            ],
          );
        },
      );
    },
  );
}
