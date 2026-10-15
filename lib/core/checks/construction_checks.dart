import '../analysis/house_analysis.dart';
import '../document/house_document.dart';
import '../geometry/derived_house.dart';
import '../geometry/floor_base.dart';

/// Construction remarks beyond the R01–R10 layout rules, after the issue list
/// of the drafting page. Each carries both languages and the plan areas to
/// highlight.
class ConstructionIssue {
  const ConstructionIssue(this.code, this.level, this.title, this.text,
      {this.floorId, this.areas = const [], this.showFoundation = false});
  final String code;
  final IssueLevel level;

  /// (Chinese, Kazakh).
  final (String, String) title, text;
  final String? floorId;
  final List<PlanRect> areas;
  final bool showFoundation;
}

String _m(double mm) => (mm / 1000).toStringAsFixed(2);

List<ConstructionIssue> constructionChecks(
    HouseDocument doc, DerivedHouse derived,
    {String Function(Room room)? nameOf}) {
  String name(Room r) => nameOf?.call(r) ?? r.name;
  final out = <ConstructionIssue>[];
  final spec = doc.extras.foundation;
  final ground = derived.floors.first;
  final groundWalls = wallsOf(ground.base, spec);
  final partitions =
      groundWalls.where((w) => w.role == WallRole.partition).toList();
  if (partitions.isNotEmpty && !spec.partitions) {
    out.add(ConstructionIssue(
        'C01',
        IssueLevel.crit,
        ('隔墙下面没有基础', 'Қалқа қабырғалардың астында іргетас жоқ'),
        (
          '首层有 ${partitions.length} 段隔墙下面没有条形基础。砌块隔墙直接落在地坪上会沉降开裂。可在“构造细节”里打开隔墙基础 (${spec.partitionWidth}×${spec.partitionHeight})，或改用轻质隔墙。',
          'Бірінші қабатта ${partitions.length} қалқа қабырғаның астында таспалы іргетас жоқ. Блок қабырға еден плитасында тұрса, отырып жарылады. «Құрылым бөлшектері» бетінде қалқа іргетасын (${spec.partitionWidth}×${spec.partitionHeight}) қосыңыз не жеңіл қабырға жасаңыз.'
        ),
        floorId: ground.base.axes.floorId,
        areas: [for (final w in partitions) w.rect],
        showFoundation: true));
  }
  final buried = spec.height - spec.plinth;
  out.add(ConstructionIssue(
      'C02',
      buried < 600 ? IssueLevel.warn : IssueLevel.chk,
      (
        '${spec.width}×${spec.height} 基础埋深 $buried mm',
        '${spec.width}×${spec.height} іргетастың тереңдігі $buried мм'
      ),
      (
        '基础露出地面 ${spec.plinth} mm、埋入 $buried mm，下设 ${spec.cushion} mm 砂砾石垫层。这在砂、砂砾土和冻深浅的地区可行，但必须做外侧 XPS 和 1 m 宽保温散水。黏土或冻深 1.5–2 m 的地区要加深或请结构师计算。动工前挖一个 1.5 m 探坑看土层。',
        'Іргетас жерден ${spec.plinth} мм шығып, $buried мм көміледі, астында ${spec.cushion} мм құм-қиыршық. Құм топырақта және қату таяз аймақта жарайды, бірақ сыртқы XPS пен ені 1 м жылы отмостка міндетті. Саз топырақта не қату 1,5–2 м жерде тереңдету керек не конструктор есептеуі тиіс. Бастамас бұрын 1,5 м шұңқыр қазып топырақты қараңыз.'
      ),
      floorId: ground.base.axes.floorId,
      areas: [
        for (final w in groundWalls.where((w) => w.role == WallRole.exterior))
          w.rect
      ],
      showFoundation: true));
  if (doc.roof.type == RoofType.flat) {
    final w = doc.footprint.width.toDouble(), d = doc.footprint.depth.toDouble();
    out.add(ConstructionIssue(
        'C03',
        IssueLevel.chk,
        ('平屋顶的雪荷载和排水', 'Тегіс шатырдың қар жүктемесі мен су ағызуы'),
        (
          '平屋顶冬天积雪不会自己滑落，屋面板和配筋要按当地雪荷载计算。排水口设在女儿墙，落水管和排水口加电伴热，防止冻堵后屋面积水渗漏。女儿墙内侧防水上翻不少于 300 mm。',
          'Тегіс шатырдан қыста қар өздігінен түспейді, жабын плитасы мен арматура жергілікті қар жүктемесі бойынша есептелуі керек. Су қабылдағыш парапетте, құбыр мен қабылдағышқа электр жылытқыш қойыңыз. Парапет ішіне гидрооқшауды кемінде 300 мм көтеріңіз.'
        ),
        floorId: derived.floors.last.base.axes.floorId,
        areas: [PlanRect(0, d - 400, w, d)]));
  }
  var bedrooms = 0, bathrooms = 0;
  for (var f = 0; f < doc.floors.length; f++) {
    final floor = doc.floors[f], g = derived.floors[f];
    bedrooms += floor.rooms.where((r) => r.type == RoomType.bedroom).length;
    bathrooms += floor.rooms.where((r) => r.type == RoomType.bathroom).length;
    PlanRect roomRect(Room r) {
      final s = g.base.roomGeometry.firstWhere((x) => x.id == r.id);
      return s.clearRects.isEmpty
          ? PlanRect(s.labelAnchor.x, s.labelAnchor.y, s.labelAnchor.x,
              s.labelAnchor.y)
          : s.clearRects.reduce((a, b) => a.area >= b.area ? a : b);
    }

    for (final room in floor.rooms.where((r) =>
        r.type == RoomType.bedroom ||
        r.type == RoomType.living ||
        r.type == RoomType.dining)) {
      final stats = roomStats(room, g, floor.height);
      final ratio = stats.floorPerWindow;
      if (stats.area > 0 && (ratio == null || ratio > 7)) {
        out.add(ConstructionIssue(
            'C04',
            IssueLevel.warn,
            ('${name(room)}采光不足', '${name(room)}: жарық жеткіліксіз'),
            (
              '窗地比 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1)}，居室宜不小于 1 : 7。可以加大窗或再开一扇窗。',
              'Терезе/еден 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1).replaceAll('.', ',')}, тұрғын бөлмеге кемінде 1 : 7 керек. Терезені үлкейтіңіз не тағы бір терезе ашыңыз.'
            ),
            floorId: floor.id,
            areas: [roomRect(room)]));
      }
    }
    // Rooms that share a wall: how they connect.
    final links = <(String, String), ({bool door, bool wall, PlanRect at})>{};
    for (final e in g.base.edges) {
      final a = g.base.owners[e.negative], b = g.base.owners[e.positive];
      if (a == null || b == null || a == b) continue;
      final key = a.compareTo(b) < 0 ? (a, b) : (b, a);
      final at = e.axis.dir == AxisDir.H
          ? PlanRect(e.start.pos.toDouble(), e.axis.pos - 150.0,
              e.end.pos.toDouble(), e.axis.pos + 150.0)
          : PlanRect(e.axis.pos - 150.0, e.start.pos.toDouble(),
              e.axis.pos + 150.0, e.end.pos.toDouble());
      final old = links[key];
      links[key] = (
        door: (old?.door ?? false) || e.kind == 'open',
        wall: (old?.wall ?? false) || e.hasWall,
        at: old == null
            ? at
            : PlanRect(
                at.left < old.at.left ? at.left : old.at.left,
                at.bottom < old.at.bottom ? at.bottom : old.at.bottom,
                at.right > old.at.right ? at.right : old.at.right,
                at.top > old.at.top ? at.top : old.at.top)
      );
    }
    for (final p in g.openings.where((p) =>
        p.status == 'ok' && p.opening.kind != OpeningKind.window)) {
      final (a, b) = roomsBeside(p, g.base);
      if (a == null || b == null) continue;
      final key = a.compareTo(b) < 0 ? (a, b) : (b, a);
      final old = links[key];
      if (old != null) links[key] = (door: true, wall: old.wall, at: old.at);
    }
    Room? byId(String id) => floor.rooms.where((r) => r.id == id).firstOrNull;
    for (final entry in links.entries) {
      final a = byId(entry.key.$1), b = byId(entry.key.$2);
      if (a == null || b == null) continue;
      final types = {a.type, b.type};
      if (types.containsAll({RoomType.kitchen, RoomType.living}) &&
          !entry.value.door) {
        out.add(ConstructionIssue(
            'C05',
            IssueLevel.warn,
            ('厨房和客厅不连通', 'Ас үй мен қонақ бөлме байланыспайды'),
            (
              '${name(a)}和${name(b)}只隔一道墙，但没有门。端菜、收碗都要绕路。可在墙上开一个约 2 m 宽、带过梁的门洞，或把一段墙设为开放。',
              '${name(a)} мен ${name(b)} арасы бір қабырға, бірақ есік жоқ — тамақты айналып әкелесіз. Қабырғадан ені шамамен 2 м, үсті аркалықпен ойық ашыңыз немесе бір бөлігін ашық етіңіз.'
            ),
            floorId: floor.id,
            areas: [entry.value.at]));
      }
      if (types.containsAll({RoomType.kitchen, RoomType.living}) &&
          entry.value.door) {
        out.add(ConstructionIssue(
            'C06',
            IssueLevel.ok,
            ('厨房和客厅相通', 'Ас үй мен қонақ бөлме жалғасқан'),
            (
              '餐桌和客厅连在一起，端菜不用绕走廊。',
              'Ас үстелі мен қонақ бөлме жалғасқан, тамақты дәліз арқылы айналып әкелмейсіз.'
            ),
            floorId: floor.id,
            areas: [entry.value.at]));
      }
    }
    for (final p in g.openings.where(
        (p) => p.status == 'ok' && p.opening.kind == OpeningKind.door)) {
      final (a, b) = roomsBeside(p, g.base);
      if (a == null || b == null) continue;
      final ra = byId(a), rb = byId(b);
      if (ra == null || rb == null) continue;
      final bed = ra.type == RoomType.bedroom
              ? ra
              : rb.type == RoomType.bedroom
                  ? rb
                  : null,
          living = ra.type == RoomType.living
              ? ra
              : rb.type == RoomType.living
                  ? rb
                  : null;
      if (bed == null || living == null) continue;
      final u = (p.start + p.end) / 2, c = p.axis.pos.toDouble();
      out.add(ConstructionIssue(
          'C07',
          IssueLevel.warn,
          ('${name(bed)}的门开向客厅', '${name(bed)} есігі қонақ бөлмеге ашылады'),
          (
            '有客人时进出卧室要穿过客厅，私密性弱。可在门前做一段玄关隔断，或把门改到走廊一侧。',
            'Қонақ келгенде жатын бөлмеге қонақ бөлме арқылы өтесіз, оңашалық әлсіз. Есік алдына қалқа жасаңыз не есікті дәліз жағына ауыстырыңыз.'
          ),
          floorId: floor.id,
          areas: [
            p.axis.dir == AxisDir.H
                ? PlanRect(p.start - 300, c - 600, p.end + 300, c + 600)
                : PlanRect(c - 600, p.start - 300, c + 600, p.end + 300)
          ]));
      if (u.isNaN) break;
    }
  }
  if (bedrooms >= 3 && bathrooms <= 1) {
    out.add(ConstructionIssue(
        'C08',
        IssueLevel.warn,
        ('只有一个卫生间', 'Жуыну бөлмесі біреу ғана'),
        (
          '$bedrooms 间卧室只配 $bathrooms 个卫生间，早晚高峰会排队。可以在门厅附近另挤一个约 1.2 m² 的小客卫。',
          '$bedrooms жатын бөлмеге $bathrooms жуыну бөлмесі ғана — таңертең кезек болады. Кіреберіс маңынан шамамен 1,2 м² шағын дәретхана қосуға болады.'
        )));
  }
  final noWindowBedroom = <Room>[];
  for (var f = 0; f < doc.floors.length; f++) {
    final g = derived.floors[f];
    for (final room
        in doc.floors[f].rooms.where((r) => r.type == RoomType.bedroom)) {
      if (!g.openings.any((p) =>
          p.status == 'ok' &&
          p.host?.kind == 'exterior' &&
          p.opening.kind != OpeningKind.door &&
          openingTouches(p, g.base, room.id))) noWindowBedroom.add(room);
    }
  }
  if (bedrooms > 0 && noWindowBedroom.isEmpty)
    out.add(const ConstructionIssue(
        'C09',
        IssueLevel.ok,
        ('每间卧室都有外窗', 'Әр жатын бөлмеде сыртқы терезе бар'),
        (
          '卧室采光和通风有保证。',
          'Жатын бөлмелердің жарығы мен желдетуі қамтамасыз етілген.'
        )));
  final spans = <double>[];
  final ground0 = groundWalls
      .where((w) => w.carriesLoad && !w.horizontal)
      .map((w) => (w.rect.left + w.rect.right) / 2)
      .toList()
    ..sort();
  for (var i = 0; i < ground0.length - 1; i++)
    spans.add(ground0[i + 1] - ground0[i]);
  final longest = spans.isEmpty ? 0.0 : spans.reduce((a, b) => a > b ? a : b);
  if (longest > 6000) {
    out.add(ConstructionIssue(
        'C10',
        IssueLevel.chk,
        ('楼板跨度偏大', 'Жабын аралығы үлкен'),
        (
          '承重墙之间最大跨度约 ${_m(longest)} m。超过 6 m 的现浇板需要加厚或加梁，请结构师计算；也可以把一道内墙加厚到 ${spec.bearingMin} mm 以上作为承重墙。',
          'Көтергіш қабырғалар арасындағы ең үлкен аралық шамамен ${_m(longest).replaceAll('.', ',')} м. 6 м-ден асса, плитаны қалыңдату не арқалық қою керек — конструктор есептесін; не бір ішкі қабырғаны ${spec.bearingMin} мм-ден қалың етіп көтергіш жасаңыз.'
        ),
        floorId: ground.base.axes.floorId));
  }
  return out;
}
