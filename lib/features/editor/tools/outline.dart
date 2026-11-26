part of '../page.dart';

/// Non-rectangular houses: cut a corner off the footprint (an L shape,
/// several cuts for T or U shapes), on every floor or just this one, and
/// put the rectangle back.
extension _OutlineTool on _HouseEditorState {
  bool get hasOutline =>
      history.present.floors.any((f) => f.outside.isNotEmpty);

  Future<void> cutCornerDialog() async {
    final doc = history.present;
    String m(int mm) => (mm / 1000).toStringAsFixed(2);
    var corner = 'tr';
    var allFloors = true;
    final width = TextEditingController(
        text: m((doc.footprint.width * 0.4 / 100).round() * 100));
    final depth = TextEditingController(
        text: m((doc.footprint.depth * 0.4 / 100).round() * 100));
    String? error;
    await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setDialog) {
              final t = Tokens.of(context);
              Widget cornerChip(String key, String label, IconData icon) =>
                  ChoiceChip(
                      avatar: Icon(icon, size: 16),
                      label: Text(label),
                      selected: corner == key,
                      onSelected: (_) => setDialog(() => corner = key));
              return AlertDialog(
                  title: Text(tr3(
                      '切掉一个角（L 形房子）',
                      'Бұрышты кесу (L пішінді үй)',
                      'Вырезать угол (Г-образный дом)',
                      'Cut a corner (L-shaped house)',
                      ky: 'Бурчту кесүү (L түрүндөгү үй)',
                      uz: 'Burchakni kesish (L shaklidagi uy)')),
                  content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Text(
                                tr3(
                                    '切掉的部分在房子外面，沿切口自动生成外墙。可以多次切出 T 形、U 形。切口处的门窗要先移走。',
                                    'Кесілген бөлік үйден тыс қалады, кесік бойымен сыртқы қабырға пайда болады. Бірнеше рет кесіп T, U пішінін жасауға болады. Кесікке түсетін есік-терезені алдымен алып тастаңыз.',
                                    'Вырезанная часть остаётся снаружи дома, вдоль выреза появляется наружная стена. Вырезая несколько раз, можно получить Т- или П-образную форму. Окна и двери, попадающие в вырез, сначала уберите.',
                                    'The cut part stays outside the house and an outer wall runs along the cut. Cut several times for a T or U shape. Remove windows and doors inside the cut first.',
                                    ky: 'Кесилген бөлүк үйдүн сыртында калат, кесик боюнча сырткы дубал өтөт. T же U түрү үчүн бир нече жолу кесиңиз. Адегенде кесик ичиндеги терезе менен эшиктерди алып салыңыз.',
                                    uz: 'Kesilgan qism uydan tashqarida qoladi, kesim boʻylab tashqi devor oʻtadi. T yoki U shakli uchun bir necha marta kesing. Avval kesim ichidagi deraza va eshiklarni olib tashlang.'),
                                style: TextStyle(fontSize: 12, color: t.muted)),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              cornerChip(
                                  'tl',
                                  tr3('左上', 'Сол жоғары', 'Левый верхний',
                                      'Top left',
                                      ky: 'Сол жогору', uz: 'Chap yuqori'),
                                  Icons.north_west),
                              cornerChip(
                                  'tr',
                                  tr3('右上', 'Оң жоғары', 'Правый верхний',
                                      'Top right',
                                      ky: 'Оң жогору', uz: 'Oʻng yuqori'),
                                  Icons.north_east),
                              cornerChip(
                                  'bl',
                                  tr3('左下', 'Сол төмен', 'Левый нижний',
                                      'Bottom left',
                                      ky: 'Сол ылдый', uz: 'Chap past'),
                                  Icons.south_west),
                              cornerChip(
                                  'br',
                                  tr3('右下', 'Оң төмен', 'Правый нижний',
                                      'Bottom right',
                                      ky: 'Оң ылдый', uz: 'Oʻng past'),
                                  Icons.south_east),
                            ]),
                            const SizedBox(height: 8),
                            TextField(
                                controller: width,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: tr3(
                                        '切掉的宽（米，左右）',
                                        'Кесік ені (м, солдан оңға)',
                                        'Ширина выреза (м, слева направо)',
                                        'Cut width (m, left to right)',
                                        ky: 'Кесиктин туурасы (м, солдон оңго)',
                                        uz: 'Kesim eni (m, chapdan oʻngga)'))),
                            TextField(
                                controller: depth,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: InputDecoration(
                                    labelText: tr3(
                                        '切掉的长（米，上下）',
                                        'Кесік ұзындығы (м, төменнен жоғары)',
                                        'Длина выреза (м, по вертикали)',
                                        'Cut length (m, vertical)',
                                        ky: 'Кесиктин узундугу (м, тикесинен)',
                                        uz: 'Kesim uzunligi (m, vertikal)'))),
                            if (doc.floors.length > 1)
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: allFloors,
                                  title: Text(tr3(
                                      '所有楼层都切掉 (取消则只切当前层，形成露台)',
                                      'Барлық қабатта (алып тастасаңыз тек осы қабатта — терраса)',
                                      'На всех этажах (если снять — только на этом этаже, получится терраса)',
                                      'On all floors (untick for this floor only, making a terrace)',
                                      ky:
                                          'Бардык кабаттарда (терраса жасоо үчүн белгини алып, ушул кабатта гана)',
                                      uz:
                                          'Barcha qavatlarda (faqat shu qavat uchun belgini olib tashlang, terrasa hosil boʻladi)')),
                                  onChanged: (v) =>
                                      setDialog(() => allFloors = v ?? true)),
                            if (error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(coreMessage(error!),
                                      style: TextStyle(color: t.crit))),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel',
                            ky: 'Жокко чыгаруу', uz: 'Bekor qilish'))),
                    FilledButton(
                        onPressed: () {
                          final w = parseNumber(width.text);
                          final d = parseNumber(depth.text);
                          if (w == null ||
                              d == null ||
                              !w.isFinite ||
                              !d.isFinite) {
                            setDialog(() => error = tr3(
                                '请输入数字',
                                'Сан енгізіңіз',
                                'Введите число',
                                'Enter a number',
                                ky: 'Сан киргизиңиз',
                                uz: 'Son kiriting'));
                            return;
                          }
                          final args = <String, dynamic>{
                            'corner': corner,
                            'width': (w * 1000).round(),
                            'depth': (d * 1000).round(),
                            if (!allFloors) 'floorIds': [floor.id],
                          };
                          final result = executeCommand(
                              presentState,
                              DesignCommand('CutOutline', args),
                              CommandContext(
                                  newId: () => const Uuid().v4(),
                                  now: () => 'unused'));
                          if (result is Rejected) {
                            setDialog(() => error = result.message);
                            return;
                          }
                          Navigator.pop(context);
                          if (action('CutOutline', args) is! Applied) {
                            return;
                          }
                          notify(
                              tr3(
                                  '已切出缺角，切口处是外墙；坡屋顶仍盖住整个矩形，缺角处成为有顶的门廊',
                                  'Бұрыш кесілді, кесікте сыртқы қабырға; еңісті шатыр бүкіл тіктөртбұрышты жабады, кесік жабық айванға айналады',
                                  'Угол вырезан, вдоль выреза идёт наружная стена; скатная крыша по-прежнему накрывает весь прямоугольник, и вырез становится крытой верандой',
                                  'Corner cut; an outer wall runs along the cut. A pitched roof still covers the whole rectangle, so the cut becomes a covered veranda',
                                  ky: 'Бурч кесилди; кесик боюнча сырткы дубал өтөт. Жантык чатыр дагы эле бүт тик бурчтукту жабат, ошондуктан кесик жабык верандага айланат',
                                  uz: 'Burchak kesildi; kesim boʻylab tashqi devor oʻtadi. Nishabli tom baribir butun toʻrtburchakni yopadi, shuning uchun kesim yopiq ayvonga aylanadi'),
                              undo: undo);
                        },
                        child: Text(tr3('切掉', 'Кесу', 'Отрезать', 'Cut',
                            ky: 'Кесүү', uz: 'Kesish'))),
                  ]);
            }));
  }

  void restoreOutlineAction() {
    if (action('RestoreOutline', {}) is! Applied) return;
    notify(
        tr3(
            '已恢复矩形外形，恢复出的部分还没有分房',
            'Тіктөртбұрыш қалпына келді, қайтқан бөлік әлі бөлмеге бөлінбеген',
            'Прямоугольная форма восстановлена, возвращённая часть ещё не разделена на комнаты',
            "Rectangle restored; the returned part isn't divided into rooms yet",
            ky: 'Тик бурчтук калыбына келди; кайтарылган бөлүк али бөлмөлөргө бөлүнгөн жок',
            uz: 'Toʻrtburchak tiklandi; qaytarilgan qism hali xonalarga boʻlinmagan'),
        undo: undo);
  }
}
