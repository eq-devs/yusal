import 'package:flutter/widgets.dart';

import 'package:yusal/shared/ui/theme.dart';
import 'package:yusal/shared/brand/path_ops.dart';

part 'brand_data.dart';

/// Brand colours from the Yusal logo book.
abstract final class YusalBrand {
  static const orange = Color(0xffD86A2B);
  static const cream = Color(0xffF7F3EE);
  static const stone = Color(0xffC2B8AB);
  static const stoneOnLight = Color(0xff6F665D);
  static const ink = Color(0xff1E1C19);
}

enum _Piece { top, left, right, word }

/// The arch cut by a Y: design on top, the homeowner on the left and the
/// builder on the right. Colours follow the theme's brightness.
class YusalMark extends StatelessWidget {
  const YusalMark({super.key, this.height = 32});
  final double height;

  @override
  Widget build(BuildContext context) =>
      _Brand(_mark, _markSize, height, YTokens.of(context).dark, 'Yusal');
}

/// The mark and the "Yusal" wordmark side by side (the horizontal lockup).
class YusalLogo extends StatelessWidget {
  const YusalLogo({super.key, this.height = 30});
  final double height;

  @override
  Widget build(BuildContext context) =>
      _Brand(_lockup, _lockupSize, height, YTokens.of(context).dark, 'Yusal');
}

class _Brand extends StatelessWidget {
  const _Brand(this.parts, this.box, this.height, this.dark, this.label);
  final List<(_Piece, List<double>)> parts;
  final Size box;
  final double height;
  final bool dark;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
      label: label,
      image: true,
      child: SizedBox(
          width: height * box.width / box.height,
          height: height,
          child: CustomPaint(painter: _BrandPainter(parts, box, dark))));
}

final Map<List<(_Piece, List<double>)>, List<Path>> _paths = {};

class _BrandPainter extends CustomPainter {
  _BrandPainter(this.parts, this.box, this.dark);
  final List<(_Piece, List<double>)> parts;
  final Size box;
  final bool dark;

  Color _color(_Piece p) => switch (p) {
        _Piece.top => YusalBrand.orange,
        _Piece.left || _Piece.word => dark ? YusalBrand.cream : YusalBrand.ink,
        _Piece.right => dark ? YusalBrand.stone : YusalBrand.stoneOnLight,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final paths =
        _paths[parts] ??= [for (final (_, ops) in parts) pathFromOps(ops)];
    canvas.save();
    canvas.scale(size.height / box.height);
    for (var i = 0; i < parts.length; i++) {
      canvas.drawPath(
          paths[i],
          Paint()
            ..color = _color(parts[i].$1)
            ..isAntiAlias = true);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BrandPainter old) =>
      old.parts != parts || old.dark != dark;
}
