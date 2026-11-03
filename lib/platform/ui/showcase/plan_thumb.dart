import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import '../../../core/document/house_document.dart';
import '../../../core/geometry/derived_house.dart';
import '../../../core/serialization/house_codec.dart';
import '../../../render2d/floor_plan_painter.dart';
import '../theme.dart';

/// Decoded designs, kept so scrolling the feed never re-parses them.
final _cache = <String, (HouseDocument, DerivedHouse)?>{};

/// The design of a showcase, or null when its text cannot be read.
(HouseDocument, DerivedHouse)? decodeShowcase(String key, String houseText) =>
    _cache.putIfAbsent(key, () {
      try {
        final loaded = loadHouse(utf8.encode(houseText));
        if (!loaded.isSuccess) return null;
        final doc = loaded.document!;
        return (doc, deriveHouse(doc));
      } catch (_) {
        return null;
      }
    });

/// A live floor-plan drawing of a published design on a warm paper card,
/// in the current day / night colours.
class PlanThumb extends StatelessWidget {
  const PlanThumb(
      {super.key,
      required this.cacheKey,
      required this.houseText,
      this.floor = 0,
      this.labels = false,
      this.padding = 14});
  final String cacheKey, houseText;
  final int floor;
  final bool labels;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final y = YTokens.of(context);
    final t = Tokens.of(context);
    final design = decodeShowcase(cacheKey, houseText);
    final background =
        y.dark ? const Color(0xff241D17) : const Color(0xffF3EBDF);
    if (design == null)
      return ColoredBox(
          color: background,
          child: Center(
              child:
                  Icon(Icons.other_houses_outlined, size: 48, color: y.faint)));
    final (doc, derived) = design;
    final i = floor.clamp(0, doc.floors.length - 1);
    final rooms = doc.floors[i].rooms;
    return ColoredBox(
        color: background,
        child: CustomPaint(
            painter: FloorPlanPainter(derived.floors[i].base,
                {for (final r in rooms) r.id: labels ? r.name : ''}, const {},
                openings: derived.floors[i].openings,
                stairs: derived.floors[i].stairs,
                tokens: t,
                furniture: doc.extras.furniture
                    .where((f) => f.floorId == doc.floors[i].id)
                    .toList(),
                showDimensions: false,
                showLabels: labels,
                viewportInsets: EdgeInsets.all(padding)),
            child: const SizedBox.expand()));
  }
}
