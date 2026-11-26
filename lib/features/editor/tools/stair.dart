part of '../page.dart';

/// Placing and moving stairs.
extension _StairTool on _HouseEditorState {
  /// A stair to slide into place, like a room of a set size. On the top
  /// floor it first offers the floor the stair would lead to.
  void startStairStamp({Stair? moving, ({int w, int d})? size}) {
    if (floorIndex == history.present.floors.length - 1) {
      final floorId = floor.id;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(
                key: const Key('stair-needs-floor'),
                content: Text(tr3(
                    '楼梯要通到上面一层，现在还没有。',
                    'Баспалдақ жоғарғы қабатқа апарады, ол әлі жоқ.',
                    'Лестница ведёт на этаж выше, а его пока нет.',
                    "The stairs lead to the floor above, which doesn't exist yet.",
                    ky: 'Тепкич үстүнкү кабатка алып барат, ал азырынча жок.',
                    uz: 'Zinapoya yuqori qavatga olib boradi, u hali yoʻq.')),
                behavior: SnackBarBehavior.floating,
                margin: EdgeInsets.fromLTRB(16, 0, 16, snackLift),
                duration: const Duration(seconds: 8),
                persist: false,
                action: SnackBarAction(
                    label: tr3('加一层并放楼梯', 'Қабат қосып, баспалдақ қою',
                        'Добавить этаж и лестницу', 'Add a floor and stairs',
                        ky: 'Кабат жана тепкич кошуу',
                        uz: 'Qavat va zinapoya qoʻshish'),
                    onPressed: () {
                      final before = history.present;
                      action('AddFloor', {'floorId': floorId});
                      if (history.present == before || !mounted) return;
                      update(derive);
                      startStairStamp();
                    })),
            snackBarAnimationStyle: Motion.toastStyle);
      return;
    }
    final fp = history.present.footprint;
    final at =
        moving == null ? null : resolveRect(base.axes, moving.region).rect;
    // A two-flight stair first: it is what most self-built houses have.
    final sizes = size != null
        ? [size]
        : at != null
            ? [(w: at.right - at.left, d: at.top - at.bottom)]
            : const [
                (w: 2400, d: 3600),
                (w: 3600, d: 2400),
                (w: 1200, d: 4800),
                (w: 4800, d: 1200)
              ];
    update(() {
      clearSelection();
      clearWallSelection();
      view3d = false;
      tool = EditorTool.box;
      stampStair = true;
      movingStairId = moving?.id;
      search:
      for (final s in sizes) {
        roomStamp = s;
        if (at != null) {
          setStamp(at.left.toDouble(), at.bottom.toDouble(), reach: 0);
          break;
        }
        for (final c in ['bl', 'br', 'tl', 'tr']) {
          setStamp(c.endsWith('l') ? 0 : (fp.width - s.w).toDouble(),
              c.startsWith('b') ? 0 : (fp.depth - s.d).toDouble());
          if (spatialError == null) break search;
        }
      }
      if (spatialError != null && at == null) {
        roomStamp = sizes.first;
        setStamp(0, 0);
      }
    });
    if (spatialPreview != null) reveal(spatialPreview!);
  }
}
