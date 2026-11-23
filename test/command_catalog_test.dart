import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/features/editor/engine/core/commands/command_catalog.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/house_core.dart';

import 'perf/engine_bench.dart';

const commandsFile = 'docs/engine_commands.json';

void main() {
  final state = typicalPlan();
  final doc = composeDocument(benchMeta, state);
  final floor = doc.floors.first;
  final ctx = benchContext;

  CommandResult typed(String kind, Map<String, dynamic> args) =>
      executeCommand(state, DesignCommand(kind, args), ctx);
  CommandResult json(String kind, Map<String, Object?> args) =>
      // Through text, as it would arrive from another process.
      executeJsonCommand(state, kind,
          (jsonDecode(jsonEncode(args)) as Map).cast<String, Object?>(), ctx);

  test('the catalog names exactly the commands the engine carries out', () {
    const dir = 'lib/features/editor/engine/core/commands';
    final source = [
      for (final f in const [
        'command_contract.dart',
        'design_commands.dart',
        'extras_commands.dart',
      ])
        File('$dir/$f').readAsStringSync()
    ].join('\n');
    final inSource = {
      for (final m in RegExp(
              r"(?:case |kind == |\|\| |\[|, |^ +)'([A-Z][a-z]+[A-Z][A-Za-z]+)'",
              multiLine: true)
          .allMatches(source))
        m.group(1)!
    }
      // Listed among the room commands, carried out by none.
      ..remove('DeleteRoom');
    final inCatalog = {for (final c in commandCatalog) c.kind};
    expect(inCatalog.difference(inSource), isEmpty,
        reason: 'in the catalog, not in the engine');
    expect(inSource.difference(inCatalog), isEmpty,
        reason: 'in the engine, not in the catalog');
    expect(inCatalog.length, commandCatalog.length, reason: 'listed twice');
  });

  test('every command is described as a tool with a schema', () {
    for (final tool in describeCommands()) {
      final parameters = tool['parameters']! as Map;
      expect(tool['summary'], isNotEmpty);
      expect(parameters['type'], 'object');
      final properties = parameters['properties'] as Map;
      for (final name in parameters['required'] as List) {
        expect(properties, contains(name), reason: '${tool['name']}');
      }
      for (final p in properties.values) {
        expect((p as Map)['type'], isNotNull, reason: '${tool['name']}');
      }
    }
  });

  test('$commandsFile is what the catalog says', () {
    final text =
        '${const JsonEncoder.withIndent('  ').convert(describeCommands())}\n';
    final file = File(commandsFile);
    if (const bool.fromEnvironment('UPDATE_CATALOG')) {
      file.writeAsStringSync(text);
    }
    expect(file.readAsStringSync(), text,
        reason: 'run flutter test test/command_catalog_test.dart '
            '--dart-define=UPDATE_CATALOG=true');
  });

  test('arguments written as JSON do what the Dart values do', () {
    final base = deriveFloorBase(doc, floor.id);
    // A wall with room for one more window.
    final wall = base.wallSegments.map((w) => w.ref.anchor).firstWhere((a) =>
        typed('AddOpening', {
          'floorId': floor.id,
          'anchor': a,
          'kind': OpeningKind.window,
          'tapT': 900
        }) is Applied);
    final wallJson = {
      'axisId': wall.axisId,
      'startAxisId': wall.startAxisId,
      'endAxisId': wall.endAxisId,
    };
    final room = floor.rooms.first;
    final opening = floor.openings.first;
    final cases = <(String, Map<String, Object?>, Map<String, dynamic>)>[
      (
        'AddOpening',
        {
          'floorId': floor.id,
          'anchor': wallJson,
          'kind': 'window',
          'tapT': 900
        },
        {
          'floorId': floor.id,
          'anchor': wall,
          'kind': OpeningKind.window,
          'tapT': 900
        }
      ),
      (
        'SetRoomType',
        {'roomId': room.id, 'value': 'bedroom'},
        {'roomId': room.id, 'value': RoomType.bedroom}
      ),
      (
        'RenameRoom',
        {'roomId': room.id, 'value': 'Study'},
        {'roomId': room.id, 'value': 'Study'}
      ),
      (
        'SetRoof',
        {
          'roof': {
            'type': 'gable',
            'ridgeDir': 'H',
            'pitchDeg': 30,
            'overhang': 400
          }
        },
        {
          'roof': {
            'type': 'gable',
            'ridgeDir': 'H',
            'pitchDeg': 30,
            'overhang': 400
          }
        }
      ),
      (
        'MoveOpening',
        {
          'openingId': opening.id,
          'position': {'type': 'fromStart', 'd': 400}
        },
        {
          'openingId': opening.id,
          'position': {'type': 'fromStart', 'd': 400}
        }
      ),
      (
        'ResizeOpening',
        // A whole number that arrives as 900.0 is still 900.
        {'openingId': opening.id, 'width': 900.0},
        {'openingId': opening.id, 'width': 900}
      ),
      (
        'EraseCells',
        {
          'floorId': floor.id,
          'cells': [
            [0, 0]
          ]
        },
        {
          'floorId': floor.id,
          'cells': [const Cell(0, 0)]
        }
      ),
      (
        'AddFurniture',
        {'floorId': floor.id, 'kind': 'sofa', 'x': 1000, 'y': 1000, 'id': 'f1'},
        {
          'floorId': floor.id,
          'kind': FurnitureKind.sofa,
          'x': 1000,
          'y': 1000,
          'id': 'f1'
        }
      ),
      (
        'AddIssue',
        {
          'title': 'Check the span',
          'level': 'warn',
          'id': 'i1',
          'areas': [
            [0, 0, 1000, 1000]
          ]
        },
        {
          'title': 'Check the span',
          'level': IssueLevel.warn,
          'id': 'i1',
          'areas': [(0, 0, 1000, 1000)]
        }
      ),
      (
        'SetLayers',
        {
          'group': 'wall',
          'layers': [
            {'name': 'Block', 'thickness': 300, 'material': 'block'},
            {
              'name': 'Wool',
              'nameKk': 'Жүн',
              'thickness': 100,
              'material': 'ins',
              'lambda': 40
            }
          ]
        },
        {
          'group': 'wall',
          'layers': [
            const Layer('Block', 'Block', 300, LayerMaterial.block),
            const Layer('Wool', 'Жүн', 100, LayerMaterial.ins, lambda: 40)
          ]
        }
      ),
      (
        'AddUtilities',
        {
          'floorId': floor.id,
          'points': [
            {'kind': 'socket', 'x': 500, 'y': 500, 'id': 'u1'},
            {'kind': 'light', 'x': 1500, 'y': 1500, 'id': 'u2'}
          ]
        },
        {
          'floorId': floor.id,
          'points': [
            {'kind': UtilityKind.socket, 'x': 500, 'y': 500, 'id': 'u1'},
            {'kind': UtilityKind.light, 'x': 1500, 'y': 1500, 'id': 'u2'}
          ]
        }
      ),
      ('SetMainEntrance', {'openingId': null}, {'openingId': null}),
      ('MirrorPlan', {'direction': 'vertical'}, {'direction': 'vertical'}),
    ];
    for (final (kind, asJson, asDart) in cases) {
      final a = json(kind, asJson);
      final b = typed(kind, asDart);
      expect(a.runtimeType, b.runtimeType,
          reason: '$kind: ${a is Rejected ? a.message : ''}');
      expect(a, isA<Applied>(), reason: kind);
      // The two runs draw different new ids from the same counter.
      String house(CommandResult r) =>
          encodeHouse(composeDocument(benchMeta, (r as Applied).newState))
              .replaceAll(RegExp(r'"b_\d+"'), '"new"');
      expect(house(a), house(b), reason: kind);
    }
  });

  test('a command that cannot be read is refused by name', () {
    final room = floor.rooms.first.id;
    void refused(String kind, Map<String, Object?> args, String code,
        [String? says]) {
      final r = json(kind, args);
      expect(r, isA<Rejected>(), reason: '$kind $args');
      expect((r as Rejected).reason, code, reason: '$kind $args');
      if (says != null) expect(r.message, contains(says));
    }

    refused('PaintTheHouse', {}, 'UNKNOWN_COMMAND');
    refused('RenameRoom', {'roomId': room}, 'BAD_ARGUMENT', 'value');
    refused('RenameRoom', {'roomId': room, 'value': 'A', 'colour': 'red'},
        'BAD_ARGUMENT', 'colour');
    refused(
        'RenameRoom', {'roomId': room, 'value': 7}, 'BAD_ARGUMENT', 'value');
    refused('RenameRoom', {'roomId': room, 'value': null}, 'BAD_ARGUMENT');
    refused('SetRoomType', {'roomId': room, 'value': 'ballroom'},
        'BAD_ARGUMENT', 'bedroom');
    refused('SetFloorHeight', {'floorId': floor.id, 'value': 2800.5},
        'BAD_ARGUMENT', 'whole number');
    refused('SetNorthAngle', {'value': 45}, 'BAD_ARGUMENT');
    refused(
        'EraseCells',
        {
          'floorId': floor.id,
          'cells': [
            [0]
          ]
        },
        'BAD_ARGUMENT',
        'cells[0]');
    refused(
        'AddOpening',
        {
          'floorId': floor.id,
          'anchor': {'axisId': '@top'},
          'kind': 'door',
          'tapT': 500
        },
        'BAD_ARGUMENT',
        'anchor.startAxisId');
    // Read correctly, then refused by the engine's own rules.
    refused(
        'RenameRoom', {'roomId': 'no-such-room', 'value': 'A'}, 'NOT_FOUND');
  });

  test('every command answers something for arguments it cannot use', () {
    // No command may throw on what the catalog lets through.
    for (final c in commandCatalog) {
      expect(() => json(c.kind, {}), returnsNormally, reason: c.kind);
    }
  });
}
