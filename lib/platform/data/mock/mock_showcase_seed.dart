import '../../../app/settings.dart';
import '../../../core/commands/house_templates.dart';
import '../../../core/commands/kz_template.dart';
import '../../../core/document/house_document.dart';
import '../../../core/serialization/house_codec.dart';
import '../../domain/models.dart';
import '../../snapshot/design_snapshot.dart';
import 'mock_backend.dart';
import 'mock_seed.dart';

/// Published house designs for the home feed, built from the design tool's
/// own templates so every one opens as a real, editable design. Words
/// follow the interface language at launch.
void seedShowcases(MockBackend b) {
  final now = b.now;
  var n = 0;
  String id() => 'seed${n++}';
  const stamp = '2026-01-01T00:00:00Z';
  HouseDocument kz(String name) =>
      createKazakhTemplate(stamp, id, name: name, names: {
        'b1': tr3('卧室 1', 'Жатын бөлме 1', 'Спальня 1'),
        'b2': tr3('卧室 2', 'Жатын бөлме 2', 'Спальня 2'),
        'bath': tr3('卫生间', 'Жуынатын бөлме', 'Санузел'),
        'liv': tr3('客厅', 'Қонақ бөлме', 'Гостиная'),
        'kit': tr3('厨房', 'Ас үй', 'Кухня'),
        'cor': tr3('走廊', 'Дәліз', 'Коридор'),
        'ent': tr3('门厅', 'Кіреберіс', 'Прихожая'),
        'boil': tr3('锅炉房', 'Қазандық', 'Котельная'),
      });
  HouseDocument template(String kind) => createTemplate(kind, stamp, id);

  void add(String showId, String owner, String projectId, String title,
      HouseDocument doc,
      {required String story,
      required String region,
      required List<String> styles,
      required int daysAgo}) {
    final f = showcaseFacts(doc);
    b.showcasesById[showId] = Showcase(
        id: showId,
        ownerId: owner,
        projectId: projectId,
        title: title,
        story: story,
        region: region,
        styles: styles,
        houseText: encodeHouse(doc),
        width: f.width,
        depth: f.depth,
        floors: f.floors,
        rooms: f.rooms,
        area: f.area,
        createdAt: now.subtract(Duration(days: daysAgo, hours: n)));
  }

  add(
      'show_kz',
      SeedIds.owner,
      'proj_seed_kz',
      tr3('塔尔加尔 · 哈萨克乡村住宅', 'Талғар · қазақ ауыл үйі',
          'Талгар · казахский сельский дом'),
      kz('哈萨克乡村住宅'),
      story: tr3(
          '给父母盖的一层平房：400 墙脊承重，西侧两间卧室，客厅铺地毯挂毯，锅炉房单独开门。基础已完成，正在找瓦工砌墙。',
          'Ата-анама бір қабатты үй: ортасында 400 мм көтергіш қабырға, батыста екі жатын бөлме, қонақ бөлмеде кілем мен тұскиіз, қазандыққа бөлек есік. Іргетас дайын, қалаушы іздеп жатырмын.',
          'Одноэтажный дом для родителей: несущая стена 400 мм по центру, две спальни на западе, ковры в гостиной, отдельный вход в котельную. Фундамент готов, ищу каменщика.'),
      region: 'talgar',
      styles: const ['kazakh', 'family', 'brick'],
      daysAgo: 4);
  add(
      'show_two',
      SeedIds.owner2,
      'proj_seed_two',
      tr3('卡斯克连 · 两层小楼', 'Қаскелең · екі қабатты үй',
          'Каскелен · двухэтажный дом'),
      template('two'),
      story: tr3(
          '一楼客厅厨房连通，二楼三间卧室，L 形楼梯。想要采光好、冬天省暖气。',
          'Бірінші қабатта қонақ бөлме мен ас үй бірге, екіншіде үш жатын бөлме, L-тәрізді баспалдақ. Жарық әрі қыста жылы болсын.',
          'Внизу гостиная с кухней, наверху три спальни, Г-образная лестница. Хочется света и экономии на отоплении.'),
      region: 'kaskelen',
      styles: const ['modern', 'family'],
      daysAgo: 2);
  add(
      'show_five',
      SeedIds.team,
      'proj_seed_five',
      tr3('15 × 10 五间平房 · 施工队样板', '15 × 10 бес бөлмелі үй · бригада үлгісі',
          '15 × 10, пять комнат · образец бригады'),
      template('five'),
      story: tr3(
          '我们队最常建的户型：五间一字排开，结构简单、造价好控制。欢迎参考、拿去改。',
          'Біздің бригада жиі салатын жоспар: бес бөлме қатарымен, құрылымы қарапайым, бағасы түсінікті. Алып, өзгерте беріңіз.',
          'Наш самый частый проект: пять комнат в ряд, простая конструкция, понятная смета. Берите и меняйте.'),
      region: 'almaty',
      styles: const ['brick', 'family'],
      daysAgo: 9);
  add(
      'show_three',
      SeedIds.mason,
      'proj_seed_three',
      tr3('小三间 · 12 × 10 入门户型', 'Шағын үш бөлме · 12 × 10',
          'Три комнаты · 12 × 10 для старта'),
      template('three'),
      story: tr3(
          '预算有限时的首选：三间房、一道纵墙，砌墙两周能完。',
          'Бюджет аз болса — ең жақсысы: үш бөлме, бір бойлық қабырға, қалау екі аптада бітеді.',
          'Лучший выбор при скромном бюджете: три комнаты, одна продольная стена, кладка за две недели.'),
      region: 'esik',
      styles: const ['compact', 'brick'],
      daysAgo: 15);
  add(
      'show_wood',
      SeedIds.roofTeam,
      'proj_seed_wood',
      tr3('伊塞克 · 木屋架坡顶住宅', 'Есік · ағаш шатырлы үй',
          'Есик · дом со скатной деревянной кровлей'),
      kz('木屋架住宅'),
      story: tr3(
          '同一套乡村住宅平面，换成木屋架和金属瓦坡屋顶，外墙做木饰面。',
          'Сол ауыл үйінің жоспары, бірақ ағаш стропила, металл черепица және ағаш қаптама.',
          'Тот же сельский план, но с деревянными стропилами, металлочерепицей и деревянной облицовкой.'),
      region: 'esik',
      styles: const ['wood', 'kazakh'],
      daysAgo: 6);
  add(
      'show_family',
      SeedIds.electrician,
      'proj_seed_family',
      tr3('科纳耶夫 · 三代同堂两层', 'Қонаев · үш буынға екі қабатты үй',
          'Конаев · двухэтажный дом для трёх поколений'),
      template('two'),
      story: tr3(
          '老人住一楼，年轻人住二楼。电路按每间独立回路设计，插座留得足。',
          'Үлкендер бірінші қабатта, жастар екіншіде. Әр бөлмеге бөлек электр желісі, розетка жеткілікті.',
          'Старшие внизу, молодые наверху. Отдельная электролиния в каждую комнату, розеток с запасом.'),
      region: 'konaev',
      styles: const ['family', 'modern'],
      daysAgo: 1);

  var c = 0;
  void comment(
      String show, String author, String text, int? rating, int hoursAgo) {
    final cid = 'cmt_seed${c++}';
    b.showcaseComments[cid] = ShowcaseComment(
        id: cid,
        showcaseId: show,
        authorId: author,
        text: text,
        rating: rating,
        createdAt: now.subtract(Duration(hours: hoursAgo)));
  }

  comment(
      'show_kz',
      SeedIds.mason,
      tr3(
          '墙脊放中间很合理，外墙 400 冬天够用。砌块可以选 600×300×200。',
          'Көтергіш қабырға ортада — дұрыс, 400 мм қысқа жетеді. Блокты 600×300×200 алыңыз.',
          'Несущая стена по центру — правильно, 400 мм зимой хватит. Блок берите 600×300×200.'),
      5,
      30);
  comment(
      'show_kz',
      SeedIds.owner2,
      tr3('锅炉房单独出入口这点学到了！', 'Қазандыққа бөлек есік — керемет идея!',
          'Отдельный вход в котельную — отличная идея!'),
      5,
      20);
  comment(
      'show_kz',
      SeedIds.team,
      tr3(
          '门厅可以再放宽 300，冬天换鞋方便。',
          'Кіреберісті 300 мм кеңейтсеңіз, қыста аяқ киім ауыстыру оңай.',
          'Прихожую бы шире на 300 мм — зимой удобнее.'),
      4,
      6);
  comment(
      'show_two',
      SeedIds.owner,
      tr3(
          '楼梯位置好，二楼卧室都朝南吗？',
          'Баспалдақ орны жақсы. Жоғарғы жатын бөлмелер оңтүстікке қарай ма?',
          'Лестница удачно. Спальни наверху на юг?'),
      null,
      12);
  comment(
      'show_two',
      SeedIds.electrician,
      tr3('采光不错，建议厨房加一扇窗。', 'Жарық жақсы, ас үйге тағы бір терезе қосыңыз.',
          'Света много, на кухню бы ещё окно.'),
      4,
      8);
  comment(
      'show_five',
      SeedIds.owner,
      tr3('造价大概多少？', 'Шамамен қанша тұрады?', 'Сколько примерно стоит?'),
      5,
      50);
  comment('show_three', SeedIds.owner2,
      tr3('入门很合适。', 'Бастау үшін өте ыңғайлы.', 'Отлично для начала.'), 4, 70);
  comment(
      'show_wood',
      SeedIds.owner,
      tr3('木饰面太好看了', 'Ағаш қаптама керемет әдемі',
          'Деревянная облицовка — очень красиво'),
      5,
      10);

  for (final (show, who) in [
    ('show_kz', SeedIds.mason),
    ('show_kz', SeedIds.owner2),
    ('show_kz', SeedIds.team),
    ('show_kz', SeedIds.electrician),
    ('show_two', SeedIds.owner),
    ('show_two', SeedIds.team),
    ('show_wood', SeedIds.owner),
    ('show_wood', SeedIds.owner2),
    ('show_wood', SeedIds.mason),
    ('show_five', SeedIds.owner),
    ('show_family', SeedIds.owner2),
  ]) {
    b.likes(show).add(who);
  }
}
