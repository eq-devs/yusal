import 'dart:math' as math;

import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart';
import 'package:yusal/features/editor/engine/core/checks/check_engine.dart';
import 'package:yusal/features/editor/engine/core/commands/command_catalog.dart';
import 'package:yusal/features/editor/engine/core/commands/command_contract.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/history/design_history.dart';

/// What became of one command sent to an [EngineSession].
class SessionResult {
  const SessionResult._(this.ok, this.code, this.message, this.choices,
      this.objectIds, this.created, this.removed, this.document);

  /// Whether the command was carried out.
  final bool ok;

  /// `OK`, the reason it was refused, or `NEEDS_RESOLUTION` when it asks for
  /// a choice first.
  final String code;
  final String? message;

  /// For `NEEDS_RESOLUTION`: the arguments to send the command again with.
  final List<String> choices;

  /// For `NEEDS_RESOLUTION`: what the command would take with it.
  final List<String> objectIds;

  /// Ids of what the command made and what it took away.
  final List<String> created;
  final List<String> removed;

  /// The house after the command; null when it was not carried out.
  final HouseDocument? document;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'code': code,
        if (message != null) 'message': message,
        if (choices.isNotEmpty) 'choices': choices,
        if (objectIds.isNotEmpty) 'objectIds': objectIds,
        if (created.isNotEmpty) 'created': created,
        if (removed.isNotEmpty) 'removed': removed,
      };
}

/// One command of a [EngineSession.transaction].
typedef SessionCommand = (String kind, Map<String, Object?> arguments);

/// A house being edited with no screen: commands in, results and facts out,
/// everything as plain JSON values. It is the whole engine behind one
/// object, for an assistant, a script or a test to drive, and it keeps the
/// same history the editor does.
class EngineSession {
  EngineSession(HouseDocument document,
      {String Function()? newId, String Function()? now})
      : _history = DesignHistory(document),
        _newId = newId ?? _randomId,
        _now = now ?? (() => DateTime.now().toUtc().toIso8601String());

  final DesignHistory _history;
  final String Function() _newId;
  final String Function() _now;
  final List<Map<String, Object?>> _log = [];

  static final _random = math.Random();
  static String _randomId() => [
        for (var i = 0; i < 4; i++)
          _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0')
      ].join();

  /// The house as it stands.
  HouseDocument get document => _history.present;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  /// Every command sent, in order, with what became of it.
  List<Map<String, Object?>> get log => List.unmodifiable(_log);

  CommandContext get _context => CommandContext(newId: _newId, now: _now);

  /// Carries out command [kind] with [arguments] written as JSON, and keeps
  /// the result as one step of history.
  SessionResult apply(String kind, Map<String, Object?> arguments) {
    final result = _run(document, kind, arguments);
    if (result.ok) _history.commit(result.document!);
    _note('apply', kind, arguments, result);
    return result;
  }

  /// What [apply] would answer, changing nothing.
  SessionResult preview(String kind, Map<String, Object?> arguments) {
    final result = _run(document, kind, arguments);
    _note('preview', kind, arguments, result);
    return result;
  }

  /// Carries out [commands] in order as one step of history. When one is
  /// refused none of them takes effect, and the answer is that refusal with
  /// the place of the command in its message.
  SessionResult transaction(List<SessionCommand> commands) {
    final before = document;
    var current = before;
    for (var i = 0; i < commands.length; i++) {
      final (kind, arguments) = commands[i];
      final step = _run(current, kind, arguments);
      _note('transaction', kind, arguments, step);
      if (!step.ok) {
        return SessionResult._(
            false,
            step.code,
            'command ${i + 1} ($kind): ${step.message ?? step.code}',
            step.choices,
            step.objectIds,
            const [],
            const [],
            null);
      }
      current = step.document!;
    }
    _history.commit(current);
    final was = _ids(before);
    final now = _ids(current);
    return SessionResult._(true, 'OK', null, const [], const [],
        now.difference(was).toList(), was.difference(now).toList(), current);
  }

  bool undo() {
    if (!canUndo) return false;
    _history.undo();
    _append({'op': 'undo'});
    return true;
  }

  bool redo() {
    if (!canRedo) return false;
    _history.redo();
    _append({'op': 'redo'});
    return true;
  }

  SessionResult _run(
      HouseDocument from, String kind, Map<String, Object?> arguments) {
    final result =
        executeJsonCommand(extractDesignState(from), kind, arguments, _context);
    switch (result) {
      case Applied(:final newState):
        final next = composeDocument(from.meta, newState);
        final was = _ids(from);
        final now = _ids(next);
        return SessionResult._(true, 'OK', null, const [], const [],
            now.difference(was).toList(), was.difference(now).toList(), next);
      case Rejected(:final reason, :final message):
        return SessionResult._(false, reason, message, const [], const [],
            const [], const [], null);
      case NeedsResolution(:final conflict):
        return SessionResult._(false, 'NEEDS_RESOLUTION', conflict.message,
            conflict.choices, conflict.objectIds, const [], const [], null);
    }
  }

  void _note(String op, String kind, Map<String, Object?> arguments,
          SessionResult result) =>
      _append({
        'op': op,
        'kind': kind,
        'arguments': arguments,
        'result': result.toJson(),
      });

  /// The log keeps the last [logLimit] entries.
  static const logLimit = 500;

  void _append(Map<String, Object?> entry) {
    _log.add(entry);
    if (_log.length > logLimit) _log.removeAt(0);
  }

  static Set<String> _ids(HouseDocument d) => {
        for (final a in d.axes.global) a.id,
        for (final a in d.axes.floor) a.id,
        for (final f in d.floors) ...[
          f.id,
          for (final r in f.rooms) r.id,
          for (final o in f.openings) o.id,
          for (final s in f.stairs) s.id,
          for (final w in f.wallOverrides) w.id,
        ],
        for (final f in d.extras.furniture) f.id,
        for (final u in d.extras.utilities) u.id,
      };

  /// The house in facts an assistant can plan from: sizes, the grid lines
  /// of each floor, and its rooms, openings and stairs with their ids.
  /// Lengths are millimetres and areas square metres.
  Map<String, Object?> describe() {
    final doc = document;
    final derived = deriveHouse(doc);
    return {
      'name': doc.meta.name,
      'footprint': {
        'width': doc.footprint.width,
        'depth': doc.footprint.depth,
        'northAngleDeg': doc.footprint.northAngleDeg,
      },
      'roof': doc.roof.type.name,
      'mainEntranceOpeningId': doc.mainEntranceOpeningId,
      'floors': [
        for (var i = 0; i < doc.floors.length; i++)
          _floor(doc.floors[i], derived.floors[i])
      ],
      'furniture': doc.extras.furniture.length,
    };
  }

  static double _m2(double mm2) => (mm2 / 1e4).round() / 100;

  Map<String, Object?> _floor(Floor f, DerivedFloor g) {
    final areas = {for (final r in g.base.roomGeometry) r.id: r};
    final placed = {for (final p in g.openings) p.opening.id: p};
    Map<String, Object?> line(dynamic a) => {'id': a.id, 'pos': a.pos};
    return {
      'id': f.id,
      'name': f.name,
      'height': f.height,
      'elevation': g.elevation.round(),
      'drawnWalls': f.explicitWalls,
      'axes': {
        'V': [for (final a in g.base.axes.v) line(a)],
        'H': [for (final a in g.base.axes.h) line(a)],
      },
      'rooms': [
        for (final r in f.rooms)
          {
            'id': r.id,
            'name': r.name,
            'type': r.type.name,
            'area': _m2(areas[r.id]?.clearArea ?? 0),
            'areaToWallCentres': _m2(areas[r.id]?.centreArea ?? 0),
            'areaToOuterFace': _m2(areas[r.id]?.nominalArea ?? 0),
            'minSpan': areas[r.id]?.minClearSpan.round() ?? 0,
          }
      ],
      'openings': [
        for (final o in f.openings)
          {
            'id': o.id,
            'kind': o.kind.name,
            'width': o.width,
            'height': o.height,
            'sill': o.sill,
            'anchor': {
              'axisId': o.anchor.axisId,
              'startAxisId': o.anchor.startAxisId,
              'endAxisId': o.anchor.endAxisId,
            },
            'status': placed[o.id]?.status ?? 'missing',
          }
      ],
      'stairs': [
        for (final s in g.stairs) {'id': s.stairId, 'fits': s.fits}
      ],
    };
  }

  /// What the layout rules find in the house as it stands.
  List<Map<String, Object?>> check() {
    final doc = document;
    return [
      for (final c in runChecks(doc, deriveHouse(doc)))
        {
          'ruleId': c.ruleId,
          'level': c.level,
          if (c.floorId != null) 'floorId': c.floorId,
          'objectIds': c.objectIds,
          'message': c.message,
        }
    ];
  }

  /// The estimate of the house as it stands, by stage and in total.
  Map<String, Object?> cost({Currency currency = Currency.cny}) {
    final doc = document;
    final e = estimateCost(doc, deriveHouse(doc), currency: currency);
    return {
      'currency': e.currency.name,
      'buildingArea': (e.buildingArea * 100).round() / 100,
      'materials': e.materials.round(),
      'labour': e.labour.round(),
      'contingency': e.contingency.round(),
      'total': e.total.round(),
      'low': e.low.round(),
      'high': e.high.round(),
      'perArea': e.perArea.round(),
      'stages': {
        for (final s in costStages)
          if (e.stageTotal(s) > 0) s: e.stageTotal(s).round()
      },
    };
  }

  /// Every command the session takes, as an assistant's tools.
  static List<Map<String, Object?>> commands() => describeCommands();
}
