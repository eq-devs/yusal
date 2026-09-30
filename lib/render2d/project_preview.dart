import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../core/document/house_document.dart';
import '../core/geometry/derived_house.dart';
import 'floor_plan_painter.dart';

Future<List<int>?> renderProjectPreview(HouseDocument document) async {
  final derived = deriveHouse(document).floors.first;
  final width = document.footprint.width.toDouble(),
      depth = document.footprint.depth.toDouble();
  final size = width >= depth
      ? Size(512, 96 + 416 * depth / width)
      : Size(96 + 416 * width / depth, 512);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xfff6f7f3));
  final rooms = document.floors.first.rooms;
  FloorPlanPainter(derived.base, {for (final r in rooms) r.id: r.name},
          {for (final r in rooms) r.id: roomColors[r.type]!},
          openings: derived.openings,
          stairs: derived.stairs,
          northAngleDeg: document.footprint.northAngleDeg)
      .paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    final webp = await FlutterImageCompress.compressWithList(
        bytes.buffer.asUint8List(),
        minWidth: size.width.round(),
        minHeight: size.height.round(),
        quality: 80,
        format: CompressFormat.webp);
    if (webp.isEmpty) return null;
    return webp;
  } finally {
    image.dispose();
    picture.dispose();
  }
}
