import 'package:flutter/widgets.dart';

import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/brand/path_ops.dart';

part 'brand_data.dart';

/// Brand colours from the Yusal "puzzle house" logo book.
abstract final class YusalBrand {
  /// The roof piece: design. Also the app's one accent.
  static const orange = Color(0xffF96A10);

  /// The left wall piece: community.
  static const sand = Color(0xffF2D2B2);

  /// The right wall piece: the builders.
  static const taupe = Color(0xff958276);

  static const cream = Color(0xffF7F3EE);
  static const ink = Color(0xff1E1C19);
}

enum _Piece { top, left, right, word }

/// Below this height the mark switches to the small-size cut, whose wider
/// gaps stay visible on screen.
const double _smallBelow = 32;

/// Three puzzle pieces that lock into a house: design is the roof,
/// the community the left wall and the builders the right wall.
///
/// [color] draws the whole mark in one colour (the logo book's mono
/// version), for places like an unselected tab.
class YusalMark extends StatelessWidget {
  const YusalMark({super.key, this.height = 32, this.color});
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final small = height < _smallBelow;
    return _Brand(small ? _markSmall : _mark, _markSize, height,
        YTokens.of(context).dark, 'Yusal', color);
  }
}

/// The mark and the "Yusal" wordmark side by side (the horizontal lockup).
class YusalLogo extends StatelessWidget {
  const YusalLogo({super.key, this.height = 30});
  final double height;

  @override
  Widget build(BuildContext context) {
    final small = height < _smallBelow;
    return _Brand(small ? _lockupSmall : _lockup, _lockupSize, height,
        YTokens.of(context).dark, 'Yusal', null);
  }
}

/// The mark as a tab icon: sized by the surrounding [IconTheme], in the
/// icon colour when unselected and in its three colours when [selected].
class YusalMarkIcon extends StatelessWidget {
  const YusalMarkIcon({super.key, this.selected = false, this.size});
  final bool selected;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    final ink = theme.color ?? YusalBrand.ink;
    return Semantics(
        excludeSemantics: true,
        child: SizedBox.square(
            dimension: s,
            child: Center(
                child: YusalMark(
                    height: s * 0.96,
                    color: selected
                        ? null
                        : ink.withValues(alpha: ink.a * (theme.opacity ?? 1))))));
  }
}

class _Brand extends StatelessWidget {
  const _Brand(
      this.parts, this.box, this.height, this.dark, this.label, this.mono);
  final List<(_Piece, List<double>)> parts;
  final Size box;
  final double height;
  final bool dark;
  final String label;
  final Color? mono;

  @override
  Widget build(BuildContext context) => Semantics(
      label: label,
      image: true,
      child: SizedBox(
          width: height * box.width / box.height,
          height: height,
          child: CustomPaint(painter: _BrandPainter(parts, box, dark, mono))));
}

final Map<List<(_Piece, List<double>)>, List<Path>> _paths = {};

class _BrandPainter extends CustomPainter {
  _BrandPainter(this.parts, this.box, this.dark, this.mono);
  final List<(_Piece, List<double>)> parts;
  final Size box;
  final bool dark;
  final Color? mono;

  // The three pieces keep their colours on light and dark grounds; only
  // the wordmark flips between ink and cream.
  Color _color(_Piece p) =>
      mono ??
      switch (p) {
        _Piece.top => YusalBrand.orange,
        _Piece.left => YusalBrand.sand,
        _Piece.right => YusalBrand.taupe,
        _Piece.word => dark ? YusalBrand.cream : YusalBrand.ink,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final paths =
        _paths[parts] ??= [for (final (_, ops) in parts) pathFromOps(ops)];
    canvas
      ..save()
      ..scale(size.height / box.height);
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
      old.parts != parts || old.dark != dark || old.mono != mono;
}
