import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/analysis/build_schedule.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/shared/brand/yicon.dart';

/// Chinese / Kazakh names for the planning pages: utility points, plot
/// items, estimate lines and units, fuels and building stages.

String utilityName(UtilityKind kind) => switch (kind) {
      UtilityKind.panel => tr3(
          '配电箱', 'Электр қалқаны', 'Электрощит', 'Electrical panel',
          ky: 'Электр щити', uz: 'Elektr shchiti'),
      UtilityKind.socket =>
        tr3('插座', 'Розетка', 'Розетка', 'Socket', ky: 'Розетка', uz: 'Rozetka'),
      UtilityKind.lightSwitch => tr3('开关', 'Ажыратқыш', 'Выключатель', 'Switch',
          ky: 'Өчүргүч', uz: 'Oʻchirgich'),
      UtilityKind.light =>
        tr3('灯', 'Шам', 'Светильник', 'Light', ky: 'Шам', uz: 'Chiroq'),
      UtilityKind.vent => tr3(
          '排气扇', 'Сорғыш желдеткіш', 'Вытяжной вентилятор', 'Extractor fan',
          ky: 'Соргуч желдеткич', uz: 'Soʻruvchi ventilyator'),
      UtilityKind.water => tr3(
          '给水点', 'Су нүктесі', 'Точка водоснабжения', 'Water point',
          ky: 'Суу чекити', uz: 'Suv nuqtasi'),
      UtilityKind.drain => tr3(
          '排水点', 'Кәріз нүктесі', 'Точка канализации', 'Drain point',
          ky: 'Агызуу чекити', uz: 'Oqova nuqtasi'),
      UtilityKind.radiator => tr3('暖气片', 'Радиатор', 'Радиатор', 'Radiator',
          ky: 'Радиатор', uz: 'Radiator'),
    };

IconData utilityIcon(UtilityKind kind) => switch (kind) {
      UtilityKind.panel => YIcons.bolt,
      UtilityKind.socket => YIcons.socket,
      UtilityKind.lightSwitch => YIcons.toggle,
      UtilityKind.light => YIcons.idea,
      UtilityKind.vent => YIcons.wind,
      UtilityKind.water => YIcons.water,
      UtilityKind.drain => YIcons.drain,
      UtilityKind.radiator => YIcons.radiator,
    };

/// Electrical, water and heating groups for the palette and the legend.
const utilityGroups = [
  [
    UtilityKind.panel,
    UtilityKind.light,
    UtilityKind.lightSwitch,
    UtilityKind.socket,
    UtilityKind.vent
  ],
  [UtilityKind.water, UtilityKind.drain],
  [UtilityKind.radiator],
];

String utilityGroupName(int group) => switch (group) {
      0 => tr3('电', 'Электр', 'Электрика', 'Electrical',
          ky: 'Электр', uz: 'Elektr'),
      1 => tr3('水', 'Су', 'Вода', 'Water', ky: 'Суу', uz: 'Suv'),
      _ =>
        tr3('暖', 'Жылу', 'Отопление', 'Heating', ky: 'Жылытуу', uz: 'Isitish'),
    };

String siteName(SiteKind kind) => switch (kind) {
      SiteKind.barn => tr3(
          '牲畜棚', 'Мал қорасы', 'Сарай для скота', 'Livestock barn',
          ky: 'Мал сарай', uz: 'Molxona'),
      SiteKind.bathhouse => tr3('澡堂', 'Монша', 'Баня', 'Bathhouse',
          ky: 'Мончо', uz: 'Hammom (banya)'),
      SiteKind.garage =>
        tr3('车库', 'Гараж', 'Гараж', 'Garage', ky: 'Гараж', uz: 'Garaj'),
      SiteKind.toilet => tr3(
          '室外厕所', 'Аула дәретханасы', 'Уличный туалет', 'Outdoor toilet',
          ky: 'Короодогу даараткана', uz: 'Hovlidagi hojatxona'),
      SiteKind.shed => tr3('储物棚', 'Қойма', 'Хозблок', 'Utility shed',
          ky: 'Чарба сарай', uz: 'Xoʻjalik ombori'),
      SiteKind.greenhouse => tr3('温室', 'Жылыжай', 'Теплица', 'Greenhouse',
          ky: 'Күнөскана', uz: 'Issiqxona'),
      SiteKind.well =>
        tr3('水井', 'Құдық', 'Колодец', 'Well', ky: 'Кудук', uz: 'Quduq'),
      SiteKind.septic => tr3('化粪池', 'Септик', 'Септик', 'Septic tank',
          ky: 'Септик', uz: 'Septik'),
      SiteKind.garden => tr3('菜园', 'Бақша', 'Огород', 'Vegetable garden',
          ky: 'Огород', uz: 'Tomorqa'),
      SiteKind.yard => tr3(
          '硬化院子', 'Төселген аула', 'Мощёный двор', 'Paved yard',
          ky: 'Төшөлгөн короо', uz: 'Qoplangan hovli'),
      SiteKind.gate =>
        tr3('大门', 'Қақпа', 'Ворота', 'Gate', ky: 'Дарбаза', uz: 'Darvoza'),
      SiteKind.custom =>
        tr3('其他', 'Басқа', 'Другое', 'Other', ky: 'Башка', uz: 'Boshqa'),
    };

IconData siteIcon(SiteKind kind) => switch (kind) {
      SiteKind.barn => YIcons.barn,
      SiteKind.bathhouse => YIcons.sauna,
      SiteKind.garage => YIcons.garage,
      SiteKind.toilet => YIcons.toilet,
      SiteKind.shed => YIcons.shed,
      SiteKind.greenhouse => YIcons.tree,
      SiteKind.well => YIcons.water,
      SiteKind.septic => YIcons.tank,
      SiteKind.garden => YIcons.grass,
      SiteKind.yard => YIcons.grid,
      SiteKind.gate => YIcons.fence,
      SiteKind.custom => YIcons.grid,
    };

String costStageName(String stage) => switch (stage) {
      'found' => tr3('基础', 'Іргетас', 'Фундамент', 'Foundation',
          ky: 'Пайдубал', uz: 'Poydevor'),
      'walls' => tr3('墙体与楼板', 'Қабырға және плиталар', 'Стены и перекрытия',
          'Walls and floors',
          ky: 'Дубалдар жана жабуулар', uz: 'Devorlar va yopmalar'),
      'roof' => tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'),
      'openings' => tr3(
          '门窗', 'Есік-терезе', 'Окна и двери', 'Windows and doors',
          ky: 'Терезелер жана эшиктер', uz: 'Derazalar va eshiklar'),
      'mep' => tr3('水电暖', 'Су, электр, жылу', 'Вода, электрика, отопление',
          'Water, electrical, heating',
          ky: 'Суу, электр, жылытуу', uz: 'Suv, elektr, isitish'),
      'finish' => tr3(
          '地面与装修', 'Еден және әрлеу', 'Полы и отделка', 'Floors and finishes',
          ky: 'Полдор жана жасалгалоо', uz: 'Pollar va pardozlash'),
      'site' => tr3('院子与附属', 'Аула және қосалқы құрылыс', 'Двор и хозпостройки',
          'Yard and outbuildings',
          ky: 'Короо жана чарба курулуштары', uz: 'Hovli va xoʻjalik binolari'),
      'general' => tr3('运输与杂项', 'Тасымал және басқа', 'Доставка и прочее',
          'Delivery and sundries',
          ky: 'Жеткирүү жана башкалар', uz: 'Yetkazib berish va boshqalar'),
      _ => tr3('其他', 'Басқа', 'Другое', 'Other', ky: 'Башка', uz: 'Boshqa'),
    };

String costLineName(String key) => switch (key) {
      'ringBeam' => tr3('圈梁 (含钢筋)', 'Арматураланған белдеу',
          'Армопояс (с арматурой)', 'Reinforced belt (with rebar)',
          ky: 'Арматураланган кур', uz: 'Armaturali belbogʻ'),
      'lintel' => tr3('门窗过梁', 'Ойық үстіндегі аражабын',
          'Перемычки над проёмами', 'Lintels over openings',
          ky: 'Тешик үстүндөгү устун', uz: 'Teshik ustidagi toʻsin'),
      'gutter' => tr3(
          '檐沟与落水管', 'Науа мен су ағызғы', 'Водосток', 'Gutters and downpipes',
          ky: 'Суу агызгыч', uz: 'Suv oqizgich'),
      'scaffold' => tr3('脚手架租赁', 'Құрылыс мінбесін жалдау', 'Аренда лесов',
          'Scaffolding hire',
          ky: 'Курулуш тепкичин ижарага алуу', uz: 'Havoza ijarasi'),
      'delivery' => tr3('材料运输 (车次)', 'Материал тасымалы (рейс)',
          'Доставка материалов (рейсы)', 'Material delivery (trips)',
          ky: 'Материал жеткирүү (рейс)', uz: 'Material yetkazish (reys)'),
      'connection' => tr3(
          '水电气接入与手续',
          'Су, электр, газға қосылу және құжаттар',
          'Подключение к сетям и оформление',
          'Utility connections and paperwork',
          ky: 'Тармактарга кошулуу жана документтер',
          uz: 'Tarmoqlarga ulanish va hujjatlar'),
      'excavation' => tr3('挖土', 'Топырақ қазу', 'Выемка грунта', 'Excavation',
          ky: 'Казуу иштери', uz: 'Qazish ishlari'),
      'cushion' => tr3('砂砾石垫层', 'Құм-қиыршық төсеме',
          'Песчано-гравийная подушка', 'Sand and gravel bed',
          ky: 'Кум-шагыл төшөмө', uz: 'Qum-shagʻal toʻshama'),
      'concrete' => tr3(
          '基础混凝土 (含损耗 3%)',
          'Іргетас бетоны (+3%)',
          'Бетон фундамента (с запасом 3% на потери)',
          'Foundation concrete (3% waste allowance)',
          ky: 'Пайдубал бетону (3% ысырап)',
          uz: 'Poydevor betoni (3% isrof)'),
      'rebar' => tr3('基础钢筋', 'Іргетас арматурасы', 'Арматура фундамента',
          'Foundation rebar',
          ky: 'Пайдубал арматурасы', uz: 'Poydevor armaturasi'),
      'formwork' =>
        tr3('模板', 'Қалып', 'Опалубка', 'Formwork', ky: 'Калып', uz: 'Qolip'),
      'xps' => tr3('基础外侧 XPS', 'Іргетас сыртындағы XPS',
          'XPS снаружи фундамента', 'XPS outside the foundation',
          ky: 'Пайдубалдын сыртындагы XPS', uz: 'Poydevor tashqarisidagi XPS'),
      'dampproof' => tr3('水平防水', 'Көлденең гидрооқшау',
          'Горизонтальная гидроизоляция', 'Damp-proof course',
          ky: 'Гидроизоляция', uz: 'Gidroizolyatsiya'),
      'blind' => tr3(
          '保温散水', 'Жылы отмостка', 'Утеплённая отмостка', 'Insulated apron',
          ky: 'Жылуу отмостка', uz: 'Isitilgan otmostka'),
      'masonryExt' => tr3('外墙砌体', 'Сыртқы қабырға қалауы',
          'Кладка наружных стен', 'Outer wall masonry',
          ky: 'Сырткы дубалды тургузуу', uz: 'Tashqi devorni terish'),
      'masonryInt' => tr3('内墙砌体', 'Ішкі қабырға қалауы', 'Кладка перегородок',
          'Partition masonry',
          ky: 'Тосмо дубалды тургузуу', uz: 'Toʻsiq devorni terish'),
      'wallIns' => tr3('外墙保温', 'Қабырға жылытқышы', 'Утеплитель наружных стен',
          'Outer wall insulation',
          ky: 'Сырткы дубалды жылуулоо',
          uz: 'Tashqi devorni issiqlik izolyatsiyalash'),
      'facade' => tr3(
          '外墙饰面', 'Қасбет әрлеуі', 'Отделка фасада', 'Facade finish',
          ky: 'Фасадды жасалгалоо', uz: 'Fasad pardozi'),
      'floorSlab' => tr3('楼板', 'Қабатаралық плита', 'Межэтажное перекрытие',
          'Intermediate floor slab',
          ky: 'Кабат аралык жабуу', uz: 'Qavatlararo yopma'),
      'roofSlab' => tr3('屋面板 (含钢筋)', 'Жабын плитасы (арматурамен)',
          'Плита покрытия (с арматурой)', 'Roof slab (with rebar)',
          ky: 'Чатыр жабуусу (арматура менен)',
          uz: 'Tom yopmasi (armatura bilan)'),
      'roofMembrane' => tr3('屋面防水', 'Шатыр гидрооқшауы', 'Гидроизоляция кровли',
          'Roof waterproofing',
          ky: 'Чатырдын гидроизоляциясы', uz: 'Tom gidroizolyatsiyasi'),
      'roofIns' => tr3(
          '屋面保温', 'Шатыр жылытқышы', 'Утеплитель кровли', 'Roof insulation',
          ky: 'Чатырды жылуулоо', uz: 'Tomni issiqlik izolyatsiyalash'),
      'parapetWp' => tr3('女儿墙上翻防水', 'Парапет гидрооқшауы',
          'Гидроизоляция парапета', 'Parapet waterproofing',
          ky: 'Парапеттин гидроизоляциясы', uz: 'Parapet gidroizolyatsiyasi'),
      'roofCover' => tr3(
          '屋面瓦', 'Шатыр жабыны', 'Кровельное покрытие', 'Roof covering',
          ky: 'Чатыр жабуучу материал', uz: 'Tom qoplamasi'),
      'roofFrame' => tr3('屋架与挂瓦条', 'Шатыр қаңқасы және тақтайлар',
          'Стропила и обрешётка', 'Rafters and battens',
          ky: 'Стропила жана рейкалар', uz: 'Stropila va reykalar'),
      'atticIns' => tr3(
          '顶棚保温', 'Төбе жылытқышы', 'Утеплитель потолка', 'Ceiling insulation',
          ky: 'Шыпты жылуулоо', uz: 'Shiftni issiqlik izolyatsiyalash'),
      'windows' => tr3('窗 (三玻 PVC)', 'Терезе (үш әйнекті ПВХ)',
          'Окно (ПВХ, тройное остекление)', 'Window (PVC, triple glazing)',
          ky: 'Терезе (ПВХ, үч катмар айнек)',
          uz: 'Deraza (PVX, uch qavatli oyna)'),
      'doorEntry' => tr3('入户门', 'Кіреберіс есік', 'Входная дверь', 'Front door',
          ky: 'Кире бериш эшик', uz: 'Kirish eshigi'),
      'doorsInt' => tr3(
          '室内门', 'Ішкі есік', 'Межкомнатная дверь', 'Interior door',
          ky: 'Ички эшик', uz: 'Ichki eshik'),
      'elecPoint' => tr3(
          '电气点位', 'Электр нүктелері', 'Электроточки', 'Electrical points',
          ky: 'Электр чекиттери', uz: 'Elektr nuqtalari'),
      'cable' => tr3('电线', 'Электр сымы', 'Электропровод', 'Electrical wire',
          ky: 'Электр зым', uz: 'Elektr simi'),
      'pipe' => tr3('水管与暖气管', 'Су және жылу құбыры',
          'Трубы водоснабжения и отопления', 'Water and heating pipes',
          ky: 'Суу жана жылытуу түтүктөрү', uz: 'Suv va isitish quvurlari'),
      'radiator' => tr3('暖气片', 'Радиатор', 'Радиатор', 'Radiator',
          ky: 'Радиатор', uz: 'Radiator'),
      'boiler' => tr3(
          '锅炉', 'Қазандық', 'Рекомендуемый котёл', 'Recommended boiler',
          ky: 'Сунушталган казан', uz: 'Tavsiya etilgan qozon'),
      'sanitary' => tr3('洁具', 'Санжабдық', 'Сантехника', 'Plumbing fixtures',
          ky: 'Сантехника', uz: 'Santexnika'),
      'groundFloor' => tr3('首层地坪', 'Бірінші қабат едені', 'Пол первого этажа',
          'Ground floor build-up',
          ky: 'Биринчи кабаттын полунун катмарлары',
          uz: 'Birinchi qavat poli qatlamlari'),
      'finishTileArea' => tr3('室内装修（瓷砖地面）', 'Ішкі әрлеу (плитка)',
          'Отделка с плиткой', 'Interior finishes with tile',
          ky: 'Плиткалуу ички жасалгалоо', uz: 'Plitkali ichki pardozlash'),
      'finishArea' => tr3(
          '室内装修', 'Ішкі әрлеу', 'Внутренняя отделка', 'Interior finishes',
          ky: 'Ички жасалгалоо', uz: 'Ichki pardozlash'),
      'fence' =>
        tr3('院墙', 'Қоршау', 'Забор', 'Fence', ky: 'Тосмо', uz: 'Panjara'),
      'gate' =>
        tr3('大门', 'Қақпа', 'Ворота', 'Gate', ky: 'Дарбаза', uz: 'Darvoza'),
      'outbuilding' => tr3(
          '附属建筑', 'Қосалқы құрылыстар', 'Хозпостройки', 'Outbuildings',
          ky: 'Чарба курулуштары', uz: 'Xoʻjalik binolari'),
      'paving' => tr3('院子硬化', 'Аула төсемі', 'Мощение двора', 'Yard paving',
          ky: 'Короону төшөө', uz: 'Hovlini qoplash'),
      'well' => tr3('水井', 'Құдық', 'Колодец', 'Well', ky: 'Кудук', uz: 'Quduq'),
      'septic' => tr3('化粪池', 'Септик', 'Септик', 'Septic tank',
          ky: 'Септик', uz: 'Septik'),
      _ => key,
    };

String unitName(String unit) => switch (unit) {
      'm' => unitM,
      'm2' => unitM2,
      'm3' => unitM3,
      't' => tr3('吨', 'т', 'т', 't', ky: 'т', uz: 't'),
      'kg' => tr3('公斤', 'кг', 'кг', 'kg', ky: 'кг', uz: 'kg'),
      'l' => tr3('升', 'л', 'л', 'l', ky: 'л', uz: 'l'),
      'pcs' => unitPcs,
      _ => unit,
    };

String currencySymbol(Currency c) => c == Currency.cny ? '¥' : '₸';

String currencyName(Currency c) => c == Currency.cny
    ? tr3('人民币 ¥', 'Юань ¥', 'Юань ¥', 'Yuan ¥', ky: 'Юань ¥', uz: 'Yuan ¥')
    : tr3('坚戈 ₸', 'Теңге ₸', 'Тенге ₸', 'Tenge ₸',
        ky: 'Теңге ₸', uz: 'Tenge ₸');

/// The currency used when the design has not chosen one.
Currency get languageCurrency => isWestern ? Currency.kzt : Currency.cny;

String fuelName(FuelKind f) => switch (f) {
      FuelKind.coal =>
        tr3('煤', 'Көмір', 'Уголь', 'Coal', ky: 'Көмүр', uz: 'Koʻmir'),
      FuelKind.gas => tr3('天然气', 'Газ', 'Газ', 'Gas', ky: 'Газ', uz: 'Gaz'),
      FuelKind.electricity => tr3('电', 'Электр', 'Электрика', 'Electrical',
          ky: 'Электр', uz: 'Elektr'),
      FuelKind.wood =>
        tr3('木柴', 'Отын', 'Дрова', 'Firewood', ky: 'Отун', uz: 'Oʻtin'),
    };

String fuelUnit(FuelKind f) => switch (f) {
      FuelKind.coal ||
      FuelKind.wood =>
        tr3('吨', 'т', 'т', 't', ky: 'т', uz: 't'),
      FuelKind.gas => unitM3,
      FuelKind.electricity =>
        tr3('度', 'кВт·сағ', 'кВт·ч', 'kWh', ky: 'кВт·с', uz: 'kVt·soat'),
    };

String stageName(BuildStage s) {
  if (s.custom) return s.name;
  final n = stageNames[s.key]!;
  return s.name.isNotEmpty ? s.name : tr(n.$1, n.$2);
}

String statusName(StageStatus s) => switch (s) {
      StageStatus.todo => tr3('未开始', 'Басталмаған', 'Не начато', 'Not started',
          ky: 'Башталган жок', uz: 'Boshlanmagan'),
      StageStatus.doing => tr3('进行中', 'Жүріп жатыр', 'В работе', 'In progress',
          ky: 'Аткарылууда', uz: 'Jarayonda'),
      StageStatus.done => tr3('已完成', 'Аяқталды', 'Завершено', 'Finished',
          ky: 'Бүттү', uz: 'Tugallandi'),
    };

/// A line of the shopping list; lines copied from the estimate keep the
/// estimate's name.
String buyName(String key) => switch (key) {
      'concrete' =>
        tr3('混凝土', 'Бетон', 'Бетон', 'Concrete', ky: 'Бетон', uz: 'Beton'),
      'rebar' => tr3('钢筋', 'Арматура', 'Арматура', 'Rebar',
          ky: 'Арматура', uz: 'Armatura'),
      'tieWire' => tr3(
          '绑扎丝', 'Байлау сымы', 'Вязальная проволока', 'Tying wire',
          ky: 'Байлоочу зым', uz: 'Bogʻlash simi'),
      'gravel' => tr3('砂砾石', 'Құм-қиыршық қоспасы', 'Песчано-гравийная смесь',
          'Sand and gravel mix',
          ky: 'Кум-шагыл аралашмасы', uz: 'Qum-shagʻal aralashmasi'),
      'formBoard' => tr3('模板', 'Қалып тақтайы', 'Опалубка', 'Formwork',
          ky: 'Калып', uz: 'Qolip'),
      'xps' => tr3('XPS 挤塑板', 'XPS плитасы', 'Плиты XPS', 'XPS boards',
          ky: 'XPS плиталары', uz: 'XPS plitalari'),
      'bitumenRoll' => tr3('防水卷材', 'Орама гидрооқшау', 'Рулонная гидроизоляция',
          'Waterproofing roll',
          ky: 'Түрмөк гидроизоляция', uz: 'Oʻrama gidroizolyatsiya'),
      'blockAerated' => tr3(
          '加气混凝土砌块', 'Газоблок', 'Газоблок', 'Aerated concrete block',
          ky: 'Газоблок', uz: 'Gazoblok'),
      'brick' =>
        tr3('砖', 'Кірпіш', 'Кирпич', 'Brick', ky: 'Кирпич', uz: 'Gʻisht'),
      'blockCinder' => tr3('炉渣砌块', 'Шлакоблок', 'Шлакоблок', 'Cinder block',
          ky: 'Шлакоблок', uz: 'Shlakoblok'),
      'glue' => tr3(
          '砌块胶', 'Газоблок желімі', 'Клей для газоблока', 'Block adhesive',
          ky: 'Газоблок желими', uz: 'Gazoblok yelimi'),
      'cement' =>
        tr3('水泥', 'Цемент', 'Цемент', 'Cement', ky: 'Цемент', uz: 'Sement'),
      'sand' => tr3('砂', 'Құм', 'Песок', 'Sand', ky: 'Кум', uz: 'Qum'),
      'insulation' => tr3(
          '保温板', 'Жылытқыш плита', 'Утеплитель', 'Insulation boards',
          ky: 'Жылуулагыч', uz: 'Issiqlik izolyatsiyasi'),
      'adhesive' => tr3('保温板粘结砂浆', 'Жылытқыш желімі', 'Клей для утеплителя',
          'Insulation adhesive',
          ky: 'Жылуулагыч желими', uz: 'Izolyatsiya yelimi'),
      'dowel' => tr3('保温锚栓', 'Жылытқыш дюбелі', 'Дюбели для утеплителя',
          'Insulation anchors',
          ky: 'Жылуулагыч дюбели', uz: 'Izolyatsiya dyubeli'),
      'mesh' => tr3(
          '网格布', 'Арматуралық тор', 'Армирующая сетка', 'Reinforcing mesh',
          ky: 'Арматуралык тор', uz: 'Armatura toʻri'),
      'render' => tr3(
          '外墙饰面砂浆', 'Қасбет сылағы', 'Фасадная штукатурка', 'Facade render',
          ky: 'Фасад шыбагы', uz: 'Fasad suvogʻi'),
      'timber' => tr3('木方', 'Ағаш материал', 'Пиломатериал', 'Timber',
          ky: 'Жыгач материал', uz: 'Yogʻoch material'),
      'roofMembrane' => tr3(
          '防水透气膜', 'Шатыр мембранасы', 'Кровельная мембрана', 'Roof underlay',
          ky: 'Чатыр мембранасы', uz: 'Tom membranasi'),
      'roofSheet' => tr3(
          '屋面板 (金属瓦)', 'Металл жабын', 'Металлочерепица', 'Metal roofing',
          ky: 'Металл чатыр', uz: 'Metall cherepitsa'),
      'ridgeCap' => tr3('屋脊瓦', 'Шатыр қыры', 'Конёк', 'Ridge cap',
          ky: 'Чатыр кыры', uz: 'Tom qirrasi'),
      'gutter' => tr3('檐沟', 'Науа', 'Водосточный жёлоб', 'Gutter',
          ky: 'Суу науасы', uz: 'Suv novi'),
      'downpipe' => tr3(
          '落水管', 'Су ағызғы құбыр', 'Водосточная труба', 'Downpipe',
          ky: 'Суу түшүрүүчү түтүк', uz: 'Suv tushirish quvuri'),
      'screw' => tr3(
          '屋面自攻钉', 'Шатыр бұрандасы', 'Кровельные саморезы', 'Roofing screws',
          ky: 'Чатыр бурамасы', uz: 'Tom burama mixi'),
      'wool' => tr3(
          '保温棉', 'Минералды мақта', 'Минеральная вата', 'Mineral wool',
          ky: 'Минералдык кебез', uz: 'Mineral paxta'),
      'roofRoll' => tr3('屋面防水卷材', 'Шатыр гидрооқшауы',
          'Кровельная гидроизоляция', 'Roofing membrane',
          ky: 'Чатыр гидроизоляциясы', uz: 'Tom gidroizolyatsiyasi'),
      'window' =>
        tr3('窗', 'Терезе', 'Окно', 'Window', ky: 'Терезе', uz: 'Deraza'),
      'doorEntry' => tr3('入户门', 'Кіреберіс есік', 'Входная дверь', 'Front door',
          ky: 'Кире бериш эшик', uz: 'Kirish eshigi'),
      'doorInt' => tr3(
          '室内门', 'Ішкі есік', 'Межкомнатная дверь', 'Interior door',
          ky: 'Ички эшик', uz: 'Ichki eshik'),
      'foam' => tr3('发泡胶', 'Монтаж көбігі', 'Монтажная пена', 'Expanding foam',
          ky: 'Монтаж көбүгү', uz: 'Montaj koʻpigi'),
      'plaster' => tr3('内墙抹灰砂浆', 'Ішкі сылақ', 'Штукатурка', 'Plaster',
          ky: 'Шыбак', uz: 'Suvoq'),
      'putty' => tr3('腻子', 'Шпаклёвка', 'Шпаклёвка', 'Filler',
          ky: 'Шпаклёвка', uz: 'Shpaklyovka'),
      'paint' => tr3('涂料', 'Бояу', 'Краска', 'Paint', ky: 'Боёк', uz: 'Boʻyoq'),
      'screed' => tr3(
          '地面找平砂浆', 'Еден тегістеу қоспасы', 'Смесь для стяжки', 'Screed mix',
          ky: 'Пол тегиздөө аралашмасы', uz: 'Pol tekislash aralashmasi'),
      'tile' =>
        tr3('瓷砖', 'Плитка', 'Плитка', 'Tiles', ky: 'Плитка', uz: 'Plitka'),
      'tileGlue' => tr3(
          '瓷砖胶', 'Плитка желімі', 'Плиточный клей', 'Tile adhesive',
          ky: 'Плитка желими', uz: 'Plitka yelimi'),
      'laminate' => tr3('地板', 'Ламинат', 'Ламинат', 'Laminate flooring',
          ky: 'Ламинат', uz: 'Laminat'),
      _ => costLineName(key),
    };

/// "12 袋" / "12 мешков": whole packs of a shopping list line.
String packName(String pack) => switch (pack) {
      'bag' => tr3('袋', 'қап', 'меш.', 'bags', ky: 'кап', uz: 'qop'),
      'bar' => tr3('根', 'шыбық', 'прут.', 'bars', ky: 'чыбык', uz: 'sterjen'),
      'roll' => tr3('卷', 'орам', 'рул.', 'rolls', ky: 'түрмөк', uz: 'oʻram'),
      'sheet' => tr3('张', 'парақ', 'лист.', 'sheets', ky: 'барак', uz: 'list'),
      'coil' => tr3('盘', 'бухта', 'бухт.', 'coils', ky: 'бухта', uz: 'buxta'),
      'can' => tr3('桶', 'шелек', 'вёдер', 'cans', ky: 'чака', uz: 'chelak'),
      'piece' => tr3('根', 'дана', 'шт.', 'pcs', ky: 'даана', uz: 'dona'),
      'pack' => tr3('盒', 'қорап', 'упак.', 'packs', ky: 'куту', uz: 'quti'),
      _ => pack,
    };

String masonryUnitName(MasonryUnit unit) => switch (unit) {
      MasonryUnit.aerated => tr3('加气块', 'Газоблок', 'Газоблок', 'Aerated block',
          ky: 'Газоблок', uz: 'Gazoblok'),
      MasonryUnit.brick =>
        tr3('砖', 'Кірпіш', 'Кирпич', 'Brick', ky: 'Кирпич', uz: 'Gʻisht'),
      MasonryUnit.cinder => tr3(
          '炉渣砌块', 'Шлакоблок', 'Шлакоблок', 'Cinder block',
          ky: 'Шлакоблок', uz: 'Shlakoblok'),
    };

String foundationTypeName(FoundationType type) => switch (type) {
      FoundationType.strip => tr3('条形基础', 'Таспалы', 'Ленточный', 'Strip',
          ky: 'Тасма', uz: 'Lentali'),
      FoundationType.slab =>
        tr3('筏板基础', 'Тұтас плита', 'Плитный', 'Slab', ky: 'Плита', uz: 'Plita'),
      FoundationType.pile =>
        tr3('桩基础', 'Қадалы', 'Свайный', 'Piles', ky: 'Казык', uz: 'Qoziqli'),
    };

/// A price region; the first is the whole country.
String priceRegionName(String region) => switch (region) {
      'kz' => tr3('哈萨克斯坦 (全国)', 'Қазақстан (жалпы)', 'Казахстан (в среднем)',
          'Kazakhstan (average)',
          ky: 'Казакстан (орточо)', uz: 'Qozogʻiston (oʻrtacha)'),
      'almaty' =>
        tr3('阿拉木图', 'Алматы', 'Алматы', 'Almaty', ky: 'Алматы', uz: 'Olmaota'),
      'astana' =>
        tr3('阿斯塔纳', 'Астана', 'Астана', 'Astana', ky: 'Астана', uz: 'Ostona'),
      'shymkent' => tr3('奇姆肯特', 'Шымкент', 'Шымкент', 'Shymkent',
          ky: 'Шымкент', uz: 'Chimkent'),
      'karaganda' => tr3('卡拉干达', 'Қарағанды', 'Караганда', 'Karaganda',
          ky: 'Караганда', uz: 'Qaragʻanda'),
      'aktobe' =>
        tr3('阿克托别', 'Ақтөбе', 'Актобе', 'Aktobe', ky: 'Актөбө', uz: 'Oqtoʻba'),
      'pavlodar' => tr3('巴甫洛达尔', 'Павлодар', 'Павлодар', 'Pavlodar',
          ky: 'Павлодар', uz: 'Pavlodar'),
      'kyzylorda' => tr3('克孜勒奥尔达', 'Қызылорда', 'Кызылорда', 'Kyzylorda',
          ky: 'Кызылордо', uz: 'Qiziloʻrda'),
      'oral' => tr3('乌拉尔', 'Орал', 'Уральск', 'Oral', ky: 'Орал', uz: 'Uralsk'),
      'atyrau' =>
        tr3('阿特劳', 'Атырау', 'Атырау', 'Atyrau', ky: 'Атырау', uz: 'Atirau'),
      'kostanay' => tr3('科斯塔奈', 'Қостанай', 'Костанай', 'Kostanay',
          ky: 'Костанай', uz: 'Qoʻstanay'),
      'oskemen' => tr3('厄斯克门', 'Өскемен', 'Усть-Каменогорск', 'Oskemen',
          ky: 'Өскемен', uz: 'Oskemen'),
      'taraz' =>
        tr3('塔拉兹', 'Тараз', 'Тараз', 'Taraz', ky: 'Тараз', uz: 'Taroz'),
      _ => region,
    };

/// Who a regional price comes from.
String priceSourceName(String source) => switch (source) {
      'stat' => tr3('官方统计', 'ресми статистика', 'официальная статистика',
          'official statistics',
          ky: 'расмий статистика', uz: 'rasmiy statistika'),
      'market' => tr3('用户报价', 'пайдаланушылар бағасы', 'цены пользователей',
          "users' prices",
          ky: 'колдонуучулардын баасы', uz: 'foydalanuvchilar narxi'),
      _ => tr3('平台录入', 'платформа енгізген', 'внесено командой',
          'entered by the team',
          ky: 'команда киргизген', uz: 'jamoa kiritgan'),
    };
