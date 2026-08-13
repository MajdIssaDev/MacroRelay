import 'package:flutter/material.dart';

import 'engine.dart';
import 'keycap.dart';
import 'theme.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.engine,
    required this.recording,
    required this.onRecord,
    required this.onStartAll,
    required this.onPauseAll,
    required this.onStopAll,
    required this.onInfo,
    required this.headerKey,
    required this.recordKey,
    required this.themeKey,
    required this.infoKey,
  });

  final NativeEngine? engine;
  final bool recording;
  final VoidCallback onRecord;
  final VoidCallback onStartAll;
  final VoidCallback onPauseAll;
  final VoidCallback onStopAll;
  final VoidCallback onInfo;
  final GlobalKey headerKey;
  final GlobalKey recordKey;
  final GlobalKey themeKey;
  final GlobalKey infoKey;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    final themes = AppTheme.controllerOf(context);
    return Material(
      color: p.panel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => engine?.windowDrag(),
                      child: Row(
                        children: [
                          const KeycapLogo(size: 22),
                          const SizedBox(width: 8),
                          Text(
                            'MACRORELAY',
                            style: TextStyle(
                              color: p.text,
                              letterSpacing: 3.2,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                  _WinBtn(icon: Icons.remove, onTap: () => engine?.windowMinimize(), color: p.muted),
                  _WinBtn(icon: Icons.crop_square, onTap: () => engine?.windowMaximizeToggle(), color: p.muted),
                  _WinBtn(icon: Icons.close, onTap: () => engine?.windowClose(), color: p.danger, hover: p.danger.withValues(alpha: 0.18)),
                ],
              ),
            ),
          ),
          Container(height: 1, color: p.line),
          SizedBox(
            key: headerKey,
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  _Ghost(label: 'Start all', onTap: onStartAll, color: p.text),
                  _Ghost(label: 'Pause all', onTap: onPauseAll, color: p.text),
                  _Ghost(label: 'Stop all', onTap: onStopAll, color: p.danger),
                  const Spacer(),
                  KeyedSubtree(
                    key: themeKey,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final pal in palettes)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Tooltip(
                              message: pal.label,
                              child: InkWell(
                                onTap: () => themes.setId(pal.id),
                                customBorder: const CircleBorder(),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: pal.accent,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                              color: p.id == pal.id ? p.text : pal.line,
                              width: p.id == pal.id ? 2 : 1,
                            ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  KeyedSubtree(
                    key: infoKey,
                    child: IconButton(
                      tooltip: 'How to use',
                      onPressed: onInfo,
                      icon: Icon(Icons.info_outline, color: p.accent, size: 20),
                    ),
                  ),
                  const SizedBox(width: 4),
                  KeyedSubtree(
                    key: recordKey,
                    child: FilledButton(
                      onPressed: onRecord,
                      style: FilledButton.styleFrom(
                        backgroundColor: recording ? p.danger : p.accent,
                        foregroundColor: p.light ? Colors.white : Colors.black,
                      ),
                      child: Text(recording ? 'Stop rec (F9)' : 'Record (F9)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: p.line),
        ],
      ),
    );
  }
}

class _WinBtn extends StatefulWidget {
  const _WinBtn({required this.icon, required this.onTap, required this.color, this.hover});
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final Color? hover;

  @override
  State<_WinBtn> createState() => _WinBtnState();
}

class _WinBtnState extends State<_WinBtn> {
  bool on = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => on = true),
      onExit: (_) => setState(() => on = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 40,
          height: 40,
          color: on ? (widget.hover ?? widget.color.withValues(alpha: 0.12)) : Colors.transparent,
          child: Icon(widget.icon, size: 14, color: widget.color),
        ),
      ),
    );
  }
}

class _Ghost extends StatelessWidget {
  const _Ghost({required this.label, required this.onTap, required this.color});
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TextButton(onPressed: onTap, child: Text(label, style: TextStyle(color: color)));
  }
}
