import '../document/house_document.dart';
import '../axis/axis_resolver.dart';
import '../validation/document_validator.dart';
import 'design_commands.dart';
import 'delete_axis.dart';
import 'room_commands.dart';

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
  Applied apply(HouseDocument document) =>
      Applied(extractDesignState(document));
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
    if (result.accepted) return apply(result.document!);
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
