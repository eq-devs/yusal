part of '../page.dart';

/// What the size form hands back: a named house of [width] × [depth] mm
/// under [roof], or, with [sketch], one whose outline is drawn first.
typedef _NewDesign = ({
  String name,
  int width,
  int depth,
  String roof,
  bool sketch
});

String _defaultHouseName() => tr3('我的房屋', 'Менің үйім', 'Мой дом', 'My house',
    ky: 'Менин үйүм', uz: 'Mening uyim');

/// The "how to start" sheet. Its second page is the size form: choosing
/// "from dimensions" pushes the form in from the right inside the same
/// sheet, which grows to fit, instead of closing it for a dialog. Without
/// [ways] the sheet is the size form alone.
class _StartSheet extends StatefulWidget {
  const _StartSheet({this.ways});

  /// The first page; calls `toSize` to move on to the size form.
  final Widget Function(BuildContext context, VoidCallback toSize)? ways;
  @override
  State<_StartSheet> createState() => _StartSheetState();
}

class _StartSheetState extends State<_StartSheet> {
  late bool size = widget.ways == null;
  // Which way the pages last moved, so going back slides the other way.
  bool forward = true;

  void go(bool toSize) {
    HapticFeedback.selectionClick();
    setState(() {
      forward = toSize;
      size = toSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    final page = size
        ? _NewDesignForm(
            key: const ValueKey('start-size'),
            onBack: widget.ways == null ? null : () => go(false))
        : KeyedSubtree(
            key: const ValueKey('start-ways'),
            child: widget.ways!(context, () => go(true)));
    return SafeArea(
        child: Padding(
            // The form stays above the keyboard.
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom),
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.88),
                child: AnimatedSize(
                    duration: reduced ? Duration.zero : Motion.enter,
                    curve: Motion.settle,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                        duration: reduced ? Duration.zero : Motion.enter,
                        reverseDuration: reduced ? Duration.zero : Motion.fast,
                        switchInCurve: Motion.settle,
                        switchOutCurve: Curves.easeOut,
                        layoutBuilder: (current, previous) => Stack(
                                alignment: Alignment.topCenter,
                                children: [
                                  ...previous,
                                  if (current != null) current
                                ]),
                        transitionBuilder: (child, animation) {
                          // The page coming in travels a short way from
                          // the side it belongs on; the one leaving only
                          // fades, so the two never cross.
                          final incoming = child.key ==
                              ValueKey(size ? 'start-size' : 'start-ways');
                          final from = Offset(forward ? 0.18 : -0.18, 0);
                          return FadeTransition(
                              opacity: animation,
                              child: incoming
                                  ? SlideTransition(
                                      position: Tween(
                                              begin: from, end: Offset.zero)
                                          .animate(animation),
                                      child: child)
                                  : child);
                        },
                        child: page)))));
  }
}

/// Name, size (with a live outline and common sizes) and roof of a new
/// house. Pops the sheet with a [_NewDesign].
class _NewDesignForm extends StatefulWidget {
  const _NewDesignForm({super.key, this.onBack});

  /// Back to the ways to start; null when the form is the whole sheet.
  final VoidCallback? onBack;
  @override
  State<_NewDesignForm> createState() => _NewDesignFormState();
}

class _NewDesignFormState extends State<_NewDesignForm> {
  final name = TextEditingController(text: _defaultHouseName());
  final width = TextEditingController(text: '12');
  final depth = TextEditingController(text: '10');
  String? validation;
  String roof = 'gable';
  // The outline the editor then grows out of.
  final preview = GlobalKey();

  @override
  void dispose() {
    name.dispose();
    width.dispose();
    depth.dispose();
    super.dispose();
  }

  double? parse(TextEditingController c) {
    final v = parseNumber(c.text);
    return v == null || !v.isFinite ? null : v;
  }

  void submit() {
    final w = parse(width);
    final d = parse(depth);
    if (w == null || d == null || w < 3 || w > 100 || d < 3 || d > 100) {
      setState(() => validation = tr3(
          '宽和长都要在 3 到 100 米之间',
          'Ені мен ұзындығы 3–100 м аралығында болуы керек',
          'Ширина и длина должны быть от 3 до 100 м',
          'Width and length must be 3 to 100 m',
          ky: 'Туурасы жана узундугу 3 мөн 100 м ортосунда болушу керек',
          uz: 'Eni va uzunligi 3 dan 100 m gacha boʻlishi kerak'));
      return;
    }
    HapticFeedback.lightImpact();
    final outline = preview.currentContext;
    if (outline != null) ZoomOrigin.mark(outline);
    Navigator.pop<Object>(context, (
      name: name.text,
      width: (w * 1000).round(),
      depth: (d * 1000).round(),
      roof: roof,
      sketch: false
    ));
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final w = parse(width);
    final d = parse(depth);
    Widget size(TextEditingController c, String label) => TextField(
        controller: c,
        onChanged: (_) => setState(() => validation = null),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label, suffixText: unitM));
    final back = widget.onBack;
    return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          SizedBox(
              height: 44,
              child: Stack(alignment: Alignment.center, children: [
                Text(
                    tr3('新建设计', 'Жаңа жоба', 'Новый проект', 'New design',
                        ky: 'Жаңы долбоор', uz: 'Yangi loyiha'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                if (back != null)
                  Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                          key: const Key('start-back'),
                          style: TextButton.styleFrom(
                              padding: const EdgeInsets.only(right: 8),
                              visualDensity: VisualDensity.compact),
                          onPressed: back,
                          icon: const Icon(Icons.arrow_back_ios_new_rounded,
                              size: 16),
                          label: Text(tr3('返回', 'Артқа', 'Назад', 'Back',
                              ky: 'Артка', uz: 'Orqaga')))),
                Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                        style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact),
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr3('取消', 'Болдырмау', 'Отмена', 'Cancel',
                            ky: 'Жокко чыгаруу', uz: 'Bekor qilish')))),
              ])),
          const SizedBox(height: 4),
          TextField(
              controller: name,
              decoration: InputDecoration(
                  labelText: tr3('设计名称', 'Жоба атауы', 'Название проекта',
                      'Design name',
                      ky: 'Долбоордун аталышы', uz: 'Loyiha nomi'))),
          const SizedBox(height: 12),
          // Live outline: the numbers become a shape.
          Container(
              key: preview,
              height: 150,
              decoration: BoxDecoration(
                  color: t.room, borderRadius: BorderRadius.circular(16)),
              child: CustomPaint(
                  painter:
                      _SizePreviewPainter(w, d, t.accent, t.ink, t.muted))),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (pw, pd) in _sizePresets)
              ChoiceChip(
                  label: Text('$pw×$pd'),
                  visualDensity: VisualDensity.compact,
                  selected: w == pw && d == pd,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      width.text = '$pw';
                      depth.text = '$pd';
                      validation = null;
                    });
                  }),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: size(
                    width,
                    tr3('面宽（左右）', 'Ені (солдан оңға)',
                        'Ширина (слева направо)', 'Width (left to right)',
                        ky: 'Туурасы (солдон оңго)',
                        uz: 'Eni (chapdan oʻngga)'))),
            const SizedBox(width: 10),
            Expanded(
                child: size(
                    depth,
                    tr3('进深（上下）', 'Ұзындығы (жоғары-төмен)',
                        'Длина (сверху вниз)', 'Length (top to bottom)',
                        ky: 'Узундугу (үстүдөн ылдый)',
                        uz: 'Uzunligi (tepadan pastga)'))),
          ]),
          const SizedBox(height: 12),
          // The roof is chosen up front and can be changed any time later.
          Text(tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'),
              style: TextStyle(fontSize: 12.5, color: t.muted)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final style in roofStyles)
              ChoiceChip(
                  key: ValueKey('new-roof-$style'),
                  avatar: RoofIcon(style,
                      size: 14, color: roof == style ? t.accent : t.ink),
                  showCheckmark: false,
                  selectedColor: t.accent.withValues(alpha: 0.14),
                  side: BorderSide(color: roof == style ? t.accent : t.line),
                  label:
                      Text(roofStyleName(style), style: TextStyle(color: t.ink)),
                  visualDensity: VisualDensity.compact,
                  selected: roof == style,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => roof = style);
                  }),
          ]),
          if (validation != null)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(validation!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          const SizedBox(height: 14),
          FilledButton(
              onPressed: submit,
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              child: Text(tr3('开始设计', 'Бастау', 'Начать', 'Start',
                  ky: 'Баштоо', uz: 'Boshlash'))),
          if (back == null)
            // Opened straight at the sizes: drawing the outline is the
            // other way in.
            Center(
                child: TextButton.icon(
                    onPressed: () => Navigator.pop<Object>(context, (
                          name: name.text,
                          width: 0,
                          depth: 0,
                          roof: roof,
                          sketch: true
                        )),
                    icon: const Icon(Icons.gesture),
                    label: Text(tr3('在画布上拖出外形', 'Пішінді сызып беру',
                        'Нарисовать контур', 'Draw the outline',
                        ky: 'Контурду чийүү', uz: 'Konturni chizish')))),
        ]);
  }
}
