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
  int index = 0;
  late final AnimationController pulse;

  @override
  void initState() {
    super.initState();
    pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
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

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    final step = widget.steps[index];
    final last = index == widget.steps.length - 1;
    final rect = _anchorRect();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: pulse,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SpotlightPainter(
                    hole: rect?.inflate(8),
                    color: Colors.black.withValues(alpha: 0.62),
                    glow: p.accent.withValues(alpha: 0.22 + pulse.value * 0.28),
                    border: p.accent,
                  ),
                );
              },
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: _cardLeft(context, rect),
            top: _cardTop(context, rect),
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

  double _cardLeft(BuildContext context, Rect? rect) {
    final w = MediaQuery.sizeOf(context).width;
    const cardW = 360.0;
    if (rect == null) return (w - cardW) / 2;
    return (rect.left).clamp(16, w - cardW - 16);
  }

  double _cardTop(BuildContext context, Rect? rect) {
    final h = MediaQuery.sizeOf(context).height;
    if (rect == null) return h * 0.32;
    final below = rect.bottom + 16;
    if (below + 220 < h - 16) return below;
    return (rect.top - 220).clamp(16, h - 236);
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
    final r = RRect.fromRectAndRadius(hole!, const Radius.circular(14));
    final cut = Path()..addRRect(r);
    final dim = Path.combine(PathOperation.difference, overlay, cut);
    canvas.drawPath(dim, Paint()..color = color);
    canvas.drawRRect(r.inflate(5), Paint()..color = glow..style = PaintingStyle.stroke..strokeWidth = 10);
    canvas.drawRRect(r, Paint()..color = border..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter old) =>
      old.hole != hole || old.color != color || old.glow != glow || old.border != border;
}
