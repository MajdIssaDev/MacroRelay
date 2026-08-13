import 'package:flutter/material.dart';

import 'theme.dart';

class KeycapLogo extends StatelessWidget {
  const KeycapLogo({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = AppTheme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KeycapPainter(p.accent, p.card, p.text)),
    );
  }
}

class _KeycapPainter extends CustomPainter {
  _KeycapPainter(this.accent, this.face, this.legend);
  final Color accent;
  final Color face;
  final Color legend;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.width * 0.22);
    final outer = RRect.fromRectAndRadius(Offset.zero & size, r);
    canvas.drawRRect(outer, Paint()..color = accent);
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.08, size.height * 0.08, size.width * 0.84, size.height * 0.72),
      Radius.circular(size.width * 0.16),
    );
    canvas.drawRRect(inner, Paint()..color = face);
    final tp = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TextStyle(
          color: legend,
          fontSize: size.width * 0.42,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height * 0.18));
  }

  @override
  bool shouldRepaint(covariant _KeycapPainter old) =>
      old.accent != accent || old.face != face || old.legend != legend;
}
