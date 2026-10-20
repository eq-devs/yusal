import 'dart:math' as math;
import '../document/house_document.dart';
import '../geometry/floor_base.dart';
import '../checks/construction_checks.dart';

/// The plot around the house: what is built on it and how far apart.
/// Distances are common advice for village plots (sanitary gaps between
/// the house, toilet, livestock and the well; room to the neighbours), not
/// a local by-law. Plot millimetres, y towards the back.

/// Items with walls and a roof.
const siteBuildings = {
  SiteKind.barn,
  SiteKind.bathhouse,
  SiteKind.garage,
  SiteKind.toilet,
  SiteKind.shed,
  SiteKind.greenhouse,
};

/// Items that can foul a well.
const siteDirty = {SiteKind.toilet, SiteKind.septic, SiteKind.barn};

/// Wall height of each outbuilding for the 3D view, mm.
const siteHeights = {
  SiteKind.barn: 2800,
  SiteKind.bathhouse: 2600,
  SiteKind.garage: 2800,
  SiteKind.toilet: 2200,
  SiteKind.shed: 2400,
  SiteKind.greenhouse: 2400,
  SiteKind.well: 900,
  SiteKind.septic: 200,
  SiteKind.garden: 150,
  SiteKind.yard: 50,
  SiteKind.gate: 2000,
  SiteKind.custom: 2400,
};

/// Advised gaps from the house, mm.
const houseGaps = {
  SiteKind.toilet: 12000,
  SiteKind.barn: 12000,
  SiteKind.bathhouse: 8000,
  SiteKind.septic: 5000,
};

/// Advised gap from a well to anything that can foul it, mm.
const wellGap = 20000;

/// The house footprint on the plot.
PlanRect houseOnPlot(HouseDocument doc, SitePlan site) => PlanRect(
    site.houseX.toDouble(),
    site.houseY.toDouble(),
    (site.houseX + doc.footprint.width).toDouble(),
    (site.houseY + doc.footprint.depth).toDouble());

PlanRect itemRect(SiteItem i) => PlanRect(
    i.x.toDouble(), i.y.toDouble(), i.right.toDouble(), i.top.toDouble());

/// Shortest distance between two rectangles, 0 when they touch.
double rectGap(PlanRect a, PlanRect b) {
  final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right)),
      dy = math.max(0.0, math.max(a.bottom - b.top, b.bottom - a.top));
  return math.sqrt(dx * dx + dy * dy);
}

bool _overlaps(PlanRect a, PlanRect b) =>
    a.left < b.right && b.left < a.right && a.bottom < b.top && b.bottom < a.top;

bool _inside(PlanRect r, SitePlan s) =>
    r.left >= 0 && r.bottom >= 0 && r.right <= s.width && r.top <= s.depth;

/// Area of each kind of plot item, m².
Map<SiteKind, double> siteAreas(SitePlan site) {
  final out = <SiteKind, double>{};
  for (final i in site.items)
    out[i.kind] = (out[i.kind] ?? 0) + i.width * i.depth / 1e6;
  return out;
}

String _m(double mm) => (mm / 1000).toStringAsFixed(1);

/// Remarks on the plot for the issue list; areas are plot coordinates.
List<ConstructionIssue> siteChecks(HouseDocument doc,
    {String Function(SiteItem item)? nameOf}) {
  final site = doc.extras.site;
  if (site == null) return const [];
  String name(SiteItem i) => nameOf?.call(i) ?? i.label ?? i.kind.name;
  final out = <ConstructionIssue>[];
  final house = houseOnPlot(doc, site);
  if (!_inside(house, site))
    out.add(ConstructionIssue(
        'S01',
        IssueLevel.crit,
        ('房子超出了宅基地', 'Үй учаскеден шығып тұр'),
        (
          '房子 ${_m(house.right - house.left)} × ${_m(house.top - house.bottom)} m 有一部分在宅基地外面。挪动房子或修改宅基地尺寸。',
          'Үйдің ${_m(house.right - house.left).replaceAll('.', ',')} × ${_m(house.top - house.bottom).replaceAll('.', ',')} м бір бөлігі учаскеден тыс. Үйді жылжытыңыз не учаске өлшемін өзгертіңіз.'
        ),
        areas: [house],
        site: true));
  for (final item in site.items) {
    final r = itemRect(item);
    if (!_inside(r, site) && item.kind != SiteKind.gate)
      out.add(ConstructionIssue(
          'S02',
          IssueLevel.warn,
          ('${name(item)}超出了宅基地', '${name(item)} учаскеден шығып тұр'),
          (
            '把它挪回宅基地以内，或者修改宅基地尺寸。',
            'Оны учаске ішіне жылжытыңыз не учаске өлшемін өзгертіңіз.'
          ),
          areas: [r],
          site: true));
    if (siteBuildings.contains(item.kind) && _overlaps(r, house))
      out.add(ConstructionIssue(
          'S03',
          IssueLevel.crit,
          ('${name(item)}和房子重叠', '${name(item)} үймен қабаттасады'),
          ('附属建筑不能压在房子上，请挪开。', 'Қосалқы құрылыс үйдің үстінде тұрмауы керек, жылжытыңыз.'),
          areas: [r, house],
          site: true));
  }
  final buildings =
      site.items.where((i) => siteBuildings.contains(i.kind)).toList();
  for (var a = 0; a < buildings.length; a++)
    for (var b = a + 1; b < buildings.length; b++) {
      final ra = itemRect(buildings[a]), rb = itemRect(buildings[b]);
      if (_overlaps(ra, rb))
        out.add(ConstructionIssue(
            'S03',
            IssueLevel.warn,
            (
              '${name(buildings[a])}和${name(buildings[b])}重叠',
              '${name(buildings[a])} мен ${name(buildings[b])} қабаттасады'
            ),
            ('请把其中一个挪开。', 'Біреуін жылжытыңыз.'),
            areas: [ra, rb],
            site: true));
    }
  // Room to the street and the neighbours.
  final front = house.bottom,
      side = math.min(house.left, site.width - house.right),
      back = site.depth - house.top;
  if (_inside(house, site) && (front < 5000 || side < 3000 || back < 3000))
    out.add(ConstructionIssue(
        'S04',
        IssueLevel.chk,
        ('房子离边界较近', 'Үй шекараға жақын'),
        (
          '房子离街道 ${_m(front)} m、离邻居 ${_m(side)} m、离后边界 ${_m(back)} m。常见要求是离街道不少于 5 m、离邻居不少于 3 m，方便防火、采光和屋檐滴水不落到邻家。请以当地审批要求为准。',
          'Үй көшеден ${_m(front).replaceAll('.', ',')} м, көршіден ${_m(side).replaceAll('.', ',')} м, артқы шекарадан ${_m(back).replaceAll('.', ',')} м. Әдетте көшеден кемінде 5 м, көршіден кемінде 3 м талап етіледі — өрт қауіпсіздігі, жарық және шатыр суы көршіге ақпауы үшін. Жергілікті рұқсат талабын нақтылаңыз.'
        ),
        areas: [house],
        site: true));
  for (final item in site.items) {
    final gap = houseGaps[item.kind];
    if (gap == null) continue;
    final r = itemRect(item), d = rectGap(r, house);
    if (d < gap && !_overlaps(r, house))
      out.add(ConstructionIssue(
          'S05',
          IssueLevel.warn,
          ('${name(item)}离房子太近', '${name(item)} үйге тым жақын'),
          (
            '现在相距 ${_m(d)} m，建议不少于 ${_m(gap.toDouble())} m，避免气味、潮气和火灾影响住房。',
            'Қазір ${_m(d).replaceAll('.', ',')} м, кемінде ${_m(gap.toDouble()).replaceAll('.', ',')} м болғаны жөн — иіс, ылғал және өрт үйге әсер етпеуі үшін.'
          ),
          areas: [r, house],
          site: true));
  }
  for (final well in site.items.where((i) => i.kind == SiteKind.well)) {
    for (final dirty in site.items.where((i) => siteDirty.contains(i.kind))) {
      final a = itemRect(well), b = itemRect(dirty), d = rectGap(a, b);
      if (d < wellGap)
        out.add(ConstructionIssue(
            'S06',
            IssueLevel.crit,
            ('水井离${name(dirty)}太近', 'Құдық ${name(dirty)} жанында тым жақын'),
            (
              '相距 ${_m(d)} m。污水会渗到井里，建议不少于 ${_m(wellGap.toDouble())} m，井要在地势较高的一侧。',
              'Арасы ${_m(d).replaceAll('.', ',')} м. Лас су құдыққа сіңеді, кемінде ${_m(wellGap.toDouble()).replaceAll('.', ',')} м керек, құдық биік жақта болсын.'
            ),
            areas: [a, b],
            site: true));
    }
  }
  for (final barn in site.items.where((i) => i.kind == SiteKind.barn)) {
    final r = itemRect(barn);
    final edge = [r.left, r.bottom, site.width - r.right, site.depth - r.top]
        .reduce(math.min);
    if (_inside(r, site) && edge < 4000)
      out.add(ConstructionIssue(
          'S07',
          IssueLevel.chk,
          ('${name(barn)}离邻居较近', '${name(barn)} көршіге жақын'),
          (
            '离边界 ${_m(edge)} m。牲畜棚常见要求离邻居边界不少于 4 m。',
            'Шекарадан ${_m(edge).replaceAll('.', ',')} м. Мал қорасы көрші шекарасынан кемінде 4 м болуы әдеттегі талап.'
          ),
          areas: [r],
          site: true));
  }
  if (site.fence && !site.items.any((i) => i.kind == SiteKind.gate))
    out.add(ConstructionIssue(
        'S08',
        IssueLevel.chk,
        ('院墙还没有大门', 'Қоршауда қақпа жоқ'),
        (
          '在临街一侧加一个大门，车能开进院子时宽度不少于 3.5 m。',
          'Көше жақтан қақпа қосыңыз; көлік кіретін болса ені кемінде 3,5 м.'
        ),
        areas: [PlanRect(0, 0, site.width.toDouble(), 300)],
        site: true));
  return out;
}
