import 'dart:ui' show Color, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/render3d/bsp.dart';
import 'package:yusal/render3d/scene_model.dart';

Face3 quad(List<Vec3> p, {List<Offset>? uv}) =>
    Face3(p, const Color(0xffffffff), doubleSided: true, uv: uv);

double area(List<Vec3> p) {
  var n = const Vec3(0, 0, 0);
  for (var i = 1; i < p.length - 1; i++)
    n = n + (p[i] - p[0]).cross(p[i + 1] - p[0]);
  return n.length / 2;
}

void main() {
  // A big wall at z = 0 and a small panel in front of it at z = 1. Their
  // average depths mislead a plain depth sort from grazing angles.
  final wall = quad(const [
    Vec3(-20, 0, 0),
    Vec3(20, 0, 0),
    Vec3(20, 3, 0),
    Vec3(-20, 3, 0),
  ]);
  final panel = quad(const [
    Vec3(15, 1, 1),
    Vec3(16, 1, 1),
    Vec3(16, 2, 1),
    Vec3(15, 2, 1),
  ]);

  List<Face3> order(BspTree tree, Vec3 eye) {
    final out = <Face3>[];
    tree.backToFront(eye, (f) => out.add(f.face));
    return out;
  }

  test('draws the face nearer the eye last, from either side', () {
    final tree = BspTree.build([panel, wall]);
    // Standing far to the left, close to the wall plane: the panel's centre
    // is farther than the wall's, yet it is in front of the wall.
    expect(order(tree, const Vec3(-40, 1.5, 4)), [wall, panel]);
    expect(order(tree, const Vec3(-40, 1.5, -4)), [panel, wall]);
  });

  test('splits a face crossing another plane, keeping area and texture', () {
    final cross = quad(const [
      Vec3(0, 0, -1),
      Vec3(0, 0, 1),
      Vec3(0, 2, 1),
      Vec3(0, 2, -1),
    ], uv: const [
      Offset(0, 0),
      Offset(1, 0),
      Offset(1, 1),
      Offset(0, 1),
    ]);
    final tree = BspTree.build([wall, cross]);
    final pieces = <Fragment>[];
    tree.backToFront(const Vec3(5, 1, 5), (f) {
      if (identical(f.face, cross)) pieces.add(f);
    });
    expect(pieces, hasLength(2));
    expect(pieces.fold(0.0, (s, f) => s + area(f.points)), closeTo(4, 1e-9));
    for (final f in pieces) {
      for (var i = 0; i < f.points.length; i++) {
        // u runs along z from −1 to 1 on this face.
        expect(f.uv![i].dx, closeTo((f.points[i].z + 1) / 2, 1e-9));
      }
    }
    expect(tree.fragmentCount, 3);
  });
}
