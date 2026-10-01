import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/geometry/derived_house.dart';

class HouseViewer extends StatefulWidget {
  const HouseViewer(
      {super.key,
      required this.house,
      this.onPick,
      this.showHint = true,
      this.resetToken = 0});
  final DerivedHouse house;
  final bool showHint;
  final int resetToken;
  final ValueChanged<SourceRef?>? onPick;
  @override
  State<HouseViewer> createState() => _HouseViewerState();
}

class _HouseViewerState extends State<HouseViewer> {
  double yaw = -math.pi / 6,
      pitch = 35 * math.pi / 180,
      zoom = 1,
      startZoom = 1;
  Offset pan = Offset.zero;
  int? floor;
  SourceRef? selected;
  _OrbitPainter? painter;
  @override
  void didUpdateWidget(covariant HouseViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resetToken != oldWidget.resetToken) {
      yaw = -math.pi / 6;
      pitch = 35 * math.pi / 180;
      zoom = 1;
      pan = Offset.zero;
    }
    if (floor != null) floor = floor!.clamp(0, widget.house.floors.length - 1);
    if (!identical(oldWidget.house, widget.house)) selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final m = floor ?? widget.house.floors.length - 1;
    return Column(children: [
      Row(children: [
        const SizedBox(width: 16),
        const Text('显示到'),
        Expanded(
            child: Slider(
                value: m.toDouble(),
                min: 0,
                max: math.max(1, widget.house.floors.length - 1).toDouble(),
                divisions: math.max(1, widget.house.floors.length - 1),
                onChanged: widget.house.floors.length > 1
                    ? (v) => setState(() => floor = v.round())
                    : null)),
        Text('${m + 1}楼'),
        IconButton(
            tooltip: '恢复视角',
            onPressed: () => setState(() {
                  yaw = -math.pi / 6;
                  pitch = 35 * math.pi / 180;
                  zoom = 1;
                  pan = Offset.zero;
                }),
            icon: const Icon(Icons.center_focus_strong))
      ]),
      Expanded(child: LayoutBuilder(builder: (context, constraints) {
        painter =
            _OrbitPainter(widget.house, m, yaw, pitch, zoom, pan, selected);
        return GestureDetector(
            onTapUp: (d) {
              final source = painter?.pick(d.localPosition);
              setState(() => selected = source);
              widget.onPick?.call(source);
            },
            onScaleStart: (_) => startZoom = zoom,
            onScaleUpdate: (d) => setState(() {
                  if (d.pointerCount == 1) {
                    yaw += d.focalPointDelta.dx / 140;
                    pitch = (pitch + d.focalPointDelta.dy / 180)
                        .clamp(5 * math.pi / 180, 85 * math.pi / 180);
                  } else {
                    zoom = (startZoom * d.scale).clamp(0.2, 6);
                    pan += d.focalPointDelta;
                  }
                }),
            child: CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: painter));
      })),
      if (widget.showHint)
        const Padding(
            padding: EdgeInsets.all(12),
            child: Text('单指旋转 · 双指缩放和平移', style: TextStyle(fontSize: 12)))
    ]);
  }
}

class _Face {
  const _Face(this.path, this.depth, this.color, this.source);
  final Path path;
  final double depth;
  final Color color;
  final SourceRef? source;
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.house, this.maxFloor, this.yaw, this.pitch, this.zoom,
      this.pan, this.selected);
  final DerivedHouse house;
  final int maxFloor;
  final double yaw, pitch, zoom;
  final Offset pan;
  final SourceRef? selected;
  List<_Face> faces = [];
  SourceRef? pick(Offset p) {
    for (final f in faces.reversed) if (f.path.contains(p)) return f.source;
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.min(size.width, size.height) *
        0.70 /
        math.max(math.max(house.width, house.depth), house.height) *
        zoom;
    final cos = math.cos(yaw),
        sin = math.sin(yaw),
        cp = math.cos(pitch),
        sp = math.sin(pitch);
    ({Offset point, double depth}) project(Point3 p) {
      final x = p.x - house.width / 2,
          y = p.y - house.depth / 2,
          z = p.z - house.height / 2;
      final rx = x * cos - y * sin, ry = x * sin + y * cos;
      return (
        point: Offset(size.width / 2 + rx * scale,
                size.height / 2 + (ry * sp - z * cp) * scale) +
            pan,
        depth: ry * cp + z * sp
      );
    }

    const colors = {
      'wall': Color(0xfff4f1e9),
      'wallTemporary': Color(0x808d9690),
      'slab': Color(0xffbfc4be),
      'glass': Color(0x665ea7c8),
      'door': Color(0xffa87b4c),
      'stair': Color(0xffbabeb8),
      'roof': Color(0xff545e57)
    };
    faces = [];
    for (final element in house.scene3d) {
      if (element.floorIndex == -1
          ? maxFloor < house.floors.length - 1
          : element.floorIndex > maxFloor) continue;
      for (final indices in element.faces) {
        final points =
            indices.map((i) => project(element.vertices[i])).toList();
        final path = Path()
          ..moveTo(points.first.point.dx, points.first.point.dy);
        for (final p in points.skip(1)) path.lineTo(p.point.dx, p.point.dy);
        path.close();
        var color = colors[element.materialRole] ?? Colors.grey;
        if (element.source != null && element.source == selected)
          color = const Color(0xff8ba86b);
        final a = element.vertices[indices[0]],
            b = element.vertices[indices[1]],
            c = element.vertices[indices[2]];
        final ux = b.x - a.x,
            uy = b.y - a.y,
            uz = b.z - a.z,
            vx = c.x - a.x,
            vy = c.y - a.y,
            vz = c.z - a.z;
        final nx = uy * vz - uz * vy,
            ny = uz * vx - ux * vz,
            nz = ux * vy - uy * vx;
        final length = math.sqrt(nx * nx + ny * ny + nz * nz);
        final shade = length == 0
            ? 1.0
            : 0.72 + 0.28 * ((nx * 0.3 - ny * 0.4 + nz * 0.85) / length).abs();
        color = Color.from(
            alpha: color.a,
            red: color.r * shade,
            green: color.g * shade,
            blue: color.b * shade);
        faces.add(_Face(
            path,
            points.fold<double>(0, (sum, p) => sum + p.depth) / points.length,
            color,
            element.source));
      }
    }
    faces.sort((a, b) => a.depth.compareTo(b.depth));
    final paint = Paint();
    for (final f in faces) {
      paint
        ..color = f.color
        ..style = PaintingStyle.fill;
      canvas.drawPath(f.path, paint);
      paint
        ..color = const Color(0xff384239).withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5;
      canvas.drawPath(f.path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter old) => true;
}
