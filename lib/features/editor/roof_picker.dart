part of '../house_editor.dart';

/// Roof styles a design can have: flat, gable (two slopes) or hip (four).
const roofStyles = ['flat', 'gable', 'hip'];

/// The SetRoof value for [style] on a [width] × [depth] house (mm), keeping
/// the current pitch and overhang when there are any.
Map<String, dynamic> roofValue(String style, int width, int depth,
        {int? pitch, int? overhang}) =>
    switch (style) {
      'flat' => {'type': 'flat', 'parapetHeight': 1000},
      'hip' => {
          'type': 'hip',
          'pitchDeg': pitch ?? 25,
          'overhang': overhang ?? 500
        },
      _ => {
          'type': 'gable',
          // Ridge along the long side, as most houses are built.
          'ridgeDir': width >= depth ? 'H' : 'V',
          'pitchDeg': pitch ?? 30,
          'overhang': overhang ?? 500
        },
    };

/// [doc] with a [style] roof, for a design being created.
HouseDocument withRoof(HouseDocument doc, String style) {
  final r = executeCommand(
      extractDesignState(doc),
      DesignCommand('SetRoof', {
        'roof': roofValue(style, doc.footprint.width, doc.footprint.depth)
      }),
      CommandContext(newId: () => const Uuid().v4(), now: () => 'unused'));
  return r is Applied ? composeDocument(doc.meta, r.newState) : doc;
}

String roofStyleName(String style) => switch (style) {
      'flat' => tr3('平屋顶', 'Тегіс шатыр', 'Плоская крыша'),
      'hip' => tr3('四坡屋顶', 'Төрт беткейлі', 'Вальмовая'),
      _ => tr3('双坡屋顶', 'Қос беткейлі', 'Двускатная'),
    };

/// A small side view of each roof style, so the choice is seen, not read.
class RoofIcon extends StatelessWidget {
  const RoofIcon(this.style, {super.key, this.color, this.size = 40});
  final String style;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size(size * 1.3, size),
      painter: _RoofIconPainter(
          style,
          // Inside a chip the icon theme follows the label, selected or not.
          color ??
              IconTheme.of(context).color ??
              Theme.of(context).colorScheme.onSurface));
}

class _RoofIconPainter extends CustomPainter {
  _RoofIconPainter(this.style, this.color);
  final String style;
  final Color color;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    final w = s.width, h = s.height;
    final wallTop = h * 0.5, left = w * 0.18, right = w * 0.82;
    canvas.drawRect(Rect.fromLTRB(left, wallTop, right, h * 0.95), p);
    final roof = Path();
    switch (style) {
      case 'flat':
        roof
          ..moveTo(left - 2, wallTop)
          ..lineTo(left - 2, wallTop - h * 0.1)
          ..lineTo(right + 2, wallTop - h * 0.1)
          ..lineTo(right + 2, wallTop);
      case 'hip':
        roof
          ..moveTo(left - w * 0.08, wallTop)
          ..lineTo(w * 0.36, h * 0.12)
          ..lineTo(w * 0.64, h * 0.12)
          ..lineTo(right + w * 0.08, wallTop);
      default:
        roof
          ..moveTo(left - w * 0.08, wallTop)
          ..lineTo(w / 2, h * 0.06)
          ..lineTo(right + w * 0.08, wallTop);
    }
    canvas.drawPath(roof, p);
  }

  @override
  bool shouldRepaint(_RoofIconPainter old) =>
      old.style != style || old.color != color;
}

extension _RoofPicker on _HouseEditorState {
  /// Current style and a sheet to change it, from the plan, 3D and details.
  String get roofStyle => history.present.roof.type.name;

  Future<void> chooseRoof() async {
    final doc = history.present;
    final picked = await showMotionSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final t = Tokens.of(context);
          return SafeArea(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr3('屋顶样式', 'Шатыр түрі', 'Тип крыши'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        Row(children: [
                          for (final style in roofStyles)
                            Expanded(
                                child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 4),
                                    child: InkWell(
                                        key: ValueKey('roof-$style'),
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () =>
                                            Navigator.pop(context, style),
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                            decoration: BoxDecoration(
                                                color: style == roofStyle
                                                    ? Tokens.mix(
                                                        t.accent, 0.12, t.panel)
                                                    : t.panel,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                    color: style == roofStyle
                                                        ? t.accent
                                                        : t.line,
                                                    width: style == roofStyle
                                                        ? 1.5
                                                        : 1)),
                                            child: Column(children: [
                                              RoofIcon(style,
                                                  color: style == roofStyle
                                                      ? t.accent
                                                      : t.ink),
                                              const SizedBox(height: 6),
                                              Text(roofStyleName(style),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600)),
                                            ]))))),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                            tr3('坡度、挑檐和女儿墙高度在“构造细节”里调。',
                                'Еңіс, карниз және парапет «Құрылым» бетінде.', 'Уклон, свес и высота парапета настраиваются в разделе «Детали конструкции».'),
                            style: TextStyle(fontSize: 12, color: t.muted)),
                      ])));
        });
    if (picked == null || picked == roofStyle) return;
    action('SetRoof', {
      'roof': roofValue(picked, doc.footprint.width, doc.footprint.depth,
          pitch: doc.roof.pitchDeg, overhang: doc.roof.overhang)
    });
    // Show the roof that was just picked.
    if (!sceneSettings.roof)
      update(() => sceneSettings = sceneSettings.copyWith(roof: true));
  }
}
