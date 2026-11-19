import '../core/document/house_document.dart';
import 'action.dart';

/// Implemented by the "My houses" list so voice can start and open
/// designs from any page.
abstract interface class HouseLibrary {
  /// The list that is alive now; set by the houses page.
  static HouseLibrary? instance;

  /// The saved designs, newest first.
  List<({String id, String name})> get designs;

  /// Opens a saved design in the editor, closing the one open now.
  Future<void> openDesign(String id);

  /// Saves [doc] as a new design and opens it.
  Future<void> addDesign(HouseDocument doc);

  /// A new design from a template ("kz", "three", "five", "two"), or an
  /// empty one of the given size.
  HouseDocument newDesign(String template,
      {String? name, int? width, int? depth});
}

const templateKeys = ['blank', 'kz', 'three', 'five', 'two'];

/// Failure code when no design or more than one has the name asked for.
const noSuchDesign = 'no_such_design';
const severalDesigns = 'several_designs';

bool _haveList(ActionContext ctx) => HouseLibrary.instance != null;

/// The designs whose name matches [ref]: the exact name if one has it,
/// otherwise every name that contains it, ignoring case and spaces.
List<({String id, String name})> matchDesigns(
    List<({String id, String name})> designs, String ref) {
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  final want = norm(ref);
  final exact = designs.where((d) => norm(d.name) == want).toList();
  if (exact.isNotEmpty) return exact;
  return [
    for (final d in designs)
      if (want.isNotEmpty &&
          (norm(d.name).contains(want) || want.contains(norm(d.name))))
        d
  ];
}

final houseActions = [
  AppAction(
    id: 'houses.create',
    title: const L3('新建房屋设计', 'Жаңа үй жобасы', 'Новый проект дома'),
    examples: const L3('新建一个十二乘十米的房子', 'Он екіге он метр жаңа үй аш',
        'Создай новый дом двенадцать на десять метров'),
    params: const {
      'template': Param.choice(templateKeys, optional: true),
      'name': Param.text(optional: true),
      'width_mm': Param.integer(optional: true),
      'depth_mm': Param.integer(optional: true),
    },
    when: _haveList,
    risk: Risk.undoable,
    run: (ctx, args) async {
      final library = HouseLibrary.instance!;
      final width = args.has('width_mm') ? args.integer('width_mm') : null,
          depth = args.has('depth_mm') ? args.integer('depth_mm') : null;
      for (final v in [width, depth]) {
        if (v != null && (v < 4000 || v > 30000)) {
          return const ActionResult.fail(ActionCodes.badArgs,
              say: {'message': 'width and depth must be 4000-30000 mm'});
        }
      }
      await library.addDesign(library.newDesign(
          args.has('template') ? args.choice('template') : 'blank',
          name: args.has('name') ? args.text('name') : null,
          width: width,
          depth: depth));
      return const ActionResult.ok();
    },
  ),
  AppAction(
    id: 'houses.open',
    title: const L3('按名称打开设计', 'Жобаны атымен ашу', 'Открыть проект по имени'),
    examples: const L3(
        '打开我的房子', '«Менің үйім» жобасын аш', 'Открой проект «Мой дом»'),
    params: const {'name': Param.text()},
    when: _haveList,
    risk: Risk.read,
    run: (ctx, args) async {
      final library = HouseLibrary.instance!;
      final found = matchDesigns(library.designs, args.text('name'));
      final names = [for (final d in library.designs.take(20)) d.name];
      if (found.isEmpty) {
        return ActionResult.fail(noSuchDesign, say: {'designs': names});
      }
      if (found.length > 1) {
        return ActionResult.fail(severalDesigns, say: {
          'designs': [for (final d in found) d.name]
        });
      }
      await library.openDesign(found.single.id);
      return ActionResult.ok(changed: [found.single.id]);
    },
  ),
];
