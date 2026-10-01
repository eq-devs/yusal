import '../document/house_document.dart';
import '../axis/axis_resolver.dart';
import '../validation/document_validator.dart';
import 'design_commands.dart';
import 'delete_axis.dart';
import 'room_commands.dart';
import 'spatial_commands.dart';
import 'spatial_wall_commands.dart';
import 'drawn_wall_commands.dart';
import '../geometry/opening_constraints.dart';

class DesignCommand {
  DesignCommand(this.kind, Map<String, dynamic> arguments)
      : arguments = Map.unmodifiable(arguments);
  final String kind;
  final Map<String, dynamic> arguments;
}

class CommandContext {
  const CommandContext({required this.newId, required this.now});
  final String Function() newId, now;
}

sealed class CommandResult {
  const CommandResult();
}

class Applied extends CommandResult {
  const Applied(this.newState);
  final UndoableDesignState newState;
}

class Rejected extends CommandResult {
  const Rejected(this.reason, this.message);
  final String reason, message;
}

class NeedsResolution extends CommandResult {
  const NeedsResolution(this.conflict);
  final CommandConflict conflict;
}

class CommandConflict {
  const CommandConflict(this.kind, this.message, this.choices, this.objectIds);
  final String kind, message;
  final List<String> choices, objectIds;
}

HouseDocument _document(UndoableDesignState state) => composeDocument(
    const Meta(
        name: '',
        createdAt: '1970-01-01T00:00:00Z',
        updatedAt: '1970-01-01T00:00:00Z'),
    state);
List<ValidationError> validateDesignState(UndoableDesignState state) =>
    validateHouse(_document(state));

CommandResult executeCommand(
    UndoableDesignState state, DesignCommand command, CommandContext context) {
  final doc = _document(state), args = command.arguments;
  CommandResult apply(HouseDocument document) {
    if ([
      'SplitSpace',
      'CarveRoom',
      'PaintCells',
      'EraseCells',
      'DeleteRoom',
      'MergeRooms',
      'AddStair',
      'UpdateStair',
      'DeleteStair'
    ].contains(command.kind)) {
      for (final floor in document.floors.where((f) => f.explicitWalls))
        document = syncRoomWalls(doc, document, floor.id, context.newId);
      if (command.kind != 'MergeRooms') {
        final healthy = documentOpenings(doc)
            .where((p) => p.status == 'ok')
            .map((p) => p.opening.id)
            .toSet();
        if (documentOpenings(document)
            .any((p) => healthy.contains(p.opening.id) && p.status != 'ok'))
          return const Rejected('HOST_CONFLICT', '此调整会影响已有门窗，请避开门窗位置');
      }
    }
    return Applied(extractDesignState(document));
  }

  try {
    if (validateHouse(doc).isNotEmpty)
      return const Rejected('INTERNAL_INVALID', '输入设计状态无效');
    final identities = <String, Set<String>>{
      'floorId': doc.floors.map((f) => f.id).toSet(),
      'axisId': {
        ...doc.axes.global.map((a) => a.id),
        ...doc.axes.floor.map((a) => a.id),
        '@left',
        '@right',
        '@bottom',
        '@top'
      },
      'roomId': doc.floors.expand((f) => f.rooms).map((r) => r.id).toSet(),
      'openingId':
          doc.floors.expand((f) => f.openings).map((o) => o.id).toSet(),
      'stairId': doc.floors.expand((f) => f.stairs).map((s) => s.id).toSet(),
    };
    for (final entry in args.entries) {
      final key =
          ['roomIdA', 'roomIdB'].contains(entry.key) ? 'roomId' : entry.key;
      if (identities.containsKey(key) &&
          entry.value != null &&
          !identities[key]!.contains(entry.value))
        return const Rejected('NOT_FOUND', '找不到要编辑的对象');
    }
    if (['AddDrawnWall', 'UpdateDrawnWall', 'DeleteDrawnWall']
        .contains(command.kind)) {
      final result = editDrawnWall(doc, command.kind, args, context.newId);
      return result.accepted
          ? apply(result.document!)
          : Rejected('WALL_CONFLICT', result.error!);
    }
    if (command.kind == 'EnableWallDrawing')
      return apply(
          enableWallDrawing(doc, args['floorId'] as String, context.newId));
    if (command.kind == 'MoveLocalWall') {
      final result = moveLocalWall(doc, args['floorId'] as String,
          args['anchor'] as BoundaryAnchor, args['pos'] as int, context.newId);
      return result.accepted
          ? apply(result.document!)
          : Rejected('SPATIAL_CONFLICT', result.error!);
    }
    if (command.kind == 'SplitSpace') {
      final result = splitSpace(
          doc,
          args['floorId'] as String,
          args['dir'] as AxisDir,
          args['pos'] as int,
          args['x'] as int,
          args['y'] as int,
          context.newId);
      return result.accepted
          ? apply(result.document!)
          : Rejected('SPATIAL_CONFLICT', result.error!);
    }
    if (command.kind == 'CarveRoom') {
      final result = carveRoom(
          doc,
          args['floorId'] as String,
          args['left'] as int,
          args['bottom'] as int,
          args['right'] as int,
          args['top'] as int,
          args['roomType'] as RoomType? ?? RoomType.custom,
          context.newId);
      return result.accepted
          ? apply(result.document!)
          : Rejected('SPATIAL_CONFLICT', result.error!);
    }
    if (command.kind == 'DeleteAxis') {
      final result = deleteAxis(doc, args['axisId'] as String, context.newId,
          resolution: args['resolution'] as String?,
          deleteHostedObjects: args['deleteHostedObjects'] == true,
          deleteStairs: args['deleteStairs'] == true);
      if (result.document != null) return apply(result.document!);
      if (result.needsResolution)
        return NeedsResolution(CommandConflict(
            'DeleteAxis',
            result.message!,
            List.unmodifiable([
              'mergeRooms',
              'keepLowSide',
              'keepHighSide',
              if (result.hasHosted) 'deleteHostedObjects',
              if (result.hasStairs) 'deleteStairs'
            ]),
            List.unmodifiable([args['axisId'] as String])));
      return Rejected('INVALID_VALUE', result.message!);
    }
    if (command.kind == 'DeleteFloor') {
      final index = doc.floors.indexWhere((f) => f.id == args['floorId']);
      if (doc.floors.length == 1) return const Rejected('LAST_FLOOR', '至少保留一层');
      if (index == doc.floors.length - 1 &&
          index > 0 &&
          doc.floors[index - 1].stairs.isNotEmpty &&
          args['deleteStairs'] != true) {
        return NeedsResolution(CommandConflict(
            'DeleteFloor',
            '下层楼梯将没有上层，请确认同时删除',
            const ['deleteStairs'],
            List.unmodifiable(doc.floors[index - 1].stairs.map((s) => s.id))));
      }
    }
    if (command.kind == 'PaintCells' || command.kind == 'EraseCells') {
      final floor = doc.floors.firstWhere((f) => f.id == args['floorId']);
      final axes = resolveFloorAxes(doc, floor.id)!;
      final cells = args['cells'] as List<Cell>;
      if (cells
          .any((c) => c.i < 0 || c.j < 0 || c.i >= axes.nx || c.j >= axes.ny))
        return const Rejected('INVALID_VALUE', '格子超出房屋范围');
      if (command.kind == 'PaintCells' &&
          cells.isNotEmpty &&
          floor.stairs.any((s) => cellsOfRect(resolveRect(axes, s.region).rect!)
              .contains(cells.first)))
        return const Rejected('STAIR_CELL', '请从楼梯以外的格子开始');
      return apply(paintCells(doc, floor.id, cells,
          args['roomType'] as RoomType? ?? RoomType.custom, context.newId,
          erase: command.kind == 'EraseCells'));
    }
    final result =
        executeDocumentCommand(doc, command.kind, args, context.newId);
    if (result.accepted) {
      var document = result.document!;
      if (command.kind == 'MergeRooms') {
        for (final floor in document.floors.where((f) => f.explicitWalls))
          document = syncRoomWalls(doc, document, floor.id, context.newId);
        final healthy = documentOpenings(doc)
            .where((p) => p.status == 'ok')
            .map((p) => p.opening.id)
            .toSet();
        final removedHosts = documentOpenings(document)
            .where((p) => healthy.contains(p.opening.id) && p.status != 'ok')
            .map((p) => p.opening.id)
            .toList();
        if (removedHosts.isNotEmpty && args['deleteHostedObjects'] != true) {
          return NeedsResolution(CommandConflict(
              'MergeRooms',
              '合并后有 ${removedHosts.length} 个门窗所在的墙会消失，需要同时移除这些门窗。',
              const ['deleteHostedObjects'],
              List.unmodifiable(removedHosts)));
        }
        for (final id in removedHosts) {
          document = executeDocumentCommand(
                  document, 'DeleteOpening', {'openingId': id}, context.newId)
              .document!;
        }
      }
      if (command.kind == 'SetWallOverride')
        document = recognizeWallRooms(
            document, args['floorId'] as String, context.newId,
            preserveOpenZones: args['type'] != 'open');
      return apply(document);
    }

    final message = result.error!;
    final reason = message.contains('间距') || message.contains('两条线')
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
    return Rejected(reason, message);
  } on StateError {
    return const Rejected('NOT_FOUND', '找不到要编辑的对象');
  } catch (_) {
    return const Rejected('INVALID_VALUE', '操作参数无效');
  }
}
