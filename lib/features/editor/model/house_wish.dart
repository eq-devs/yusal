import 'package:flutter/material.dart';
import 'package:yusal/shared/settings/settings.dart';
import 'package:yusal/core/commands/house_wish.dart';
import 'package:yusal/core/document/house_document.dart';
import 'package:yusal/core/number_input.dart';
import 'package:yusal/render2d/furniture_names.dart';
import 'package:yusal/shared/motion/motion.dart';

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
  final double width, depth;
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
          names: {
            for (final t in RoomType.values)
              if (t != RoomType.custom) t.name: roomTypeName(t),
            'stair': tr3('楼梯间', 'Баспалдақ алаңы', 'Лестничный холл'),
            'family': tr3('起居室', 'Отбасы бөлмесі', 'Общая комната'),
          });

  /// The wish as one sentence in the app's language, for the assistant
  /// that designs whole houses.
  String sentence() {
    String m(double v) =>
        dec(v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1));
    final extras = [
      if (hall) tr3('门厅', 'тамбур', 'тамбур'),
      if (boiler) tr3('锅炉房', 'қазандық бөлмесі', 'котельная'),
      if (storage) tr3('储藏间', 'қойма', 'кладовая'),
      if (dining) tr3('餐厅', 'асхана', 'столовая'),
    ];
    return tr3(
        '帮我设计一栋 ${m(width)}×${m(depth)} 米的 $floors 层房子：$bedrooms 间卧室、$bathrooms 个卫生间、客厅和厨房'
            '${extras.isEmpty ? '' : '，还要${extras.join('、')}'}。每个房间都要有门，卧室、客厅和厨房要有窗。',
        '${m(width)}×${m(depth)} метр, $floors қабатты үй жобалап бер: $bedrooms жатын бөлме, $bathrooms жуынатын бөлме, қонақ бөлме және асүй'
            '${extras.isEmpty ? '' : ', сонымен қатар ${extras.join(', ')}'}. Әр бөлменің есігі болсын, жатын бөлмелерде, қонақ бөлмеде және асүйде терезе болсын.',
        'Спроектируй дом ${m(width)}×${m(depth)} метров, этажей: $floors. Спален: $bedrooms, санузлов: $bathrooms, гостиная и кухня'
            '${extras.isEmpty ? '' : ', а ещё ${extras.join(', ')}'}. У каждой комнаты должна быть дверь, в спальнях, гостиной и кухне — окно.');
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
                                  'Какой дом нужен?'),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(draft
                              ? tr3(
                                  '回答几项，马上画出第一版，之后都能改。',
                                  'Бірнеше сұраққа жауап беріңіз, алғашқы нұсқасы бірден сызылады. Кейін бәрін өзгертуге болады.',
                                  'Ответьте на несколько вопросов — первый вариант будет начерчен сразу. Потом всё можно изменить.')
                              : tr3(
                                  '回答几项，助手画出第一版，之后都能改。',
                                  'Бірнеше сұраққа жауап беріңіз, көмекші алғашқы нұсқасын сызады. Кейін бәрін өзгертуге болады.',
                                  'Ответьте на несколько вопросов — помощник начертит первый вариант. Потом всё можно изменить.')),
                          title(tr3('房子外形（米）', 'Үйдің өлшемі (м)',
                              'Размер дома (м)')),
                          Row(children: [
                            size(width, tr3('宽', 'Ені', 'Ширина')),
                            const SizedBox(width: 12),
                            size(depth, tr3('长', 'Ұзындығы', 'Длина')),
                          ]),
                          title(tr3('几层', 'Қабат саны', 'Этажей')),
                          pick('floors', [1, 2], floors, (v) => floors = v),
                          title(tr3('几间卧室', 'Жатын бөлме саны', 'Спален')),
                          pick('bedrooms', [1, 2, 3, 4, 5], bedrooms,
                              (v) => bedrooms = v),
                          title(
                              tr3('几个卫生间', 'Жуынатын бөлме саны', 'Санузлов')),
                          pick('bathrooms', [1, 2], bathrooms,
                              (v) => bathrooms = v),
                          title(tr3('还要', 'Тағы не керек', 'Что ещё нужно')),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            extra(tr3('门厅', 'Тамбур', 'Тамбур'), hall,
                                (v) => hall = v),
                            extra(tr3('锅炉房', 'Қазандық', 'Котельная'), boiler,
                                (v) => boiler = v),
                            extra(tr3('储藏间', 'Қойма', 'Кладовая'), storage,
                                (v) => storage = v),
                            extra(tr3('餐厅', 'Асхана', 'Столовая'), dining,
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
                                      'Размер должен быть в пределах 3–100 м'));
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
                                      'В дом такого размера столько комнат не поместится. Уберите часть комнат, добавьте этаж или увеличьте дом.'));
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
                                  'Начертить первый вариант'))),
                        ])));
          }));
}
