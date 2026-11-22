part of 'house_editor.dart';

/// Option sheets and dialogs of the design tool: settings, grid, footprint, floors, room by size, wall settings, dimensions, export.
extension _EditorDialogs on _HouseEditorState {
  Future<void> settings() async {
    final choice = await showMotionSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final e in {
                'width': tr3('房屋宽度', 'Үйдің ені', 'Ширина дома'),
                'depth': tr3('房屋进深', 'Үйдің тереңдігі', 'Глубина дома'),
                'north':
                    tr3('正北方向', 'Солтүстік бағыты', 'Направление на север'),
                'flat': tr3('平屋顶', 'Тегіс шатыр', 'Плоская крыша'),
                'gable': tr3('双坡屋顶', 'Қос беткейлі шатыр', 'Двускатная крыша'),
                'hip': tr3('四坡屋顶', 'Төрт беткейлі шатыр', 'Вальмовая крыша'),
                'cut': tr3('切掉一个角（L 形）', 'Бұрышты кесу (L пішін)',
                    'Вырезать угол (Г-образная форма)'),
                if (hasOutline)
                  'restore': tr3('恢复矩形外形', 'Тіктөртбұрышқа қайтару',
                      'Вернуть прямоугольник'),
                'grid': tr3('编辑网格', 'Торды өзгерту', 'Изменить сетку'),
                'defaults':
                    tr3('默认尺寸', 'Әдепкі өлшемдер', 'Размеры по умолчанию')
              }.entries)
                ListTile(
                    title: Text(e.value),
                    onTap: () => Navigator.pop(context, e.key))
            ])));
    if (choice == 'width' || choice == 'depth') {
      final value = await length(
          choice == 'width'
              ? tr3('房屋宽度', 'Үйдің ені', 'Ширина дома')
              : tr3('房屋进深', 'Үйдің тереңдігі', 'Глубина дома'),
          choice == 'width'
              ? history.present.footprint.width
              : history.present.footprint.depth);
      if (value != null) action('SetFootprintSize', {choice!: value});
    }
    if (choice == 'flat') {
      final height = await length(
          tr3('女儿墙高度', 'Парапет биіктігі', 'Высота парапета'),
          history.present.roof.parapetHeight ?? 900);
      if (height != null) {
        action('SetRoof', {
          'roof': {'type': 'flat', 'parapetHeight': height}
        });
      }
    }
    if (choice == 'hip') {
      final pitchText = await ask(
          tr3('屋顶坡度（5–60°）', 'Шатыр еңісі (5–60°)', 'Уклон крыши (5–60°)'),
          '${history.present.roof.pitchDeg ?? 25}',
          number: true);
      final pitch = int.tryParse(pitchText ?? '');
      if (pitch == null) return;
      final overhang = await length(
          tr3('屋檐伸出', 'Карниз шығыңқылығы', 'Карнизный свес'),
          history.present.roof.overhang ?? 500);
      if (overhang == null) return;
      action('SetRoof', {
        'roof': {'type': 'hip', 'pitchDeg': pitch, 'overhang': overhang}
      });
    }
    if (choice == 'gable') {
      final pitchText = await ask(
          tr3('屋顶坡度（5–60°）', 'Шатыр еңісі (5–60°)', 'Уклон крыши (5–60°)'),
          '${history.present.roof.pitchDeg ?? 30}',
          number: true);
      if (pitchText == null) return;
      final pitch = int.tryParse(pitchText);
      if (pitch == null) return;
      final overhang = await length(
          tr3('屋檐伸出', 'Карниз шығыңқылығы', 'Карнизный свес'),
          history.present.roof.overhang ?? 500);
      if (overhang == null) return;
      final direction = await showMotionSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                ListTile(
                    title: Text(tr3('屋脊沿进深方向', 'Жота тереңдік бойымен',
                        'Конёк вдоль глубины')),
                    onTap: () => Navigator.pop(context, 'V')),
                ListTile(
                    title: Text(tr3(
                        '屋脊沿宽度方向', 'Жота ені бойымен', 'Конёк вдоль ширины')),
                    onTap: () => Navigator.pop(context, 'H')),
              ])));
      if (direction != null) {
        action('SetRoof', {
          'roof': {
            'type': 'gable',
            'ridgeDir': direction,
            'pitchDeg': pitch,
            'overhang': overhang
          }
        });
      }
    }
    if (choice == 'defaults') {
      final raw =
          jsonDecode(encodeHouse(history.present)) as Map<String, dynamic>;
      final defaults = raw['defaults'] as Map<String, dynamic>;
      final labels = {
        'outerWallThickness':
            tr3('外墙厚度', 'Сыртқы қабырға қалыңдығы', 'Толщина наружной стены'),
        'innerWallThickness':
            tr3('内墙厚度', 'Ішкі қабырға қалыңдығы', 'Толщина перегородки'),
        'slabThickness': tr3('楼板厚度', 'Плита қалыңдығы', 'Толщина плиты'),
        'stairRiserMax': tr3('楼梯最大步高', 'Баспалдақтың ең үлкен биіктігі',
            'Максимальная высота ступени'),
        'stairTread': tr3('楼梯踏步进深', 'Баспалдақ табанының тереңдігі',
            'Глубина проступи лестницы'),
        'stairWidthMin': tr3(
            '楼梯最小宽度', 'Баспалдақтың ең аз ені', 'Минимальная ширина лестницы'),
        'floorHeight':
            tr3('默认层高', 'Әдепкі қабат биіктігі', 'Высота этажа по умолчанию'),
        'doorWidth':
            tr3('默认门宽', 'Әдепкі есік ені', 'Ширина двери по умолчанию'),
        'doorHeight':
            tr3('默认门高', 'Әдепкі есік биіктігі', 'Высота двери по умолчанию'),
        'windowWidth':
            tr3('默认窗宽', 'Әдепкі терезе ені', 'Ширина окна по умолчанию'),
        'windowHeight':
            tr3('默认窗高', 'Әдепкі терезе биіктігі', 'Высота окна по умолчанию'),
        'windowSill': tr3('默认窗台高度', 'Әдепкі терезе алды биіктігі',
            'Высота подоконника по умолчанию')
      };
      final field = await showMotionSheet<String>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final entry in labels.entries)
                  ListTile(
                      title: Text(entry.value),
                      subtitle: Text(
                          '${dec(((defaults[entry.key] as int) / 1000).toString())} $unitM'),
                      onTap: () => Navigator.pop(context, entry.key)),
              ])));
      if (field != null) {
        final value = await length(labels[field]!, defaults[field] as int);
        if (value != null) {
          action('SetDefault', {'field': field, 'value': value});
        }
      }
    }
    if (choice == 'north') {
      final value = await showMotionSheet<int>(
          context: context,
          builder: (context) => SafeArea(
                  child: ListView(shrinkWrap: true, children: [
                for (final angle in [0, 90, 180, 270])
                  ListTile(
                      title: Text(tr3(
                          '正北指向 $angle°',
                          'Солтүстік $angle° бағытта',
                          'Направление на север: $angle°')),
                      onTap: () => Navigator.pop(context, angle))
              ])));
      if (value != null) action('SetNorthAngle', {'value': value});
    }
    if (choice == 'grid') grid();
    if (choice == 'cut') cutCornerDialog();
    if (choice == 'restore') restoreOutlineAction();
  }

  Future<void> grid() async {
    final selected = await showMotionSheet<Object>(
        context: context,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: 360,
                child: ListView(children: [
                  ListTile(
                      title: Text(tr3('新增竖向分隔线', 'Тік бөлу сызығын қосу',
                          'Добавить вертикальную разделительную линию')),
                      onTap: () => Navigator.pop(context, AxisDir.V)),
                  ListTile(
                      title: Text(tr3('新增横向分隔线', 'Көлденең бөлу сызығын қосу',
                          'Добавить горизонтальную разделительную линию')),
                      onTap: () => Navigator.pop(context, AxisDir.H)),
                  for (final axis
                      in base.axes.all.where((a) => a.kind != 'boundary'))
                    ListTile(
                        title: Text(tr3(
                            '${axis.dir == AxisDir.V ? '竖' : '横'}线 · ${(axis.pos / 1000).toStringAsFixed(2)} 米',
                            '${axis.dir == AxisDir.V ? 'Тік' : 'Көлденең'} сызық · ${m2dp(axis.pos)} м',
                            '${axis.dir == AxisDir.V ? 'Вертикальная' : 'Горизонтальная'} линия · ${m2dp(axis.pos)} м')),
                        onTap: () => Navigator.pop(context, axis))
                ]))));
    if (selected is AxisDir) {
      final value = await length(
          tr3('新分隔线位置', 'Жаңа сызықтың орны', 'Положение новой линии'),
          selected == AxisDir.V
              ? history.present.footprint.width ~/ 2
              : history.present.footprint.depth ~/ 2);
      if (value != null) {
        final scope = await showMotionSheet<String>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  ListTile(
                      title: Text(tr3('所有楼层', 'Барлық қабат', 'Все этажи')),
                      onTap: () => Navigator.pop(context, 'global')),
                  ListTile(
                      title:
                          Text(tr3('仅本层', 'Тек осы қабат', 'Только этот этаж')),
                      onTap: () => Navigator.pop(context, 'floor')),
                ])));
        if (scope != null) {
          action('AddAxis', {
            'dir': selected,
            'pos': value,
            if (scope == 'floor') 'floorId': floor.id
          });
        }
      }
    }
    if (selected is ResolvedAxis) {
      final operation = await showMotionSheet<String>(
        context: context,
        builder: (context) => SafeArea(
            child: ListView(shrinkWrap: true, children: [
          ListTile(
              title: Text(tr3('修改位置', 'Орнын өзгерту', 'Изменить положение')),
              onTap: () => Navigator.pop(context, 'move')),
          if (selected.kind == 'floor')
            ListTile(
                title: Text(tr3('同步到所有楼层', 'Барлық қабатқа тарату',
                    'Применить ко всем этажам')),
                onTap: () => Navigator.pop(context, 'promote')),
          ListTile(
              title: Text(tr3('删除分隔线', 'Сызықты жою', 'Удалить линию')),
              onTap: () => Navigator.pop(context, 'delete')),
        ])),
      );
      if (operation == 'move') {
        final value = await length(
            tr3('分隔线位置', 'Сызықтың орны', 'Положение линии'), selected.pos);
        if (value != null) {
          action('MoveAxis', {'axisId': selected.id, 'pos': value});
        }
      }
      if (operation == 'promote') {
        action('PromoteFloorAxis', {'axisId': selected.id});
      }
      if (operation == 'delete') {
        var result =
            deleteAxis(history.present, selected.id, () => const Uuid().v4());
        if (result.needsResolution && mounted) {
          final resolution = await showDialog<String>(
              context: context,
              builder: (context) => AlertDialog(
                    title: Text(tr3('删除分隔线', 'Сызықты жою', 'Удалить линию')),
                    content: Text(
                        '${coreMessage(result.message ?? '')}\n${result.hasHosted ? tr3('这条线上的门窗和墙设置将删除。\n', 'Осы сызықтағы есік-терезе мен қабырға баптаулары жойылады.\n', 'Окна, двери и настройки стен на этой линии будут удалены.\n') : ''}${result.hasStairs ? tr3('受影响的楼梯将删除。\n', 'Әсер ететін баспалдақтар жойылады.\n', 'Затронутые лестницы будут удалены.\n') : ''}${tr3('请选择合并后保留的房间。', 'Біріктірген соң қалатын бөлмені таңдаңыз.', 'Выберите комнату, которая останется после объединения.')}'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                      for (final entry in {
                        'mergeRooms': tr3('合并房间', 'Бөлмелерді біріктіру',
                            'Объединить комнаты'),
                        'keepLowSide': tr3(
                            '保留左 / 下侧',
                            'Сол / төменгі жағын қалдыру',
                            'Оставить левую / нижнюю сторону'),
                        'keepHighSide': tr3(
                            '保留右 / 上侧',
                            'Оң / жоғарғы жағын қалдыру',
                            'Оставить правую / верхнюю сторону')
                      }.entries)
                        TextButton(
                            onPressed: () => Navigator.pop(context, entry.key),
                            child: Text(entry.value)),
                    ],
                  ));
          if (resolution == null) return;
          result = deleteAxis(
              history.present, selected.id, () => const Uuid().v4(),
              resolution: resolution,
              deleteHostedObjects: true,
              deleteStairs: true);
        }
        if (!mounted) return;
        if (result.document != null) {
          update(() {
            if (history
                .commit(withExtras(result.document!, history.present.extras))) {
              changed();
            }
          });
        } else {
          notify(result.message ??
              tr3('无法删除分隔线', 'Сызықты жою мүмкін емес',
                  'Линию нельзя удалить'));
        }
      }
    }
  }

  Future<void> footprintOptions() async {
    final width = TextEditingController(
        text: (history.present.footprint.width / 1000).toStringAsFixed(2));
    final depth = TextEditingController(
        text: (history.present.footprint.depth / 1000).toStringAsFixed(2));
    String? error;
    await showMotionSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 20, 20,
                            MediaQuery.viewInsetsOf(context).bottom + 20),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  tr3('房屋长宽', 'Үйдің ені мен ұзындығы',
                                      'Ширина и длина дома'),
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600)),
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(tr3(
                                      '外形尺寸用于全部楼层。内部房间位置保持不变。',
                                      'Сыртқы өлшем барлық қабатқа қолданылады. Ішкі бөлмелердің орны сақталады.',
                                      'Наружный размер применяется ко всем этажам. Положение внутренних комнат сохраняется.'))),
                              TextField(
                                  controller: width,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                      labelText: tr3(
                                          '宽（米，左右方向）',
                                          'Ені (м, солдан оңға)',
                                          'Ширина (м, слева направо)'))),
                              TextField(
                                  controller: depth,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: InputDecoration(
                                      labelText: tr3(
                                          '长（米，上下方向）',
                                          'Ұзындығы (м, төменнен жоғары)',
                                          'Длина (м, снизу вверх)'))),
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
                                  onPressed: () {
                                    final w = parseNumber(width.text);
                                    final d = parseNumber(depth.text);
                                    if (w == null ||
                                        d == null ||
                                        !w.isFinite ||
                                        !d.isFinite ||
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
                                    final args = <String, dynamic>{
                                      'width': (w * 1000).round(),
                                      'depth': (d * 1000).round()
                                    };
                                    final result = executeCommand(
                                        presentState,
                                        DesignCommand('SetFootprintSize', args),
                                        CommandContext(
                                            newId: () => const Uuid().v4(),
                                            now: () => 'unused'));
                                    if (result is Rejected) {
                                      update(() =>
                                          error = coreMessage(result.message));
                                      return;
                                    }
                                    Navigator.pop(context);
                                    action('SetFootprintSize', args);
                                  },
                                  child: Text(tr3('应用尺寸', 'Өлшемді қолдану',
                                      'Применить размер'))),
                              TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    update(() {
                                      view3d = false;
                                      tool = EditorTool.resize;
                                      placementHint = null;
                                    });
                                  },
                                  icon: const Icon(Icons.open_in_full),
                                  label: Text(tr3(
                                      '拖动外边框调整',
                                      'Сыртқы жиекті сүйреп өзгерту',
                                      'Изменить, перетаскивая внешний контур'))),
                              TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    cutCornerDialog();
                                  },
                                  icon: const Icon(Icons.crop),
                                  label: Text(tr3(
                                      '切掉一个角（L 形）',
                                      'Бұрышты кесу (L пішін)',
                                      'Вырезать угол (Г-образная форма)'))),
                              // The same plan for a plot whose road or sun
                              // is on the other side.
                              TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    action('MirrorPlan',
                                        {'direction': 'horizontal'});
                                  },
                                  icon: const Icon(Icons.flip),
                                  label: Text(tr3(
                                      '整个房子左右翻转',
                                      'Бүкіл үйді оңнан солға аудару',
                                      'Отразить весь дом слева направо'))),
                              TextButton.icon(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    action('MirrorPlan',
                                        {'direction': 'vertical'});
                                  },
                                  icon: const RotatedBox(
                                      quarterTurns: 1, child: Icon(Icons.flip)),
                                  label: Text(tr3(
                                      '整个房子上下翻转',
                                      'Бүкіл үйді жоғарыдан төменге аудару',
                                      'Отразить весь дом сверху вниз'))),
                              if (hasOutline)
                                TextButton.icon(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      restoreOutlineAction();
                                    },
                                    icon: const Icon(Icons.crop_square),
                                    label: Text(tr3(
                                        '恢复矩形外形',
                                        'Тіктөртбұрышқа қайтару',
                                        'Вернуть прямоугольник'))),
                            ]))))));
  }

  Future<void> moreTools() async {
    final choice = await showMotionSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
            child: SizedBox(
                height: math.min(MediaQuery.sizeOf(context).height * 0.7, 500),
                child: ListView(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                          tr3('更多工具', 'Басқа құралдар', 'Другие инструменты'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600))),
                  if (phoneTools)
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          // A tool picked here closes the sheet.
                          for (final w in secondaryToolButtons())
                            Listener(
                                onPointerUp: (_) => Future.microtask(() {
                                      if (context.mounted) {
                                        Navigator.maybePop(context);
                                      }
                                    }),
                                child: w)
                        ])),
                  for (final entry in {
                    'fit': tr3(
                        '恢复画布视角', 'Көріністі қалпына келтіру', 'Сбросить вид'),
                    'addRoom': tr3('按尺寸加房间', 'Өлшеммен бөлме қосу',
                        'Добавить комнату по размерам'),
                    'grid': tr3('网格', 'Тор', 'Сетка'),
                    'opening': tr3('门窗', 'Есік-терезе', 'Окна и двери'),
                    'stair': tr3('楼梯', 'Баспалдақ', 'Лестница'),
                    for (final type in RoomType.values)
                      type.name: roomTypeName(type),
                    'erase': tr3('擦除', 'Өшіру', 'Стереть')
                  }.entries)
                    ListTile(
                        title: Text(entry.value),
                        onTap: () => Navigator.pop(context, entry.key)),
                ]))));
    if (choice == null || !mounted) return;
    if (choice == 'fit') {
      canvasTransform.value = Matrix4.identity();
      return;
    }
    if (choice == 'addRoom') return addRoomBySize();
    if (choice == 'stair') return startStairStamp();
    update(() {
      erase = choice == 'erase';
      placementHint = null;
      if (['grid', 'opening', 'stair'].contains(choice)) {
        tool = EditorTool.values.byName(choice);
      } else {
        tool = EditorTool.room;
        if (!erase) brush = RoomType.values.firstWhere((t) => t.name == choice);
      }
    });
  }

  Future<void> floorOptions() async {
    final choice = await showMotionSheet<String>(
        context: context,
        builder: (context) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              for (final entry in {
                'AddFloor':
                    tr3('新增空层', 'Бос қабат қосу', 'Добавить пустой этаж'),
                'CopyFloor': tr3('复制本层', 'Қабатты көшіру', 'Копировать этаж'),
                'RenameFloor': tr3('楼层名称', 'Қабат атауы', 'Название этажа'),
                'SetFloorHeight': tr3('层高', 'Қабат биіктігі', 'Высота этажа'),
                'DeleteFloor': tr3('删除本层', 'Қабатты жою', 'Удалить этаж')
              }.entries)
                ListTile(
                    title: Text(entry.value),
                    onTap: () => Navigator.pop(context, entry.key))
            ])));
    if (choice == null) return;
    if (choice == 'SetFloorHeight') {
      final value = await length(
          tr3('层高', 'Қабат биіктігі', 'Высота этажа'), floor.height);
      if (value != null) action(choice, {'floorId': floor.id, 'value': value});
    } else if (choice == 'RenameFloor') {
      final value =
          await ask(tr3('楼层名称', 'Қабат атауы', 'Название этажа'), floor.name);
      if (value != null) action(choice, {'floorId': floor.id, 'value': value});
    } else {
      if (choice == 'DeleteFloor') {
        final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text(tr3(
                        '删除本层及其全部内容？',
                        'Қабатты бүкіл ішімен жою керек пе?',
                        'Удалить этаж со всем содержимым?')),
                    content: Text(tr3(
                        '本层房间和门窗将删除。删除顶层时，下层通向本层的楼梯也会删除。',
                        'Қабаттағы бөлмелер мен есік-терезелер жойылады. Жоғарғы қабат жойылса, оған апаратын баспалдақ та жойылады.',
                        'Комнаты, окна и двери этажа будут удалены. При удалении верхнего этажа лестница, ведущая на него, тоже удаляется.')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(tr3('删除', 'Жою', 'Удалить')))
                    ]));
        if (yes != true) return;
      }
      final before = history.present;
      final index = floorIndex;
      action(choice, {
        'floorId': floor.id,
        if (choice == 'DeleteFloor') 'deleteStairs': true
      });
      if (history.present == before || !mounted) return;
      update(() {
        cancelDrag();
        clearWallSelection();
        drawingOrigin = null;
        floorIndex = choice == 'DeleteFloor'
            ? math.min(index, history.present.floors.length - 1)
            : index + 1;
        derive();
      });
      notify(choice == 'DeleteFloor'
          ? tr3(
              '已删除楼层，现在是「${displayFloorName(floor.name)}」',
              'Қабат жойылды, қазір «${displayFloorName(floor.name)}»',
              'Этаж удалён, сейчас открыт «${displayFloorName(floor.name)}»')
          : tr3(
              '已新增「${displayFloorName(floor.name)}」，现在编辑这一层',
              '«${displayFloorName(floor.name)}» қосылды, енді осы қабатты өзгертесіз',
              'Добавлен «${displayFloorName(floor.name)}», теперь вы редактируете этот этаж'));
    }
  }

  /// A room from its use, its size and the corner of the house it goes
  /// in, for those who would rather type than draw.
  Future<void> addRoomBySize() async {
    var type = RoomType.bedroom;
    var corner = 'bl';
    final width = TextEditingController();
    final depth = TextEditingController();
    void fill() {
      width.text = dec('${_HouseEditorState.roomSizes[type]!.$1}');
      depth.text = dec('${_HouseEditorState.roomSizes[type]!.$2}');
    }

    fill();
    String? error;
    final args = await showMotionSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => SafeArea(
                child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(20, 20, 20,
                        MediaQuery.viewInsetsOf(context).bottom + 20),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                              tr3('按尺寸加房间', 'Өлшеммен бөлме қосу',
                                  'Добавить комнату по размерам'),
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            for (final t in RoomType.values)
                              ChoiceChip(
                                  key: Key('add-room-${t.name}'),
                                  label: Text(roomTypeName(t)),
                                  selected: type == t,
                                  onSelected: (_) => update(() {
                                        type = t;
                                        fill();
                                      }))
                          ]),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: width,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: InputDecoration(
                                        labelText: tr3(
                                            '宽（米）', 'Ені (м)', 'Ширина (м)')))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: TextField(
                                    controller: depth,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: InputDecoration(
                                        labelText: tr3('长（米）', 'Ұзындығы (м)',
                                            'Длина (м)')))),
                          ]),
                          const SizedBox(height: 12),
                          Text(tr3('放在房子的哪个角', 'Үйдің қай бұрышына',
                              'В какой угол дома')),
                          const SizedBox(height: 6),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            for (final c in {
                              'tl': tr3('左上', 'Сол жақ жоғары', 'Слева вверху'),
                              'tr': tr3('右上', 'Оң жақ жоғары', 'Справа вверху'),
                              'bl': tr3('左下', 'Сол жақ төмен', 'Слева внизу'),
                              'br': tr3('右下', 'Оң жақ төмен', 'Справа внизу'),
                            }.entries)
                              ChoiceChip(
                                  key: Key('add-room-${c.key}'),
                                  label: Text(c.value),
                                  selected: corner == c.key,
                                  onSelected: (_) =>
                                      update(() => corner = c.key))
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
                              key: const Key('add-room-go'),
                              onPressed: () {
                                final fp = history.present.footprint;
                                final w =
                                    ((parseNumber(width.text) ?? 0) * 1000)
                                        .round();
                                final d =
                                    ((parseNumber(depth.text) ?? 0) * 1000)
                                        .round();
                                if (w < 300 ||
                                    d < 300 ||
                                    w > fp.width ||
                                    d > fp.depth) {
                                  update(() => error = tr3(
                                      '房间要在 0.3 米到房屋长宽之间',
                                      'Бөлме 0,3 м мен үй өлшемі аралығында болуы керек',
                                      'Комната должна быть от 0,3 м до размеров дома'));
                                  return;
                                }
                                final left =
                                    corner.endsWith('l') ? 0 : fp.width - w;
                                final bottom =
                                    corner.startsWith('b') ? 0 : fp.depth - d;
                                Navigator.pop(context, <String, dynamic>{
                                  'w': w,
                                  'd': d,
                                  'left': left,
                                  'bottom': bottom,
                                  'roomType': type,
                                  'corner': corner
                                });
                              },
                              child: Text(tr3(
                                  '放到图上', 'Сызбаға қою', 'Поставить на план'))),
                        ])))));
    if (args != null && mounted) {
      startStamp(args['roomType'] as RoomType, args['w'] as int,
          args['d'] as int, args['corner'] as String);
    }
  }

  Future<void> wallSettings({bool directThickness = false}) async {
    if (selectedDrawnAnchor == null) return;
    final choice = directThickness
        ? 'thickness'
        : await showMotionSheet<String>(
            context: context,
            builder: (context) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  ListTile(
                      title: Text(tr3(
                          '调整墙厚', 'Қалыңдығын өзгерту', 'Изменить толщину')),
                      onTap: () => Navigator.pop(context, 'thickness')),
                  ListTile(
                      title: Text(tr3('恢复默认墙厚', 'Әдепкі қалыңдықты қайтару',
                          'Вернуть толщину по умолчанию')),
                      onTap: () => Navigator.pop(context, 'default'))
                ])));
    if (choice == null) return;
    int? value;
    if (choice == 'thickness') {
      final current = floor.wallOverrides
          .where((w) => w.anchor == selectedDrawnAnchor)
          .firstOrNull;
      final thickness = current is SolidWall
          ? current.value
          : current is ThicknessWall
              ? current.value
              : selectedWall?.thickness.round() ??
                  history.present.defaults.innerWallThickness;
      value = await showDialog<int>(
          context: context,
          builder: (_) => WallThicknessDialog(initial: thickness));
      if (value == null || !mounted) return;
    }
    final start = editStart;
    final end = editEnd;
    action('SetWallOverride', {
      'floorId': floor.id,
      'anchor': selectedDrawnAnchor,
      'type': choice,
      if (value != null) 'value': value
    });
    if (start != null && end != null) {
      update(() => refreshWallSelection(start, end));
    }
  }

  /// A figure on the plan was tapped: type the size wanted and say which
  /// wall gives way. The number asked for is the number drawn, wall face
  /// to wall face, so there is nothing to convert.
  Future<void> editDimension(DimensionSpan span) async {
    final fp = history.present.footprint;
    if (span.overall) {
      update(() => editingDimension = span);
      final value = await length(
          span.horizontal
              ? tr3('房屋总宽', 'Үйдің жалпы ені', 'Общая ширина дома')
              : tr3('房屋总深', 'Үйдің жалпы тереңдігі', 'Общая глубина дома'),
          span.length.round());
      if (mounted) update(() => editingDimension = null);
      if (value != null && mounted) {
        action(
            'SetFootprintSize', {span.horizontal ? 'width' : 'depth': value});
      }
      return;
    }
    final walls = wallsOf(base, const FoundationSpec()).where((w) =>
        w.role != WallRole.temporary &&
        w.horizontal != span.horizontal &&
        switch (span.side) {
          'top' => w.rect.top >= fp.depth - 600,
          'bottom' => w.rect.bottom <= 600,
          'left' => w.rect.left <= 600,
          _ => w.rect.right >= fp.width - 600,
        });
    double lo(WallInfo w) => span.horizontal ? w.rect.left : w.rect.bottom;
    double hi(WallInfo w) => span.horizontal ? w.rect.right : w.rect.top;
    if (walls
        .any((w) => (lo(w) - span.a).abs() < 2 && (hi(w) - span.b).abs() < 2)) {
      notify(tr3(
          '这是墙的厚度。点一下墙可以改厚度。',
          'Бұл қабырғаның қалыңдығы. Өзгерту үшін қабырғаны басыңыз.',
          'Это толщина стены. Нажмите на стену, чтобы изменить её.'));
      return;
    }
    bool inner(WallInfo w) => w.segment.axis.kind != 'boundary';
    final low =
        walls.where((w) => (hi(w) - span.a).abs() < 2 && inner(w)).firstOrNull;
    final high =
        walls.where((w) => (lo(w) - span.b).abs() < 2 && inner(w)).firstOrNull;
    update(() => editingDimension = span);
    final lowName = span.horizontal
        ? tr3('动左边的墙', 'Сол қабырға жылжиды', 'Двигать левую стену')
        : tr3('动下边的墙', 'Төменгі қабырға жылжиды', 'Двигать нижнюю стену');
    final highName = span.horizontal
        ? tr3('动右边的墙', 'Оң қабырға жылжиды', 'Двигать правую стену')
        : tr3('动上边的墙', 'Жоғарғы қабырға жылжиды', 'Двигать верхнюю стену');
    final field =
        TextEditingController(text: (span.length / 1000).toStringAsFixed(2));
    field.selection =
        TextSelection(baseOffset: 0, extentOffset: field.text.length);
    var moveHigh = high != null;
    final choice = await showDialog<({int length, bool moveHigh})>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, setDialog) {
              void done() {
                final v = parseNumber(field.text);
                if (v == null || v <= 0) return;
                Navigator.pop(
                    context, (length: (v * 1000).round(), moveHigh: moveHigh));
              }

              return AlertDialog(
                  title: Text(span.horizontal
                      ? tr3('这一段的净宽（米）', 'Осы бөліктің таза ені (м)',
                          'Ширина этого участка в свету (м)')
                      : tr3('这一段的净深（米）', 'Осы бөліктің таза тереңдігі (м)',
                          'Глубина этого участка в свету (м)')),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                            key: const Key('dim-field'),
                            controller: field,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            onSubmitted: (_) => done()),
                        const SizedBox(height: 12),
                        if (low != null && high != null)
                          Wrap(spacing: 8, children: [
                            ChoiceChip(
                                key: const Key('dim-low'),
                                label: Text(lowName),
                                selected: !moveHigh,
                                onSelected: (_) =>
                                    setDialog(() => moveHigh = false)),
                            ChoiceChip(
                                key: const Key('dim-high'),
                                label: Text(highName),
                                selected: moveHigh,
                                onSelected: (_) =>
                                    setDialog(() => moveHigh = true)),
                          ])
                        else
                          Text(
                              low == null && high == null
                                  ? tr3(
                                      '两边都是外墙，房屋会跟着变大或变小。',
                                      'Екі жағы да сыртқы қабырға, үй өлшемі өзгереді.',
                                      'С обеих сторон наружные стены: изменится размер дома.')
                                  : (high != null ? highName : lowName),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Tokens.of(context).muted)),
                      ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr3('取消', 'Болдырмау', 'Отмена'))),
                    FilledButton(
                        key: const Key('dim-ok'),
                        onPressed: done,
                        child: Text(tr3('好了', 'Дайын', 'Готово'))),
                  ]);
            }));
    if (mounted) update(() => editingDimension = null);
    if (choice == null || !mounted) return;
    final delta = choice.length - span.length.round();
    if (delta == 0) return;
    if (low == null && high == null) {
      action('SetFootprintSize', {
        span.horizontal ? 'width' : 'depth':
            (span.horizontal ? fp.width : fp.depth) + delta
      });
      return;
    }
    final wall = (choice.moveHigh ? high : low)!.segment;
    final along = (wall.start.pos + wall.end.pos) / 2;
    final solid = floor.wallOverrides.whereType<SolidWall>().where((w) {
      final c = resolveAnchor(base.axes, w.anchor).chain!;
      return c.carrier.id == wall.axis.id &&
          c.startPos <= along &&
          c.endPos >= along;
    }).firstOrNull;
    action('MoveDrawnWall', {
      'floorId': floor.id,
      if (solid != null) 'wallId': solid.id,
      if (solid == null) 'anchor': wall.ref.anchor,
      'pos': wall.axis.pos + (choice.moveHigh ? delta : -delta),
    });
  }

  /// The drawing set as a PDF, or the current floor's plan as a PNG,
  /// downloaded on the web and shared on phones.
  Future<void> exportDrawings({bool png = false}) async {
    await save();
    if (!mounted) return;
    final progress = ValueNotifier<String>(
        tr3('正在准备图纸…', 'Сызбалар дайындалып жатыр…', 'Подготовка чертежей…'));
    final today = DateTime.now();
    final input = DrawingInput(
        doc: history.present,
        derived: derived,
        roomName: displayRoomName,
        floorName: displayFloorName,
        openingLabel: openingLabel,
        date:
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}');
    unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
            canPop: false,
            child: AlertDialog(
                content: Row(children: [
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 16),
              Expanded(
                  child: ValueListenableBuilder<String>(
                      valueListenable: progress,
                      builder: (context, text, _) => Text(text))),
            ])))));
    try {
      final bytes = png
          ? await buildPlanPng(input, floorIndex)
          : await buildDrawingPdf(input,
              onProgress: (done, total) => progress.value = tr3(
                  '正在绘制第 $done / $total 张图纸…',
                  '$done / $total сызба салынып жатыр…',
                  'Создаётся чертёж $done / $total…'));
      final cleaned = history.present.meta.name
          .replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '')
          .trim();
      final base =
          cleaned.isEmpty ? tr3('房屋设计', 'Үй жобасы', 'Проект дома') : cleaned;
      final filename = png
          ? '$base ${displayFloorName(floor.name)}.png'
          : '$base ${tr3('图纸', 'сызбалар', 'чертежи')}.pdf';
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      final file = XFile.fromData(bytes,
          mimeType: png ? 'image/png' : 'application/pdf', name: filename);
      if (kIsWeb) {
        await file.saveTo(filename);
      } else if (mounted) {
        final box = context.findRenderObject() as RenderBox?;
        await SharePlus.instance.share(ShareParams(
            files: [file],
            sharePositionOrigin: box == null
                ? null
                : box.localToGlobal(Offset.zero) & box.size));
      }
    } catch (_) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
        notify(tr3('暂时无法生成图纸', 'Сызбаларды қазір жасау мүмкін емес',
            'Сейчас не удаётся создать чертежи'));
      }
    } finally {
      progress.dispose();
    }
  }
}
