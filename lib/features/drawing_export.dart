import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../app/settings.dart';
import '../app/tokens.dart';
import '../core/analysis/build_schedule.dart';
import '../core/analysis/cost_estimate.dart';
import '../core/analysis/heat_loss.dart';
import '../core/analysis/house_analysis.dart';
import '../core/analysis/site_analysis.dart';
import '../core/analysis/utility_plan.dart';
import '../core/document/house_document.dart';
import '../core/geometry/derived_house.dart';
import '../render2d/floor_plan_painter.dart';
import '../render2d/planning_names.dart';
import '../render2d/section_painters.dart';
import '../render2d/site_plan_painter.dart';
import '../render3d/scene_model.dart';
import '../render3d/scene_view.dart';

/// A drawing set to print or send to builders: A4 landscape sheets drawn
/// with the app's own painters (plans, sections, 3D, site) and tables,
/// each with a title block, put together as a PDF. Text follows the
/// interface language.

/// A4 landscape at 150 dpi.
const sheetWidth = 1754.0, sheetHeight = 1240.0;

const _ink = Color(0xff1C2326), _muted = Color(0xff5B666B), _line = Color(0xffC8D0D2);

/// What the sheets need from the editor besides the design.
class DrawingInput {
  const DrawingInput(
      {required this.doc,
      required this.derived,
      required this.roomName,
      required this.floorName,
      required this.openingLabel,
      required this.date});
  final HouseDocument doc;
  final DerivedHouse derived;
  final String Function(Room room) roomName;
  final String Function(String name) floorName;
  final String Function(OpeningPlacement p, int floorIndex) openingLabel;

  /// Shown in the title block, "YYYY-MM-DD".
  final String date;
}

class _Cell {
  const _Cell(this.text, {this.numeric = false, this.bold = false, this.muted = false});
  final String text;
  final bool numeric, bold, muted;
}

typedef _Draw = void Function(Canvas canvas, Rect area);

class _Sheet {
  const _Sheet(this.title, this.draw);
  final String title;
  final _Draw draw;
}

TextPainter _tp(String text,
    {double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = _ink,
    bool monospace = false,
    double? maxWidth,
    int? maxLines,
    TextAlign align = TextAlign.left}) {
  final style = monospace
      ? mono(size: size, weight: weight, color: color)
      : TextStyle(
          fontFamily: fontBody,
          fontFamilyFallback: bodyFallback,
          fontSize: size,
          height: 1.3,
          fontWeight: weight,
          color: color);
  return TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: maxLines,
      ellipsis: maxLines == null ? null : '…')
    ..layout(maxWidth: maxWidth ?? double.infinity);
}

/// Paints [text] with its top-left at [at]; returns its height.
double _text(Canvas c, String text, Offset at,
    {double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = _ink,
    bool monospace = false,
    double? maxWidth,
    int? maxLines}) {
  final p = _tp(text,
      size: size,
      weight: weight,
      color: color,
      monospace: monospace,
      maxWidth: maxWidth,
      maxLines: maxLines);
  p.paint(c, at);
  return p.height;
}

const _rowHeight = 27.0, _headHeight = 30.0;

/// Rows of a table that fit [height].
int _rowsFitting(double height) =>
    math.max(1, ((height - _headHeight) / _rowHeight).floor());

/// A plain table from the top of [area]; returns the height used.
double _table(Canvas c, Rect area, List<String> header, List<List<_Cell>> rows,
    List<double> flex) {
  final total = flex.fold(0.0, (s, f) => s + f);
  final widths = [for (final f in flex) area.width * f / total];
  final pen = Paint()
    ..color = _line
    ..strokeWidth = 1;
  var y = area.top;
  var x = area.left;
  for (var i = 0; i < header.length; i++) {
    final p = _tp(header[i],
        size: 13,
        color: _muted,
        weight: FontWeight.w500,
        maxWidth: widths[i] - 12,
        maxLines: 1);
    final numeric = rows.isNotEmpty && i < rows.first.length && rows.first[i].numeric;
    p.paint(c, Offset(numeric ? x + widths[i] - 6 - p.width : x + 6, y + 7));
    x += widths[i];
  }
  y += _headHeight;
  c.drawLine(Offset(area.left, y), Offset(area.right, y),
      Paint()
        ..color = _ink
        ..strokeWidth = 1.2);
  for (final row in rows) {
    x = area.left;
    for (var i = 0; i < row.length && i < widths.length; i++) {
      final cell = row[i];
      final p = _tp(cell.text,
          size: 14,
          weight: cell.bold ? FontWeight.w700 : FontWeight.w400,
          color: cell.muted ? _muted : _ink,
          monospace: cell.numeric,
          maxWidth: widths[i] - 12,
          maxLines: 1);
      p.paint(c,
          Offset(cell.numeric ? x + widths[i] - 6 - p.width : x + 6, y + 5));
      x += widths[i];
    }
    y += _rowHeight;
    c.drawLine(Offset(area.left, y), Offset(area.right, y), pen);
  }
  return y - area.top;
}

/// Key–value lines in two columns; returns the height used.
double _figures(Canvas c, Rect area, List<(String, String)> items) {
  var y = area.top;
  for (final (label, value) in items) {
    _text(c, label, Offset(area.left, y), size: 14, color: _muted,
        maxWidth: area.width * 0.55, maxLines: 1);
    final p = _tp(value, size: 15, weight: FontWeight.w600, monospace: true,
        maxWidth: area.width * 0.45, maxLines: 1);
    p.paint(c, Offset(area.right - p.width, y));
    y += 28;
    c.drawLine(Offset(area.left, y - 4), Offset(area.right, y - 4),
        Paint()
          ..color = _line
          ..strokeWidth = 0.8);
  }
  return y - area.top;
}

void _heading(Canvas c, Offset at, String text) =>
    _text(c, text, at, size: 17, weight: FontWeight.w700);

/// Paints a whole sheet: frame, title block and the sheet's content.
void _paintSheet(Canvas c, _Sheet sheet, DrawingInput input, int number, int count) {
  c.drawRect(const Rect.fromLTWH(0, 0, sheetWidth, sheetHeight),
      Paint()..color = Colors.white);
  final frame = const Rect.fromLTRB(36, 36, sheetWidth - 36, sheetHeight - 36);
  final pen = Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  c.drawRect(frame, pen);
  // Title block along the bottom.
  final strip = Rect.fromLTRB(frame.left, frame.bottom - 78, frame.right, frame.bottom);
  c.drawLine(strip.topLeft, strip.topRight, pen);
  final cells = [0.34, 0.30, 0.12, 0.12, 0.12];
  var x = strip.left;
  final values = [
    (tr('工程名称', 'Жоба'), input.doc.meta.name),
    (tr('图名', 'Сызба'), sheet.title),
    (tr('图号', 'Нөмірі'), 'A-${number.toString().padLeft(2, '0')} / $count'),
    (tr('日期', 'Күні'), input.date),
    (tr('单位', 'Бірлік'), tr('毫米 · 示意', 'мм · сызба-нұсқа')),
  ];
  for (var i = 0; i < cells.length; i++) {
    final w = strip.width * cells[i];
    if (i > 0)
      c.drawLine(Offset(x, strip.top), Offset(x, strip.bottom),
          Paint()
            ..color = _ink
            ..strokeWidth = 1);
    _text(c, values[i].$1, Offset(x + 12, strip.top + 10), size: 12, color: _muted);
    _text(c, values[i].$2, Offset(x + 12, strip.top + 32),
        size: i < 2 ? 20 : 15,
        weight: i < 2 ? FontWeight.w700 : FontWeight.w500,
        maxWidth: w - 24,
        maxLines: 1);
    x += w;
  }
  _text(c, sheet.title, Offset(frame.left + 24, frame.top + 18),
      size: 26, weight: FontWeight.w700);
  final area = Rect.fromLTRB(
      frame.left + 24, frame.top + 66, frame.right - 24, strip.top - 18);
  c.save();
  c.clipRect(area.inflate(8));
  sheet.draw(c, area);
  c.restore();
}

/// Paints [painter] scaled into [area] as if it were [size] on screen.
void _fit(Canvas c, Rect area, CustomPainter painter, {double zoom = 1}) {
  c.save();
  c.translate(area.left, area.top);
  c.scale(zoom);
  painter.paint(c, Size(area.width / zoom, area.height / zoom));
  c.restore();
}

FloorPlanPainter _plan(DrawingInput input, int f,
    {bool furniture = true,
    bool utilities = false,
    bool foundation = false}) {
  final doc = input.doc, g = input.derived.floors[f];
  final floor = doc.floors[f];
  return FloorPlanPainter(
      g.base,
      {for (final r in floor.rooms) r.id: input.roomName(r)},
      const {},
      openings: g.openings,
      stairs: g.stairs,
      northAngleDeg: doc.footprint.northAngleDeg,
      viewportInsets: const EdgeInsets.fromLTRB(70, 70, 80, 70),
      tokens: Tokens.light,
      bearingMin: doc.extras.foundation.bearingMin,
      furniture: [
        for (final i in doc.extras.furniture)
          if (i.floorId == floor.id) i
      ],
      showFurniture: furniture,
      utilities: utilities
          ? [
              for (final u in doc.extras.utilities)
                if (u.floorId == floor.id) u
            ]
          : const [],
      foundation: foundation ? foundationTakeoff(doc, input.derived) : null,
      sleeves: foundation ? doc.extras.sleeves : const []);
}

String _n(double v, [int digits = 1]) => dec(v.toStringAsFixed(digits));

List<_Sheet> _sheets(DrawingInput input) {
  final doc = input.doc, derived = input.derived, x = doc.extras;
  final sheets = <_Sheet>[];
  final multi = doc.floors.length > 1;
  final cost = estimateCost(doc, derived, currency: languageCurrency);
  final loss = heatLoss(doc, derived);
  final sym = currencySymbol(cost.currency);
  final roofName = switch (doc.roof.type) {
    RoofType.flat => tr('平屋顶', 'Тегіс шатыр'),
    RoofType.gable => tr('双坡屋顶', 'Қос беткейлі шатыр'),
    RoofType.hip => tr('四坡屋顶', 'Төрт беткейлі шатыр'),
  };

  // 1. Cover: the house in 3D and the main figures.
  sheets.add(_Sheet(tr('总说明与效果图', 'Жалпы мәлімет және көрініс'), (c, area) {
    final picture = Rect.fromLTRB(area.left, area.top, area.left + area.width * 0.62, area.bottom);
    final model = buildScene(doc, derived, const SceneOptions(), input.roomName);
    final pose = viewPose(model, 'iso');
    c.save();
    c.clipRect(picture);
    c.translate(picture.left, picture.top);
    ScenePainter(
            model: model,
            camera: orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance),
            settings: const SceneSettings(),
            northAngleDeg: doc.footprint.northAngleDeg,
            walk: false,
            labels: false)
        .paint(c, picture.size);
    c.restore();
    final side = Rect.fromLTRB(picture.right + 36, area.top, area.right, area.bottom);
    var y = side.top;
    var area0 = 0.0;
    for (final g in derived.floors)
      for (final r in g.base.roomGeometry) area0 += r.clearArea / 1e6;
    y += _figures(c, Rect.fromLTRB(side.left, y, side.right, side.bottom), [
      (tr('外形尺寸', 'Сыртқы өлшемі'), '${_n(doc.footprint.width / 1000, 2)} × ${_n(doc.footprint.depth / 1000, 2)} ${tr('米', 'м')}'),
      (tr('层数', 'Қабат саны'), '${doc.floors.length}'),
      (tr('建筑面积 (各层)', 'Құрылыс ауданы'), '${_n(cost.buildingArea)} $unitM2'),
      (tr('室内净面积', 'Ішкі таза аудан'), '${_n(area0)} $unitM2'),
      (tr('外墙厚', 'Сыртқы қабырға'), '${doc.defaults.outerWallThickness} $unitMm'),
      (tr('屋顶', 'Шатыр'), roofName),
      (tr('条形基础', 'Таспалы іргетас'), '${x.foundation.width} × ${x.foundation.height}'),
      (tr('预算合计', 'Смета барлығы'), '$sym ${money(cost.total)}'),
      (tr('设计热负荷', 'Жылу жүктемесі'), '${_n(loss.total / 1000)} kW'),
      (tr('建议锅炉', 'Қазандық'), '${loss.boilerKw} kW'),
    ]);
    y += 20;
    _heading(c, Offset(side.left, y), tr('房间', 'Бөлмелер'));
    y += 30;
    final rows = <List<_Cell>>[];
    for (var f = 0; f < doc.floors.length; f++)
      for (final r in doc.floors[f].rooms) {
        final g = derived.floors[f].base.roomGeometry.firstWhere((s) => s.id == r.id);
        rows.add([
          _Cell(input.roomName(r)),
          if (multi) _Cell(input.floorName(doc.floors[f].name), muted: true),
          _Cell('${_n(g.clearArea / 1e6)} $unitM2', numeric: true),
        ]);
      }
    final fit = _rowsFitting(side.bottom - y);
    _table(c, Rect.fromLTRB(side.left, y, side.right, side.bottom),
        [tr('房间', 'Бөлме'), if (multi) tr('楼层', 'Қабат'), tr('净面积', 'Таза аудан')],
        rows.take(fit).toList(), multi ? [3, 2, 2] : [3, 2]);
  }));

  // 2. Floor plans.
  for (var f = 0; f < doc.floors.length; f++)
    sheets.add(_Sheet(
        '${input.floorName(doc.floors[f].name)} ${tr('平面图', 'жоспары')}',
        (c, area) => _fit(c, area, _plan(input, f), zoom: 1.25)));

  // 3. Electrical, water and heating points.
  for (var f = 0; f < doc.floors.length; f++) {
    final points = x.utilities.where((u) => u.floorId == doc.floors[f].id).toList();
    if (points.isEmpty) continue;
    sheets.add(_Sheet(
        '${input.floorName(doc.floors[f].name)} ${tr('水电暖点位图', 'су, электр, жылу нүктелері')}',
        (c, area) {
      final plan = Rect.fromLTRB(area.left, area.top, area.right - 360, area.bottom);
      _fit(c, plan, _plan(input, f, furniture: false, utilities: true), zoom: 1.25);
      final legend = Rect.fromLTRB(plan.right + 24, area.top, area.right, area.bottom);
      _heading(c, legend.topLeft, tr('图例与数量', 'Шартты белгі және саны'));
      final take = utilityTakeoff(doc);
      var y = legend.top + 36;
      for (final k in UtilityKind.values) {
        final n = points.where((u) => u.kind == k).length;
        if (n == 0) continue;
        final color = switch (k) {
          UtilityKind.water || UtilityKind.drain => Tokens.light.chk,
          UtilityKind.radiator => Tokens.light.rug,
          _ => Tokens.light.accent,
        };
        c.drawCircle(Offset(legend.left + 8, y + 10), 6, Paint()..color = color);
        _text(c, utilityName(k), Offset(legend.left + 24, y), size: 15);
        final p = _tp('$n', size: 15, monospace: true);
        p.paint(c, Offset(legend.right - p.width, y));
        y += 30;
      }
      y += 16;
      _figures(c, Rect.fromLTRB(legend.left, y, legend.right, legend.bottom), [
        (tr('照明线 3×1.5', 'Жарық сымы 3×1,5'), '${money(take.lightCable)} $unitM'),
        (tr('插座线 3×2.5', 'Розетка сымы 3×2,5'), '${money(take.powerCable)} $unitM'),
        (tr('给水管 (冷热)', 'Су құбыры (суық+ыстық)'), '${money(take.waterPipe)} $unitM'),
        (tr('排水管', 'Кәріз құбыры'), '${money(take.drainPipe)} $unitM'),
        (tr('暖气管 (供回)', 'Жылу құбыры'), '${money(take.heatingPipe)} $unitM'),
      ]);
    }));
  }

  // 4. Foundation plan and section.
  final fd = foundationTakeoff(doc, derived), f0 = x.foundation;
  sheets.add(_Sheet(tr('基础平面图与剖面', 'Іргетас жоспары және қимасы'), (c, area) {
    final plan = Rect.fromLTRB(area.left, area.top, area.left + area.width * 0.58, area.bottom);
    _fit(c, plan, _plan(input, 0, furniture: false, foundation: true), zoom: 1.2);
    final side = Rect.fromLTRB(plan.right + 30, area.top, area.right, area.bottom);
    final section = FoundationSectionPainter(Tokens.light, f0,
        doc.defaults.outerWallThickness, {
      'ground': tr('室外地面', 'жер беті'),
      'wall': '${tr('外墙', 'Сыртқы қабырға')} ${doc.defaults.outerWallThickness}',
      'damp': tr('水平防水：2 层卷材', 'Көлденең гидрооқшау: 2 қабат'),
      'topBars': '${tr('上部纵筋', 'Үстіңгі арматура')} ${f0.topBars}Ø${f0.barDia}',
      'floor': tr('地坪（见地坪构造）', 'Еден (еден құрылымын қараңыз)'),
      'stirrups': '${tr('箍筋', 'Қамыт')} Ø${f0.stirrupDia} @${f0.stirrupStep}',
      'concrete': '${tr('混凝土', 'Бетон')} ${f0.concrete}',
      'bottomBars': '${tr('下部纵筋', 'Астыңғы арматура')} ${f0.bottomBars}Ø${f0.barDia}',
      'cover': '${tr('保护层', 'Қорғаныш қабаты')} ${f0.cover} $unitMm',
      'cushion': '${tr('砂砾石垫层', 'Құм-қиыршық')} ${f0.cushion}',
      'blind': tr('保温散水 1000 · 下铺 XPS 50', 'Жылы отмостка 1000 · астында XPS 50'),
      'xps': tr('XPS 50 + 沥青防水', 'XPS 50 + битум'),
    });
    final h = math.min(side.height * 0.55, side.width * section.viewH / section.viewW);
    final w = h * section.viewW / section.viewH;
    c.save();
    c.translate(side.left, side.top);
    section.paint(c, Size(w, h));
    c.restore();
    final rebar = (fd.mainBarLength / 1000 * barKgPerM(f0.barDia) +
            fd.partitionBarLength / 1000 * barKgPerM(f0.partitionBarDia) +
            fd.stirrupLength / 1000 * barKgPerM(f0.stirrupDia) +
            fd.partitionStirrupLength / 1000 * barKgPerM(f0.partitionStirrupDia)) /
        1000;
    _figures(c, Rect.fromLTRB(side.left, side.top + h + 24, side.right, side.bottom), [
      (tr('基础长度', 'Іргетас ұзындығы'), '${_n((fd.mainLength + fd.partitionLength) / 1000)} $unitM'),
      (tr('混凝土 (+3%)', 'Бетон (+3%)'), '${_n(fd.concrete * 1.03 / 1e9)} $unitM3'),
      (tr('钢筋', 'Арматура'), '${_n(rebar, 2)} ${tr('吨', 'т')}'),
      (tr('挖土', 'Қазу'), '${_n(fd.excavation / 1e9)} $unitM3'),
      (tr('砂砾石垫层', 'Құм-қиыршық'), '${_n(fd.cushion / 1e9)} $unitM3'),
      (tr('模板', 'Қалып'), '${_n(fd.formwork / 1e6)} $unitM2'),
      (tr('预留套管', 'Гильзалар'), '${x.sleeves.length}'),
    ]);
  }));

  // 5. Wall, roof and floor build-ups.
  sheets.add(_Sheet(tr('构造做法', 'Құрылым шешімдері'), (c, area) {
    final groups = [
      ('${tr('外墙', 'Сыртқы қабырға')} · U ${_n(loss.wallU, 2)}', x.wallLayers, true),
      ('$roofName · U ${_n(loss.roofU, 2)}', x.roofLayers, false),
      ('${tr('首层地面', 'Бірінші қабат едені')} · U ${_n(loss.floorU, 2)}', x.floorLayers, false),
    ];
    final colW = (area.width - 2 * 30) / 3;
    for (var i = 0; i < groups.length; i++) {
      final (title, layers, horizontal) = groups[i];
      final col = Rect.fromLTWH(area.left + i * (colW + 30), area.top, colW, area.height);
      _heading(c, col.topLeft, '$title · ${layers.fold(0, (s, l) => s + l.thickness)} $unitMm');
      final names = [for (final l in layers) isKk ? l.nameKk : l.name];
      final SectionPainter painter = horizontal
          ? WallSectionPainter(Tokens.light, layers, names,
              outside: tr('室外', 'Сырты'), inside: tr('室内', 'Іші'))
          : LayerStackPainter(Tokens.light, layers, names, scale: 0.2);
      final h = math.min(col.height * 0.5, colW * painter.viewH / painter.viewW);
      final w = h * painter.viewW / painter.viewH;
      c.save();
      c.translate(col.left, col.top + 36);
      painter.paint(c, Size(w, h));
      c.restore();
      _table(c, Rect.fromLTRB(col.left, col.top + 36 + h + 20, col.right, col.bottom),
          [tr('构造层', 'Қабат'), unitMm, 'λ'], [
        for (final l in layers)
          [
            _Cell(isKk ? l.nameKk : l.name),
            _Cell('${l.thickness}', numeric: true),
            _Cell(dec((l.conductivity / 1000).toStringAsFixed(3)), numeric: true),
          ]
      ], [5, 1.3, 1.5]);
    }
  }));

  // 6. Door and window schedule; room areas.
  final openingRows = <List<_Cell>>[];
  var doorNo = 0, windowNo = 0;
  for (var f = 0; f < doc.floors.length; f++)
    for (final p in derived.floors[f].openings) {
      final o = p.opening;
      final door = o.kind != OpeningKind.window;
      openingRows.add([
        _Cell(door ? 'M${++doorNo}' : 'C${++windowNo}', bold: true),
        if (multi) _Cell(input.floorName(doc.floors[f].name), muted: true),
        _Cell(input.openingLabel(p, f)),
        _Cell('${o.width} × ${o.height}', numeric: true),
        _Cell(o.sill == 0 ? '—' : '${o.sill}', numeric: true),
        _Cell(switch (o) {
          DoorOpening() => tr('平开门', 'Ашылмалы есік'),
          SlidingOpening() => tr('推拉门', 'Сырғымалы есік'),
          WindowOpening() => tr('窗', 'Терезе'),
        }),
      ]);
    }
  final roomRows = <List<_Cell>>[];
  for (var f = 0; f < doc.floors.length; f++)
    for (final r in doc.floors[f].rooms) {
      final g = derived.floors[f].base.roomGeometry.firstWhere((s) => s.id == r.id);
      final label = x.rooms[r.id]?.labelArea;
      roomRows.add([
        _Cell(input.roomName(r)),
        if (multi) _Cell(input.floorName(doc.floors[f].name), muted: true),
        _Cell(_n(g.clearArea / 1e6), numeric: true),
        _Cell(label == null ? '—' : _n(label / 100), numeric: true),
      ]);
    }
  const scheduleRows = 30;
  final pages = math.max(1,
      math.max((openingRows.length / scheduleRows).ceil(), (roomRows.length / scheduleRows).ceil()));
  for (var page = 0; page < pages; page++)
    sheets.add(_Sheet(
        '${tr('门窗表与房间面积', 'Есік-терезе және бөлме аудандары')}${pages > 1 ? ' (${page + 1})' : ''}',
        (c, area) {
      final left = Rect.fromLTRB(area.left, area.top, area.left + area.width * 0.6, area.bottom);
      _heading(c, left.topLeft, tr('门窗表', 'Есік-терезе кестесі'));
      _table(c, Rect.fromLTRB(left.left, left.top + 32, left.right, left.bottom), [
        tr('编号', 'Код'),
        if (multi) tr('楼层', 'Қабат'),
        tr('位置', 'Орны'),
        tr('宽 × 高', 'Ені × биіктігі'),
        tr('窗台', 'Терезе алды'),
        tr('类型', 'Түрі'),
      ], openingRows.skip(page * scheduleRows).take(scheduleRows).toList(),
          multi ? [1, 1.4, 3.6, 2, 1.2, 1.6] : [1, 4, 2, 1.2, 1.6]);
      final right = Rect.fromLTRB(left.right + 30, area.top, area.right, area.bottom);
      _heading(c, right.topLeft, tr('房间面积 (实算 / 图纸)', 'Бөлме ауданы (есеп / сызба)'));
      _table(c, Rect.fromLTRB(right.left, right.top + 32, right.right, right.bottom), [
        tr('房间', 'Бөлме'),
        if (multi) tr('楼层', 'Қабат'),
        tr('实算 m²', 'Есеп, м²'),
        tr('图纸 m²', 'Сызба, м²'),
      ], roomRows.skip(page * scheduleRows).take(scheduleRows).toList(),
          multi ? [3, 2, 2, 2] : [3, 2, 2]);
    }));

  // 7. Budget.
  final costRows = <List<_Cell>>[];
  for (final stage in costStages) {
    final lines = cost.lines.where((l) => l.stage == stage).toList();
    if (lines.isEmpty) continue;
    costRows.add([
      _Cell(costStageName(stage), bold: true),
      const _Cell(''),
      const _Cell(''),
      _Cell(money(cost.stageMaterials(stage)), numeric: true, bold: true),
    ]);
    for (final l in lines)
      costRows.add([
        _Cell('   ${l.custom ? l.name! : costLineName(l.key)}${l.estimated ? tr(' (估)', ' (шамамен)') : ''}',
            muted: l.estimated),
        _Cell('${_n(l.quantity, l.quantity >= 100 ? 0 : 2)} ${l.custom ? l.unit : unitName(l.unit)}', numeric: true),
        _Cell(money(l.price), numeric: true),
        _Cell(money(l.total), numeric: true),
      ]);
  }
  costRows.addAll([
    [_Cell(tr('材料合计', 'Материалдар'), bold: true), const _Cell(''), const _Cell(''), _Cell(money(cost.materials), numeric: true, bold: true)],
    [_Cell('${tr('人工', 'Жұмыс ақысы')} ${cost.labourPct}%', bold: true), const _Cell(''), const _Cell(''), _Cell(money(cost.labour), numeric: true, bold: true)],
    [_Cell('${tr('预备费', 'Резерв')} ${cost.contingencyPct}%', bold: true), const _Cell(''), const _Cell(''), _Cell(money(cost.contingency), numeric: true, bold: true)],
    [_Cell('${tr('总计', 'Барлығы')} ($sym)', bold: true), _Cell('${money(cost.perArea)} $sym/$unitM2', numeric: true, muted: true), const _Cell(''), _Cell(money(cost.total), numeric: true, bold: true)],
  ]);
  const costPerColumn = 31;
  final costColumns = (costRows.length / costPerColumn).ceil();
  for (var page = 0; page < (costColumns / 2).ceil(); page++)
    sheets.add(_Sheet(
        '${tr('造价预算', 'Құрылыс сметасы')} ($sym)${costColumns > 2 ? ' (${page + 1})' : ''}',
        (c, area) {
      final colW = (area.width - 30) / 2;
      for (var k = 0; k < 2; k++) {
        final chunk = costRows
            .skip((page * 2 + k) * costPerColumn)
            .take(costPerColumn)
            .toList();
        if (chunk.isEmpty) continue;
        _table(c, Rect.fromLTWH(area.left + k * (colW + 30), area.top, colW, area.height), [
          tr('项目', 'Атауы'),
          tr('数量', 'Мөлшері'),
          tr('单价', 'Бағасы'),
          tr('金额', 'Сомасы'),
        ], chunk, [4, 2, 1.6, 1.8]);
      }
      final note = tr('单价为示例或用户填写，工程量按模型计算，未含损耗以外的变更。仅供估算和与施工方沟通。',
          'Бағалар — мысал не пайдаланушы енгізгені, көлемдер модельден есептелген. Тек бағалау және құрылысшымен сөйлесу үшін.');
      _text(c, note, Offset(area.left, area.bottom - 22), size: 12, color: _muted,
          maxWidth: area.width, maxLines: 1);
    }));

  // 8. Heat loss.
  sheets.add(_Sheet(tr('保温与采暖计算', 'Жылу шығыны есебі'), (c, area) {
    final colW = (area.width - 30) / 2;
    final left = Rect.fromLTWH(area.left, area.top, colW, area.height);
    var y = left.top;
    y += _figures(c, Rect.fromLTRB(left.left, y, left.right, left.bottom), [
      (tr('室外 / 室内计算温度', 'Сыртқы / ішкі температура'), '${x.heat.outdoor} / ${x.heat.indoor} °C'),
      (tr('设计热负荷', 'Есептік жүктеме'), '${_n(loss.total / 1000)} kW'),
      (tr('每平方米', 'Әр шаршы метрге'), '${loss.perArea.round()} W/$unitM2'),
      (tr('建议锅炉', 'Ұсынылатын қазандық'), '${loss.boilerKw} kW'),
      (tr('采暖季用热', 'Маусымдық жылу'), '${money(loss.seasonKwh)} kWh'),
      ('${tr('燃料', 'Отын')} · ${fuelName(x.heat.fuel)}', '${_n(loss.fuel)} ${fuelUnit(x.heat.fuel)}'),
    ]);
    y += 24;
    _table(c, Rect.fromLTRB(left.left, y, left.right, left.bottom), [
      tr('部位', 'Бөлік'), 'U W/(m²·K)', tr('面积', 'Аудан'), 'W'
    ], [
      for (final (name, u, a, w) in [
        (tr('外墙', 'Сыртқы қабырға'), loss.wallU, loss.wallArea, loss.walls),
        (tr('窗', 'Терезе'), loss.windowU, loss.windowArea, loss.windows),
        (tr('外门', 'Сыртқы есік'), loss.doorU, loss.doorArea, loss.doors),
        (tr('屋顶', 'Шатыр'), loss.roofU, loss.roofArea, loss.roof),
        (tr('地面', 'Еден'), loss.floorU, loss.floorArea, loss.floor),
      ])
        [
          _Cell(name),
          _Cell(_n(u, 2), numeric: true),
          _Cell('${_n(a)} $unitM2', numeric: true),
          _Cell(money(w), numeric: true),
        ],
      [
        _Cell(tr('通风换气', 'Желдету')),
        const _Cell('—', numeric: true),
        _Cell('${_n(loss.volume)} $unitM3', numeric: true),
        _Cell(money(loss.air), numeric: true),
      ],
    ], [3, 2, 2, 2]);
    final right = Rect.fromLTWH(area.left + colW + 30, area.top, colW, area.height);
    final rows = <List<_Cell>>[];
    for (final s in loss.spaces) {
      final room = doc.floors[s.floorIndex].rooms.where((r) => r.id == s.id).firstOrNull;
      if (room == null || s.total <= 0) continue;
      rows.add([
        _Cell(input.roomName(room)),
        _Cell(_n(s.area), numeric: true),
        _Cell(money(s.total), numeric: true),
        _Cell('${s.sections}', numeric: true),
      ]);
    }
    _table(c, right, [
      tr('房间', 'Бөлме'), unitM2, 'W', tr('暖气片 片', 'Секция')
    ], rows.take(_rowsFitting(right.height)).toList(), [3, 1.5, 1.5, 1.5]);
  }));

  // 9. Site plan.
  final site = x.site;
  if (site != null)
    sheets.add(_Sheet(tr('宅基地总平面图', 'Учаскенің бас жоспары'), (c, area) {
      final plan = Rect.fromLTRB(area.left, area.top, area.right - 420, area.bottom);
      c.save();
      c.translate(plan.left, plan.top);
      SitePlanPainter(doc: doc, site: site, tokens: Tokens.light).paint(c, plan.size);
      c.restore();
      final side = Rect.fromLTRB(plan.right + 24, area.top, area.right, area.bottom);
      var y = side.top;
      y += _figures(c, Rect.fromLTRB(side.left, y, side.right, side.bottom), [
        (tr('宅基地', 'Учаске'), '${_n(site.width / 1000)} × ${_n(site.depth / 1000)} ${tr('米', 'м')}'),
        (tr('占地', 'Аудан'), '${_n(site.width * site.depth / 1e6, 0)} $unitM2'),
        for (final i in site.items)
          (i.label ?? siteName(i.kind), '${_n(i.width / 1000)} × ${_n(i.depth / 1000)}'),
      ]);
      final checks =
          siteChecks(doc, nameOf: (i) => i.label ?? siteName(i.kind));
      if (checks.isNotEmpty) {
        y += 16;
        _heading(c, Offset(side.left, y), tr('间距检查', 'Арақашықтық тексеруі'));
        y += 32;
        for (final ch in checks) {
          if (y > side.bottom - 40) break;
          y += _text(c, '• ${tr(ch.title.$1, ch.title.$2)}', Offset(side.left, y),
                  size: 14, weight: FontWeight.w600, maxWidth: side.width) +
              2;
          y += _text(c, tr(ch.text.$1, ch.text.$2), Offset(side.left + 14, y),
                  size: 12, color: _muted, maxWidth: side.width - 14, maxLines: 4) +
              8;
        }
      }
    }));

  // 10. Schedule.
  final plan = planStages(x.stages);
  final budgets = stageBudgets(cost);
  sheets.add(_Sheet(tr('施工进度计划', 'Құрылыс кестесі'), (c, area) {
    _table(c, area, [
      '#',
      tr('阶段', 'Кезең'),
      tr('状态', 'Күйі'),
      tr('开工', 'Басталуы'),
      tr('完工', 'Аяқталуы'),
      tr('天', 'Күн'),
      '${tr('预算', 'Смета')} $sym',
      '${tr('已花', 'Жұмсалды')} $sym',
      tr('检查', 'Тексеру'),
    ], [
      for (var i = 0; i < plan.length; i++)
        [
          _Cell('${i + 1}', muted: true),
          _Cell(stageName(plan[i].stage), bold: true),
          _Cell(statusName(plan[i].stage.status)),
          _Cell(plan[i].start == null ? '—' : formatDay(plan[i].start!), numeric: true),
          _Cell(plan[i].end == null ? '—' : formatDay(plan[i].end!), numeric: true),
          _Cell('${plan[i].stage.days}', numeric: true),
          _Cell(budgets[plan[i].stage.key] == null ? '—' : money(budgets[plan[i].stage.key]!), numeric: true),
          _Cell(money(plan[i].stage.spent), numeric: true),
          _Cell('${plan[i].stage.checks.length}/${stageChecks[plan[i].stage.key]?.length ?? 0}', numeric: true),
        ]
    ], [0.5, 3, 1.4, 1.8, 1.8, 0.9, 2, 2, 1.1]);
  }));
  return sheets;
}

Future<Uint8List> _rasterize(_Sheet sheet, DrawingInput input, int number, int count) async {
  final recorder = ui.PictureRecorder();
  _paintSheet(Canvas(recorder), sheet, input, number, count);
  final picture = recorder.endRecording();
  final image = await picture.toImage(sheetWidth.round(), sheetHeight.round());
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Lays every sheet's text out once so fonts for all the characters are
/// fetched before the real drawing (the web loads fallback fonts lazily).
Future<void> _warmUp(List<_Sheet> sheets, DrawingInput input) async {
  for (var i = 0; i < sheets.length; i++) {
    final recorder = ui.PictureRecorder();
    _paintSheet(Canvas(recorder), sheets[i], input, i + 1, sheets.length);
    recorder.endRecording().dispose();
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
}

/// The whole drawing set as a PDF, one A4 landscape page per sheet.
Future<Uint8List> buildDrawingPdf(DrawingInput input,
    {void Function(int done, int total)? onProgress}) async {
  final sheets = _sheets(input);
  await _warmUp(sheets, input);
  final document = pw.Document(
      title: input.doc.meta.name, creator: tr('自建房设计', 'Үй жобалау'));
  for (var i = 0; i < sheets.length; i++) {
    final png = await _rasterize(sheets[i], input, i + 1, sheets.length);
    document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain)));
    onProgress?.call(i + 1, sheets.length);
    // Let the progress dialog repaint between pages.
    await Future<void>.delayed(Duration.zero);
  }
  return document.save();
}

/// One floor's plan sheet as a PNG, for chat apps.
Future<Uint8List> buildPlanPng(DrawingInput input, int floorIndex) async {
  final sheets = _sheets(input);
  final title = '${input.floorName(input.doc.floors[floorIndex].name)} ${tr('平面图', 'жоспары')}';
  final index = sheets.indexWhere((s) => s.title == title);
  await _warmUp([sheets[index]], input);
  return _rasterize(sheets[index], input, index + 1, sheets.length);
}

/// Names of the sheets in the set, for tests and the export dialog.
List<String> drawingSheetTitles(DrawingInput input) =>
    [for (final s in _sheets(input)) s.title];
