part of '../house_editor.dart';

/// Non-rectangular houses: cut a corner off the footprint (an L shape,
/// several cuts for T or U shapes), on every floor or just this one, and
/// put the rectangle back.
extension _OutlineTool on _HouseEditorState {
  bool get hasOutline => history.present.floors.any((f) => f.outside.isNotEmpty);

  Future<void> cutCornerDialog() async {
    final doc = history.present;
    String m(int mm) => (mm / 1000).toStringAsFixed(2);
    var corner = 'tr';
    var allFloors = true;
    final width = TextEditingController(
            text: m((doc.footprint.width * 0.4 / 100).round() * 100)),
        depth = TextEditingController(
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
                  title: Text(tr3('切掉一个角（L 形房子）', 'Бұрышты кесу (L пішінді үй)', 'Вырезать угол (Г-образный дом)')),
                  content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            Text(
                                tr3('切掉的部分在房子外面，沿切口自动生成外墙。可以多次切出 T 形、U 形。切口处的门窗要先移走。',
                                    'Кесілген бөлік үйден тыс қалады, кесік бойымен сыртқы қабырға пайда болады. Бірнеше рет кесіп T, U пішінін жасауға болады. Кесікке түсетін есік-терезені алдымен алып тастаңыз.', 'Вырезанная часть остаётся снаружи дома, вдоль выреза появляется наружная стена. Вырезая несколько раз, можно получить Т- или П-образную форму. Окна и двери, попадающие в вырез, сначала уберите.'),
                                style: TextStyle(fontSize: 12, color: t.muted)),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              cornerChip('tl', tr3('左上', 'Сол жоғары', 'Левый верхний'), Icons.north_west),
                              cornerChip('tr', tr3('右上', 'Оң жоғары', 'Правый верхний'), Icons.north_east),
                              cornerChip('bl', tr3('左下', 'Сол төмен', 'Левый нижний'), Icons.south_west),
                              cornerChip('br', tr3('右下', 'Оң төмен', 'Правый нижний'), Icons.south_east),
                            ]),
                            const SizedBox(height: 8),
                            TextField(
                                controller: width,
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                decoration: InputDecoration(
                                    labelText: tr3('切掉的宽（米，左右）', 'Кесік ені (м, солдан оңға)', 'Ширина выреза (м, слева направо)'))),
                            TextField(
                                controller: depth,
                                keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true),
                                decoration: InputDecoration(
                                    labelText: tr3('切掉的长（米，上下）', 'Кесік ұзындығы (м, төменнен жоғары)', 'Длина выреза (м, по вертикали)'))),
                            if (doc.floors.length > 1)
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: allFloors,
                                  title: Text(tr3('所有楼层都切掉 (取消则只切当前层，形成露台)',
                                      'Барлық қабатта (алып тастасаңыз тек осы қабатта — терраса)', 'На всех этажах (если снять — только на этом этаже, получится терраса)')),
                                  onChanged: (v) => setDialog(() => allFloors = v ?? true)),
                            if (error != null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(coreMessage(error!),
                                      style: TextStyle(color: t.crit))),
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                    FilledButton(
                        onPressed: () {
                          final w = double.tryParse(width.text.replaceAll(',', '.')),
                              d = double.tryParse(depth.text.replaceAll(',', '.'));
                          if (w == null || d == null || !w.isFinite || !d.isFinite) {
                            setDialog(() => error = tr3('请输入数字', 'Сан енгізіңіз', 'Введите число'));
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
                          action('CutOutline', args);
                          notify(tr3('已切出缺角，切口处是外墙；坡屋顶仍盖住整个矩形，缺角处成为有顶的门廊',
                              'Бұрыш кесілді, кесікте сыртқы қабырға; еңісті шатыр бүкіл тіктөртбұрышты жабады, кесік жабық айванға айналады', 'Угол вырезан, вдоль выреза идёт наружная стена; скатная крыша по-прежнему накрывает весь прямоугольник, и вырез становится крытой верандой'),
                              undo: undo);
                        },
                        child: Text(tr3('切掉', 'Кесу', 'Отрезать'))),
                  ]);
            }));
  }

  void restoreOutlineAction() {
    action('RestoreOutline', {});
    notify(tr3('已恢复矩形外形，恢复出的部分还没有分房', 'Тіктөртбұрыш қалпына келді, қайтқан бөлік әлі бөлмеге бөлінбеген', 'Прямоугольная форма восстановлена, возвращённая часть ещё не разделена на комнаты'),
        undo: undo);
  }
}
