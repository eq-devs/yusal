import 'package:yusal/features/editor/engine/core/analysis/house_analysis.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/geometry/floor_base.dart';

/// Construction remarks beyond the R01–R10 layout rules, after the issue list
/// of the drafting page. Each carries both languages and the plan areas to
/// highlight.
class ConstructionIssue {
  const ConstructionIssue(this.code, this.level, this.title, this.text,
      {this.floorId,
      this.areas = const [],
      this.showFoundation = false,
      this.site = false});
  final String code;
  final IssueLevel level;

  /// (Chinese, Kazakh, Russian, English, Kyrgyz, Uzbek).
  final (String, String, String, String, String, String) title;
  final (String, String, String, String, String, String) text;
  final String? floorId;
  final List<PlanRect> areas;
  final bool showFoundation;

  /// [areas] are on the plot drawing rather than a floor plan.
  final bool site;
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
        (
          '隔墙下面没有基础',
          'Қалқа қабырғалардың астында іргетас жоқ',
          'Под перегородками нет фундамента',
          'No foundation under partitions',
          'Тосмолордун астында пайдубал жок',
          'Toʻsiqlar ostida poydevor yoʻq'
        ),
        (
          '首层有 ${partitions.length} 段隔墙下面没有条形基础。砌块隔墙直接落在地坪上会沉降开裂。可在“构造细节”里打开隔墙基础 (${spec.partitionWidth}×${spec.partitionHeight})，或改用轻质隔墙。',
          'Бірінші қабатта ${partitions.length} қалқа қабырғаның астында таспалы іргетас жоқ. Блок қабырға еден плитасында тұрса, отырып жарылады. «Құрылым бөлшектері» бетінде қалқа іргетасын (${spec.partitionWidth}×${spec.partitionHeight}) қосыңыз не жеңіл қабырға жасаңыз.',
          'На первом этаже под перегородками (${partitions.length} шт.) нет ленточного фундамента. Стена из блоков, поставленная на плиту пола, просядет и треснет. В разделе «Детали конструкции» добавьте фундамент под перегородки (${spec.partitionWidth}×${spec.partitionHeight}) или сделайте лёгкие перегородки.',
          'On the ground floor ${partitions.length} partitions have no strip foundation. A block wall standing on the floor slab will settle and crack. Turn on the partition foundation (${spec.partitionWidth}×${spec.partitionHeight}) in “Construction details”, or use lightweight partitions.',
          'Биринчи кабатта ${partitions.length} тосмонун тасма пайдубалы жок. Пол жабуусунда турган блок дубал отуруп, жарака кетет. «Конструкция деталдары» бөлүмүндө тосмо пайдубалын (${spec.partitionWidth}×${spec.partitionHeight}) күйгүзүңүз же жеңил тосмолорду колдонуңуз.',
          'Birinchi qavatda ${partitions.length} ta toʻsiqning lentali poydevori yoʻq. Pol yopmasida turgan blok devor choʻkib, yoriladi. “Konstruksiya tafsilotlari” boʻlimida toʻsiq poydevorini (${spec.partitionWidth}×${spec.partitionHeight}) yoqing yoki yengil toʻsiqlardan foydalaning.'
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
        '${spec.width}×${spec.height} іргетастың тереңдігі $buried мм',
        'Глубина фундамента ${spec.width}×${spec.height}: $buried мм',
        'Foundation depth ${spec.width}×${spec.height}: $buried mm',
        'Пайдубалдын тереңдиги ${spec.width}×${spec.height}: $buried мм',
        'Poydevor chuqurligi ${spec.width}×${spec.height}: $buried mm'
      ),
      (
        '基础露出地面 ${spec.plinth} mm、埋入 $buried mm，下设 ${spec.cushion} mm 砂砾石垫层。这在砂、砂砾土和冻深浅的地区可行，但必须做外侧 XPS 和 1 m 宽保温散水。黏土或冻深 1.5–2 m 的地区要加深或请结构师计算。动工前挖一个 1.5 m 探坑看土层。',
        'Іргетас жерден ${spec.plinth} мм шығып, $buried мм көміледі, астында ${spec.cushion} мм құм-қиыршық. Құм топырақта және қату таяз аймақта жарайды, бірақ сыртқы XPS пен ені 1 м жылы отмостка міндетті. Саз топырақта не қату 1,5–2 м жерде тереңдету керек не конструктор есептеуі тиіс. Бастамас бұрын 1,5 м шұңқыр қазып топырақты қараңыз.',
        'Фундамент выступает над землёй на ${spec.plinth} мм и заглублён на $buried мм, под ним ${spec.cushion} мм песчано-гравийной подушки. Для песчаного грунта и небольшой глубины промерзания этого достаточно, но наружный XPS и утеплённая отмостка шириной 1 м обязательны. На глине или при промерзании 1,5–2 м нужно заглублять фундамент или заказывать расчёт у конструктора. До начала работ выкопайте шурф 1,5 м и посмотрите грунт.',
        "The foundation rises ${spec.plinth} mm above ground and goes $buried mm deep, on a ${spec.cushion} mm sand and gravel bed. That's enough for sandy soil and shallow frost, but outer XPS and a 1 m insulated apron are required. On clay or with 1.5–2 m frost depth, take the foundation deeper or have an engineer design it. Before starting, dig a 1.5 m test pit and look at the soil.",
        'Пайдубал жерден ${spec.plinth} мм көтөрүлүп, $buried мм тереңдикке түшөт, ${spec.cushion} мм кум-шагыл төшөмөдө. Бул кумдуу топурак жана тайыз тоң үчүн жетиштүү, бирок сырткы XPS жана 1 м жылуу отмостка милдеттүү. Чопо топуракта же тоң 1,5–2 м болсо, пайдубалды тереңирээк түшүрүңүз же инженерге долбоорлотуңуз. Баштоодон мурун 1,5 м сынамык чуңкур казып, топуракты караңыз.',
        'Poydevor yerdan ${spec.plinth} mm koʻtariladi va $buried mm chuqurlikka tushadi, ${spec.cushion} mm qum-shagʻal toʻshamada. Bu qumli tuproq va sayoz muzlash uchun yetarli, lekin tashqi XPS va 1 m isitilgan otmostka majburiy. Loy tuproqda yoki muzlash 1,5–2 m boʻlsa, poydevorni chuqurroq tushiring yoki muhandisga loyihalating. Boshlashdan oldin 1,5 m sinov chuquri qazib, tuproqni koʻring.'
      ),
      floorId: ground.base.axes.floorId,
      areas: [
        for (final w in groundWalls.where((w) => w.role == WallRole.exterior))
          w.rect
      ],
      showFoundation: true));
  if (doc.roof.type == RoofType.flat) {
    final w = doc.footprint.width.toDouble();
    final d = doc.footprint.depth.toDouble();
    out.add(ConstructionIssue(
        'C03',
        IssueLevel.chk,
        (
          '平屋顶的雪荷载和排水',
          'Тегіс шатырдың қар жүктемесі мен су ағызуы',
          'Снеговая нагрузка и водоотвод плоской крыши',
          'Flat roof snow load and drainage',
          'Жалпак чатырдын кар жүгү жана суу агызуу',
          'Tekis tomning qor yuklamasi va suv oqizish'
        ),
        (
          '平屋顶冬天积雪不会自己滑落，屋面板和配筋要按当地雪荷载计算。排水口设在女儿墙，落水管和排水口加电伴热，防止冻堵后屋面积水渗漏。女儿墙内侧防水上翻不少于 300 mm。',
          'Тегіс шатырдан қыста қар өздігінен түспейді, жабын плитасы мен арматура жергілікті қар жүктемесі бойынша есептелуі керек. Су қабылдағыш парапетте, құбыр мен қабылдағышқа электр жылытқыш қойыңыз. Парапет ішіне гидрооқшауды кемінде 300 мм көтеріңіз.',
          'С плоской крыши снег зимой сам не сходит, плиту перекрытия и арматуру нужно рассчитывать по местной снеговой нагрузке. Водоприёмник — в парапете, на трубу и водоприёмник поставьте электрообогрев. Заведите гидроизоляцию на внутреннюю сторону парапета не менее чем на 300 мм.',
          "Snow doesn't slide off a flat roof in winter, so size the slab and rebar for the local snow load. Put the roof drain in the parapet and fit heating cable on the pipe and drain. Take the waterproofing at least 300 mm up the inside of the parapet.",
          'Кышында жалпак чатырдан кар түшпөйт, ошондуктан жабууну жана арматураны жергиликтүү кар жүгүнө ылайык эсептеңиз. Чатыр воронкасын парапетке коюп, түтүк менен воронкага ысытуучу кабель орнотуңуз. Гидроизоляцияны парапеттин ички жагынан кеминде 300 мм көтөрүңүз.',
          'Qishda tekis tomdan qor tushmaydi, shuning uchun yopma va armaturani mahalliy qor yuklamasiga moslab hisoblang. Tom voronkasini parapetga qoʻying va quvur hamda voronkaga isituvchi kabel oʻrnating. Gidroizolyatsiyani parapetning ichki tomonidan kamida 300 mm koʻtaring.'
        ),
        floorId: derived.floors.last.base.axes.floorId,
        areas: [PlanRect(0, d - 400, w, d)]));
  }
  var bedrooms = 0;
  var bathrooms = 0;
  for (var f = 0; f < doc.floors.length; f++) {
    final floor = doc.floors[f];
    final g = derived.floors[f];
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
            (
              '${name(room)}采光不足',
              '${name(room)}: жарық жеткіліксіз',
              '${name(room)}: мало света',
              '${name(room)}: little light',
              '${name(room)}: жарык аз',
              '${name(room)}: yorugʻlik kam'
            ),
            (
              '窗地比 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1)}，居室宜不小于 1 : 7。可以加大窗或再开一扇窗。',
              'Терезе/еден 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1).replaceAll('.', ',')}, тұрғын бөлмеге кемінде 1 : 7 керек. Терезені үлкейтіңіз не тағы бір терезе ашыңыз.',
              'Окна/пол 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1).replaceAll('.', ',')}, для жилой комнаты нужно не меньше 1 : 7. Увеличьте окно или добавьте ещё одно.',
              'Windows/floor 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1)}; a living room needs at least 1 : 7. Make the window bigger or add another one.',
              'Терезе/пол 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1).replaceAll('.', ',')}; турак бөлмөгө кеминде 1 : 7 керек. Терезени чоңойтуңуз же дагы бирин кошуңуз.',
              'Deraza/pol 1 : ${ratio == null ? '∞' : ratio.toStringAsFixed(1).replaceAll('.', ',')}; turar xonaga kamida 1 : 7 kerak. Derazani kattalashtiring yoki yana bittasini qoʻshing.'
            ),
            floorId: floor.id,
            areas: [roomRect(room)]));
      }
    }
    // Rooms that share a wall: how they connect.
    final links = <(String, String), ({bool door, bool wall, PlanRect at})>{};
    for (final e in g.base.edges) {
      final a = g.base.owners[e.negative];
      final b = g.base.owners[e.positive];
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
    for (final p in g.openings.where(
        (p) => p.status == 'ok' && p.opening.kind != OpeningKind.window)) {
      final (a, b) = roomsBeside(p, g.base);
      if (a == null || b == null) continue;
      final key = a.compareTo(b) < 0 ? (a, b) : (b, a);
      final old = links[key];
      if (old != null) links[key] = (door: true, wall: old.wall, at: old.at);
    }
    Room? byId(String id) => floor.rooms.where((r) => r.id == id).firstOrNull;
    for (final entry in links.entries) {
      final a = byId(entry.key.$1);
      final b = byId(entry.key.$2);
      if (a == null || b == null) continue;
      final types = {a.type, b.type};
      if (types.containsAll({RoomType.kitchen, RoomType.living}) &&
          !entry.value.door) {
        out.add(ConstructionIssue(
            'C05',
            IssueLevel.warn,
            (
              '厨房和客厅不连通',
              'Ас үй мен қонақ бөлме байланыспайды',
              'Кухня и гостиная не связаны',
              "Kitchen and living room aren't connected",
              'Ашкана менен мейманкана туташкан эмес',
              'Oshxona va mehmonxona bogʻlanmagan'
            ),
            (
              '${name(a)}和${name(b)}只隔一道墙，但没有门。端菜、收碗都要绕路。可在墙上开一个约 2 m 宽、带过梁的门洞，或把一段墙设为开放。',
              '${name(a)} мен ${name(b)} арасы бір қабырға, бірақ есік жоқ — тамақты айналып әкелесіз. Қабырғадан ені шамамен 2 м, үсті аркалықпен ойық ашыңыз немесе бір бөлігін ашық етіңіз.',
              '${name(a)} и ${name(b)} разделены одной стеной без двери — еду придётся носить в обход. Сделайте в стене проём шириной около 2 м с перемычкой или оставьте часть стены открытой.',
              '${name(a)} and ${name(b)} are separated by a wall with no door, so food has to go the long way round. Make an opening about 2 m wide with a lintel, or leave part of the wall open.',
              '${name(a)} менен ${name(b)} эшиги жок дубал менен бөлүнгөн, ошондуктан тамак айланып барат. Үстүнө тосмо устун коюп, туурасы 2 мдей ачык жер жасаңыз же дубалдын бир бөлүгүн ачык калтырыңыз.',
              '${name(a)} va ${name(b)} eshiksiz devor bilan ajratilgan, shuning uchun ovqat aylanib boradi. Peremichkali, eni taxminan 2 m ochiq joy qiling yoki devorning bir qismini ochiq qoldiring.'
            ),
            floorId: floor.id,
            areas: [entry.value.at]));
      }
      if (types.containsAll({RoomType.kitchen, RoomType.living}) &&
          entry.value.door) {
        out.add(ConstructionIssue(
            'C06',
            IssueLevel.ok,
            (
              '厨房和客厅相通',
              'Ас үй мен қонақ бөлме жалғасқан',
              'Кухня и гостиная соединены',
              'Kitchen and living room are connected',
              'Ашкана менен мейманкана туташкан',
              'Oshxona va mehmonxona bogʻlangan'
            ),
            (
              '餐桌和客厅连在一起，端菜不用绕走廊。',
              'Ас үстелі мен қонақ бөлме жалғасқан, тамақты дәліз арқылы айналып әкелмейсіз.',
              'Обеденная зона и гостиная соединены, еду не нужно носить в обход через коридор.',
              "The dining area and living room are connected, so food doesn't go the long way round through the corridor.",
              'Тамак ичүүчү жай менен мейманкана туташкан, ошондуктан тамак коридор аркылуу айланып барбайт.',
              'Ovqatlanish joyi va mehmonxona bogʻlangan, shuning uchun ovqat koridor orqali aylanib bormaydi.'
            ),
            floorId: floor.id,
            areas: [entry.value.at]));
      }
    }
    for (final p in g.openings
        .where((p) => p.status == 'ok' && p.opening.kind == OpeningKind.door)) {
      final (a, b) = roomsBeside(p, g.base);
      if (a == null || b == null) continue;
      final ra = byId(a);
      final rb = byId(b);
      if (ra == null || rb == null) continue;
      final bed = ra.type == RoomType.bedroom
          ? ra
          : rb.type == RoomType.bedroom
              ? rb
              : null;
      final living = ra.type == RoomType.living
          ? ra
          : rb.type == RoomType.living
              ? rb
              : null;
      if (bed == null || living == null) continue;
      final u = (p.start + p.end) / 2;
      final c = p.axis.pos.toDouble();
      out.add(ConstructionIssue(
          'C07',
          IssueLevel.warn,
          (
            '${name(bed)}的门开向客厅',
            '${name(bed)} есігі қонақ бөлмеге ашылады',
            '${name(bed)}: дверь открывается в гостиную',
            '${name(bed)}: the door opens into the living room',
            '${name(bed)}: эшик мейманканага ачылат',
            '${name(bed)}: eshik mehmonxonaga ochiladi'
          ),
          (
            '有客人时进出卧室要穿过客厅，私密性弱。可在门前做一段玄关隔断，或把门改到走廊一侧。',
            'Қонақ келгенде жатын бөлмеге қонақ бөлме арқылы өтесіз, оңашалық әлсіз. Есік алдына қалқа жасаңыз не есікті дәліз жағына ауыстырыңыз.',
            'Когда придут гости, в спальню придётся проходить через гостиную, уединения мало. Поставьте перегородку перед дверью или перенесите дверь на сторону коридора.',
            "When guests come you'll have to pass through the living room to the bedroom, so there's little privacy. Put a partition in front of the door or move the door to the corridor side.",
            'Конок келгенде уктоочу бөлмөгө мейманкана аркылуу өтүүгө туура келет, ошондуктан жеке мейкиндик аз. Эшиктин алдына тосмо коюңуз же эшикти коридор тарапка жылдырыңыз.',
            'Mehmon kelganda yotoqxonaga mehmonxona orqali oʻtishga toʻgʻri keladi, shuning uchun shaxsiy joy kam. Eshik oldiga toʻsiq qoʻying yoki eshikni koridor tomonga suring.'
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
    out.add(ConstructionIssue('C08', IssueLevel.warn, (
      '只有一个卫生间',
      'Жуыну бөлмесі біреу ғана',
      'Санузел только один',
      'Only one bathroom',
      'Бир гана ванна бөлмө',
      'Faqat bitta hammom'
    ), (
      '$bedrooms 间卧室只配 $bathrooms 个卫生间，早晚高峰会排队。可以在门厅附近另挤一个约 1.2 m² 的小客卫。',
      '$bedrooms жатын бөлмеге $bathrooms жуыну бөлмесі ғана — таңертең кезек болады. Кіреберіс маңынан шамамен 1,2 м² шағын дәретхана қосуға болады.',
      'Спален: $bedrooms, санузлов: $bathrooms — по утрам будет очередь. У прихожей можно добавить небольшой туалет площадью около 1,2 м².',
      '$bedrooms bedrooms and $bathrooms bathrooms means a morning queue. You can add a small toilet of about 1.2 m² by the hallway.',
      '$bedrooms уктоочу бөлмө жана $bathrooms ванна бөлмө болсо, эртең менен кезек болот. Кире бериштин жанына болжол менен 1,2 м² кичинекей даараткана кошсоңуз болот.',
      '$bedrooms ta yotoqxona va $bathrooms ta hammom boʻlsa, ertalab navbat boʻladi. Dahliz yoniga taxminan 1,2 m² kichik hojatxona qoʻshishingiz mumkin.'
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
          openingTouches(p, g.base, room.id))) {
        noWindowBedroom.add(room);
      }
    }
  }
  if (bedrooms > 0 && noWindowBedroom.isEmpty) {
    out.add(const ConstructionIssue('C09', IssueLevel.ok, (
      '每间卧室都有外窗',
      'Әр жатын бөлмеде сыртқы терезе бар',
      'В каждой спальне есть окно наружу',
      'Every bedroom has an outside window',
      'Ар бир уктоочу бөлмөдө сыртка караган терезе бар',
      'Har bir yotoqxonada tashqariga qaragan deraza bor'
    ), (
      '卧室采光和通风有保证。',
      'Жатын бөлмелердің жарығы мен желдетуі қамтамасыз етілген.',
      'Освещение и вентиляция спален обеспечены.',
      'Bedrooms have light and ventilation.',
      'Уктоочу бөлмөлөрдө жарык жана желдетүү бар.',
      'Yotoqxonalarda yorugʻlik va shamollatish bor.'
    )));
  }
  final spans = <double>[];
  final ground0 = groundWalls
      .where((w) => w.carriesLoad && !w.horizontal)
      .map((w) => (w.rect.left + w.rect.right) / 2)
      .toList()
    ..sort();
  for (var i = 0; i < ground0.length - 1; i++) {
    spans.add(ground0[i + 1] - ground0[i]);
  }
  final longest = spans.isEmpty ? 0.0 : spans.reduce((a, b) => a > b ? a : b);
  if (longest > 6000) {
    out.add(ConstructionIssue(
        'C10',
        IssueLevel.chk,
        ('楼板跨度偏大', 'Жабын аралығы үлкен', 'Большой пролёт перекрытия', 'Large floor span', 'Жабуунун аралыгы чоң', 'Yopma oraligʻi katta'),
        (
          '承重墙之间最大跨度约 ${_m(longest)} m。超过 6 m 的现浇板需要加厚或加梁，请结构师计算；也可以把一道内墙加厚到 ${spec.bearingMin} mm 以上作为承重墙。',
          'Көтергіш қабырғалар арасындағы ең үлкен аралық шамамен ${_m(longest).replaceAll('.', ',')} м. 6 м-ден асса, плитаны қалыңдату не арқалық қою керек — конструктор есептесін; не бір ішкі қабырғаны ${spec.bearingMin} мм-ден қалың етіп көтергіш жасаңыз.',
          'Самый большой пролёт между несущими стенами — около ${_m(longest).replaceAll('.', ',')} м. Если он больше 6 м, нужно утолщать плиту или ставить балку — пусть рассчитает конструктор; либо сделайте одну внутреннюю стену толще ${spec.bearingMin} мм, чтобы она стала несущей.',
          'The largest span between load-bearing walls is about ${_m(longest)} m. Over 6 m the slab needs to be thicker or a beam added; have an engineer calculate it, or make one interior wall thicker than ${spec.bearingMin} mm so it becomes load-bearing.',
          'Көтөрүүчү дубалдардын ортосундагы эң чоң аралык болжол менен ${_m(longest).replaceAll('.', ',')} м. 6 мден ашса, плитаны калыңдатуу же устун коюу керек; инженерге эсептетиңиз же бир ички дубалды ${spec.bearingMin} ммден калың кылып, көтөрүүчү кылыңыз.',
          'Yuk koʻtaruvchi devorlar orasidagi eng katta oraliq taxminan ${_m(longest).replaceAll('.', ',')} m. 6 m dan oshsa, plitani qalinlashtirish yoki toʻsin qoʻyish kerak; muhandisga hisoblating yoki bitta ichki devorni ${spec.bearingMin} mm dan qalin qilib, yuk koʻtaruvchi qiling.'
        ),
        floorId: ground.base.axes.floorId));
  }
  return out;
}
