import 'package:flutter/widgets.dart';

import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/brand/brand.dart';
import 'package:yusal/features/shared/brand/path_ops.dart';

part 'yicon_data.dart';

/// One of the Yusal icons, drawn like an [Icon]: it takes its size and
/// colour from the surrounding [IconTheme], and its one orange detail from
/// the theme accent.
class YusalIcon extends StatelessWidget {
  const YusalIcon(this.icon,
      {super.key, this.size, this.color, this.accent, this.mono = false});
  final YIcon icon;
  final double? size;
  final Color? color;

  /// Colour of the icon's one highlighted detail. Defaults to the accent.
  final Color? accent;

  /// Draws the highlighted detail in the icon colour too, for an
  /// unselected tab.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final ink = color ?? theme.color ?? const Color(0xff1E1C19);
    final hi = mono ? ink : accent ?? YTokens.of(context).accent;
    return Semantics(
        excludeSemantics: true,
        child: SizedBox.square(
            dimension: s,
            child: CustomPaint(
                painter: _YIconPainter(icon,
                    ink.withValues(alpha: ink.a * (theme.opacity ?? 1)), hi))));
  }
}

enum _R { ink, accent, stone, knock }

class _Stroke {
  const _Stroke(this.width, this.cap, this.join);
  final double width;
  final StrokeCap cap;
  final StrokeJoin join;
}

class _S {
  const _S(this.role, this.stroke, this.ops);
  final _R role;
  final _Stroke? stroke;
  final List<double> ops;
}

final Map<YIcon, List<(_S, Path)>> _cache = {};

class _YIconPainter extends CustomPainter {
  _YIconPainter(this.icon, this.ink, this.accent);
  final YIcon icon;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final shapes = _cache[icon] ??= [
      for (final s in _shapes[icon]!) (s, pathFromOps(s.ops))
    ];
    // The drawings sit in 10–86 of their 96 grid; that band fills the box,
    // so a Yusal icon reads as large as a Material one at the same size.
    final k = size.shortestSide / 76;
    // A layer so "knock-out" strokes cut through to whatever is behind.
    canvas
      ..saveLayer(Offset.zero & size, Paint())
      ..scale(k)
      ..translate(-10, -10);
    for (final (s, path) in shapes) {
      final paint = Paint()..isAntiAlias = true;
      switch (s.role) {
        case _R.ink:
          paint.color = ink;
        case _R.accent:
          paint.color = accent;
        case _R.stone:
          paint.color = YusalBrand.stone;
        case _R.knock:
          paint.blendMode = BlendMode.clear;
      }
      final st = s.stroke;
      if (st != null) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = st.width
          ..strokeCap = st.cap
          ..strokeJoin = st.join;
      }
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_YIconPainter old) =>
      old.icon != icon || old.ink != ink || old.accent != accent;
}
