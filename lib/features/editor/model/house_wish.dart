import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/commands/house_layout.dart';
import 'package:yusal/features/editor/engine/core/commands/house_wish.dart';
import 'package:yusal/features/editor/engine/core/geometry/derived_house.dart';
import 'package:yusal/features/editor/engine/core/number_input.dart';
import 'package:yusal/features/editor/engine/render2d/floor_plan_painter.dart';
import 'package:yusal/features/editor/engine/render2d/furniture_names.dart';
import 'package:yusal/features/shared/motion/motion.dart';

/// What the questions collect before a house is asked for.
class HouseWish {
  const HouseWish(
      {required this.width,
      required this.depth,
      required this.floors,
      required this.bedrooms,
      required this.bathrooms,
      this.hall = true,
      this.boiler = false,
      this.storage = false,
      this.dining = false});

  /// Metres.
  final double width;
  final double depth;
  final int floors;
  final int bedrooms;
  final int bathrooms;
  final bool hall;
  final bool boiler;
  final bool storage;
  final bool dining;

  /// The wish as a house spec drawn without the assistant: two rows of
  /// rooms along a corridor, named in the app's language.
  Map<String, Object?> spec(String name) => wishSpec(
      name: name,
      width: (width * 1000).round(),
      depth: (depth * 1000).round(),
      floors: floors,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      hall: hall,
      boiler: boiler,
      storage: storage,
      dining: dining,
      names: wishRoomNames());

  /// The wish as a brief for [housePlans], which lays it out several
  /// ways.
  HouseBrief get brief => HouseBrief(
      width: (width * 1000).round(),
      depth: (depth * 1000).round(),
      floors: floors,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      hall: hall,
      boiler: boiler,
      storage: storage,
      dining: dining);

  /// The wish as one sentence in the app's language, for the assistant
  /// that designs whole houses.
  String sentence() {
    String m(double v) =>
        dec(v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1));
    final extras = [
      if (hall) tr3('门厅', 'тамбур', 'тамбур', 'vestibule', ky: 'тамбур', uz: 'tambur'),
      if (boiler) tr3('锅炉房', 'қазандық бөлмесі', 'котельная', 'boiler room', ky: 'казандык', uz: 'qozonxona'),
      if (storage) tr3('储藏间', 'қойма', 'кладовая', 'storeroom', ky: 'кампа', uz: 'omborxona'),
      if (dining) tr3('餐厅', 'асхана', 'столовая', 'dining room', ky: 'ашкана-конок бөлмө', uz: 'ovqatlanish xonasi'),
    ];
    return tr3(
        '帮我设计一栋 ${m(width)}×${m(depth)} 米的 $floors 层房子：$bedrooms 间卧室、$bathrooms 个卫生间、客厅和厨房'
            '${extras.isEmpty ? '' : '，还要${extras.join('、')}'}。每个房间都要有门，卧室、客厅和厨房要有窗。',
        '${m(width)}×${m(depth)} метр, $floors қабатты үй жобалап бер: $bedrooms жатын бөлме, $bathrooms жуынатын бөлме, қонақ бөлме және асүй'
            '${extras.isEmpty ? '' : ', сонымен қатар ${extras.join(', ')}'}. Әр бөлменің есігі болсын, жатын бөлмелерде, қонақ бөлмеде және асүйде терезе болсын.',
        'Спроектируй дом ${m(width)}×${m(depth)} метров, этажей: $floors. Спален: $bedrooms, санузлов: $bathrooms, гостиная и кухня'
            '${extras.isEmpty ? '' : ', а ещё ${extras.join(', ')}'}. У каждой комнаты должна быть дверь, в спальнях, гостиной и кухне — окно.',
        'Design a ${m(width)}×${m(depth)} m house with $floors floors, $bedrooms bedrooms, $bathrooms bathrooms, a living room and a kitchen${extras.isEmpty ? '' : ', plus ${extras.join(', ')}'}. Every room needs a door; bedrooms, the living room and the kitchen need a window.', ky: '${m(width)}×${m(depth)} м үй долбоорлоп бериңиз: $floors кабат, $bedrooms уктоочу бөлмө, $bathrooms ванна бөлмө, мейманкана жана ашкана${extras.isEmpty ? '' : ', ошондой эле ${extras.join(', ')}'}. Ар бир бөлмөдө эшик болсун; уктоочу бөлмөлөрдө, мейманканада жана ашканада терезе болсун.', uz: '${m(width)}×${m(depth)} m uy loyihalang: $floors qavat, $bedrooms yotoqxona, $bathrooms hammom, mehmonxona va oshxona${extras.isEmpty ? '' : ', shuningdek ${extras.join(', ')}'}. Har bir xonada eshik boʻlsin; yotoqxonalar, mehmonxona va oshxonada deraza boʻlsin.');
  }
}

/// A few questions instead of a blank sheet; returns the wish, or null
/// when the sheet is closed.
///
/// With [draft] the first version is drawn on the spot, so a wish the
/// house is too small for is turned down here, where it can be changed.
Future<HouseWish?> showHouseWizard(BuildContext context, {bool draft = false}) {
  final width = TextEditingController(text: '12');
  final depth = TextEditingController(text: '10');
  var floors = 1;
  var bedrooms = 3;
  var bathrooms = 1;
  var hall = true;
  var boiler = true;
  var storage = false;
  var dining = false;
  String? error;
  return showMotionSheet<HouseWish>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, update) {
            Widget title(String text) => Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 6),
                child: Text(text,
                    style: const TextStyle(fontWeight: FontWeight.w700)));
            Widget pick(String key, List<int> values, int value,
                    void Function(int) set) =>
                Wrap(spacing: 8, children: [
                  for (final v in values)
                    ChoiceChip(
                        key: Key('wizard-$key-$v'),
                        label: Text('$v'),
                        selected: value == v,
                        onSelected: (_) => update(() => set(v)))
                ]);
            Widget extra(String label, bool value, void Function(bool) set) =>
                FilterChip(
                    label: Text(label),
                    // A chosen chip is dark: its words take the light
                    // colour the number chips use.
                    labelStyle: value
                        ? ChipTheme.of(context).secondaryLabelStyle
                        : null,
                    checkmarkColor: value
                        ? ChipTheme.of(context).secondaryLabelStyle?.color
                        : null,
                    selected: value,
                    onSelected: (v) => update(() => set(v)));
            Widget size(TextEditingController c, String label) => Expanded(
                child: TextField(
                    controller: c,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: label)));
            return SafeArea(
                child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 8, 20,
                        MediaQuery.viewInsetsOf(context).bottom + 20),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              tr3('想要什么样的房子？', 'Қандай үй керек?',
                                  'Какой дом нужен?',
                                  'What house do you need?', ky: 'Кандай үй керек?', uz: 'Qanday uy kerak?'),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(draft
                              ? tr3(
                                  '回答几项，马上画出第一版，之后都能改。',
                                  'Бірнеше сұраққа жауап беріңіз, алғашқы нұсқасы бірден сызылады. Кейін бәрін өзгертуге болады.',
                                  'Ответьте на несколько вопросов — первый вариант будет начерчен сразу. Потом всё можно изменить.',
                                  'Answer a few questions and the first version is drawn right away. You can change everything later.', ky: 'Бир нече суроого жооп бериңиз, биринчи вариант дароо чийилет. Кийин баарын өзгөртсөңүз болот.', uz: 'Bir nechta savolga javob bering, birinchi variant darhol chiziladi. Keyin hammasini oʻzgartirishingiz mumkin.')
                              : tr3(
                                  '回答几项，助手画出第一版，之后都能改。',
                                  'Бірнеше сұраққа жауап беріңіз, көмекші алғашқы нұсқасын сызады. Кейін бәрін өзгертуге болады.',
                                  'Ответьте на несколько вопросов — помощник начертит первый вариант. Потом всё можно изменить.',
                                  'Answer a few questions and the assistant draws the first version. You can change everything later.', ky: 'Бир нече суроого жооп бериңиз, жардамчы биринчи вариантты чийет. Кийин баарын өзгөртсөңүз болот.', uz: 'Bir nechta savolga javob bering, yordamchi birinchi variantni chizadi. Keyin hammasini oʻzgartirishingiz mumkin.')),
                          title(tr3('房子外形（米）', 'Үйдің өлшемі (м)',
                              'Размер дома (м)',
                              'House size (m)', ky: 'Үйдүн өлчөмү (м)', uz: 'Uy oʻlchami (m)')),
                          Row(children: [
                            size(width, tr3('宽', 'Ені', 'Ширина', 'Width', ky: 'Туурасы', uz: 'Eni')),
                            const SizedBox(width: 12),
                            size(depth, tr3('长', 'Ұзындығы', 'Длина', 'Length', ky: 'Узундугу', uz: 'Uzunligi')),
                          ]),
                          title(tr3('几层', 'Қабат саны', 'Этажей', 'Floors', ky: 'Кабаттар', uz: 'Qavatlar')),
                          pick('floors', [1, 2], floors, (v) => floors = v),
                          title(tr3('几间卧室', 'Жатын бөлме саны', 'Спален', 'Bedrooms', ky: 'Уктоочу бөлмөлөр', uz: 'Yotoqxonalar')),
                          pick('bedrooms', [1, 2, 3, 4, 5], bedrooms,
                              (v) => bedrooms = v),
                          title(
                              tr3('几个卫生间', 'Жуынатын бөлме саны', 'Санузлов', 'Bathrooms', ky: 'Ванна бөлмөлөр', uz: 'Hammomlar')),
                          pick('bathrooms', [1, 2], bathrooms,
                              (v) => bathrooms = v),
                          title(tr3('还要', 'Тағы не керек', 'Что ещё нужно', 'What else you need', ky: 'Дагы эмне керек', uz: 'Yana nima kerak')),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            extra(tr3('门厅', 'Тамбур', 'Тамбур', 'Vestibule', ky: 'Тамбур', uz: 'Tambur'), hall,
                                (v) => hall = v),
                            extra(tr3('锅炉房', 'Қазандық', 'Котельная', 'Boiler room', ky: 'Казандык', uz: 'Qozonxona'), boiler,
                                (v) => boiler = v),
                            extra(tr3('储藏间', 'Қойма', 'Кладовая', 'Storeroom', ky: 'Кампа', uz: 'Omborxona'), storage,
                                (v) => storage = v),
                            extra(tr3('餐厅', 'Асхана', 'Столовая', 'Dining room', ky: 'Ашкана-конок бөлмө', uz: 'Ovqatlanish xonasi'), dining,
                                (v) => dining = v),
                          ]),
                          if (error != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                          const SizedBox(height: 16),
                          FilledButton(
                              key: const Key('wizard-go'),
                              onPressed: () {
                                final w = parseNumber(width.text);
                                final d = parseNumber(depth.text);
                                if (w == null ||
                                    d == null ||
                                    w < 3 ||
                                    d < 3 ||
                                    w > 100 ||
                                    d > 100) {
                                  update(() => error = tr3(
                                      '长宽需在 3–100 米之间',
                                      'Өлшем 3–100 м аралығында болуы керек',
                                      'Размер должен быть в пределах 3–100 м',
                                      'Size must be 3–100 m', ky: 'Өлчөм 3–100 м болушу керек', uz: 'Oʻlcham 3–100 m boʻlishi kerak'));
                                  return;
                                }
                                final wish = HouseWish(
                                    width: w,
                                    depth: d,
                                    floors: floors,
                                    bedrooms: bedrooms,
                                    bathrooms: bathrooms,
                                    hall: hall,
                                    boiler: boiler,
                                    storage: storage,
                                    dining: dining);
                                if (draft && wishTooSmall(wish.spec(''))) {
                                  update(() => error = tr3(
                                      '这么大的房子放不下这么多房间。减几间，加一层，或者把房子加大。',
                                      'Мұндай үйге осынша бөлме сыймайды. Бөлмені азайтыңыз, қабат қосыңыз не үйді үлкейтіңіз.',
                                      'В дом такого размера столько комнат не поместится. Уберите часть комнат, добавьте этаж или увеличьте дом.',
                                      "That many rooms won't fit in a house this size. Remove some rooms, add a floor or make the house bigger.", ky: 'Мынча бөлмө бул өлчөмдөгү үйгө батпайт. Айрым бөлмөлөрдү алып салыңыз, кабат кошуңуз же үйдү чоңойтуңуз.', uz: 'Buncha xona bu oʻlchamdagi uyga sigʻmaydi. Baʼzi xonalarni olib tashlang, qavat qoʻshing yoki uyni kattalashtiring.'));
                                  return;
                                }
                                Navigator.pop(
                                    context,
                                    HouseWish(
                                        width: w,
                                        depth: d,
                                        floors: floors,
                                        bedrooms: bedrooms,
                                        bathrooms: bathrooms,
                                        hall: hall,
                                        boiler: boiler,
                                        storage: storage,
                                        dining: dining));
                              },
                              child: Text(tr3('画出第一版', 'Алғашқы нұсқасын сызу',
                                  'Начертить первый вариант',
                                  'Draw the first version', ky: 'Биринчи вариантты чийүү', uz: 'Birinchi variantni chizish'))),
                        ])));
          }));
}

/// The plans a wish can be laid out as, each drawn small, to pick one
/// from; returns it, or null when the sheet is closed.
Future<HousePlan?> showHousePlans(BuildContext context, List<HousePlan> plans) {
  return showMotionSheet<HousePlan>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        tr3('选一个方案', 'Бір нұсқасын таңдаңыз',
                            'Выберите вариант', 'Pick a layout', ky: 'Вариантты тандаңыз', uz: 'Variantni tanlang'),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(tr3(
                        '同样的要求，不同的排法。选了之后都能改。',
                        'Талап бірдей, орналасуы әртүрлі. Кейін бәрін өзгертуге болады.',
                        'Те же пожелания, разная планировка. Потом всё можно изменить.', 'Same wishes, different layouts. You can change everything later.', ky: 'Каалоолор бирдей, жайгашуусу ар башка. Кийин баарын өзгөртсө болот.', uz: 'Istaklar bir xil, joylashuvi har xil. Keyin hammasini oʻzgartirish mumkin.')),
                    for (final (i, plan) in plans.indexed)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: OutlinedButton(
                              key: Key('plan-$i'),
                              style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.all(12)),
                              onPressed: () => Navigator.pop(context, plan),
                              child: Column(children: [
                                AspectRatio(
                                    aspectRatio: plan.document.footprint.width /
                                        plan.document.footprint.depth,
                                    child: CustomPaint(
                                        painter: _planPainter(plan))),
                                const SizedBox(height: 8),
                                Text(plan.layout.startsWith('hub')
                                    ? tr3(
                                        '不设走廊，房间围着客厅',
                                        'Дәлізсіз, бөлмелер қонақ бөлмені айнала',
                                        'Без коридора, комнаты вокруг гостиной', 'No corridor; rooms around the living room', ky: 'Коридорсуз, бөлмөлөр конок бөлмөнү айланып', uz: 'Koridorsiz, xonalar mehmonxona atrofida')
                                    : tr3(
                                        '中间一条走廊，房间在两侧',
                                        'Ортасында дәліз, бөлмелер екі жағында',
                                        'Коридор посередине, комнаты по сторонам', 'A corridor down the middle, rooms on both sides', ky: 'Ортодо коридор, бөлмөлөр эки жагында', uz: 'Oʻrtada koridor, xonalar ikki tomonda')),
                              ])))
                  ]))));
}

/// The ground floor of [plan], as the editor draws it.
FloorPlanPainter _planPainter(HousePlan plan) {
  final doc = plan.document;
  final floor = deriveHouse(doc).floors.first;
  final rooms = doc.floors.first.rooms;
  return FloorPlanPainter(floor.base, {for (final r in rooms) r.id: r.name},
      {for (final r in rooms) r.id: roomColors[r.type]!},
      openings: floor.openings,
      stairs: floor.stairs,
      northAngleDeg: doc.footprint.northAngleDeg);
}
