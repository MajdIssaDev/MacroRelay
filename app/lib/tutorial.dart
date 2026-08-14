import 'package:flutter/material.dart';

import 'theme.dart';

class TutorialStep {
  const TutorialStep({required this.title, required this.body, this.anchor});
  final String title;
  final String body;
  final GlobalKey? anchor;
}

Future<void> showTutorial(BuildContext context, List<TutorialStep> steps) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, anim, secondary) => TutorialOverlay(steps: steps),
    transitionBuilder: (ctx, anim, _, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}

class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({super.key, required this.steps});
  final List<TutorialStep> steps;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> with SingleTickerProviderStateMixin {
  static const _holePad = 14.0;
  static const _cardW = 360.0;
  static const _cardH = 220.0;

  int index = 0;
  late final AnimationController pulse;

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  Rect? _anchorRect() {
    final key = widget.steps[index].anchor;
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Rect? _holeRect(Rect? anchor) => anchor?.inflate(_holePad);

  Offset _cardOrigin(BuildContext context, Rect? anchor) {
    final size = MediaQuery.sizeOf(context);
    if (anchor == null) {
      return Offset((size.width - _cardW) / 2, size.height * 0.32);
    }
    final hole = _holeRect(anchor)!;
    const gap = 16.0;

    var top = hole.bottom + gap;
    if (top + _cardH > size.height - gap) {
      top = hole.top - _cardH - gap;
    }
    if (top < gap) {
      top = (hole.bottom + gap).clamp(gap, size.height - _cardH - gap);
    }

    var left = hole.center.dx - _cardW / 2;
    left = left.clamp(gap, size.width - _cardW - gap);

    final card = Rect.fromLTWH(left, top, _cardW, _cardH);
    if (card.overlaps(hole)) {
      top = hole.bottom + gap;
      if (top + _cardH > size.height - gap) {
        top = hole.top - _cardH - gap;
      }
      left = hole.center.dx - _cardW / 2;
      left = left.clamp(gap, size.width - _cardW - gap);
    }

    return Offset(left, top);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    final step = widget.steps[index];
    final last = index == widget.steps.length - 1;
    final anchor = _anchorRect();
    final hole = _holeRect(anchor);
    final cardOrigin = _cardOrigin(context, anchor);

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SpotlightPainter(
                    hole: hole,
                    color: Colors.black.withValues(alpha: 0.62),
                    glow: p.accent.withValues(alpha: 0.22 + pulse.value * 0.28),
                    border: p.accent,
                  ),
                );
              },
            ),
          ),
          if (hole != null)
            Positioned.fromRect(
              rect: hole,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 22,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: cardOrigin.dx,
            top: cardOrigin.dy,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              child: _Card(
                key: ValueKey(index),
                palette: p,
                title: step.title,
                body: step.body,
                index: index,
                total: widget.steps.length,
                last: last,
                onPrev: index == 0 ? null : () => setState(() => index--),
                onNext: () {
                  if (last) {
                    Navigator.pop(context);
                  } else {
                    setState(() => index++);
                  }
                },
                onEnd: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    super.key,
    required this.palette,
    required this.title,
    required this.body,
    required this.index,
    required this.total,
    required this.last,
    required this.onPrev,
    required this.onNext,
    required this.onEnd,
  });

  final Palette palette;
  final String title;
  final String body;
  final int index;
  final int total;
  final bool last;
  final VoidCallback? onPrev;
  final VoidCallback onNext;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Container(
      width: 360,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: p.accent.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(color: p.accent.withValues(alpha: 0.18), blurRadius: 28, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: p.text, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(body, style: TextStyle(color: p.muted, height: 1.45, fontSize: 13)),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('${index + 1}/$total', style: TextStyle(color: p.muted, fontSize: 12)),
              const Spacer(),
              TextButton(onPressed: onEnd, child: Text('End tutorial', style: TextStyle(color: p.muted))),
              if (onPrev != null) TextButton(onPressed: onPrev, child: Text('Previous', style: TextStyle(color: p.text))),
              FilledButton(
                onPressed: onNext,
                style: FilledButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.light ? Colors.white : Colors.black),
                child: Text(last ? 'Done' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter({required this.hole, required this.color, required this.glow, required this.border});
  final Rect? hole;
  final Color color;
  final Color glow;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(overlay, Paint()..color = color);
      return;
    }

    final inner = RRect.fromRectAndRadius(hole!, const Radius.circular(14));
    final cut = Path()..addRRect(inner);
    final dim = Path.combine(PathOperation.difference, overlay, cut);
    canvas.drawPath(dim, Paint()..color = color);

    // Draw glow and border outside the hole so highlighted UI is not covered.
    const glowBand = 8.0;
    const borderBand = 2.0;
    _drawRing(canvas, inner, glowBand, glow);
    _drawRing(canvas, inner, borderBand, border);
  }

  void _drawRing(Canvas canvas, RRect inner, double band, Color paintColor) {
    final outer = Path()..addRRect(inner.inflate(band));
    final ring = Path.combine(PathOperation.difference, outer, Path()..addRRect(inner));
    canvas.drawPath(
      ring,
      Paint()
        ..color = paintColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.color != color || old.glow != glow || old.border != border;
}
