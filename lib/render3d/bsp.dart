import 'dart:ui' show Offset;
import 'package:yusal/render3d/scene_model.dart';

/// A piece of a [Face3] after the BSP tree split it; [uv] follows the
/// split so textile patterns stay in place.
class Fragment {
  Fragment(this.face, this.points, this.uv);
  final Face3 face;
  final List<Vec3> points;
  final List<Offset>? uv;

  /// True when the face was not split.
  bool get whole => identical(points, face.points);
}

class _Node {
  _Node(this.normal, this.offset);
  final Vec3 normal;
  final double offset;
  final on = <Fragment>[];
  _Node? front;
  _Node? back;

  /// Box around every fragment in this subtree.
  Vec3 lo = const Vec3(0, 0, 0), hi = const Vec3(0, 0, 0);
}

/// Binary space partitioning tree of the scene faces.
///
/// The painter's algorithm sorted faces by average depth, which is wrong
/// whenever a large face (a slab, a long wall, a roof plane) and a small
/// one overlap: the small one could flicker in front of or behind it while
/// the camera turns. A BSP tree (the method classic software renderers and
/// CAD viewers used before depth buffers) splits faces along each other's
/// planes once, when the model is built, and then gives an exact
/// back-to-front order for any eye position by a simple tree walk.
class BspTree {
  BspTree._(this._root, this.fragmentCount);
  final _Node? _root;

  /// Faces after splitting; for tests and diagnostics.
  final int fragmentCount;

  static const eps = 1e-5;

  factory BspTree.build(List<Face3> faces) {
    final list = <Fragment>[
      for (final f in faces)
        if (f.points.length >= 3 && f.normal.length > 0.5)
          Fragment(f, f.points, f.uv)
    ];
    var count = 0;
    _Node? build(List<Fragment> frags) {
      if (frags.isEmpty) return null;
      final splitter = _choose(frags);
      final n = splitter.face.normal;
      final node = _Node(n, n.dot(splitter.points.first));
      final front = <Fragment>[];
      final back = <Fragment>[];
      for (final f in frags) {
        _split(f, n, node.offset, node.on, front, back);
      }
      count += node.on.length;
      node.front = build(front);
      node.back = build(back);
      var lo = const Vec3(double.infinity, double.infinity, double.infinity);
      var hi = const Vec3(-double.infinity, -double.infinity, -double.infinity);
      void grow(Vec3 a, Vec3 b) {
        lo = Vec3(a.x < lo.x ? a.x : lo.x, a.y < lo.y ? a.y : lo.y,
            a.z < lo.z ? a.z : lo.z);
        hi = Vec3(b.x > hi.x ? b.x : hi.x, b.y > hi.y ? b.y : hi.y,
            b.z > hi.z ? b.z : hi.z);
      }

      for (final f in node.on)
        for (final p in f.points) {
          grow(p, p);
        }
      for (final c in [node.front, node.back]) {
        if (c != null) grow(c.lo, c.hi);
      }
      node.lo = lo;
      node.hi = hi;
      return node;
    }

    final root = build(list);
    return BspTree._(root, count);
  }

  /// Pick a splitter among a few evenly spaced candidates: fewest splits,
  /// then the most even partition.
  static Fragment _choose(List<Fragment> frags) {
    if (frags.length <= 2) return frags.first;
    final step = (frags.length / 10).ceil();
    Fragment best = frags.first;
    var bestScore = double.infinity;
    for (var i = 0; i < frags.length; i += step) {
      final c = frags[i];
      final n = c.face.normal;
      final d = n.dot(c.points.first);
      var splits = 0;
      var front = 0;
      var back = 0;
      // Sample the others too on big inputs to keep the build fast.
      final sampleStep = frags.length > 400 ? (frags.length / 400).ceil() : 1;
      for (var j = 0; j < frags.length; j += sampleStep) {
        var pos = false;
        var neg = false;
        for (final p in frags[j].points) {
          final s = n.dot(p) - d;
          if (s > eps) pos = true;
          if (s < -eps) neg = true;
        }
        if (pos && neg) {
          splits++;
        } else if (pos) {
          front++;
        } else if (neg) {
          back++;
        }
      }
      final score = splits * 8.0 + (front - back).abs();
      if (score < bestScore) {
        bestScore = score;
        best = c;
      }
    }
    return best;
  }

  static void _split(Fragment f, Vec3 n, double d, List<Fragment> on,
      List<Fragment> front, List<Fragment> back) {
    final pts = f.points;
    final dist = [for (final p in pts) n.dot(p) - d];
    var pos = false;
    var neg = false;
    for (final s in dist) {
      if (s > eps) pos = true;
      if (s < -eps) neg = true;
    }
    if (!pos && !neg) {
      on.add(f);
      return;
    }
    if (!neg) {
      front.add(f);
      return;
    }
    if (!pos) {
      back.add(f);
      return;
    }
    final uv = f.uv;
    final fp = <Vec3>[];
    final bp = <Vec3>[];
    final fu = <Offset>[];
    final bu = <Offset>[];
    for (var i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      final a = pts[i];
      final b = pts[j];
      final da = dist[i];
      final db = dist[j];
      if (da >= -eps) {
        fp.add(a);
        if (uv != null) fu.add(uv[i]);
      }
      if (da <= eps) {
        bp.add(a);
        if (uv != null) bu.add(uv[i]);
      }
      if ((da > eps && db < -eps) || (da < -eps && db > eps)) {
        final t = da / (da - db);
        final m = Vec3.lerp(a, b, t);
        fp.add(m);
        bp.add(m);
        if (uv != null) {
          final mu = Offset.lerp(uv[i], uv[j], t)!;
          fu.add(mu);
          bu.add(mu);
        }
      }
    }
    if (fp.length >= 3) front.add(Fragment(f.face, fp, uv == null ? null : fu));
    if (bp.length >= 3) back.add(Fragment(f.face, bp, uv == null ? null : bu));
  }

  /// Visit every fragment from farthest to nearest as seen from [eye].
  ///
  /// [inView] gets the box around a whole subtree; when it says the box is
  /// out of sight (outside the view frustum) none of it is visited.
  void backToFront(Vec3 eye, void Function(Fragment) visit,
      {bool Function(Vec3 lo, Vec3 hi)? inView}) {
    void walk(_Node? node) {
      if (node == null) return;
      if (inView != null && !inView(node.lo, node.hi)) return;
      final side = node.normal.dot(eye) - node.offset;
      if (side >= 0) {
        walk(node.back);
        node.on.forEach(visit);
        walk(node.front);
      } else {
        walk(node.front);
        node.on.forEach(visit);
        walk(node.back);
      }
    }

    walk(_root);
  }
}
