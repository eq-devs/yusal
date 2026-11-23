import 'dart:math' as math;
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';
import 'package:yusal/features/editor/engine/core/checks/construction_checks.dart';

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
  final dx = math.max(0.0, math.max(a.left - b.right, b.left - a.right));
  final dy = math.max(0.0, math.max(a.bottom - b.top, b.bottom - a.top));
  return math.sqrt(dx * dx + dy * dy);
}

bool _overlaps(PlanRect a, PlanRect b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.bottom < b.top &&
    b.bottom < a.top;

bool _inside(PlanRect r, SitePlan s) =>
    r.left >= 0 && r.bottom >= 0 && r.right <= s.width && r.top <= s.depth;

/// Area of each kind of plot item, m².
Map<SiteKind, double> siteAreas(SitePlan site) {
  final out = <SiteKind, double>{};
  for (final i in site.items) {
    out[i.kind] = (out[i.kind] ?? 0) + i.width * i.depth / 1e6;
  }
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
  if (!_inside(house, site)) {
    out.add(ConstructionIssue(
        'S01',
        IssueLevel.crit,
        (
          '房子超出了宅基地',
          'Үй учаскеден шығып тұр',
          'Дом выходит за пределы участка',
          'The house extends beyond the plot',
          'Үй участоктон чыгып турат',
          'Uy uchastkadan chiqib turibdi'
        ),
        (
          '房子 ${_m(house.right - house.left)} × ${_m(house.top - house.bottom)} m 有一部分在宅基地外面。挪动房子或修改宅基地尺寸。',
          'Үйдің ${_m(house.right - house.left).replaceAll('.', ',')} × ${_m(house.top - house.bottom).replaceAll('.', ',')} м бір бөлігі учаскеден тыс. Үйді жылжытыңыз не учаске өлшемін өзгертіңіз.',
          'Часть дома ${_m(house.right - house.left).replaceAll('.', ',')} × ${_m(house.top - house.bottom).replaceAll('.', ',')} м выходит за пределы участка. Передвиньте дом или измените размер участка.',
          'A ${_m(house.right - house.left)} × ${_m(house.top - house.bottom)} m part of the house is outside the plot. Move the house or change the plot size.',
          'Үйдүн ${_m(house.right - house.left).replaceAll('.', ',')} × ${_m(house.top - house.bottom).replaceAll('.', ',')} м бөлүгү участоктун сыртында. Үйдү жылдырыңыз же участоктун өлчөмүн өзгөртүңүз.',
          'Uyning ${_m(house.right - house.left).replaceAll('.', ',')} × ${_m(house.top - house.bottom).replaceAll('.', ',')} m qismi uchastkadan tashqarida. Uyni suring yoki uchastka oʻlchamini oʻzgartiring.'
        ),
        areas: [house],
        site: true));
  }
  for (final item in site.items) {
    final r = itemRect(item);
    if (!_inside(r, site) && item.kind != SiteKind.gate) {
      out.add(ConstructionIssue(
          'S02',
          IssueLevel.warn,
          (
            '${name(item)}超出了宅基地',
            '${name(item)} учаскеден шығып тұр',
            '${name(item)} выходит за пределы участка',
            '${name(item)} extends beyond the plot',
            '${name(item)} участоктон чыгып турат',
            '${name(item)} uchastkadan chiqib turibdi'
          ),
          (
            '把它挪回宅基地以内，或者修改宅基地尺寸。',
            'Оны учаске ішіне жылжытыңыз не учаске өлшемін өзгертіңіз.',
            'Перенесите объект внутрь участка или измените размер участка.',
            'Move the item inside the plot or change the plot size.',
            'Нерсени участоктун ичине жылдырыңыз же участоктун өлчөмүн өзгөртүңүз.',
            'Elementni uchastka ichiga suring yoki uchastka oʻlchamini oʻzgartiring.'
          ),
          areas: [r],
          site: true));
    }
    if (siteBuildings.contains(item.kind) && _overlaps(r, house)) {
      out.add(ConstructionIssue(
          'S03',
          IssueLevel.crit,
          (
            '${name(item)}和房子重叠',
            '${name(item)} үймен қабаттасады',
            '${name(item)} накладывается на дом',
            '${name(item)} overlaps the house',
            '${name(item)} үй менен кесилишет',
            '${name(item)} uy bilan kesishadi'
          ),
          (
            '附属建筑不能压在房子上，请挪开。',
            'Қосалқы құрылыс үйдің үстінде тұрмауы керек, жылжытыңыз.',
            'Хозпостройка не должна стоять на месте дома, сдвиньте её.',
            "An outbuilding can't stand where the house is; move it.",
            'Чарба курулушу үй турган жерде тура албайт; жылдырыңыз.',
            'Xoʻjalik binosi uy turgan joyda tura olmaydi; suring.'
          ),
          areas: [r, house],
          site: true));
    }
  }
  final buildings =
      site.items.where((i) => siteBuildings.contains(i.kind)).toList();
  for (var a = 0; a < buildings.length; a++) {
    for (var b = a + 1; b < buildings.length; b++) {
      final ra = itemRect(buildings[a]);
      final rb = itemRect(buildings[b]);
      if (_overlaps(ra, rb)) {
        out.add(ConstructionIssue(
            'S03',
            IssueLevel.warn,
            (
              '${name(buildings[a])}和${name(buildings[b])}重叠',
              '${name(buildings[a])} мен ${name(buildings[b])} қабаттасады',
              '${name(buildings[a])} и ${name(buildings[b])} накладываются друг на друга',
              '${name(buildings[a])} and ${name(buildings[b])} overlap',
              '${name(buildings[a])} менен ${name(buildings[b])} кесилишет',
              '${name(buildings[a])} va ${name(buildings[b])} kesishadi'
            ),
            ('请把其中一个挪开。', 'Біреуін жылжытыңыз.', 'Сдвиньте одну из построек.', 'Move one of the buildings.', 'Курулуштардын бирин жылдырыңыз.', 'Binolardan birini suring.'),
            areas: [ra, rb],
            site: true));
      }
    }
  }
  // Room to the street and the neighbours.
  final front = house.bottom;
  final side = math.min(house.left, site.width - house.right);
  final back = site.depth - house.top;
  if (_inside(house, site) && (front < 5000 || side < 3000 || back < 3000)) {
    out.add(ConstructionIssue(
        'S04',
        IssueLevel.chk,
        ('房子离边界较近', 'Үй шекараға жақын', 'Дом близко к границе', 'The house is close to the boundary', 'Үй чек арага жакын', 'Uy chegaraga yaqin'),
        (
          '房子离街道 ${_m(front)} m、离邻居 ${_m(side)} m、离后边界 ${_m(back)} m。常见要求是离街道不少于 5 m、离邻居不少于 3 m，方便防火、采光和屋檐滴水不落到邻家。请以当地审批要求为准。',
          'Үй көшеден ${_m(front).replaceAll('.', ',')} м, көршіден ${_m(side).replaceAll('.', ',')} м, артқы шекарадан ${_m(back).replaceAll('.', ',')} м. Әдетте көшеден кемінде 5 м, көршіден кемінде 3 м талап етіледі — өрт қауіпсіздігі, жарық және шатыр суы көршіге ақпауы үшін. Жергілікті рұқсат талабын нақтылаңыз.',
          'От дома до улицы ${_m(front).replaceAll('.', ',')} м, до соседа ${_m(side).replaceAll('.', ',')} м, до задней границы ${_m(back).replaceAll('.', ',')} м. Обычно требуется не меньше 5 м от улицы и 3 м от соседа — ради пожарной безопасности, света и чтобы вода с крыши не стекала к соседу. Уточните местные требования к разрешению.',
          "From the house to the street is ${_m(front)} m, to the neighbour ${_m(side)} m, to the back boundary ${_m(back)} m. Usually at least 5 m from the street and 3 m from the neighbour are required, for fire safety, light and so roof water doesn't run onto the neighbour. Check your local permit requirements.",
          'Үйдөн көчөгө чейин ${_m(front).replaceAll('.', ',')} м, коңшуга чейин ${_m(side).replaceAll('.', ',')} м, арткы чек арага чейин ${_m(back).replaceAll('.', ',')} м. Адатта өрт коопсуздугу, жарык жана чатырдын суусу коңшуга акпашы үчүн көчөдөн кеминде 5 м, коңшудан кеминде 3 м талап кылынат. Жергиликтүү уруксат талаптарын тактаңыз.',
          'Uydan koʻchagacha ${_m(front).replaceAll('.', ',')} m, qoʻshnigacha ${_m(side).replaceAll('.', ',')} m, orqa chegaragacha ${_m(back).replaceAll('.', ',')} m. Odatda yongʻin xavfsizligi, yorugʻlik va tom suvi qoʻshniga oqmasligi uchun koʻchadan kamida 5 m, qoʻshnidan kamida 3 m talab qilinadi. Mahalliy ruxsat talablarini aniqlang.'
        ),
        areas: [house],
        site: true));
  }
  for (final item in site.items) {
    final gap = houseGaps[item.kind];
    if (gap == null) continue;
    final r = itemRect(item);
    final d = rectGap(r, house);
    if (d < gap && !_overlaps(r, house)) {
      out.add(ConstructionIssue(
          'S05',
          IssueLevel.warn,
          (
            '${name(item)}离房子太近',
            '${name(item)} үйге тым жақын',
            '${name(item)} слишком близко к дому',
            '${name(item)} is too close to the house',
            '${name(item)} үйгө өтө жакын',
            '${name(item)} uyga juda yaqin'
          ),
          (
            '现在相距 ${_m(d)} m，建议不少于 ${_m(gap.toDouble())} m，避免气味、潮气和火灾影响住房。',
            'Қазір ${_m(d).replaceAll('.', ',')} м, кемінде ${_m(gap.toDouble()).replaceAll('.', ',')} м болғаны жөн — иіс, ылғал және өрт үйге әсер етпеуі үшін.',
            'Сейчас ${_m(d).replaceAll('.', ',')} м, лучше не меньше ${_m(gap.toDouble()).replaceAll('.', ',')} м — чтобы запах, сырость и огонь не доходили до дома.',
            "Now ${_m(d)} m; at least ${_m(gap.toDouble())} m is better so smell, damp and fire don't reach the house.",
            'Азыр ${_m(d).replaceAll('.', ',')} м; жыт, нымдуулук жана өрт үйгө жетпеши үчүн кеминде ${_m(gap.toDouble()).replaceAll('.', ',')} м болгону жакшы.',
            'Hozir ${_m(d).replaceAll('.', ',')} m; hid, namlik va yongʻin uyga yetmasligi uchun kamida ${_m(gap.toDouble()).replaceAll('.', ',')} m boʻlgani yaxshi.'
          ),
          areas: [r, house],
          site: true));
    }
  }
  for (final well in site.items.where((i) => i.kind == SiteKind.well)) {
    for (final dirty in site.items.where((i) => siteDirty.contains(i.kind))) {
      final a = itemRect(well);
      final b = itemRect(dirty);
      final d = rectGap(a, b);
      if (d < wellGap) {
        out.add(ConstructionIssue(
            'S06',
            IssueLevel.crit,
            (
              '水井离${name(dirty)}太近',
              'Құдық ${name(dirty)} жанында тым жақын',
              'Колодец слишком близко: ${name(dirty)}',
              'The well is too close: ${name(dirty)}',
              'Кудук өтө жакын: ${name(dirty)}',
              'Quduq juda yaqin: ${name(dirty)}'
            ),
            (
              '相距 ${_m(d)} m。污水会渗到井里，建议不少于 ${_m(wellGap.toDouble())} m，井要在地势较高的一侧。',
              'Арасы ${_m(d).replaceAll('.', ',')} м. Лас су құдыққа сіңеді, кемінде ${_m(wellGap.toDouble()).replaceAll('.', ',')} м керек, құдық биік жақта болсын.',
              'Между ними ${_m(d).replaceAll('.', ',')} м. Грязная вода просачивается в колодец: нужно не меньше ${_m(wellGap.toDouble()).replaceAll('.', ',')} м, и колодец должен стоять выше по уклону.',
              "They're ${_m(d)} m apart. Dirty water seeps into the well: you need at least ${_m(wellGap.toDouble())} m, and the well should be uphill.",
              'Алардын ортосу ${_m(d).replaceAll('.', ',')} м. Кир суу кудукка сиңет: кеминде ${_m(wellGap.toDouble()).replaceAll('.', ',')} м керек, кудук бийик жерде болушу керек.',
              'Ular orasi ${_m(d).replaceAll('.', ',')} m. Iflos suv quduqqa singadi: kamida ${_m(wellGap.toDouble()).replaceAll('.', ',')} m kerak, quduq balandroq joyda boʻlishi kerak.'
            ),
            areas: [a, b],
            site: true));
      }
    }
  }
  for (final barn in site.items.where((i) => i.kind == SiteKind.barn)) {
    final r = itemRect(barn);
    final edge = [r.left, r.bottom, site.width - r.right, site.depth - r.top]
        .reduce(math.min);
    if (_inside(r, site) && edge < 4000) {
      out.add(ConstructionIssue(
          'S07',
          IssueLevel.chk,
          (
            '${name(barn)}离邻居较近',
            '${name(barn)} көршіге жақын',
            '${name(barn)} близко к соседу',
            '${name(barn)} is close to the neighbour',
            '${name(barn)} коңшуга жакын',
            '${name(barn)} qoʻshniga yaqin'
          ),
          (
            '离边界 ${_m(edge)} m。牲畜棚常见要求离邻居边界不少于 4 m。',
            'Шекарадан ${_m(edge).replaceAll('.', ',')} м. Мал қорасы көрші шекарасынан кемінде 4 м болуы әдеттегі талап.',
            'До границы ${_m(edge).replaceAll('.', ',')} м. Обычно сарай для скота ставят не ближе 4 м от границы с соседом.',
            "${_m(edge)} m to the boundary. A livestock barn is usually placed at least 4 m from the neighbour's boundary.",
            'Чек арага чейин ${_m(edge).replaceAll('.', ',')} м. Мал сарай адатта коңшунун чек арасынан кеминде 4 м алыс коюлат.',
            'Chegaragacha ${_m(edge).replaceAll('.', ',')} m. Molxona odatda qoʻshni chegarasidan kamida 4 m uzoqda quriladi.'
          ),
          areas: [r],
          site: true));
    }
  }
  if (site.fence && !site.items.any((i) => i.kind == SiteKind.gate)) {
    out.add(ConstructionIssue(
        'S08',
        IssueLevel.chk,
        ('院墙还没有大门', 'Қоршауда қақпа жоқ', 'В заборе нет ворот', 'The fence has no gate', 'Тосмодо дарбаза жок', 'Panjarada darvoza yoʻq'),
        (
          '在临街一侧加一个大门，车能开进院子时宽度不少于 3.5 m。',
          'Көше жақтан қақпа қосыңыз; көлік кіретін болса ені кемінде 3,5 м.',
          'Добавьте ворота со стороны улицы; если будет заезжать машина, ширина не менее 3,5 м.',
          'Add a gate on the street side; if a car will drive in, make it at least 3.5 m wide.',
          'Көчө тарапка дарбаза кошуңуз; машина кире турган болсо, туурасы кеминде 3,5 м болсун.',
          'Koʻcha tomonga darvoza qoʻshing; mashina kiradigan boʻlsa, eni kamida 3,5 m boʻlsin.'
        ),
        areas: [PlanRect(0, 0, site.width.toDouble(), 300)],
        site: true));
  }
  return out;
}
