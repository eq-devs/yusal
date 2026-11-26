import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/constant/tokens.dart';
import 'package:yusal/features/editor/engine/core/analysis/build_schedule.dart';
import 'package:yusal/features/editor/engine/core/analysis/cost_estimate.dart';
import 'package:yusal/features/editor/engine/core/analysis/heat_loss.dart';
import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';
import 'package:yusal/features/editor/engine/core/analysis/materials.dart';
import 'package:yusal/features/editor/engine/core/analysis/site_analysis.dart';
import 'package:yusal/features/editor/engine/core/analysis/utility_plan.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/engine/render2d/planning_names.dart';
import 'package:yusal/features/editor/engine/render2d/section_painters.dart';
import 'package:yusal/features/editor/engine/render2d/site_plan_painter.dart';
import 'package:yusal/features/editor/engine/render3d/scene_model.dart';
import 'package:yusal/features/editor/engine/render3d/scene_view.dart';

/// A drawing set to print or send to builders: A4 landscape sheets drawn
/// with the app's own painters (plans, sections, 3D, site) and tables,
/// each with a title block, put together as a PDF. Text follows the
/// interface language.

/// A4 landscape at 150 dpi.
const sheetWidth = 1754.0;
const sheetHeight = 1240.0;

const _ink = Color(0xff1C2326);
const _muted = Color(0xff5B666B);
const _line = Color(0xffC8D0D2);

/// What the sheets need from the editor besides the design.
class DrawingInput {
  const DrawingInput(
      {required this.doc,
      required this.derived,
      required this.roomName,
      required this.floorName,
      required this.openingLabel,
      required this.date,
      this.book});
  final HouseDocument doc;

  /// The price list of the design's region, when one was read.
  final PriceBook? book;
  final DerivedHouse derived;
  final String Function(Room room) roomName;
  final String Function(String name) floorName;
  final String Function(OpeningPlacement p, int floorIndex) openingLabel;

  /// Shown in the title block, "YYYY-MM-DD".
  final String date;
}

class _Cell {
  const _Cell(this.text,
      {this.numeric = false, this.bold = false, this.muted = false});
  final String text;
  final bool numeric;
  final bool bold;
  final bool muted;
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
      maxLines: maxLines)
    ..paint(c, at);
  return p.height;
}

const _rowHeight = 27.0;
const _headHeight = 30.0;

/// Where a sheet's drawing goes: inside the frame, under the title, over
/// the title block.
const _sheetArea = Rect.fromLTRB(60, 102, sheetWidth - 60, 1108);

/// A table's rows beyond what its own sheet shows go on sheets of their
/// own, all of them, so nothing is cut off. A table on a sheet with other
/// content shows what fits and ends with a row pointing here.
List<_Sheet> _scheduleSheets(String title, List<String> header,
    List<List<_Cell>> rows, List<double> flex) {
  final per = _rowsFitting(_sheetArea.height);
  final pages = (rows.length / per).ceil();
  return [
    for (var p = 0; p < pages; p++)
      _Sheet(pages == 1 ? title : '$title ${p + 1}/$pages', (c, area) {
        _table(c, area, header,
            rows.sublist(p * per, math.min(rows.length, (p + 1) * per)), flex);
      })
  ];
}

/// [rows] as they fit [fit] rows: all of them, or the first ones and a
/// last row saying the rest are on the schedule sheets.
List<List<_Cell>> _shown(List<List<_Cell>> rows, int fit, int columns) {
  if (rows.length <= fit) return rows;
  final rest = rows.length - (fit - 1);
  return [
    ...rows.take(fit - 1),
    [
      _Cell(
          tr3('… 另有 $rest 行，见附表', '… тағы $rest жол, кестені қараңыз',
              '… ещё строк: $rest, см. ведомость', '… $rest more rows, see the schedule',
              ky: '… дагы $rest сап, тизмени караңыз', uz: '… yana $rest qator, jadvalga qarang'),
          muted: true),
      for (var i = 1; i < columns; i++) const _Cell(''),
    ]
  ];
}

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
    final numeric =
        rows.isNotEmpty && i < rows.first.length && rows.first[i].numeric;
    p.paint(c, Offset(numeric ? x + widths[i] - 6 - p.width : x + 6, y + 7));
    x += widths[i];
  }
  y += _headHeight;
  c.drawLine(
      Offset(area.left, y),
      Offset(area.right, y),
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
      p.paint(
          c, Offset(cell.numeric ? x + widths[i] - 6 - p.width : x + 6, y + 5));
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
    _text(c, label, Offset(area.left, y),
        size: 14, color: _muted, maxWidth: area.width * 0.55, maxLines: 1);
    final p = _tp(value,
        weight: FontWeight.w600,
        monospace: true,
        maxWidth: area.width * 0.45,
        maxLines: 1);
    p.paint(c, Offset(area.right - p.width, y));
    y += 28;
    c.drawLine(
        Offset(area.left, y - 4),
        Offset(area.right, y - 4),
        Paint()
          ..color = _line
          ..strokeWidth = 0.8);
  }
  return y - area.top;
}

void _heading(Canvas c, Offset at, String text) =>
    _text(c, text, at, size: 17, weight: FontWeight.w700);

/// Paints a whole sheet: frame, title block and the sheet's content.
void _paintSheet(
    Canvas c, _Sheet sheet, DrawingInput input, int number, int count) {
  c.drawRect(const Rect.fromLTWH(0, 0, sheetWidth, sheetHeight),
      Paint()..color = Colors.white);
  const frame = Rect.fromLTRB(36, 36, sheetWidth - 36, sheetHeight - 36);
  final pen = Paint()
    ..color = _ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2;
  c.drawRect(frame, pen);
  // Title block along the bottom.
  final strip =
      Rect.fromLTRB(frame.left, frame.bottom - 78, frame.right, frame.bottom);
  c.drawLine(strip.topLeft, strip.topRight, pen);
  final cells = [0.34, 0.30, 0.12, 0.12, 0.12];
  var x = strip.left;
  final values = [
    (tr3('工程名称', 'Жоба', 'Проект', 'Project', ky: 'Долбоор', uz: 'Loyiha'), input.doc.meta.name),
    (tr3('图名', 'Сызба', 'Чертёж', 'Drawing', ky: 'Чийилүүдө', uz: 'Chizilmoqda'), sheet.title),
    (
      tr3('图号', 'Нөмірі', 'Номер листа', 'Sheet no.', ky: 'Барак №', uz: 'Varaq №'),
      'A-${number.toString().padLeft(2, '0')} / $count'
    ),
    (tr3('日期', 'Күні', 'Дата', 'Date', ky: 'Күнү', uz: 'Sana'), input.date),
    (
      tr3('单位', 'Бірлік', 'Единицы', 'Units', ky: 'Бирдиктер', uz: 'Birliklar'),
      tr3('毫米 · 示意', 'мм · сызба-нұсқа', 'мм · схема', 'mm · schematic', ky: 'мм · схема', uz: 'mm · sxema')
    ),
  ];
  for (var i = 0; i < cells.length; i++) {
    final w = strip.width * cells[i];
    if (i > 0) {
      c.drawLine(
          Offset(x, strip.top),
          Offset(x, strip.bottom),
          Paint()
            ..color = _ink
            ..strokeWidth = 1);
    }
    _text(c, values[i].$1, Offset(x + 12, strip.top + 10),
        size: 12, color: _muted);
    _text(c, values[i].$2, Offset(x + 12, strip.top + 32),
        size: i < 2 ? 20 : 15,
        weight: i < 2 ? FontWeight.w700 : FontWeight.w500,
        maxWidth: w - 24,
        maxLines: 1);
    x += w;
  }
  _text(c, sheet.title, Offset(frame.left + 24, frame.top + 18),
      size: 26, weight: FontWeight.w700);
  const area = _sheetArea;
  c
    ..save()
    ..clipRect(area.inflate(8));
  sheet.draw(c, area);
  c.restore();
}

/// Paints [painter] scaled into [area] as if it were [size] on screen.
void _fit(Canvas c, Rect area, CustomPainter painter, {double zoom = 1}) {
  c
    ..save()
    ..translate(area.left, area.top)
    ..scale(zoom);
  painter.paint(c, Size(area.width / zoom, area.height / zoom));
  c.restore();
}

FloorPlanPainter _plan(DrawingInput input, int f,
    {bool furniture = true, bool utilities = false, bool foundation = false}) {
  final doc = input.doc;
  final g = input.derived.floors[f];
  final floor = doc.floors[f];
  return FloorPlanPainter(
      g.base, {for (final r in floor.rooms) r.id: input.roomName(r)}, const {},
      openings: g.openings,
      stairs: g.stairs,
      areaBasis: doc.extras.areaBasis,
      northAngleDeg: doc.footprint.northAngleDeg,
      viewportInsets: const EdgeInsets.fromLTRB(70, 70, 80, 70),
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
  final doc = input.doc;
  final derived = input.derived;
  final x = doc.extras;
  final sheets = <_Sheet>[];
  final multi = doc.floors.length > 1;
  final cost = estimateCost(doc, derived,
      currency: languageCurrency, book: input.book);
  final loss = heatLoss(doc, derived);
  final sym = currencySymbol(cost.currency);
  final roofName = switch (doc.roof.type) {
    RoofType.flat => tr3('平屋顶', 'Тегіс шатыр', 'Плоская крыша', 'Flat roof', ky: 'Жалпак чатыр', uz: 'Tekis tom'),
    RoofType.gable => tr3('双坡屋顶', 'Қос беткейлі шатыр', 'Двускатная крыша', 'Gable roof', ky: 'Эки капталдуу чатыр', uz: 'Ikki nishabli tom'),
    RoofType.hip => tr3('四坡屋顶', 'Төрт беткейлі шатыр', 'Вальмовая крыша', 'Hip roof', ky: 'Төрт капталдуу чатыр', uz: 'Toʻrt nishabli tom'),
  };

  // The cover lists what fits; the room schedule further on has them all.
  final coverRows = <List<_Cell>>[
    for (var f = 0; f < doc.floors.length; f++)
      for (final r in doc.floors[f].rooms)
        [
          _Cell(input.roomName(r)),
          if (multi) _Cell(input.floorName(doc.floors[f].name), muted: true),
          _Cell(
              '${_n(derived.floors[f].base.roomsById[r.id]!.area(x.areaBasis) / 1e6)} $unitM2',
              numeric: true),
        ]
  ];
  final roomHeader = [
    tr3('房间', 'Бөлме', 'Комната', 'Room', ky: 'Бөлмө', uz: 'Xona'),
    if (multi) tr3('楼层', 'Қабат', 'Этаж', 'Floor', ky: 'Кабат', uz: 'Qavat'),
    tr3('净面积', 'Таза аудан', 'Площадь нетто', 'Net area', ky: 'Таза аянт', uz: 'Sof maydon')
  ];
  final roomFlex = multi ? [3.0, 2.0, 2.0] : [3.0, 2.0];

  // 1. Cover: the house in 3D and the main figures.
  sheets.add(_Sheet(
      tr3('总说明与效果图', 'Жалпы мәлімет және көрініс',
          'Общие сведения и визуализация',
          'Overview and rendering', ky: 'Жалпы көрүнүш жана сүрөт', uz: 'Umumiy koʻrinish va tasvir'), (c, area) {
    final picture = Rect.fromLTRB(
        area.left, area.top, area.left + area.width * 0.62, area.bottom);
    final model =
        buildScene(doc, derived, const SceneOptions(), input.roomName);
    final pose = viewPose(model, 'iso');
    c
      ..save()
      ..clipRect(picture)
      ..translate(picture.left, picture.top);
    ScenePainter(
            model: model,
            camera:
                orbitCamera(pose.target, pose.yaw, pose.pitch, pose.distance),
            settings: const SceneSettings(),
            northAngleDeg: doc.footprint.northAngleDeg,
            walk: false,
            labels: false)
        .paint(c, picture.size);
    c.restore();
    final side =
        Rect.fromLTRB(picture.right + 36, area.top, area.right, area.bottom);
    var y = side.top;
    var area0 = 0.0;
    for (final g in derived.floors) {
      for (final r in g.base.roomGeometry) {
        area0 += r.area(doc.extras.areaBasis) / 1e6;
      }
    }
    y += _figures(c, Rect.fromLTRB(side.left, y, side.right, side.bottom), [
      (
        tr3('外形尺寸', 'Сыртқы өлшемі', 'Габаритные размеры', 'Overall dimensions', ky: 'Жалпы өлчөмдөр', uz: 'Umumiy oʻlchamlar'),
        '${_n(doc.footprint.width / 1000, 2)} × ${_n(doc.footprint.depth / 1000, 2)} ${tr3('米', 'м', 'м', 'm', ky: 'м', uz: 'm')}'
      ),
      (tr3('层数', 'Қабат саны', 'Число этажей', 'Floors', ky: 'Кабаттар', uz: 'Qavatlar'), '${doc.floors.length}'),
      (
        tr3('建筑面积 (各层)', 'Құрылыс ауданы', 'Общая площадь', 'Total area', ky: 'Жалпы аянт', uz: 'Umumiy maydon'),
        '${_n(cost.buildingArea)} $unitM2'
      ),
      (
        tr3('室内净面积', 'Ішкі таза аудан', 'Площадь помещений нетто', 'Net room area', ky: 'Бөлмөлөрдүн таза аянты', uz: 'Xonalarning sof maydoni'),
        '${_n(area0)} $unitM2'
      ),
      (
        tr3('外墙厚', 'Сыртқы қабырға', 'Толщина наружной стены', 'Outer wall thickness', ky: 'Сырткы дубалдын калыңдыгы', uz: 'Tashqi devor qalinligi'),
        '${doc.defaults.outerWallThickness} $unitMm'
      ),
      (tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'), roofName),
      (
        tr3('条形基础', 'Таспалы іргетас', 'Ленточный фундамент', 'Strip foundation', ky: 'Тасма пайдубал', uz: 'Lentali poydevor'),
        '${x.foundation.width} × ${x.foundation.height}'
      ),
      (
        tr3('预算合计', 'Смета барлығы', 'Итого по смете', 'Estimate total', ky: 'Сметанын жыйынтыгы', uz: 'Smeta jami'),
        '$sym ${money(cost.total)}'
      ),
      (
        tr3('设计热负荷', 'Жылу жүктемесі', 'Тепловая нагрузка', 'Heat load', ky: 'Жылуулук жүгү', uz: 'Issiqlik yuklamasi'),
        '${_n(loss.total / 1000)} kW'
      ),
      (tr3('建议锅炉', 'Қазандық', 'Рекомендуемый котёл', 'Recommended boiler', ky: 'Сунушталган казан', uz: 'Tavsiya etilgan qozon'), '${loss.boilerKw} kW'),
    ]);
    y += 20;
    _heading(c, Offset(side.left, y), tr3('房间', 'Бөлмелер', 'Комнаты', 'Rooms', ky: 'Бөлмөлөр', uz: 'Xonalar'));
    y += 30;
    _table(c, Rect.fromLTRB(side.left, y, side.right, side.bottom), roomHeader,
        _shown(coverRows, _rowsFitting(side.bottom - y), roomHeader.length),
        roomFlex);
  }));


  // 2. Floor plans.
  for (var f = 0; f < doc.floors.length; f++) {
    sheets.add(_Sheet(
        '${input.floorName(doc.floors[f].name)} ${tr3('平面图', 'жоспары', 'план', 'plan', ky: 'план', uz: 'reja')}',
        (c, area) => _fit(c, area, _plan(input, f), zoom: 1.25)));
  }

  // 3. Electrical, water and heating points.
  for (var f = 0; f < doc.floors.length; f++) {
    final points =
        x.utilities.where((u) => u.floorId == doc.floors[f].id).toList();
    if (points.isEmpty) continue;
    sheets.add(_Sheet(
        '${input.floorName(doc.floors[f].name)} ${tr3('水电暖点位图', 'су, электр, жылу нүктелері', 'точки воды, электрики и отопления', 'water, electrical and heating points', ky: 'суу, электр жана жылытуу чекиттери', uz: 'suv, elektr va isitish nuqtalari')}',
        (c, area) {
      final plan =
          Rect.fromLTRB(area.left, area.top, area.right - 360, area.bottom);
      _fit(c, plan, _plan(input, f, furniture: false, utilities: true),
          zoom: 1.25);
      final legend =
          Rect.fromLTRB(plan.right + 24, area.top, area.right, area.bottom);
      _heading(
          c,
          legend.topLeft,
          tr3('图例与数量', 'Шартты белгі және саны',
              'Условные обозначения и количество',
              'Legend and quantities', ky: 'Шарттуу белгилер жана көлөмдөр', uz: 'Shartli belgilar va hajmlar'));
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
        c.drawCircle(
            Offset(legend.left + 8, y + 10), 6, Paint()..color = color);
        _text(c, utilityName(k), Offset(legend.left + 24, y));
        final p = _tp('$n', monospace: true);
        p.paint(c, Offset(legend.right - p.width, y));
        y += 30;
      }
      y += 16;
      _figures(c, Rect.fromLTRB(legend.left, y, legend.right, legend.bottom), [
        (
          tr3('照明线 3×1.5', 'Жарық сымы 3×1,5', 'Кабель освещения 3×1,5', 'Lighting cable 3×1.5', ky: 'Жарык кабели 3×1,5', uz: 'Yoritish kabeli 3×1,5'),
          '${money(take.lightCable)} $unitM'
        ),
        (
          tr3('插座线 3×2.5', 'Розетка сымы 3×2,5', 'Кабель розеток 3×2,5', 'Socket cable 3×2.5', ky: 'Розетка кабели 3×2,5', uz: 'Rozetka kabeli 3×2,5'),
          '${money(take.powerCable)} $unitM'
        ),
        (
          tr3('给水管 (冷热)', 'Су құбыры (суық+ыстық)',
              'Труба водоснабжения (хол.+гор.)',
              'Water pipe (cold + hot)', ky: 'Суу түтүгү (муздак + ысык)', uz: 'Suv quvuri (sovuq + issiq)'),
          '${money(take.waterPipe)} $unitM'
        ),
        (
          tr3('排水管', 'Кәріз құбыры', 'Канализационная труба', 'Drain pipe', ky: 'Канализация түтүгү', uz: 'Kanalizatsiya quvuri'),
          '${money(take.drainPipe)} $unitM'
        ),
        (
          tr3('暖气管 (供回)', 'Жылу құбыры', 'Труба отопления (подача/обратка)', 'Heating pipe (flow/return)', ky: 'Жылытуу түтүгү (берүү/кайтаруу)', uz: 'Isitish quvuri (berish/qaytish)'),
          '${money(take.heatingPipe)} $unitM'
        ),
      ]);
    }));
  }

  // 4. Foundation plan and section.
  final fd = foundationTakeoff(doc, derived);
  final f0 = x.foundation;
  sheets
    ..add(_Sheet(
        tr3('基础平面图与剖面', 'Іргетас жоспары және қимасы',
            'План и разрез фундамента',
            'Foundation plan and section', ky: 'Пайдубалдын планы жана кесилиши', uz: 'Poydevor rejasi va kesimi'), (c, area) {
      final plan = Rect.fromLTRB(
          area.left, area.top, area.left + area.width * 0.58, area.bottom);
      _fit(c, plan, _plan(input, 0, furniture: false, foundation: true),
          zoom: 1.2);
      final side =
          Rect.fromLTRB(plan.right + 30, area.top, area.right, area.bottom);
      final section = FoundationSectionPainter(
          Tokens.light, f0, doc.defaults.outerWallThickness, {
        'ground': tr3('室外地面', 'жер беті', 'уровень земли', 'ground level', ky: 'жер деңгээли', uz: 'yer sathi'),
        'wall':
            '${tr3('外墙', 'Сыртқы қабырға', 'Толщина наружной стены', 'Outer wall thickness', ky: 'Сырткы дубалдын калыңдыгы', uz: 'Tashqi devor qalinligi')} ${doc.defaults.outerWallThickness}',
        'damp': tr3('水平防水：2 层卷材', 'Көлденең гидрооқшау: 2 қабат',
            'Горизонтальная гидроизоляция: 2 слоя рулонного материала',
            'Damp-proof course: 2 layers of roll membrane', ky: 'Гидроизоляция: 2 катмар рулон мембрана', uz: 'Gidroizolyatsiya: 2 qatlam rulonli membrana'),
        'topBars':
            '${tr3('上部纵筋', 'Үстіңгі арматура', 'Верхняя арматура', 'Top rebar', ky: 'Үстүнкү арматура', uz: 'Yuqori armatura')} ${f0.topBars}Ø${f0.barDia}',
        'floor': tr3('地坪（见地坪构造）', 'Еден (еден құрылымын қараңыз)',
            'Пол (см. конструкцию пола)',
            'Floor (see floor build-up)', ky: 'Пол (пол катмарларын караңыз)', uz: 'Pol (pol qatlamlariga qarang)'),
        'stirrups':
            '${tr3('箍筋', 'Қамыт', 'Хомут', 'Stirrup', ky: 'Хомут', uz: 'Xomut')} Ø${f0.stirrupDia} @${f0.stirrupStep}',
        'concrete': '${tr3('混凝土', 'Бетон', 'Бетон', 'Concrete', ky: 'Бетон', uz: 'Beton')} ${f0.concrete}',
        'bottomBars':
            '${tr3('下部纵筋', 'Астыңғы арматура', 'Нижняя арматура', 'Bottom rebar', ky: 'Астыңкы арматура', uz: 'Pastki armatura')} ${f0.bottomBars}Ø${f0.barDia}',
        'cover':
            '${tr3('保护层', 'Қорғаныш қабаты', 'Защитный слой', 'Cover', ky: 'Коргоочу катмар', uz: 'Himoya qatlami')} ${f0.cover} $unitMm',
        'cushion':
            '${tr3('砂砾石垫层', 'Құм-қиыршық', 'Песчано-гравийная подушка', 'Sand and gravel bed', ky: 'Кум-шагыл төшөмө', uz: 'Qum-shagʻal toʻshama')} ${f0.cushion}',
        'blind': tr3(
            '保温散水 1000 · 下铺 XPS 50',
            'Жылы отмостка 1000 · астында XPS 50',
            'Утеплённая отмостка 1000 · снизу XPS 50',
            'Insulated apron 1000 · XPS 50 below', ky: 'Жылуу отмостка 1000 · астында XPS 50', uz: 'Isitilgan otmostka 1000 · ostida XPS 50'),
        'xps': tr3('XPS 50 + 沥青防水', 'XPS 50 + битум', 'XPS 50 + битум', 'XPS 50 + bitumen', ky: 'XPS 50 + битум', uz: 'XPS 50 + bitum'),
      });
      final h = math.min(
          side.height * 0.55, side.width * section.viewH / section.viewW);
      final w = h * section.viewW / section.viewH;
      c
        ..save()
        ..translate(side.left, side.top);
      section.paint(c, Size(w, h));
      c.restore();
      final rebar = (fd.mainBarLength / 1000 * barKgPerM(f0.barDia) +
              fd.partitionBarLength / 1000 * barKgPerM(f0.partitionBarDia) +
              fd.stirrupLength / 1000 * barKgPerM(f0.stirrupDia) +
              fd.partitionStirrupLength /
                  1000 *
                  barKgPerM(f0.partitionStirrupDia)) /
          1000;
      _figures(
          c,
          Rect.fromLTRB(side.left, side.top + h + 24, side.right, side.bottom),
          [
            (
              tr3('基础长度', 'Іргетас ұзындығы', 'Длина фундамента', 'Foundation length', ky: 'Пайдубалдын узундугу', uz: 'Poydevor uzunligi'),
              '${_n((fd.mainLength + fd.partitionLength) / 1000)} $unitM'
            ),
            (
              tr3('混凝土 (+3%)', 'Бетон (+3%)', 'Бетон (+3%)', 'Concrete (+3%)', ky: 'Бетон (+3%)', uz: 'Beton (+3%)'),
              '${_n(fd.concrete * 1.03 / 1e9)} $unitM3'
            ),
            (
              tr3('钢筋', 'Арматура', 'Арматура', 'Rebar', ky: 'Арматура', uz: 'Armatura'),
              '${_n(rebar, 2)} ${tr3('吨', 'т', 'т', 't', ky: 'т', uz: 't')}'
            ),
            (
              tr3('挖土', 'Қазу', 'Выемка грунта', 'Excavation', ky: 'Казуу иштери', uz: 'Qazish ishlari'),
              '${_n(fd.excavation / 1e9)} $unitM3'
            ),
            (
              tr3('砂砾石垫层', 'Құм-қиыршық', 'Песчано-гравийная подушка', 'Sand and gravel bed', ky: 'Кум-шагыл төшөмө', uz: 'Qum-shagʻal toʻshama'),
              '${_n(fd.cushion / 1e9)} $unitM3'
            ),
            (
              tr3('模板', 'Қалып', 'Опалубка', 'Formwork', ky: 'Калып', uz: 'Qolip'),
              '${_n(fd.formwork / 1e6)} $unitM2'
            ),
            (tr3('预留套管', 'Гильзалар', 'Гильзы', 'Sleeves', ky: 'Гильзалар', uz: 'Gilzalar'), '${x.sleeves.length}'),
          ]);
    }))

    // 5. Wall, roof and floor build-ups.
    ..add(_Sheet(tr3('构造做法', 'Құрылым шешімдері', 'Конструктивные решения', 'Construction details', ky: 'Конструкция деталдары', uz: 'Konstruksiya tafsilotlari'),
        (c, area) {
      final groups = [
        (
          '${tr3('外墙', 'Сыртқы қабырға', 'Толщина наружной стены', 'Outer wall thickness', ky: 'Сырткы дубалдын калыңдыгы', uz: 'Tashqi devor qalinligi')} · U ${_n(loss.wallU, 2)}',
          x.wallLayers,
          true
        ),
        ('$roofName · U ${_n(loss.roofU, 2)}', x.roofLayers, false),
        (
          '${tr3('首层地面', 'Бірінші қабат едені', 'Пол первого этажа', 'Ground floor build-up', ky: 'Биринчи кабаттын полунун катмарлары', uz: 'Birinchi qavat poli qatlamlari')} · U ${_n(loss.floorU, 2)}',
          x.floorLayers,
          false
        ),
      ];
      final colW = (area.width - 2 * 30) / 3;
      for (var i = 0; i < groups.length; i++) {
        final (title, layers, horizontal) = groups[i];
        final col = Rect.fromLTWH(
            area.left + i * (colW + 30), area.top, colW, area.height);
        _heading(c, col.topLeft,
            '$title · ${layers.fold(0, (s, l) => s + l.thickness)} $unitMm');
        final names = [for (final l in layers) tr(l.name, l.nameKk)];
        final SectionPainter painter = horizontal
            ? WallSectionPainter(Tokens.light, layers, names,
                outside: tr3('室外', 'Сырты', 'Снаружи', 'Outside', ky: 'Сырты', uz: 'Tashqari'),
                inside: tr3('室内', 'Іші', 'Внутри', 'Inside', ky: 'Ичи', uz: 'Ichkari'))
            : LayerStackPainter(Tokens.light, layers, names, scale: 0.2);
        final h =
            math.min(col.height * 0.5, colW * painter.viewH / painter.viewW);
        final w = h * painter.viewW / painter.viewH;
        c
          ..save()
          ..translate(col.left, col.top + 36);
        painter.paint(c, Size(w, h));
        c.restore();
        _table(
            c,
            Rect.fromLTRB(
                col.left, col.top + 36 + h + 20, col.right, col.bottom),
            [
              tr3('构造层', 'Қабат', 'Слой', 'Layer', ky: 'Катмар', uz: 'Qatlam'),
              unitMm,
              'λ'
            ],
            [
              for (final l in layers)
                [
                  _Cell(tr(l.name, l.nameKk)),
                  _Cell('${l.thickness}', numeric: true),
                  _Cell(dec((l.conductivity / 1000).toStringAsFixed(3)),
                      numeric: true),
                ]
            ],
            [
              5,
              1.3,
              1.5
            ]);
      }
    }));

  // 6. Door and window schedule; room areas.
  final openingRows = <List<_Cell>>[];
  var doorNo = 0;
  var windowNo = 0;
  for (var f = 0; f < doc.floors.length; f++) {
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
          DoorOpening() => tr3('平开门', 'Ашылмалы есік', 'Распашная дверь', 'Hinged door', ky: 'Ачылма эшик', uz: 'Ochiladigan eshik'),
          SlidingOpening() => tr3('推拉门', 'Сырғымалы есік', 'Раздвижная дверь', 'Sliding door', ky: 'Жылма эшик', uz: 'Surma eshik'),
          WindowOpening() => tr3('窗', 'Терезе', 'Окно', 'Window', ky: 'Терезе', uz: 'Deraza'),
        }),
      ]);
    }
  }
  final roomRows = <List<_Cell>>[];
  for (var f = 0; f < doc.floors.length; f++) {
    for (final r in doc.floors[f].rooms) {
      final g =
          derived.floors[f].base.roomGeometry.firstWhere((s) => s.id == r.id);
      final label = x.rooms[r.id]?.labelArea;
      roomRows.add([
        _Cell(input.roomName(r)),
        if (multi) _Cell(input.floorName(doc.floors[f].name), muted: true),
        _Cell(_n(g.area(doc.extras.areaBasis) / 1e6), numeric: true),
        _Cell(label == null ? '—' : _n(label / 100), numeric: true),
      ]);
    }
  }
  const scheduleRows = 30;
  final pages = math.max(
      1,
      math.max((openingRows.length / scheduleRows).ceil(),
          (roomRows.length / scheduleRows).ceil()));
  for (var page = 0; page < pages; page++) {
    sheets.add(_Sheet(
        '${tr3('门窗表与房间面积', 'Есік-терезе және бөлме аудандары', 'Окна, двери и площади комнат', 'Windows, doors and room areas', ky: 'Терезелер, эшиктер жана бөлмө аянттары', uz: 'Derazalar, eshiklar va xona maydonlari')}${pages > 1 ? ' (${page + 1})' : ''}',
        (c, area) {
      final left = Rect.fromLTRB(
          area.left, area.top, area.left + area.width * 0.6, area.bottom);
      _heading(c, left.topLeft,
          tr3('门窗表', 'Есік-терезе кестесі', 'Ведомость окон и дверей', 'Window and door schedule', ky: 'Терезе жана эшик тизмеси', uz: 'Deraza va eshiklar roʻyxati'));
      _table(
          c,
          Rect.fromLTRB(left.left, left.top + 32, left.right, left.bottom),
          [
            tr3('编号', 'Код', 'Марка', 'Mark', ky: 'Белги', uz: 'Belgi'),
            if (multi) tr3('楼层', 'Қабат', 'Этаж', 'Floor', ky: 'Кабат', uz: 'Qavat'),
            tr3('位置', 'Орны', 'Место', 'Location', ky: 'Жайгашкан жери', uz: 'Joylashuvi'),
            tr3('宽 × 高', 'Ені × биіктігі', 'Ширина × высота', 'Width × height', ky: 'Туурасы × бийиктиги', uz: 'Eni × balandligi'),
            tr3('窗台', 'Терезе алды', 'Подоконник', 'Sill', ky: 'Терезе алды', uz: 'Deraza tokchasi'),
            tr3('类型', 'Түрі', 'Тип', 'Type', ky: 'Түрү', uz: 'Turi'),
          ],
          openingRows.skip(page * scheduleRows).take(scheduleRows).toList(),
          multi ? [1, 1.4, 3.6, 2, 1.2, 1.6] : [1, 4, 2, 1.2, 1.6]);
      final right =
          Rect.fromLTRB(left.right + 30, area.top, area.right, area.bottom);
      _heading(
          c,
          right.topLeft,
          tr3('房间面积 (实算 / 图纸)', 'Бөлме ауданы (есеп / сызба)',
              'Площадь комнат (расчёт / чертёж)',
              'Room areas (calculated / drawing)', ky: 'Бөлмө аянттары (эсептелген / чийме)', uz: 'Xona maydonlari (hisoblangan / chizma)'));
      _table(
          c,
          Rect.fromLTRB(right.left, right.top + 32, right.right, right.bottom),
          [
            tr3('房间', 'Бөлме', 'Комната', 'Room', ky: 'Бөлмө', uz: 'Xona'),
            if (multi) tr3('楼层', 'Қабат', 'Этаж', 'Floor', ky: 'Кабат', uz: 'Qavat'),
            tr3('实算 m²', 'Есеп, м²', 'Расчёт, м²', 'Calculated, m²', ky: 'Эсептелген, м²', uz: 'Hisoblangan, m²'),
            tr3('图纸 m²', 'Сызба, м²', 'Чертёж, м²', 'Drawing, m²', ky: 'Чийме, м²', uz: 'Chizma, m²'),
          ],
          roomRows.skip(page * scheduleRows).take(scheduleRows).toList(),
          multi ? [3, 2, 2, 2] : [3, 2, 2]);
    }));
  }

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
    for (final l in lines) {
      costRows.add([
        _Cell(
            '   ${l.custom ? l.name! : costLineName(l.key)}${l.estimated ? tr3(' (估)', ' (шамамен)', ' (прибл.)', ' (approx.)', ky: ' (болжол менен)', uz: ' (taxminan)') : ''}',
            muted: l.estimated),
        _Cell(
            '${_n(l.quantity, l.quantity >= 100 ? 0 : 2)} ${l.custom ? l.unit : unitName(l.unit)}',
            numeric: true),
        _Cell(money(l.price), numeric: true),
        _Cell(money(l.total), numeric: true),
      ]);
    }
  }
  costRows.addAll([
    [
      _Cell(tr3('材料合计', 'Материалдар', 'Материалы', 'Materials', ky: 'Материалдар', uz: 'Materiallar'), bold: true),
      const _Cell(''),
      const _Cell(''),
      _Cell(money(cost.materials), numeric: true, bold: true)
    ],
    [
      _Cell('${tr3('人工', 'Жұмыс ақысы', 'Оплата работ', 'Labour', ky: 'Жумуш', uz: 'Ish haqi')}${cost.labourByWork ? '' : ' ${cost.labourPct}%'}',
          bold: true),
      const _Cell(''),
      const _Cell(''),
      _Cell(money(cost.labour), numeric: true, bold: true)
    ],
    [
      _Cell('${tr3('预备费', 'Резерв', 'Резерв', 'Contingency', ky: 'Күтүлбөгөн чыгымдар', uz: 'Kutilmagan xarajatlar')} ${cost.contingencyPct}%',
          bold: true),
      const _Cell(''),
      const _Cell(''),
      _Cell(money(cost.contingency), numeric: true, bold: true)
    ],
    [
      _Cell('${tr3('总计', 'Барлығы', 'Итого', 'Total', ky: 'Бардыгы', uz: 'Jami')} ($sym)', bold: true),
      _Cell('${money(cost.perArea)} $sym/$unitM2', numeric: true, muted: true),
      const _Cell(''),
      _Cell(money(cost.total), numeric: true, bold: true)
    ],
    [
      _Cell(tr3('可能的区间', 'Ықтимал аралық', 'Возможный диапазон', 'Likely range', ky: 'Мүмкүн болгон аралык', uz: 'Ehtimoliy oraliq'), muted: true),
      const _Cell(''),
      const _Cell(''),
      _Cell('${money(cost.low)} – ${money(cost.high)}',
          numeric: true, muted: true)
    ],
  ]);
  const costPerColumn = 31;
  final costColumns = (costRows.length / costPerColumn).ceil();
  for (var page = 0; page < (costColumns / 2).ceil(); page++) {
    sheets.add(_Sheet(
        '${tr3('造价预算', 'Құрылыс сметасы', 'Смета строительства', 'Construction estimate', ky: 'Курулуш сметасы', uz: 'Qurilish smetasi')} ($sym)${costColumns > 2 ? ' (${page + 1})' : ''}',
        (c, area) {
      final colW = (area.width - 30) / 2;
      for (var k = 0; k < 2; k++) {
        final chunk = costRows
            .skip((page * 2 + k) * costPerColumn)
            .take(costPerColumn)
            .toList();
        if (chunk.isEmpty) continue;
        _table(
            c,
            Rect.fromLTWH(
                area.left + k * (colW + 30), area.top, colW, area.height),
            [
              tr3('项目', 'Атауы', 'Наименование', 'Item', ky: 'Аталышы', uz: 'Nomi'),
              tr3('数量', 'Мөлшері', 'Количество', 'Quantity', ky: 'Саны', uz: 'Miqdori'),
              tr3('单价', 'Бағасы', 'Цена', 'Price', ky: 'Баасы', uz: 'Narxi'),
              tr3('金额', 'Сомасы', 'Сумма', 'Amount', ky: 'Суммасы', uz: 'Summa'),
            ],
            chunk,
            [4, 2, 1.6, 1.8]);
      }
      final note = tr3(
          '单价为示例或用户填写，工程量按模型计算，未含损耗以外的变更。仅供估算和与施工方沟通。',
          'Бағалар — мысал не пайдаланушы енгізгені, көлемдер модельден есептелген. Тек бағалау және құрылысшымен сөйлесу үшін.',
          'Цены — примерные или введённые пользователем, объёмы рассчитаны по модели; изменения сверх запаса на отходы не учтены. Только для оценки и обсуждения со строителями.',
          "Prices are approximate or entered by you; quantities come from the model; changes beyond the waste allowance aren't included. For estimates and talks with builders only.", ky: 'Баалар болжолдуу же сиз киргизгенсиз; көлөмдөр моделден алынат; ысырап чегинен ашкан өзгөртүүлөр кирбейт. Эсеп-кысап жана куруучулар менен сүйлөшүү үчүн гана.', uz: 'Narxlar taxminiy yoki siz kiritgansiz; miqdorlar modeldan olinadi; isrof meʼyoridan ortiq oʻzgarishlar kirmaydi. Faqat hisob-kitob va quruvchilar bilan muzokara uchun.');
      _text(c, note, Offset(area.left, area.bottom - 22),
          size: 12, color: _muted, maxWidth: area.width, maxLines: 1);
    }));
  }

  // Materials to buy.
  final buyRows = <List<_Cell>>[];
  String? buyStage;
  for (final l in materialList(doc, derived, estimate: cost)) {
    if (l.stage != buyStage) {
      buyStage = l.stage;
      buyRows.add([
        _Cell(costStageName(l.stage), bold: true),
        const _Cell(''),
        const _Cell(''),
      ]);
    }
    buyRows.add([
      _Cell('   ${buyName(l.key)}${l.detail.isEmpty ? '' : ' ${l.detail}'}',
          muted: l.estimated),
      _Cell(
          '${l.unit == 'pcs' ? '${l.quantity.round()}' : _n(l.quantity, l.quantity >= 100 ? 0 : 2)} ${unitName(l.unit)}',
          numeric: true),
      _Cell([
        if (l.packs != null) '${l.packs} ${packName(l.pack)}',
        if (l.weight != null) '${_n(l.weight!, 0)} ${unitName('kg')}',
      ].join(' · '), numeric: true),
    ]);
  }
  final buyColumns = (buyRows.length / costPerColumn).ceil();
  for (var page = 0; page < (buyColumns / 2).ceil(); page++) {
    sheets.add(_Sheet(
        '${tr3('材料清单', 'Материалдар тізімі', 'Список материалов', 'Materials list', ky: 'Материалдардын тизмеси', uz: 'Materiallar roʻyxati')}${buyColumns > 2 ? ' (${page + 1})' : ''}',
        (c, area) {
      final colW = (area.width - 30) / 2;
      for (var k = 0; k < 2; k++) {
        final chunk = buyRows
            .skip((page * 2 + k) * costPerColumn)
            .take(costPerColumn)
            .toList();
        if (chunk.isEmpty) continue;
        _table(
            c,
            Rect.fromLTWH(
                area.left + k * (colW + 30), area.top, colW, area.height),
            [
              tr3('材料', 'Материал', 'Материал', 'Material', ky: 'Материал', uz: 'Material'),
              tr3('要买 (含损耗)', 'Сатып алу (ысыраппен)', 'Купить (с запасом)', 'To buy (with waste)', ky: 'Сатып алуу (ысырап менен)', uz: 'Sotib olish (isrof bilan)'),
              tr3('整包', 'Тұтас қаптама', 'Упаковок', 'Packs', ky: 'Таңгак', uz: 'Qadoq'),
            ],
            chunk,
            [4, 2.2, 2.2]);
      }
    }));
  }

  final heatRows = <List<_Cell>>[
    for (final s in loss.spaces)
      if (doc.floors[s.floorIndex].rooms.where((r) => r.id == s.id).firstOrNull
              case final room?
          when s.total > 0)
        [
          _Cell(input.roomName(room)),
          _Cell(_n(s.area), numeric: true),
          _Cell(money(s.total), numeric: true),
          _Cell('${s.sections}', numeric: true),
        ]
  ];
  final heatHeader = [
    tr3('房间', 'Бөлме', 'Комната', 'Room', ky: 'Бөлмө', uz: 'Xona'),
    unitM2,
    'W',
    tr3('暖气片 片', 'Секция', 'Секций', 'Sections', ky: 'Кесилиштер', uz: 'Kesimlar')
  ];
  const heatFlex = [3.0, 1.5, 1.5, 1.5];

  // 8. Heat loss.
  sheets.add(_Sheet(tr3('保温与采暖计算', 'Жылу шығыны есебі', 'Расчёт теплопотерь', 'Heat loss calculation', ky: 'Жылуулук жоготуунун эсеби', uz: 'Issiqlik yoʻqotish hisobi'),
      (c, area) {
    final colW = (area.width - 30) / 2;
    final left = Rect.fromLTWH(area.left, area.top, colW, area.height);
    var y = left.top;
    y += _figures(c, Rect.fromLTRB(left.left, y, left.right, left.bottom), [
      (
        tr3('室外 / 室内计算温度', 'Сыртқы / ішкі температура',
            'Расчётная температура: наружная / внутренняя',
            'Design temperature: outside / inside', ky: 'Эсептик температура: сыртта / ичинде', uz: 'Hisobiy harorat: tashqarida / ichkarida'),
        '${x.heat.outdoor} / ${x.heat.indoor} °C'
      ),
      (
        tr3('设计热负荷', 'Есептік жүктеме', 'Расчётная тепловая нагрузка', 'Design heat load', ky: 'Эсептик жылуулук жүгү', uz: 'Hisobiy issiqlik yuklamasi'),
        '${_n(loss.total / 1000)} kW'
      ),
      (
        tr3('每平方米', 'Әр шаршы метрге', 'На квадратный метр', 'Per square metre', ky: 'Бир чарчы метрге', uz: 'Bir kvadrat metrga'),
        '${loss.perArea.round()} W/$unitM2'
      ),
      (
        tr3('建议锅炉', 'Ұсынылатын қазандық', 'Рекомендуемый котёл', 'Recommended boiler', ky: 'Сунушталган казан', uz: 'Tavsiya etilgan qozon'),
        '${loss.boilerKw} kW'
      ),
      (
        tr3('采暖季用热', 'Маусымдық жылу', 'Расход тепла за сезон', 'Heat use per season', ky: 'Мезгилге жылуулук сарпталышы', uz: 'Mavsumiy issiqlik sarfi'),
        '${money(loss.seasonKwh)} kWh'
      ),
      (
        '${tr3('燃料', 'Отын', 'Топливо', 'Fuel', ky: 'Отун', uz: 'Yoqilgʻi')} · ${fuelName(x.heat.fuel)}',
        '${_n(loss.fuel)} ${fuelUnit(x.heat.fuel)}'
      ),
    ]);
    y += 24;
    _table(c, Rect.fromLTRB(left.left, y, left.right, left.bottom), [
      tr3('部位', 'Бөлік', 'Элемент', 'Element', ky: 'Элемент', uz: 'Element'),
      'U W/(m²·K)',
      tr3('面积', 'Аудан', 'Площадь', 'Area', ky: 'Аянт', uz: 'Maydon'),
      'W'
    ], [
      for (final (name, u, a, w) in [
        (
          tr3('外墙', 'Сыртқы қабырға', 'Толщина наружной стены', 'Outer wall thickness', ky: 'Сырткы дубалдын калыңдыгы', uz: 'Tashqi devor qalinligi'),
          loss.wallU,
          loss.wallArea,
          loss.walls
        ),
        (
          tr3('窗', 'Терезе', 'Окно', 'Window', ky: 'Терезе', uz: 'Deraza'),
          loss.windowU,
          loss.windowArea,
          loss.windows
        ),
        (
          tr3('外门', 'Сыртқы есік', 'Наружная дверь', 'Exterior door', ky: 'Сырткы эшик', uz: 'Tashqi eshik'),
          loss.doorU,
          loss.doorArea,
          loss.doors
        ),
        (tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'), loss.roofU, loss.roofArea, loss.roof),
        (tr3('地面', 'Еден', 'Пол', 'Floor', ky: 'Пол', uz: 'Pol'), loss.floorU, loss.floorArea, loss.floor),
      ])
        [
          _Cell(name),
          _Cell(_n(u, 2), numeric: true),
          _Cell('${_n(a)} $unitM2', numeric: true),
          _Cell(money(w), numeric: true),
        ],
      [
        _Cell(tr3('通风换气', 'Желдету', 'Вентиляция', 'Ventilation', ky: 'Желдетүү', uz: 'Shamollatish')),
        const _Cell('—', numeric: true),
        _Cell('${_n(loss.volume)} $unitM3', numeric: true),
        _Cell(money(loss.air), numeric: true),
      ],
    ], [
      3,
      2,
      2,
      2
    ]);
    final right =
        Rect.fromLTWH(area.left + colW + 30, area.top, colW, area.height);
    _table(c, right, heatHeader,
        _shown(heatRows, _rowsFitting(right.height), heatHeader.length),
        heatFlex);
  }));
  if (heatRows.length > _rowsFitting(_sheetArea.height) ~/ 2) {
    sheets.addAll(_scheduleSheets(
        tr3('房间热负荷表', 'Бөлмелердің жылу жүктемесі', 'Теплопотери по комнатам',
            'Heat load by room', ky: 'Бөлмөлөрдүн жылуулук жүгү', uz: 'Xonalar boʻyicha issiqlik yuklamasi'),
        heatHeader,
        heatRows,
        heatFlex));
  }

  // 9. Site plan.
  final site = x.site;
  if (site != null) {
    sheets.add(_Sheet(
        tr3('宅基地总平面图', 'Учаскенің бас жоспары', 'Генеральный план участка', 'Site plan', ky: 'Участоктун планы', uz: 'Uchastka rejasi'),
        (c, area) {
      final plan =
          Rect.fromLTRB(area.left, area.top, area.right - 420, area.bottom);
      c
        ..save()
        ..translate(plan.left, plan.top);
      SitePlanPainter(doc: doc, site: site, tokens: Tokens.light)
          .paint(c, plan.size);
      c.restore();
      final side =
          Rect.fromLTRB(plan.right + 24, area.top, area.right, area.bottom);
      var y = side.top;
      y += _figures(c, Rect.fromLTRB(side.left, y, side.right, side.bottom), [
        (
          tr3('宅基地', 'Учаске', 'Участок', 'Site', ky: 'Участок', uz: 'Uchastka'),
          '${_n(site.width / 1000)} × ${_n(site.depth / 1000)} ${tr3('米', 'м', 'м', 'm', ky: 'м', uz: 'm')}'
        ),
        (
          tr3('占地', 'Аудан', 'Площадь', 'Area', ky: 'Аянт', uz: 'Maydon'),
          '${_n(site.width * site.depth / 1e6, 0)} $unitM2'
        ),
        for (final i in site.items)
          (
            i.label ?? siteName(i.kind),
            '${_n(i.width / 1000)} × ${_n(i.depth / 1000)}'
          ),
      ]);
      final checks =
          siteChecks(doc, nameOf: (i) => i.label ?? siteName(i.kind));
      if (checks.isNotEmpty) {
        y += 16;
        _heading(c, Offset(side.left, y),
            tr3('间距检查', 'Арақашықтық тексеруі', 'Проверка расстояний', 'Distance check', ky: 'Аралыкты текшерүү', uz: 'Masofani tekshirish'));
        y += 32;
        for (final ch in checks) {
          if (y > side.bottom - 40) break;
          y += _text(c, '• ${tr3(ch.title.$1, ch.title.$2, ch.title.$3, ch.title.$4, ky: ch.title.$5, uz: ch.title.$6)}',
                  Offset(side.left, y),
                  size: 14, weight: FontWeight.w600, maxWidth: side.width) +
              2;
          y += _text(c, tr3(ch.text.$1, ch.text.$2, ch.text.$3, ch.text.$4, ky: ch.text.$5, uz: ch.text.$6),
                  Offset(side.left + 14, y),
                  size: 12,
                  color: _muted,
                  maxWidth: side.width - 14,
                  maxLines: 4) +
              8;
        }
      }
    }));
  }

  // 10. Schedule.
  final plan = planStages(x.stages);
  final budgets = stageBudgets(cost);
  sheets.add(_Sheet(tr3('施工进度计划', 'Құрылыс кестесі', 'График строительства', 'Build schedule', ky: 'Курулуш графиги', uz: 'Qurilish jadvali'),
      (c, area) {
    _table(c, area, [
      '#',
      tr3('阶段', 'Кезең', 'Этап', 'Stage', ky: 'Этап', uz: 'Bosqich'),
      tr3('状态', 'Күйі', 'Статус', 'Status', ky: 'Абалы', uz: 'Holati'),
      tr3('开工', 'Басталуы', 'Начало', 'Start', ky: 'Башталышы', uz: 'Boshlanishi'),
      tr3('完工', 'Аяқталуы', 'Окончание', 'End', ky: 'Аягы', uz: 'Tugashi'),
      tr3('天', 'Күн', 'Дней', 'Days', ky: 'Күн', uz: 'Kun'),
      '${tr3('预算', 'Смета', 'Смета', 'Estimate', ky: 'Смета', uz: 'Smeta')} $sym',
      '${tr3('已花', 'Жұмсалды', 'Потрачено', 'Spent', ky: 'Жумшалды', uz: 'Sarflandi')} $sym',
      tr3('检查', 'Тексеру', 'Проверка', 'Check', ky: 'Текшерүү', uz: 'Tekshiruv'),
    ], [
      for (var i = 0; i < plan.length; i++)
        [
          _Cell('${i + 1}', muted: true),
          _Cell(stageName(plan[i].stage), bold: true),
          _Cell(statusName(plan[i].stage.status)),
          _Cell(plan[i].start == null ? '—' : formatDay(plan[i].start!),
              numeric: true),
          _Cell(plan[i].end == null ? '—' : formatDay(plan[i].end!),
              numeric: true),
          _Cell('${plan[i].stage.days}', numeric: true),
          _Cell(
              budgets[plan[i].stage.key] == null
                  ? '—'
                  : money(budgets[plan[i].stage.key]!),
              numeric: true),
          _Cell(money(plan[i].stage.spent), numeric: true),
          _Cell(
              '${plan[i].stage.checks.length}/${stageChecks[plan[i].stage.key]?.length ?? 0}',
              numeric: true),
        ]
    ], [
      0.5,
      3,
      1.4,
      1.8,
      1.8,
      0.9,
      2,
      2,
      1.1
    ]);
  }));
  return sheets;
}

Future<Uint8List> _rasterize(
    _Sheet sheet, DrawingInput input, int number, int count) async {
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
      title: input.doc.meta.name,
      creator: tr3('自建房设计', 'Үй жобалау', 'Проектирование дома', 'House design', ky: 'Үй долбоору', uz: 'Uy loyihasi'));
  for (var i = 0; i < sheets.length; i++) {
    final png = await _rasterize(sheets[i], input, i + 1, sheets.length);
    document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(png))));
    onProgress?.call(i + 1, sheets.length);
    // Let the progress dialog repaint between pages.
    await Future<void>.delayed(Duration.zero);
  }
  return document.save();
}

/// One floor's plan sheet as a PNG, for chat apps.
Future<Uint8List> buildPlanPng(DrawingInput input, int floorIndex) async {
  final sheets = _sheets(input);
  final title =
      '${input.floorName(input.doc.floors[floorIndex].name)} ${tr3('平面图', 'жоспары', 'план', 'plan', ky: 'план', uz: 'reja')}';
  final index = sheets.indexWhere((s) => s.title == title);
  await _warmUp([sheets[index]], input);
  return _rasterize(sheets[index], input, index + 1, sheets.length);
}

/// Names of the sheets in the set, for tests and the export dialog.
@visibleForTesting
List<String> drawingSheetTitles(DrawingInput input) =>
    [for (final s in _sheets(input)) s.title];
