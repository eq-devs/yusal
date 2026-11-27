import 'package:flutter/widgets.dart';

import 'package:yusal/constant/theme.dart';
import 'package:yusal/features/shared/brand/yicons.dart';

export 'package:yusal/features/shared/brand/yicons.dart';

/// One of the Yusal icons in two colours, drawn like an [Icon]: it takes its
/// size and colour from the surrounding [IconTheme], and its one orange
/// piece from the theme accent.
///
/// The icons are glyphs of the YusalIcons font: the ink part and the orange
/// piece are two glyphs laid one over the other. Where one colour is enough,
/// `Icon(YIcons.x)` draws the same icon as a single glyph.
class YusalIcon extends StatelessWidget {
  const YusalIcon(this.icon,
      {super.key, this.size, this.color, this.accent, this.mono = false});
  final YIcon icon;
  final double? size;
  final Color? color;

  /// Colour of the icon's orange piece. Defaults to the accent.
  final Color? accent;

  /// Draws the orange piece in the icon colour too, for an unselected tab.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final piece = icon.accent;
    if (mono || piece == null) {
      return ExcludeSemantics(
          child: Icon(icon.glyph, size: size, color: color));
    }
    final s = size ?? IconTheme.of(context).size ?? 24;
    final hi = accent ?? YTokens.of(context).accent;
    final ink = icon.ink;
    return ExcludeSemantics(
        child: SizedBox.square(
            dimension: s,
            child: Stack(children: [
              if (ink != null) Icon(ink, size: s, color: color),
              Icon(piece, size: s, color: hi),
            ])));
  }
}
