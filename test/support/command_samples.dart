import 'package:yusal/features/editor/engine/core/house_core.dart';
import 'package:yusal/features/editor/engine/core/commands/command_catalog.dart';

/// Sample commands for [doc]: ordinary ones, ones that break a rule, and
/// ones with arguments of the wrong type.
List<(String, Map<String, dynamic>)> commandsFor(HouseDocument doc) {
  final out = <(String, Map<String, dynamic>)>[];
  void add(String kind, Map<String, dynamic> args) => out.add((kind, args));
  final fp = doc.footprint;
  for (final args in <Map<String, dynamic>>[
    {'width': fp.width + 500},
    {'depth': fp.depth + 500},
    {'width': fp.width - 500, 'depth': fp.depth - 500},
    {'width': 1000},
    {'width': fp.width + 0.5},
    {'width': null},
    {'depth': 5000000000},
    {},
  ]) {
    add('SetFootprintSize', args);
  }
  for (final value in [0, 90, 180, 270, 45, '90', null, 90.0]) {
    add('SetNorthAngle', {'value': value});
  }
  for (final dir in [AxisDir.V, AxisDir.H, 'V', null]) {
    final size = dir == AxisDir.H ? fp.depth : fp.width;
    for (final pos in [
      size ~/ 2 + 137,
      450,
      size - 450,
      100,
      size + 500,
      1.5
    ]) {
      add('AddAxis', {'dir': dir, 'pos': pos});
      for (final f in doc.floors.take(2)) {
        add('AddAxis', {'dir': dir, 'pos': pos, 'floorId': f.id});
      }
    }
  }
  add('AddAxis', {'dir': AxisDir.V, 'pos': 2000, 'floorId': 'no-such-floor'});
  add('AddAxis', {'dir': AxisDir.V});
  for (final (id, pos) in [
    ...doc.axes.global.map((a) => (a.id, a.pos)),
    ...doc.axes.floor.map((a) => (a.id, a.pos)),
  ].take(doc.floors.first.rooms.length > 30 ? 3 : 10)) {
    for (final next in [pos + 100, pos - 100, pos + 5000, pos - 5000, pos]) {
      add('MoveAxis', {'axisId': id, 'pos': next});
    }
    add('MoveAxis', {'axisId': id, 'pos': pos + 0.5});
    add('MoveAxis', {'axisId': id});
  }
  add('MoveAxis', {'axisId': '@left', 'pos': 500});
  add('MoveAxis', {'axisId': 'no-such-axis', 'pos': 500});
  add('MoveAxis', {'axisId': 7, 'pos': 500});
  for (final f in doc.floors) {
    for (final value in [
      f.height + 100,
      f.height - 100,
      500,
      90000,
      null,
      2.5
    ]) {
      add('SetFloorHeight', {'floorId': f.id, 'value': value});
    }
    for (final value in ['Attic', '', null, 5]) {
      add('RenameFloor', {'floorId': f.id, 'value': value});
    }
    for (final r in f.rooms.take(4)) {
      for (final value in ['Study', '', null, 5]) {
        add('RenameRoom', {'roomId': r.id, 'value': value});
      }
      for (final value in [
        RoomType.bedroom,
        RoomType.kitchen,
        RoomType.custom,
        'bedroom',
        null
      ]) {
        add('SetRoomType', {'roomId': r.id, 'value': value});
      }
    }
    final openings =
        f.openings.take(doc.floors.first.rooms.length > 30 ? 2 : 8).toList();
    for (final o in openings) {
      for (final args in <Map<String, dynamic>>[
        {'width': o.width - 100},
        {'width': o.width + 100},
        {'width': o.width + 6000},
        {'height': o.height + 100},
        {'height': 90000},
        {'sill': 300},
        {'width': 0},
        {'width': -5},
        {'width': o.width + 0.5},
        {'width': null},
        {'width': o.width - 50, 'height': o.height - 50, 'sill': 100},
        {},
      ]) {
        add('ResizeOpening', {'openingId': o.id, ...args});
      }
      for (final args in <Map<String, dynamic>>[
        {'hinge': 'end'},
        {'hinge': 'start'},
        {'opensTo': 'negativeSide'},
        {'hinge': 'end', 'opensTo': 'positiveSide'},
        {'hinge': 'sideways'},
        {'hinge': null},
        {'opensTo': OpeningSide.negativeSide},
        {},
      ]) {
        add('FlipDoor', {'openingId': o.id, ...args});
      }
      final other = openings[(openings.indexOf(o) + 1) % openings.length];
      for (final args in <Map<String, dynamic>>[
        {
          'position': {'type': 'center'}
        },
        {
          'position': {'type': 'fromStart', 'd': 100}
        },
        {
          'position': {'type': 'fromEnd', 'd': 100}
        },
        {
          'position': {'type': 'fromStart', 'd': 99999}
        },
        {
          'position': {'type': 'fromStart', 'd': -10}
        },
        {
          'position': {'type': 'fromStart'}
        },
        {
          'position': {'type': 'center', 'd': 5}
        },
        {
          'position': {'type': 'middle'}
        },
        {
          'position': {'type': 'fromStart', 'd': 10.5}
        },
        {'position': null},
        {},
        {
          'anchor': other.anchor,
          'position': {'type': 'center'}
        },
        {
          'anchor': other.anchor,
          'position': {'type': 'fromStart', 'd': 50}
        },
        {
          'anchor': other.anchor,
          'position': {'type': 'fromEnd', 'd': 50}
        },
        {
          'anchor': const BoundaryAnchor(
              axisId: 'nope', startAxisId: 'nope', endAxisId: 'nope'),
          'position': {'type': 'center'}
        },
        {
          'anchor': 'not an anchor',
          'position': {'type': 'center'}
        },
      ]) {
        add('MoveOpening', {'openingId': o.id, ...args});
      }
      add('DeleteOpening', {'openingId': o.id});
      add('SetMainEntrance', {'openingId': o.id});
    }
  }
  add('DeleteOpening', {'openingId': 'no-such-opening'});
  add('DeleteOpening', {'openingId': null});
  add('DeleteOpening', {'openingId': doc.mainEntranceOpeningId});
  add('SetMainEntrance', {'openingId': null});
  add('SetMainEntrance', {'openingId': 'no-such-opening'});
  add('SetMainEntrance', {'openingId': 5});
  add('SetMainEntrance', {});
  for (final kind in commandCatalog.map((c) => c.kind)) {
    add(kind, {});
    add(kind, {
      'floorId': 'missing',
      'roomId': 'missing',
      'openingId': 'missing',
      'axisId': 'missing',
      'value': 'x',
      'pos': 1
    });
  }
  return out;
}
