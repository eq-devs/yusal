import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/analysis/build_schedule.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';

/// Chinese / Kazakh names for the planning pages: utility points, plot
/// items, estimate lines and units, fuels and building stages.

String utilityName(UtilityKind kind) => switch (kind) {
      UtilityKind.panel => tr3('配电箱', 'Электр қалқаны', 'Электрощит', 'Electrical panel'),
      UtilityKind.socket => tr3('插座', 'Розетка', 'Розетка', 'Socket'),
      UtilityKind.lightSwitch => tr3('开关', 'Ажыратқыш', 'Выключатель', 'Switch'),
      UtilityKind.light => tr3('灯', 'Шам', 'Светильник', 'Light'),
      UtilityKind.vent => tr3('排气扇', 'Сорғыш желдеткіш', 'Вытяжной вентилятор', 'Extractor fan'),
      UtilityKind.water => tr3('给水点', 'Су нүктесі', 'Точка водоснабжения', 'Water point'),
      UtilityKind.drain => tr3('排水点', 'Кәріз нүктесі', 'Точка канализации', 'Drain point'),
      UtilityKind.radiator => tr3('暖气片', 'Радиатор', 'Радиатор', 'Radiator'),
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
      0 => tr3('电', 'Электр', 'Электрика', 'Electrical'),
      1 => tr3('水', 'Су', 'Вода', 'Water'),
      _ => tr3('暖', 'Жылу', 'Отопление', 'Heating'),
    };

String siteName(SiteKind kind) => switch (kind) {
      SiteKind.barn => tr3('牲畜棚', 'Мал қорасы', 'Сарай для скота', 'Livestock barn'),
      SiteKind.bathhouse => tr3('澡堂', 'Монша', 'Баня', 'Bathhouse'),
      SiteKind.garage => tr3('车库', 'Гараж', 'Гараж', 'Garage'),
      SiteKind.toilet => tr3('室外厕所', 'Аула дәретханасы', 'Уличный туалет', 'Outdoor toilet'),
      SiteKind.shed => tr3('储物棚', 'Қойма', 'Хозблок', 'Utility shed'),
      SiteKind.greenhouse => tr3('温室', 'Жылыжай', 'Теплица', 'Greenhouse'),
      SiteKind.well => tr3('水井', 'Құдық', 'Колодец', 'Well'),
      SiteKind.septic => tr3('化粪池', 'Септик', 'Септик', 'Septic tank'),
      SiteKind.garden => tr3('菜园', 'Бақша', 'Огород', 'Vegetable garden'),
      SiteKind.yard => tr3('硬化院子', 'Төселген аула', 'Мощёный двор', 'Paved yard'),
      SiteKind.gate => tr3('大门', 'Қақпа', 'Ворота', 'Gate'),
      SiteKind.custom => tr3('其他', 'Басқа', 'Другое', 'Other'),
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
      'found' => tr3('基础', 'Іргетас', 'Фундамент', 'Foundation'),
      'walls' => tr3('墙体与楼板', 'Қабырға және плиталар', 'Стены и перекрытия', 'Walls and floors'),
      'roof' => tr3('屋顶', 'Шатыр', 'Крыша', 'Roof'),
      'openings' => tr3('门窗', 'Есік-терезе', 'Окна и двери', 'Windows and doors'),
      'mep' => tr3('水电暖', 'Су, электр, жылу', 'Вода, электрика, отопление', 'Water, electrical, heating'),
      'finish' => tr3('地面与装修', 'Еден және әрлеу', 'Полы и отделка', 'Floors and finishes'),
      'site' =>
        tr3('院子与附属', 'Аула және қосалқы құрылыс', 'Двор и хозпостройки', 'Yard and outbuildings'),
      _ => tr3('其他', 'Басқа', 'Другое', 'Other'),
    };

String costLineName(String key) => switch (key) {
      'excavation' => tr3('挖土', 'Топырақ қазу', 'Выемка грунта', 'Excavation'),
      'cushion' =>
        tr3('砂砾石垫层', 'Құм-қиыршық төсеме', 'Песчано-гравийная подушка', 'Sand and gravel bed'),
      'concrete' => tr3('基础混凝土 (含损耗 3%)', 'Іргетас бетоны (+3%)',
          'Бетон фундамента (с запасом 3% на потери)',
          'Foundation concrete (3% waste allowance)'),
      'rebar' => tr3('基础钢筋', 'Іргетас арматурасы', 'Арматура фундамента', 'Foundation rebar'),
      'formwork' => tr3('模板', 'Қалып', 'Опалубка', 'Formwork'),
      'xps' =>
        tr3('基础外侧 XPS', 'Іргетас сыртындағы XPS', 'XPS снаружи фундамента', 'XPS outside the foundation'),
      'dampproof' =>
        tr3('水平防水', 'Көлденең гидрооқшау', 'Горизонтальная гидроизоляция', 'Damp-proof course'),
      'blind' => tr3('保温散水', 'Жылы отмостка', 'Утеплённая отмостка', 'Insulated apron'),
      'masonryExt' =>
        tr3('外墙砌体', 'Сыртқы қабырға қалауы', 'Кладка наружных стен', 'Outer wall masonry'),
      'masonryInt' => tr3('内墙砌体', 'Ішкі қабырға қалауы', 'Кладка перегородок', 'Partition masonry'),
      'wallIns' => tr3('外墙保温', 'Қабырға жылытқышы', 'Утеплитель наружных стен', 'Outer wall insulation'),
      'facade' => tr3('外墙饰面', 'Қасбет әрлеуі', 'Отделка фасада', 'Facade finish'),
      'floorSlab' => tr3('楼板', 'Қабатаралық плита', 'Межэтажное перекрытие', 'Intermediate floor slab'),
      'roofSlab' => tr3('屋面板 (含钢筋)', 'Жабын плитасы (арматурамен)',
          'Плита покрытия (с арматурой)',
          'Roof slab (with rebar)'),
      'roofMembrane' =>
        tr3('屋面防水', 'Шатыр гидрооқшауы', 'Гидроизоляция кровли', 'Roof waterproofing'),
      'roofIns' => tr3('屋面保温', 'Шатыр жылытқышы', 'Утеплитель кровли', 'Roof insulation'),
      'parapetWp' =>
        tr3('女儿墙上翻防水', 'Парапет гидрооқшауы', 'Гидроизоляция парапета', 'Parapet waterproofing'),
      'roofCover' => tr3('屋面瓦', 'Шатыр жабыны', 'Кровельное покрытие', 'Roof covering'),
      'roofFrame' =>
        tr3('屋架与挂瓦条', 'Шатыр қаңқасы және тақтайлар', 'Стропила и обрешётка', 'Rafters and battens'),
      'atticIns' => tr3('顶棚保温', 'Төбе жылытқышы', 'Утеплитель потолка', 'Ceiling insulation'),
      'windows' => tr3('窗 (三玻 PVC)', 'Терезе (үш әйнекті ПВХ)',
          'Окно (ПВХ, тройное остекление)',
          'Window (PVC, triple glazing)'),
      'doorEntry' => tr3('入户门', 'Кіреберіс есік', 'Входная дверь', 'Front door'),
      'doorsInt' => tr3('室内门', 'Ішкі есік', 'Межкомнатная дверь', 'Interior door'),
      'elecPoint' => tr3('电气点位', 'Электр нүктелері', 'Электроточки', 'Electrical points'),
      'cable' => tr3('电线', 'Электр сымы', 'Электропровод', 'Electrical wire'),
      'pipe' =>
        tr3('水管与暖气管', 'Су және жылу құбыры', 'Трубы водоснабжения и отопления', 'Water and heating pipes'),
      'radiator' => tr3('暖气片', 'Радиатор', 'Радиатор', 'Radiator'),
      'boiler' => tr3('锅炉', 'Қазандық', 'Рекомендуемый котёл', 'Recommended boiler'),
      'sanitary' => tr3('洁具', 'Санжабдық', 'Сантехника', 'Plumbing fixtures'),
      'groundFloor' => tr3('首层地坪', 'Бірінші қабат едені', 'Пол первого этажа', 'Ground floor build-up'),
      'finishArea' => tr3('室内装修', 'Ішкі әрлеу', 'Внутренняя отделка', 'Interior finishes'),
      'fence' => tr3('院墙', 'Қоршау', 'Забор', 'Fence'),
      'gate' => tr3('大门', 'Қақпа', 'Ворота', 'Gate'),
      'outbuilding' => tr3('附属建筑', 'Қосалқы құрылыстар', 'Хозпостройки', 'Outbuildings'),
      'paving' => tr3('院子硬化', 'Аула төсемі', 'Мощение двора', 'Yard paving'),
      'well' => tr3('水井', 'Құдық', 'Колодец', 'Well'),
      'septic' => tr3('化粪池', 'Септик', 'Септик', 'Septic tank'),
      _ => key,
    };

String unitName(String unit) => switch (unit) {
      'm' => unitM,
      'm2' => unitM2,
      'm3' => unitM3,
      't' => tr3('吨', 'т', 'т', 't'),
      'pcs' => unitPcs,
      _ => unit,
    };

String currencySymbol(Currency c) => c == Currency.cny ? '¥' : '₸';

String currencyName(Currency c) => c == Currency.cny
    ? tr3('人民币 ¥', 'Юань ¥', 'Юань ¥', 'Yuan ¥')
    : tr3('坚戈 ₸', 'Теңге ₸', 'Тенге ₸', 'Tenge ₸');

/// The currency used when the design has not chosen one.
Currency get languageCurrency => isWestern ? Currency.kzt : Currency.cny;

/// 1234567 → "1 234 567" (Kazakh) or "1,234,567" (Chinese).
String money(num value) {
  final digits = value.round().abs().toString();
  final sep = isKk ? ' ' : ',';
  final out = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(sep);
    out.write(digits[i]);
  }
  return out.toString();
}

String fuelName(FuelKind f) => switch (f) {
      FuelKind.coal => tr3('煤', 'Көмір', 'Уголь', 'Coal'),
      FuelKind.gas => tr3('天然气', 'Газ', 'Газ', 'Gas'),
      FuelKind.electricity => tr3('电', 'Электр', 'Электрика', 'Electrical'),
      FuelKind.wood => tr3('木柴', 'Отын', 'Дрова', 'Firewood'),
    };

String fuelUnit(FuelKind f) => switch (f) {
      FuelKind.coal || FuelKind.wood => tr3('吨', 'т', 'т', 't'),
      FuelKind.gas => unitM3,
      FuelKind.electricity => tr3('度', 'кВт·сағ', 'кВт·ч', 'kWh'),
    };

String stageName(BuildStage s) {
  if (s.custom) return s.name;
  final n = stageNames[s.key]!;
  return s.name.isNotEmpty ? s.name : tr(n.$1, n.$2);
}

String statusName(StageStatus s) => switch (s) {
      StageStatus.todo => tr3('未开始', 'Басталмаған', 'Не начато', 'Not started'),
      StageStatus.doing => tr3('进行中', 'Жүріп жатыр', 'В работе', 'In progress'),
      StageStatus.done => tr3('已完成', 'Аяқталды', 'Завершено', 'Finished'),
    };
