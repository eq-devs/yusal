import '../axis/axis_resolver.dart';
import '../document/house_document.dart';

class RegionCellsResult {
  const RegionCellsResult(this.cells, this.selfOverlap, this.errors);
  final Set<Cell> cells;
  final bool selfOverlap;
  final List<AxisReferenceError> errors;
  bool get isSuccess => errors.isEmpty;
}

class CanonicalCellsResult {
  const CanonicalCellsResult.success(this.regions) : errors = const [];
  const CanonicalCellsResult.failure(this.errors) : regions = const [];
  final List<AxisRectangle> regions;
  final List<AxisReferenceError> errors;
  bool get isSuccess => errors.isEmpty;
}

class CellSetResult {
  const CellSetResult(this.cells, this.errors);
  final List<Set<Cell>> cells;
  final List<AxisReferenceError> errors;
  bool get isSuccess => errors.isEmpty;
}

int _rowOrder(Cell a, Cell b) =>
    a.j != b.j ? a.j.compareTo(b.j) : a.i.compareTo(b.i);
List<Cell> _ordered(Iterable<Cell> cells) => cells.toList()..sort(_rowOrder);

RegionCellsResult regionCells(ResolvedAxes axes, List<AxisRectangle> regions) {
  final result = <Cell>{};
  final errors = <AxisReferenceError>[];
  var overlap = false;
  for (var r = 0; r < regions.length; r++) {
    final resolved = resolveRect(axes, regions[r]);
    if (!resolved.isSuccess) {
      for (final e in resolved.errors)
        errors.add(AxisReferenceError(e.code, 'regions/$r/${e.field}'));
      continue;
    }
    for (final cell in cellsOfRect(resolved.rect!)) {
      if (!result.add(cell)) overlap = true;
    }
  }
  return RegionCellsResult(
    Set.unmodifiable(result),
    overlap,
    List.unmodifiable(errors),
  );
}

CanonicalCellsResult canonicalizeCells(ResolvedAxes axes, Set<Cell> cells) {
  final invalid = _ordered(
    cells.where((c) => c.i < 0 || c.i >= axes.nx || c.j < 0 || c.j >= axes.ny),
  );
  if (invalid.isNotEmpty)
    return CanonicalCellsResult.failure([
      for (final c in invalid) AxisReferenceError('CELL_OUT_OF_RANGE', '$c'),
    ]);
  final rows = <int, Set<int>>{};
  for (final c in cells) {
    (rows[c.j] ??= <int>{}).add(c.i);
  }
  final open = <String, (int, int, int)>{};
  final out = <({int i0, int i1, int j0, int j1})>[];
  var previous = -2;
  void closeAll() {
    for (final e in open.values)
      out.add((i0: e.$1, i1: e.$2, j0: e.$3, j1: previous + 1));
    open.clear();
  }

  for (final j in (rows.keys.toList()..sort())) {
    if (j != previous + 1 && open.isNotEmpty) closeAll();
    final cols = rows[j]!.toList()..sort();
    final intervals = <(int, int)>[];
    var start = cols.first, end = start + 1;
    for (final x in cols.skip(1)) {
      if (x == end) {
        end++;
      } else {
        intervals.add((start, end));
        start = x;
        end = x + 1;
      }
    }
    intervals.add((start, end));
    final keys = intervals
        .map((interval) => '${interval.$1}:${interval.$2}')
        .toSet();
    for (final key in open.keys.toList())
      if (!keys.contains(key)) {
        final e = open.remove(key)!;
        out.add((i0: e.$1, i1: e.$2, j0: e.$3, j1: previous + 1));
      }
    for (final interval in intervals) {
      final key = '${interval.$1}:${interval.$2}';
      open[key] = (interval.$1, interval.$2, open[key]?.$3 ?? j);
    }
    previous = j;
  }
  if (open.isNotEmpty) closeAll();
  out.sort((a, b) {
    var c = a.j0.compareTo(b.j0);
    if (c != 0) return c;
    c = a.i0.compareTo(b.i0);
    if (c != 0) return c;
    c = a.j1.compareTo(b.j1);
    return c != 0 ? c : a.i1.compareTo(b.i1);
  });
  final v = axes.v, h = axes.h;
  return CanonicalCellsResult.success(
    List.unmodifiable([
      for (final r in out)
        AxisRectangle(
          x0: v[r.i0].id,
          x1: v[r.i1].id,
          y0: h[r.j0].id,
          y1: h[r.j1].id,
        ),
    ]),
  );
}

CanonicalCellsResult canonicalizeRegions(
  ResolvedAxes axes,
  List<AxisRectangle> regions,
) {
  final expanded = regionCells(axes, regions);
  if (!expanded.isSuccess) return CanonicalCellsResult.failure(expanded.errors);
  return canonicalizeCells(axes, expanded.cells);
}

bool isCanonical(ResolvedAxes axes, List<AxisRectangle> regions) {
  final expanded = regionCells(axes, regions);
  if (!expanded.isSuccess || expanded.selfOverlap) return false;
  final normalized = canonicalizeCells(axes, expanded.cells);
  if (!normalized.isSuccess || normalized.regions.length != regions.length)
    return false;
  for (var i = 0; i < regions.length; i++)
    if (regions[i] != normalized.regions[i]) return false;
  return true;
}

bool isConnected(Set<Cell> cells) {
  if (cells.isEmpty) return false;
  final visited = <Cell>{cells.first};
  final queue = <Cell>[cells.first];
  for (var i = 0; i < queue.length; i++) {
    final c = queue[i];
    for (final n in [
      Cell(c.i + 1, c.j),
      Cell(c.i - 1, c.j),
      Cell(c.i, c.j + 1),
      Cell(c.i, c.j - 1),
    ])
      if (cells.contains(n) && visited.add(n)) queue.add(n);
  }
  return visited.length == cells.length;
}

CellSetResult components(ResolvedAxes axes, Set<Cell> cells) {
  final normalized = canonicalizeCells(axes, cells);
  if (!normalized.isSuccess) return CellSetResult(const [], normalized.errors);
  final remaining = <Cell>{...cells};
  final parts = <Set<Cell>>[];
  while (remaining.isNotEmpty) {
    final seed = _ordered(remaining).first;
    final part = <Cell>{seed};
    final queue = <Cell>[seed];
    remaining.remove(seed);
    for (var i = 0; i < queue.length; i++) {
      final c = queue[i];
      for (final n in [
        Cell(c.i + 1, c.j),
        Cell(c.i - 1, c.j),
        Cell(c.i, c.j + 1),
        Cell(c.i, c.j - 1),
      ])
        if (remaining.remove(n)) {
          part.add(n);
          queue.add(n);
        }
    }
    parts.add(Set.unmodifiable(part));
  }
  parts.sort((a, b) {
    final areaA = a.fold<int>(
      0,
      (s, c) =>
          s +
          (axes.v[c.i + 1].pos - axes.v[c.i].pos) *
              (axes.h[c.j + 1].pos - axes.h[c.j].pos),
    );
    final areaB = b.fold<int>(
      0,
      (s, c) =>
          s +
          (axes.v[c.i + 1].pos - axes.v[c.i].pos) *
              (axes.h[c.j + 1].pos - axes.h[c.j].pos),
    );
    if (areaA != areaB) return areaB.compareTo(areaA);
    return _rowOrder(_ordered(a).first, _ordered(b).first);
  });
  return CellSetResult(List.unmodifiable(parts), const []);
}

int compareComponentPriority(ResolvedAxes axes, Set<Cell> a, Set<Cell> b) {
  int area(Set<Cell> s) => s.fold<int>(
    0,
    (sum, c) =>
        sum +
        (axes.v[c.i + 1].pos - axes.v[c.i].pos) *
            (axes.h[c.j + 1].pos - axes.h[c.j].pos),
  );
  final c = area(b).compareTo(area(a));
  return c != 0 ? c : _rowOrder(_ordered(a).first, _ordered(b).first);
}
