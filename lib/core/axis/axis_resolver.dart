import '../document/house_document.dart';

class ResolvedAxis {
  const ResolvedAxis({
    required this.id,
    required this.dir,
    required this.pos,
    required this.kind,
    required this.index,
  });
  final String id;
  final AxisDir dir;
  final int pos;
  final String kind;
  final int index;
  @override
  bool operator ==(Object other) =>
      other is ResolvedAxis &&
      id == other.id &&
      dir == other.dir &&
      pos == other.pos &&
      kind == other.kind &&
      index == other.index;
  @override
  int get hashCode => Object.hash(id, dir, pos, kind, index);
}

class AxisIssue {
  AxisIssue(this.code, this.dir, List<String> axisIds)
      : axisIds = List.unmodifiable(axisIds);
  final String code;
  final AxisDir? dir;
  final List<String> axisIds;
  @override
  bool operator ==(Object other) =>
      other is AxisIssue &&
      code == other.code &&
      dir == other.dir &&
      axisIds.length == other.axisIds.length &&
      [for (var i = 0; i < axisIds.length; i++) axisIds[i] == other.axisIds[i]]
          .every((v) => v);
  @override
  int get hashCode => Object.hash(code, dir, Object.hashAll(axisIds));
}

class AxisRecord {
  const AxisRecord(this.kind, this.floorId, this.dir, this.pos);
  final String kind;
  final String? floorId;
  final AxisDir dir;
  final int pos;
}

class ResolvedAxes {
  ResolvedAxes({
    required this.floorId,
    required List<ResolvedAxis> v,
    required List<ResolvedAxis> h,
    required List<AxisIssue> issues,
    required Map<String, List<AxisRecord>> axisRegistry,
  })  : v = List.unmodifiable(v),
        h = List.unmodifiable(h),
        issues = List.unmodifiable(issues),
        axisRegistry = Map.unmodifiable(axisRegistry.map((key, value) =>
            MapEntry(key, List<AxisRecord>.unmodifiable(value))));
  final String floorId;
  final List<ResolvedAxis> v, h;
  final List<AxisIssue> issues;
  final Map<String, List<AxisRecord>> axisRegistry;
  int get nx => v.length - 1;
  int get ny => h.length - 1;
  List<ResolvedAxis> get all => List.unmodifiable([...v, ...h]);
}

class AxisLookupFailure {
  const AxisLookupFailure(this.code);
  final String code;
}

class Cell {
  const Cell(this.i, this.j);
  final int i, j;
  @override
  bool operator ==(Object other) =>
      other is Cell && i == other.i && j == other.j;
  @override
  int get hashCode => Object.hash(i, j);
  @override
  String toString() => '($i,$j)';
}

class ResolvedRect {
  const ResolvedRect({
    required this.left,
    required this.right,
    required this.bottom,
    required this.top,
    required this.i0,
    required this.i1,
    required this.j0,
    required this.j1,
  });
  final int left, right, bottom, top, i0, i1, j0, j1;
  int get nominalArea => (right - left) * (top - bottom);
}

class AxisReferenceError {
  const AxisReferenceError(this.code, this.field);
  final String code, field;
  @override
  bool operator ==(Object other) =>
      other is AxisReferenceError && code == other.code && field == other.field;
  @override
  int get hashCode => Object.hash(code, field);
}

class ResolveRectResult {
  const ResolveRectResult.success(this.rect) : errors = const [];
  const ResolveRectResult.failure(this.errors) : rect = null;
  final ResolvedRect? rect;
  final List<AxisReferenceError> errors;
  bool get isSuccess => rect != null;
}

class ChainSegment {
  const ChainSegment({
    required this.start,
    required this.end,
    required this.negativeSide,
    required this.positiveSide,
  });
  final int start, end;
  final Cell? negativeSide, positiveSide;
}

class ResolvedChain {
  const ResolvedChain({
    required this.carrier,
    required this.start,
    required this.end,
    required this.startPos,
    required this.endPos,
    required this.segments,
  });
  final ResolvedAxis carrier, start, end;
  final int startPos, endPos;
  final List<ChainSegment> segments;
  int get nominalLength => endPos - startPos;
  ChainSegment? locate(int t) {
    if (t < 0 || t > nominalLength) return null;
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      if (t >= s.start && (t < s.end || i == segments.length - 1)) return s;
    }
    return null;
  }
}

class ResolveChainResult {
  const ResolveChainResult.success(this.chain) : errors = const [];
  const ResolveChainResult.failure(this.errors) : chain = null;
  final ResolvedChain? chain;
  final List<AxisReferenceError> errors;
  bool get isSuccess => chain != null;
}

ResolvedAxes? resolveFloorAxes(HouseDocument doc, String floorId) {
  if (!doc.floors.any((f) => f.id == floorId)) return null;
  final registry = <String, List<AxisRecord>>{};
  for (final a in doc.axes.global) {
    (registry[a.id] ??= []).add(AxisRecord('global', null, a.dir, a.pos));
  }
  for (final a in doc.axes.floor) {
    (registry[a.id] ??= []).add(AxisRecord('floor', a.floorId, a.dir, a.pos));
  }
  final visible = <ResolvedAxis>[
    ResolvedAxis(
      id: '@left',
      dir: AxisDir.V,
      pos: 0,
      kind: 'boundary',
      index: 0,
    ),
    for (final a in doc.axes.global.where((a) => !a.id.startsWith('@')))
      ResolvedAxis(id: a.id, dir: a.dir, pos: a.pos, kind: 'global', index: -1),
    for (final a in doc.axes.floor.where(
      (a) => a.floorId == floorId && !a.id.startsWith('@'),
    ))
      ResolvedAxis(id: a.id, dir: a.dir, pos: a.pos, kind: 'floor', index: -1),
  ];
  visible.add(
    ResolvedAxis(
      id: '@right',
      dir: AxisDir.V,
      pos: doc.footprint.width,
      kind: 'boundary',
      index: -1,
    ),
  );
  visible.addAll([
    ResolvedAxis(
      id: '@bottom',
      dir: AxisDir.H,
      pos: 0,
      kind: 'boundary',
      index: -1,
    ),
    ResolvedAxis(
      id: '@top',
      dir: AxisDir.H,
      pos: doc.footprint.depth,
      kind: 'boundary',
      index: -1,
    ),
  ]);
  int kindOrder(String k) => switch (k) {
        'boundary' => 0,
        'global' => 1,
        _ => 2,
      };
  List<ResolvedAxis> sort(AxisDir d) {
    final list = visible.where((a) => a.dir == d).toList()
      ..sort((a, b) {
        final p = a.pos.compareTo(b.pos);
        if (p != 0) return p;
        final k = kindOrder(a.kind).compareTo(kindOrder(b.kind));
        return k != 0 ? k : a.id.compareTo(b.id);
      });
    return List.unmodifiable([
      for (var i = 0; i < list.length; i++)
        ResolvedAxis(
          id: list[i].id,
          dir: d,
          pos: list[i].pos,
          kind: list[i].kind,
          index: i,
        ),
    ]);
  }

  final v = sort(AxisDir.V), h = sort(AxisDir.H);
  final issues = <AxisIssue>[];
  final reserved = [
    ...doc.axes.global.where((a) => a.id.startsWith('@')).map((a) => a.id),
    ...doc.axes.floor.where((a) => a.id.startsWith('@')).map((a) => a.id),
  ];
  for (final id in reserved) issues.add(AxisIssue('RESERVED_ID', null, [id]));
  for (final dir in AxisDir.values) {
    final list = dir == AxisDir.V ? v : h;
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      if (a.kind != 'boundary' &&
          (a.pos <= 0 ||
              a.pos >=
                  (dir == AxisDir.V
                      ? doc.footprint.width
                      : doc.footprint.depth)))
        issues.add(AxisIssue('POSITION_OUT_OF_RANGE', dir, [a.id]));
      for (var j = i + 1; j < list.length; j++)
        if (list[j].id == a.id)
          issues.add(AxisIssue('DUPLICATE_ID', dir, [a.id, list[j].id]));
      if (i > 0) {
        final delta = a.pos - list[i - 1].pos;
        if (delta == 0)
          issues.add(
            AxisIssue('POSITION_COLLISION', dir, [list[i - 1].id, a.id]),
          );
        else if (delta > 0 && delta < 300)
          issues.add(
            AxisIssue('SPACING_TOO_SMALL', dir, [list[i - 1].id, a.id]),
          );
      }
    }
  }
  const issueOrder = {
    'RESERVED_ID': 0,
    'DUPLICATE_ID': 1,
    'POSITION_OUT_OF_RANGE': 2,
    'POSITION_COLLISION': 3,
    'SPACING_TOO_SMALL': 4,
  };
  final ordinal = {for (var i = 0; i < issues.length; i++) issues[i]: i};
  issues.sort((a, b) {
    final c = (issueOrder[a.code] ?? 9).compareTo(issueOrder[b.code] ?? 9);
    if (c != 0) return c;
    final d = (a.dir == AxisDir.V ? 0 : 1).compareTo(
      b.dir == AxisDir.V ? 0 : 1,
    );
    if (d != 0) return d;
    if (a.dir != null) {
      final axes = a.dir == AxisDir.V ? v : h;
      final ai = axes.indexWhere((axis) => axis.id == a.axisIds.first);
      final bi = axes.indexWhere((axis) => axis.id == b.axisIds.first);
      if (ai != bi) return ai.compareTo(bi);
    }
    return ordinal[a]!.compareTo(ordinal[b]!);
  });
  return ResolvedAxes(
    floorId: floorId,
    v: v,
    h: h,
    issues: issues,
    axisRegistry: registry,
  );
}

({ResolvedAxis? axis, AxisLookupFailure? failure}) lookupAxis(
  ResolvedAxes axes,
  String id,
) {
  if (id.startsWith('@')) {
    for (final a in axes.all)
      if (a.id == id && a.kind == 'boundary') return (axis: a, failure: null);
    return (
      axis: null,
      failure: const AxisLookupFailure('INVALID_RESERVED_REF'),
    );
  }
  final matches = axes.all.where((a) => a.id == id).toList();
  if (matches.length == 1) return (axis: matches.single, failure: null);
  if (matches.length > 1)
    return (axis: null, failure: const AxisLookupFailure('AXIS_AMBIGUOUS'));
  if ((axes.axisRegistry[id] ?? const <AxisRecord>[]).any(
    (a) => a.kind == 'floor' && a.floorId != axes.floorId,
  )) return (axis: null, failure: const AxisLookupFailure('AXIS_NOT_VISIBLE'));
  return (axis: null, failure: const AxisLookupFailure('AXIS_NOT_FOUND'));
}

ResolveRectResult resolveRect(ResolvedAxes axes, AxisRectangle rect) {
  const refs = [('x0', 'x0'), ('x1', 'x1'), ('y0', 'y0'), ('y1', 'y1')];
  final found = <String, ResolvedAxis>{};
  final errors = <AxisReferenceError>[];
  for (final (field, key) in refs) {
    final r = lookupAxis(
        axes,
        switch (key) {
          'x0' => rect.x0,
          'x1' => rect.x1,
          'y0' => rect.y0,
          _ => rect.y1,
        });
    if (r.axis != null)
      found[field] = r.axis!;
    else
      errors.add(AxisReferenceError(r.failure!.code, field));
  }
  if (errors.isNotEmpty)
    return ResolveRectResult.failure(List.unmodifiable(errors));
  final wrong = <AxisReferenceError>[];
  if (found['x0']!.dir != AxisDir.V)
    wrong.add(const AxisReferenceError('RECT_WRONG_DIR', 'x0'));
  if (found['x1']!.dir != AxisDir.V)
    wrong.add(const AxisReferenceError('RECT_WRONG_DIR', 'x1'));
  if (found['y0']!.dir != AxisDir.H)
    wrong.add(const AxisReferenceError('RECT_WRONG_DIR', 'y0'));
  if (found['y1']!.dir != AxisDir.H)
    wrong.add(const AxisReferenceError('RECT_WRONG_DIR', 'y1'));
  if (wrong.isNotEmpty)
    return ResolveRectResult.failure(List.unmodifiable(wrong));
  final inverted = <String>[];
  if (found['x0']!.pos >= found['x1']!.pos) inverted.add('x');
  if (found['y0']!.pos >= found['y1']!.pos) inverted.add('y');
  if (inverted.isNotEmpty)
    return ResolveRectResult.failure([
      for (final d in inverted) AxisReferenceError('RECT_EMPTY_OR_INVERTED', d),
    ]);
  return ResolveRectResult.success(
    ResolvedRect(
      left: found['x0']!.pos,
      right: found['x1']!.pos,
      bottom: found['y0']!.pos,
      top: found['y1']!.pos,
      i0: found['x0']!.index,
      i1: found['x1']!.index,
      j0: found['y0']!.index,
      j1: found['y1']!.index,
    ),
  );
}

List<Cell> cellsOfRect(ResolvedRect rect) => [
      for (var j = rect.j0; j < rect.j1; j++)
        for (var i = rect.i0; i < rect.i1; i++) Cell(i, j),
    ];

ResolveChainResult resolveAnchor(ResolvedAxes axes, BoundaryAnchor anchor) {
  final refs = [
    ('axisId', anchor.axisId),
    ('startAxisId', anchor.startAxisId),
    ('endAxisId', anchor.endAxisId),
  ];
  final found = <String, ResolvedAxis>{};
  final errors = <AxisReferenceError>[];
  for (final (field, id) in refs) {
    final r = lookupAxis(axes, id);
    if (r.axis != null)
      found[field] = r.axis!;
    else
      errors.add(AxisReferenceError(r.failure!.code, field));
  }
  if (errors.isNotEmpty)
    return ResolveChainResult.failure(List.unmodifiable(errors));
  final c = found['axisId']!,
      s = found['startAxisId']!,
      e = found['endAxisId']!;
  final wrong = <AxisReferenceError>[];
  if (s.dir == c.dir)
    wrong.add(const AxisReferenceError('ANCHOR_WRONG_DIR', 'startAxisId'));
  if (e.dir == c.dir)
    wrong.add(const AxisReferenceError('ANCHOR_WRONG_DIR', 'endAxisId'));
  if (wrong.isNotEmpty) return ResolveChainResult.failure(wrong);
  if (s.pos >= e.pos)
    return ResolveChainResult.failure([
      const AxisReferenceError('ANCHOR_EMPTY_OR_INVERTED', 'anchor'),
    ]);
  final perpendicular = c.dir == AxisDir.H ? axes.v : axes.h;
  final segments = <ChainSegment>[];
  for (var k = s.index; k < e.index; k++) {
    final a = perpendicular[k], b = perpendicular[k + 1];
    final idx = c.index;
    Cell? neg, pos;
    if (c.dir == AxisDir.H) {
      if (idx > 0) neg = Cell(k, idx - 1);
      if (idx < axes.ny) pos = Cell(k, idx);
    } else {
      if (idx > 0) neg = Cell(idx - 1, k);
      if (idx < axes.nx) pos = Cell(idx, k);
    }
    segments.add(
      ChainSegment(
        start: a.pos - s.pos,
        end: b.pos - s.pos,
        negativeSide: neg,
        positiveSide: pos,
      ),
    );
  }
  return ResolveChainResult.success(
    ResolvedChain(
      carrier: c,
      start: s,
      end: e,
      startPos: s.pos,
      endPos: e.pos,
      segments: List.unmodifiable(segments),
    ),
  );
}
