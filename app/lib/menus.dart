import 'package:flutter/material.dart';

import 'theme.dart';

class MenuChoice<T> {
  const MenuChoice(this.value, this.label);
  final T value;
  final String label;
}

Future<T?> showAppMenu<T>({
  required BuildContext context,
  required Offset position,
  required List<MenuChoice<T>> items,
}) {
  final p = AppTheme.of(context);
  return showMenu<T>(
    context: context,
    color: p.card,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: p.line),
    ),
    position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
    items: [
      for (final item in items)
        PopupMenuItem<T>(
          value: item.value,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.panel.withValues(alpha: p.light ? 0.9 : 0.65),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.line.withValues(alpha: 0.7)),
            ),
            child: Text(item.label, style: TextStyle(color: p.text, fontSize: 13)),
          ),
        ),
    ],
  );
}

Offset buttonMenuOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  final origin = box.localToGlobal(Offset.zero);
  return origin + Offset(0, box.size.height + 4);
}
