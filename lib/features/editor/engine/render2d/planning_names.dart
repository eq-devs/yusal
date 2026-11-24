import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/analysis/build_schedule.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';

/// Chinese / Kazakh names for the planning pages: utility points, plot
/// items, estimate lines and units, fuels and building stages.

String utilityName(UtilityKind kind) => switch (kind) {
      UtilityKind.panel => tr3('配电箱', 'Электр қалқаны', 'Электрощит', 'Electrical panel', ky: 'Электр щити', uz: 'Elektr shchiti'),
      UtilityKind.socket => tr3('插座', 'Розетка', 'Розетка', 'Socket', ky: 'Розетка', uz: 'Rozetka'),
      UtilityKind.lightSwitch => tr3('开关', 'Ажыратқыш', 'Выключатель', 'Switch', ky: 'Өчүргүч', uz: 'Oʻchirgich'),
      UtilityKind.light => tr3('灯', 'Шам', 'Светильник', 'Light', ky: 'Шам', uz: 'Chiroq'),
      UtilityKind.vent => tr3('排气扇', 'Сорғыш желдеткіш', 'Вытяжной вентилятор', 'Extractor fan', ky: 'Соргуч желдеткич', uz: 'Soʻruvchi ventilyator'),
      UtilityKind.water => tr3('给水点', 'Су нүктесі', 'Точка водоснабжения', 'Water point', ky: 'Суу чекити', uz: 'Suv nuqtasi'),
      UtilityKind.drain => tr3('排水点', 'Кәріз нүктесі', 'Точка канализации', 'Drain point', ky: 'Агызуу чекити', uz: 'Oqova nuqtasi'),
      UtilityKind.radiator => tr3('暖气片', 'Радиатор', 'Радиатор', 'Radiator', ky: 'Радиатор', uz: 'Radiator'),
    };

IconData utilityIcon(UtilityKind kind) => switch (kind) {
      UtilityKind.panel => Icons.electrical_services,
      UtilityKind.socket => Icons.power_outlined,
      UtilityKind.lightSwitch => Icons.toggle_on_outlined,
      UtilityKind.light => Icons.lightbulb_outline,
      UtilityKind.vent => Icons.air,
      UtilityKind.water => Icons.water_drop_outlined,
      UtilityKind.drain => Icons.vertical_align_bottom,
      UtilityKind.radiator => Icons.heat_pump_outlined,
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
      0 => tr3('电', 'Электр', 'Электрика', 'Electrical', ky: 'Электр', uz: 'Elektr'),
      1 => tr3('水', 'Су', 'Вода', 'Water', ky: 'Суу', uz: 'Suv'),
      _ => tr3('暖', 'Жылу', 'Отопление', 'Heating', ky: 'Жылытуу', uz: 'Isitish'),
    };

String siteName(SiteKind kind) => switch (kind) {
      SiteKind.barn => tr3('牲畜棚', 'Мал қорасы', 'Сарай для скота', 'Livestock barn', ky: 'Мал сарай', uz: 'Molxona'),
      SiteKind.bathhouse => tr3('澡堂', 'Монша', 'Баня', 'Bathhouse', ky: 'Мончо', uz: 'Hammom (banya)'),
      SiteKind.garage => tr3('车库', 'Гараж', 'Гараж', 'Garage', ky: 'Гараж', uz: 'Garaj'),
      SiteKind.toilet => tr3('室外厕所', 'Аула дәретханасы', 'Уличный туалет', 'Outdoor toilet', ky: 'Короодогу даараткана', uz: 'Hovlidagi hojatxona'),
      SiteKind.shed => tr3('储物棚', 'Қойма', 'Хозблок', 'Utility shed', ky: 'Чарба сарай', uz: 'Xoʻjalik ombori'),
      SiteKind.greenhouse => tr3('温室', 'Жылыжай', 'Теплица', 'Greenhouse', ky: 'Күнөскана', uz: 'Issiqxona'),
      SiteKind.well => tr3('水井', 'Құдық', 'Колодец', 'Well', ky: 'Кудук', uz: 'Quduq'),
      SiteKind.septic => tr3('化粪池', 'Септик', 'Септик', 'Septic tank', ky: 'Септик', uz: 'Septik'),
      SiteKind.garden => tr3('菜园', 'Бақша', 'Огород', 'Vegetable garden', ky: 'Огород', uz: 'Tomorqa'),
      SiteKind.yard => tr3('硬化院子', 'Төселген аула', 'Мощёный двор', 'Paved yard', ky: 'Төшөлгөн короо', uz: 'Qoplangan hovli'),
      SiteKind.gate => tr3('大门', 'Қақпа', 'Ворота', 'Gate', ky: 'Дарбаза', uz: 'Darvoza'),
      SiteKind.custom => tr3('其他', 'Басқа', 'Другое', 'Other', ky: 'Башка', uz: 'Boshqa'),
    };

IconData siteIcon(SiteKind kind) => switch (kind) {
      SiteKind.barn => Icons.agriculture_outlined,
      SiteKind.bathhouse => Icons.hot_tub_outlined,
      SiteKind.garage => Icons.garage_outlined,
      SiteKind.toilet => Icons.wc_outlined,
      SiteKind.shed => Icons.warehouse_outlined,
      SiteKind.greenhouse => Icons.yard_outlined,
      SiteKind.well => Icons.water_outlined,
      SiteKind.septic => Icons.recycling,
      SiteKind.garden => Icons.grass,
      SiteKind.yard => Icons.grid_on,
      SiteKind.gate => Icons.door_sliding_outlined,
      SiteKind.custom => Icons.category_outlined,
    };

String costStageName(String stage) => switch (stage) {
      'found' => tr3('基础', 'Іргетас', 'Фундамент', 'Foundation', ky: 'Пайдубал', uz: 'Poydevor'),
      'walls' => tr3('墙体与楼板', 'Қабырға және плиталар', 'Стены и перекрытия', 'Walls and floors', ky: 'Дубалдар жана жабуулар', uz: 'Devorlar va yopmalar'),
      'roof' => tr3('屋顶', 'Шатыр', 'Крыша', 'Roof', ky: 'Чатыр', uz: 'Tom'),
      'openings' => tr3('门窗', 'Есік-терезе', 'Окна и двери', 'Windows and doors', ky: 'Терезелер жана эшиктер', uz: 'Derazalar va eshiklar'),
      'mep' => tr3('水电暖', 'Су, электр, жылу', 'Вода, электрика, отопление', 'Water, electrical, heating', ky: 'Суу, электр, жылытуу', uz: 'Suv, elektr, isitish'),
      'finish' => tr3('地面与装修', 'Еден және әрлеу', 'Полы и отделка', 'Floors and finishes', ky: 'Полдор жана жасалгалоо', uz: 'Pollar va pardozlash'),
      'site' =>
        tr3('院子与附属', 'Аула және қосалқы құрылыс', 'Двор и хозпостройки', 'Yard and outbuildings', ky: 'Короо жана чарба курулуштары', uz: 'Hovli va xoʻjalik binolari'),
      _ => tr3('其他', 'Басқа', 'Другое', 'Other', ky: 'Башка', uz: 'Boshqa'),
    };

String costLineName(String key) => switch (key) {
      'excavation' => tr3('挖土', 'Топырақ қазу', 'Выемка грунта', 'Excavation', ky: 'Казуу иштери', uz: 'Qazish ishlari'),
      'cushion' =>
        tr3('砂砾石垫层', 'Құм-қиыршық төсеме', 'Песчано-гравийная подушка', 'Sand and gravel bed', ky: 'Кум-шагыл төшөмө', uz: 'Qum-shagʻal toʻshama'),
      'concrete' => tr3('基础混凝土 (含损耗 3%)', 'Іргетас бетоны (+3%)',
          'Бетон фундамента (с запасом 3% на потери)',
          'Foundation concrete (3% waste allowance)', ky: 'Пайдубал бетону (3% ысырап)', uz: 'Poydevor betoni (3% isrof)'),
      'rebar' => tr3('基础钢筋', 'Іргетас арматурасы', 'Арматура фундамента', 'Foundation rebar', ky: 'Пайдубал арматурасы', uz: 'Poydevor armaturasi'),
      'formwork' => tr3('模板', 'Қалып', 'Опалубка', 'Formwork', ky: 'Калып', uz: 'Qolip'),
      'xps' =>
        tr3('基础外侧 XPS', 'Іргетас сыртындағы XPS', 'XPS снаружи фундамента', 'XPS outside the foundation', ky: 'Пайдубалдын сыртындагы XPS', uz: 'Poydevor tashqarisidagi XPS'),
      'dampproof' =>
        tr3('水平防水', 'Көлденең гидрооқшау', 'Горизонтальная гидроизоляция', 'Damp-proof course', ky: 'Гидроизоляция', uz: 'Gidroizolyatsiya'),
      'blind' => tr3('保温散水', 'Жылы отмостка', 'Утеплённая отмостка', 'Insulated apron', ky: 'Жылуу отмостка', uz: 'Isitilgan otmostka'),
      'masonryExt' =>
        tr3('外墙砌体', 'Сыртқы қабырға қалауы', 'Кладка наружных стен', 'Outer wall masonry', ky: 'Сырткы дубалды тургузуу', uz: 'Tashqi devorni terish'),
      'masonryInt' => tr3('内墙砌体', 'Ішкі қабырға қалауы', 'Кладка перегородок', 'Partition masonry', ky: 'Тосмо дубалды тургузуу', uz: 'Toʻsiq devorni terish'),
      'wallIns' => tr3('外墙保温', 'Қабырға жылытқышы', 'Утеплитель наружных стен', 'Outer wall insulation', ky: 'Сырткы дубалды жылуулоо', uz: 'Tashqi devorni issiqlik izolyatsiyalash'),
      'facade' => tr3('外墙饰面', 'Қасбет әрлеуі', 'Отделка фасада', 'Facade finish', ky: 'Фасадды жасалгалоо', uz: 'Fasad pardozi'),
      'floorSlab' => tr3('楼板', 'Қабатаралық плита', 'Межэтажное перекрытие', 'Intermediate floor slab', ky: 'Кабат аралык жабуу', uz: 'Qavatlararo yopma'),
      'roofSlab' => tr3('屋面板 (含钢筋)', 'Жабын плитасы (арматурамен)',
          'Плита покрытия (с арматурой)',
          'Roof slab (with rebar)', ky: 'Чатыр жабуусу (арматура менен)', uz: 'Tom yopmasi (armatura bilan)'),
      'roofMembrane' =>
        tr3('屋面防水', 'Шатыр гидрооқшауы', 'Гидроизоляция кровли', 'Roof waterproofing', ky: 'Чатырдын гидроизоляциясы', uz: 'Tom gidroizolyatsiyasi'),
      'roofIns' => tr3('屋面保温', 'Шатыр жылытқышы', 'Утеплитель кровли', 'Roof insulation', ky: 'Чатырды жылуулоо', uz: 'Tomni issiqlik izolyatsiyalash'),
      'parapetWp' =>
        tr3('女儿墙上翻防水', 'Парапет гидрооқшауы', 'Гидроизоляция парапета', 'Parapet waterproofing', ky: 'Парапеттин гидроизоляциясы', uz: 'Parapet gidroizolyatsiyasi'),
      'roofCover' => tr3('屋面瓦', 'Шатыр жабыны', 'Кровельное покрытие', 'Roof covering', ky: 'Чатыр жабуучу материал', uz: 'Tom qoplamasi'),
      'roofFrame' =>
        tr3('屋架与挂瓦条', 'Шатыр қаңқасы және тақтайлар', 'Стропила и обрешётка', 'Rafters and battens', ky: 'Стропила жана рейкалар', uz: 'Stropila va reykalar'),
      'atticIns' => tr3('顶棚保温', 'Төбе жылытқышы', 'Утеплитель потолка', 'Ceiling insulation', ky: 'Шыпты жылуулоо', uz: 'Shiftni issiqlik izolyatsiyalash'),
      'windows' => tr3('窗 (三玻 PVC)', 'Терезе (үш әйнекті ПВХ)',
          'Окно (ПВХ, тройное остекление)',
          'Window (PVC, triple glazing)', ky: 'Терезе (ПВХ, үч катмар айнек)', uz: 'Deraza (PVX, uch qavatli oyna)'),
      'doorEntry' => tr3('入户门', 'Кіреберіс есік', 'Входная дверь', 'Front door', ky: 'Кире бериш эшик', uz: 'Kirish eshigi'),
      'doorsInt' => tr3('室内门', 'Ішкі есік', 'Межкомнатная дверь', 'Interior door', ky: 'Ички эшик', uz: 'Ichki eshik'),
      'elecPoint' => tr3('电气点位', 'Электр нүктелері', 'Электроточки', 'Electrical points', ky: 'Электр чекиттери', uz: 'Elektr nuqtalari'),
      'cable' => tr3('电线', 'Электр сымы', 'Электропровод', 'Electrical wire', ky: 'Электр зым', uz: 'Elektr simi'),
      'pipe' =>
        tr3('水管与暖气管', 'Су және жылу құбыры', 'Трубы водоснабжения и отопления', 'Water and heating pipes', ky: 'Суу жана жылытуу түтүктөрү', uz: 'Suv va isitish quvurlari'),
      'radiator' => tr3('暖气片', 'Радиатор', 'Радиатор', 'Radiator', ky: 'Радиатор', uz: 'Radiator'),
      'boiler' => tr3('锅炉', 'Қазандық', 'Рекомендуемый котёл', 'Recommended boiler', ky: 'Сунушталган казан', uz: 'Tavsiya etilgan qozon'),
      'sanitary' => tr3('洁具', 'Санжабдық', 'Сантехника', 'Plumbing fixtures', ky: 'Сантехника', uz: 'Santexnika'),
      'groundFloor' => tr3('首层地坪', 'Бірінші қабат едені', 'Пол первого этажа', 'Ground floor build-up', ky: 'Биринчи кабаттын полунун катмарлары', uz: 'Birinchi qavat poli qatlamlari'),
      'finishArea' => tr3('室内装修', 'Ішкі әрлеу', 'Внутренняя отделка', 'Interior finishes', ky: 'Ички жасалгалоо', uz: 'Ichki pardozlash'),
      'fence' => tr3('院墙', 'Қоршау', 'Забор', 'Fence', ky: 'Тосмо', uz: 'Panjara'),
      'gate' => tr3('大门', 'Қақпа', 'Ворота', 'Gate', ky: 'Дарбаза', uz: 'Darvoza'),
      'outbuilding' => tr3('附属建筑', 'Қосалқы құрылыстар', 'Хозпостройки', 'Outbuildings', ky: 'Чарба курулуштары', uz: 'Xoʻjalik binolari'),
      'paving' => tr3('院子硬化', 'Аула төсемі', 'Мощение двора', 'Yard paving', ky: 'Короону төшөө', uz: 'Hovlini qoplash'),
      'well' => tr3('水井', 'Құдық', 'Колодец', 'Well', ky: 'Кудук', uz: 'Quduq'),
      'septic' => tr3('化粪池', 'Септик', 'Септик', 'Septic tank', ky: 'Септик', uz: 'Septik'),
      _ => key,
    };

String unitName(String unit) => switch (unit) {
      'm' => unitM,
      'm2' => unitM2,
      'm3' => unitM3,
      't' => tr3('吨', 'т', 'т', 't', ky: 'т', uz: 't'),
      'pcs' => unitPcs,
      _ => unit,
    };

String currencySymbol(Currency c) => c == Currency.cny ? '¥' : '₸';

String currencyName(Currency c) => c == Currency.cny
    ? tr3('人民币 ¥', 'Юань ¥', 'Юань ¥', 'Yuan ¥', ky: 'Юань ¥', uz: 'Yuan ¥')
    : tr3('坚戈 ₸', 'Теңге ₸', 'Тенге ₸', 'Tenge ₸', ky: 'Теңге ₸', uz: 'Tenge ₸');

/// The currency used when the design has not chosen one.
Currency get languageCurrency => isWestern ? Currency.kzt : Currency.cny;

/// 1234567 → "1 234 567" (Kazakh) or "1,234,567" (Chinese).
String money(num value) {
  final digits = value.round().abs().toString();
  final sep = isWestern && !isEn ? ' ' : ',';
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(sep);
    out.write(digits[i]);
  }
  return out.toString();
}

String fuelName(FuelKind f) => switch (f) {
      FuelKind.coal => tr3('煤', 'Көмір', 'Уголь', 'Coal', ky: 'Көмүр', uz: 'Koʻmir'),
      FuelKind.gas => tr3('天然气', 'Газ', 'Газ', 'Gas', ky: 'Газ', uz: 'Gaz'),
      FuelKind.electricity => tr3('电', 'Электр', 'Электрика', 'Electrical', ky: 'Электр', uz: 'Elektr'),
      FuelKind.wood => tr3('木柴', 'Отын', 'Дрова', 'Firewood', ky: 'Отун', uz: 'Oʻtin'),
    };

String fuelUnit(FuelKind f) => switch (f) {
      FuelKind.coal || FuelKind.wood => tr3('吨', 'т', 'т', 't', ky: 'т', uz: 't'),
      FuelKind.gas => unitM3,
      FuelKind.electricity => tr3('度', 'кВт·сағ', 'кВт·ч', 'kWh', ky: 'кВт·с', uz: 'kVt·soat'),
    };

String stageName(BuildStage s) {
  if (s.custom) return s.name;
  final n = stageNames[s.key]!;
  return s.name.isNotEmpty ? s.name : tr(n.$1, n.$2);
}

String statusName(StageStatus s) => switch (s) {
      StageStatus.todo => tr3('未开始', 'Басталмаған', 'Не начато', 'Not started', ky: 'Башталган жок', uz: 'Boshlanmagan'),
      StageStatus.doing => tr3('进行中', 'Жүріп жатыр', 'В работе', 'In progress', ky: 'Аткарылууда', uz: 'Jarayonda'),
      StageStatus.done => tr3('已完成', 'Аяқталды', 'Завершено', 'Finished', ky: 'Бүттү', uz: 'Tugallandi'),
    };
