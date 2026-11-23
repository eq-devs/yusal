import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/design_commands.dart';
import 'package:yusal/features/editor/engine/core/commands/document_edits.dart';
import 'package:yusal/features/editor/engine/core/commands/house_templates.dart';
import 'package:yusal/features/editor/engine/core/commands/kz_template.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

import 'perf/engine_bench.dart';

/// Commands of every kind done by copying objects, for [doc]: ordinary
/// ones, ones that break a rule, and ones with arguments of the wrong type.
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
  for (final kind in objectEditKinds) {
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

void main() {
  var n = 0;
  String id() => 'id${n++}';
  HouseDocument fixture(String name) =>
      loadHouse(File('test/fixtures/$name').readAsBytesSync()).document!;
  final houses = <String, HouseDocument>{
    for (final f in Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.house')))
      f.uri.pathSegments.last: fixture(f.uri.pathSegments.last),
    'kz': createKazakhTemplate('2026-10-14T00:00:00Z', id),
    'two': createTemplate('two', '2026-10-14T00:00:00Z', id),
    'five': createTemplate('five', '2026-10-14T00:00:00Z', id),
    'typical': composeDocument(benchMeta, typicalPlan()),
    'large': composeDocument(benchMeta, largePlan()),
  };

  test('every object edit kind is covered by the comparison', () {
    final kinds = {
      for (final h in houses.values)
        for (final c in commandsFor(h)) c.$1
    };
    expect(kinds, objectEditKinds);
  });

  for (final house in houses.entries) {
    test('${house.key}: copying objects gives what the file round trip gives',
        () {
      final doc = house.value;
      final quickDone = <String>{};
      var compared = 0;
      for (final (kind, args) in commandsFor(doc)) {
        final viaFile =
            executeDocumentCommand(doc, kind, args, id, objectEdits: false);
        final viaObjects = executeDocumentCommand(doc, kind, args, id);
        final what = '$kind $args';
        expect(viaObjects.accepted, viaFile.accepted, reason: what);
        expect(viaObjects.error, viaFile.error, reason: what);
        expect(viaObjects.document, viaFile.document, reason: what);
        compared++;

        // A refusal never comes from the quick path, and the quick path
        // never accepts what the round trip refuses.
        final quick = editDocumentObjects(doc, kind, args);
        if (quick != null && validateHouse(quick).isEmpty) {
          expect(viaFile.accepted || viaFile.error != null, isTrue);
          if (viaFile.accepted) {
            expect(quick, viaFile.document, reason: what);
            quickDone.add(kind);
          }
        }
      }
      expect(compared, greaterThan(50));
      // Which kinds a house can exercise depends on what is in it.
      expect(quickDone, containsAll(['SetFootprintSize', 'SetNorthAngle']));
      if (doc.floors.any((f) => f.openings.isNotEmpty)) {
        expect(
            quickDone,
            containsAll([
              'ResizeOpening',
              'MoveOpening',
              'DeleteOpening',
              'RenameRoom'
            ]));
      }
    });
  }

  test('a refusal carries the reason its wording used to imply', () {
    final seen = <String>{};
    for (final house in ['typical', 'full_two_floor_gable.house', 'two']) {
      final doc = houses[house]!;
      final top = doc.floors.last;
      final rooms = doc.floors.first.rooms;
      final commands = [
        ...commandsFor(doc),
        ('MergeRooms', {'roomIdA': rooms.first.id, 'roomIdB': rooms.last.id}),
        (
          'AddStair',
          {
            'floorId': top.id,
            'region': top.rooms.first.regions.first,
            'type': StairType.straight
          }
        ),
      ];
      for (final (kind, args) in commands) {
        final result = executeDocumentCommand(doc, kind, args, id);
        if (result.accepted) continue;
        final expected = reasonFromWords(result.error!);
        // A room outside the house now says so; its wording implied nothing.
        if (result.code == 'OUTSIDE') continue;
        expect(result.code, expected, reason: '$kind $args: ${result.error}');
        seen.add(result.code);
      }
    }
    expect(
        seen,
        containsAll([
          'SPACING',
          'NOT_A_DOOR',
          'TOP_FLOOR',
          'OVERLAP',
          'INVALID_VALUE'
        ]));
  });

  test('an edit keeps every object it does not change', () {
    final doc = houses['typical']!;
    final floor = doc.floors.first;
    final room = floor.rooms.first;
    final result = executeDocumentCommand(
        doc, 'RenameRoom', {'roomId': room.id, 'value': 'Study'}, id);
    final next = result.document!;
    expect(next.floors.first.rooms.first.name, 'Study');
    expect(identical(next.floors[1], doc.floors[1]), isTrue);
    expect(identical(next.floors.first.rooms[1], floor.rooms[1]), isTrue);
    expect(identical(next.floors.first.openings.first, floor.openings.first),
        isTrue);
    expect(identical(next.axes, doc.axes), isTrue);
    expect(identical(next.extras, doc.extras), isTrue);
    expect(next.meta, doc.meta);
    expect(next.schemaVersion, doc.schemaVersion);
  });

  test('a quick edit that breaks a rule is refused in the usual words', () {
    final doc = houses['typical']!;
    final opening = doc.floors.first.openings.first;
    final args = {'openingId': opening.id, 'width': opening.width + 60000};
    final viaFile = executeDocumentCommand(doc, 'ResizeOpening', args, id,
        objectEdits: false);
    final viaObjects = executeDocumentCommand(doc, 'ResizeOpening', args, id);
    expect(viaFile.accepted, isFalse);
    expect(viaObjects.error, viaFile.error);
  });
}

/// How a refusal's reason used to be worked out, from its wording.
String reasonFromWords(String message) =>
    message.contains('间距') || message.contains('两条线')
        ? 'SPACING'
        : message.contains('相邻房间')
            ? 'NOT_ADJACENT'
            : message.contains('主入口需要') || message.contains('只有门')
                ? 'NOT_A_DOOR'
                : message.contains('上方还有')
                    ? 'TOP_FLOOR'
                    : message.contains('重叠')
                        ? 'OVERLAP'
                        : 'INVALID_VALUE';
