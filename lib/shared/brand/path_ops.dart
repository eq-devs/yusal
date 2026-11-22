import 'dart:ui';

/// Builds a [Path] from the flat op list the generated brand files use:
/// 0 x y = moveTo, 1 x y = lineTo, 2 x1 y1 x2 y2 x y = cubicTo, 3 = close.
Path pathFromOps(List<double> ops) {
  final p = Path();
  var i = 0;
  while (i < ops.length) {
    switch (ops[i].toInt()) {
      case 0:
        p.moveTo(ops[i + 1], ops[i + 2]);
        i += 3;
      case 1:
        p.lineTo(ops[i + 1], ops[i + 2]);
        i += 3;
      case 2:
        p.cubicTo(ops[i + 1], ops[i + 2], ops[i + 3], ops[i + 4], ops[i + 5],
            ops[i + 6]);
        i += 7;
      default:
        p.close();
        i += 1;
    }
  }
  return p;
}
