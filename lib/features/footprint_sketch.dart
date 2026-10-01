import 'dart:math' as math;
import 'package:flutter/material.dart';

typedef FootprintDimensions = ({int width, int depth});

/// A pre-project sketch: cancelled drawings never enter project storage.
class FootprintSketch extends StatefulWidget {
  const FootprintSketch({super.key});
  @override
  State<FootprintSketch> createState() => _FootprintSketchState();
}

class _FootprintSketchState extends State<FootprintSketch> {
  Offset? start, end;
  final pointers = <int>{};
  bool cancelled = false, numericPreview = false;
  final width = TextEditingController(), depth = TextEditingController();
  FootprintDimensions? dimensions;
  double factor(Size size) => math.max(
      0.001,
      math.min(size.width - 48, size.height - 48) /
          (numericPreview && dimensions != null
              ? math.max(20000, math.max(dimensions!.width, dimensions!.depth))
              : 20000));
  void update(Offset point, Size size) {
    final clamped = Offset(point.dx.clamp(24, math.max(24, size.width - 24)),
        point.dy.clamp(24, math.max(24, size.height - 24)));
    start ??= clamped;
    end = clamped;
    final scale = factor(size);
    final w = ((start!.dx - end!.dx).abs() / scale / 100).round() * 100;
    final d = ((start!.dy - end!.dy).abs() / scale / 100).round() * 100;
    dimensions = w >= 3000 && d >= 3000 && w <= 100000 && d <= 100000
        ? (width: w, depth: d)
        : null;
    width.text = (w / 1000).toStringAsFixed(2);
    depth.text = (d / 1000).toStringAsFixed(2);
  }

  void editDimensions() {
    numericPreview = true;
    final w = double.tryParse(width.text), d = double.tryParse(depth.text);
    setState(() => dimensions = w != null &&
            d != null &&
            w.isFinite &&
            d.isFinite &&
            w >= 3 &&
            d >= 3 &&
            w <= 100 &&
            d <= 100
        ? (width: (w * 1000).round(), depth: (d * 1000).round())
        : null);
  }

  @override
  void dispose() {
    width.dispose();
    depth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('拖出房屋外形')),
      body: SafeArea(
          child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                  child: SizedBox(
                      height: math.max(460, viewport.maxHeight),
                      child: Column(children: [
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('从一个角拖到另一个角。1 格为 1 米，之后可以输入精确长宽。')),
                        Expanded(child:
                            LayoutBuilder(builder: (context, constraints) {
                          final size =
                              Size(constraints.maxWidth, constraints.maxHeight);
                          return Listener(
                              onPointerDown: (event) {
                                pointers.add(event.pointer);
                                if (pointers.length == 1)
                                  setState(() {
                                    cancelled = false;
                                    numericPreview = false;
                                    start = null;
                                    update(event.localPosition, size);
                                  });
                                if (pointers.length > 1)
                                  setState(() {
                                    cancelled = true;
                                    start = null;
                                    end = null;
                                    dimensions = null;
                                  });
                              },
                              onPointerUp: (event) =>
                                  pointers.remove(event.pointer),
                              onPointerCancel: (event) {
                                pointers.remove(event.pointer);
                                setState(() {
                                  cancelled = true;
                                  start = null;
                                  end = null;
                                  dimensions = null;
                                });
                              },
                              child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (details) {
                                    if (pointers.length > 1) return;
                                    if (start == null && !cancelled)
                                      setState(() =>
                                          update(details.localPosition, size));
                                  },
                                  onPanUpdate: (details) {
                                    if (!cancelled && pointers.length <= 1)
                                      setState(() =>
                                          update(details.localPosition, size));
                                  },
                                  child: CustomPaint(
                                      key: const ValueKey(
                                          'footprint-sketch-canvas'),
                                      size: size,
                                      painter: _SketchPainter(
                                          numericPreview && dimensions != null
                                              ? const Offset(24, 24)
                                              : start,
                                          numericPreview && dimensions != null
                                              ? Offset(
                                                  24 +
                                                      dimensions!.width *
                                                          factor(size),
                                                  24 +
                                                      dimensions!.depth *
                                                          factor(size))
                                              : end,
                                          factor(size),
                                          dimensions != null))));
                        })),
                        Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Column(children: [
                              Row(children: [
                                Expanded(
                                    child: TextField(
                                        controller: width,
                                        onChanged: (_) => editDimensions(),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                            labelText: '宽（米）'))),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: TextField(
                                        controller: depth,
                                        onChanged: (_) => editDimensions(),
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                            labelText: '长（米）')))
                              ]),
                              const SizedBox(height: 12),
                              Text(dimensions == null
                                  ? '长宽至少 3 米，可重新拖动或输入尺寸'
                                  : '外形已确定，可以继续分房'),
                              const SizedBox(height: 12),
                              SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                      onPressed: dimensions == null
                                          ? null
                                          : () => Navigator.pop(
                                              context, dimensions),
                                      child: const Text('使用这个外形'))),
                            ])),
                      ]))))));
}

class _SketchPainter extends CustomPainter {
  _SketchPainter(this.start, this.end, this.scale, this.valid);
  final Offset? start, end;
  final double scale;
  final bool valid;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xffdce2dd)
      ..strokeWidth = 0.6;
    final gap = math.max(1.0, 1000 * scale);
    for (double x = 24; x < size.width - 24; x += gap)
      canvas.drawLine(Offset(x, 24), Offset(x, size.height - 24), grid);
    for (double y = 24; y < size.height - 24; y += gap)
      canvas.drawLine(Offset(24, y), Offset(size.width - 24, y), grid);
    if (start == null || end == null) return;
    final rect = Rect.fromPoints(start!, end!);
    final color = valid ? const Color(0xff356a55) : const Color(0xffa14539);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRect(
        rect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
    for (final point in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight
    ]) canvas.drawCircle(point, 5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SketchPainter oldDelegate) => true;
}
