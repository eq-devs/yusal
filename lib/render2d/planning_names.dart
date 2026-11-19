import 'package:flutter/material.dart';
import '../app/settings.dart';
import '../core/analysis/build_schedule.dart';
import '../core/document/house_document.dart';

/// Chinese / Kazakh names for the planning pages: utility points, plot
/// items, estimate lines and units, fuels and building stages.

String utilityName(UtilityKind kind) => switch (kind) {
      UtilityKind.panel => tr3('配电箱', 'Электр қалқаны', 'Электрощит'),
      UtilityKind.socket => tr3('插座', 'Розетка', 'Розетка'),
      UtilityKind.lightSwitch => tr3('开关', 'Ажыратқыш', 'Выключатель'),
      UtilityKind.light => tr3('灯', 'Шам', 'Светильник'),
      UtilityKind.vent => tr3('排气扇', 'Сорғыш желдеткіш', 'Вытяжной вентилятор'),
      UtilityKind.water => tr3('给水点', 'Су нүктесі', 'Точка водоснабжения'),
      UtilityKind.drain => tr3('排水点', 'Кәріз нүктесі', 'Точка канализации'),
      UtilityKind.radiator => tr3('暖气片', 'Радиатор', 'Радиатор'),
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
      0 => tr3('电', 'Электр', 'Электрика'),
      1 => tr3('水', 'Су', 'Вода'),
      _ => tr3('暖', 'Жылу', 'Отопление'),
    };

String siteName(SiteKind kind) => switch (kind) {
      SiteKind.barn => tr3('牲畜棚', 'Мал қорасы', 'Сарай для скота'),
      SiteKind.bathhouse => tr3('澡堂', 'Монша', 'Баня'),
      SiteKind.garage => tr3('车库', 'Гараж', 'Гараж'),
      SiteKind.toilet => tr3('室外厕所', 'Аула дәретханасы', 'Уличный туалет'),
      SiteKind.shed => tr3('储物棚', 'Қойма', 'Хозблок'),
      SiteKind.greenhouse => tr3('温室', 'Жылыжай', 'Теплица'),
      SiteKind.well => tr3('水井', 'Құдық', 'Колодец'),
      SiteKind.septic => tr3('化粪池', 'Септик', 'Септик'),
      SiteKind.garden => tr3('菜园', 'Бақша', 'Огород'),
      SiteKind.yard => tr3('硬化院子', 'Төселген аула', 'Мощёный двор'),
      SiteKind.gate => tr3('大门', 'Қақпа', 'Ворота'),
      SiteKind.custom => tr3('其他', 'Басқа', 'Другое'),
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
      'found' => tr3('基础', 'Іргетас', 'Фундамент'),
      'walls' => tr3('墙体与楼板', 'Қабырға және плиталар', 'Стены и перекрытия'),
      'roof' => tr3('屋顶', 'Шатыр', 'Крыша'),
      'openings' => tr3('门窗', 'Есік-терезе', 'Окна и двери'),
      'mep' => tr3('水电暖', 'Су, электр, жылу', 'Вода, электрика, отопление'),
      'finish' => tr3('地面与装修', 'Еден және әрлеу', 'Полы и отделка'),
      'site' => tr3('院子与附属', 'Аула және қосалқы құрылыс', 'Двор и хозпостройки'),
      _ => tr3('其他', 'Басқа', 'Другое'),
    };

String costLineName(String key) => switch (key) {
      'excavation' => tr3('挖土', 'Топырақ қазу', 'Выемка грунта'),
      'cushion' => tr3('砂砾石垫层', 'Құм-қиыршық төсеме', 'Песчано-гравийная подушка'),
      'concrete' => tr3('基础混凝土 (含损耗 3%)', 'Іргетас бетоны (+3%)', 'Бетон фундамента (с запасом 3% на потери)'),
      'rebar' => tr3('基础钢筋', 'Іргетас арматурасы', 'Арматура фундамента'),
      'formwork' => tr3('模板', 'Қалып', 'Опалубка'),
      'xps' => tr3('基础外侧 XPS', 'Іргетас сыртындағы XPS', 'XPS снаружи фундамента'),
      'dampproof' => tr3('水平防水', 'Көлденең гидрооқшау', 'Горизонтальная гидроизоляция'),
      'blind' => tr3('保温散水', 'Жылы отмостка', 'Утеплённая отмостка'),
      'masonryExt' => tr3('外墙砌体', 'Сыртқы қабырға қалауы', 'Кладка наружных стен'),
      'masonryInt' => tr3('内墙砌体', 'Ішкі қабырға қалауы', 'Кладка перегородок'),
      'wallIns' => tr3('外墙保温', 'Қабырға жылытқышы', 'Утеплитель наружных стен'),
      'facade' => tr3('外墙饰面', 'Қасбет әрлеуі', 'Отделка фасада'),
      'floorSlab' => tr3('楼板', 'Қабатаралық плита', 'Межэтажное перекрытие'),
      'roofSlab' => tr3('屋面板 (含钢筋)', 'Жабын плитасы (арматурамен)', 'Плита покрытия (с арматурой)'),
      'roofMembrane' => tr3('屋面防水', 'Шатыр гидрооқшауы', 'Гидроизоляция кровли'),
      'roofIns' => tr3('屋面保温', 'Шатыр жылытқышы', 'Утеплитель кровли'),
      'parapetWp' => tr3('女儿墙上翻防水', 'Парапет гидрооқшауы', 'Гидроизоляция парапета'),
      'roofCover' => tr3('屋面瓦', 'Шатыр жабыны', 'Кровельное покрытие'),
      'roofFrame' => tr3('屋架与挂瓦条', 'Шатыр қаңқасы және тақтайлар', 'Стропила и обрешётка'),
      'atticIns' => tr3('顶棚保温', 'Төбе жылытқышы', 'Утеплитель потолка'),
      'windows' => tr3('窗 (三玻 PVC)', 'Терезе (үш әйнекті ПВХ)', 'Окно (ПВХ, тройное остекление)'),
      'doorEntry' => tr3('入户门', 'Кіреберіс есік', 'Входная дверь'),
      'doorsInt' => tr3('室内门', 'Ішкі есік', 'Межкомнатная дверь'),
      'elecPoint' => tr3('电气点位', 'Электр нүктелері', 'Электроточки'),
      'cable' => tr3('电线', 'Электр сымы', 'Электропровод'),
      'pipe' => tr3('水管与暖气管', 'Су және жылу құбыры', 'Трубы водоснабжения и отопления'),
      'radiator' => tr3('暖气片', 'Радиатор', 'Радиатор'),
      'boiler' => tr3('锅炉', 'Қазандық', 'Рекомендуемый котёл'),
      'sanitary' => tr3('洁具', 'Санжабдық', 'Сантехника'),
      'groundFloor' => tr3('首层地坪', 'Бірінші қабат едені', 'Пол первого этажа'),
      'finishArea' => tr3('室内装修', 'Ішкі әрлеу', 'Внутренняя отделка'),
      'fence' => tr3('院墙', 'Қоршау', 'Забор'),
      'gate' => tr3('大门', 'Қақпа', 'Ворота'),
      'outbuilding' => tr3('附属建筑', 'Қосалқы құрылыстар', 'Хозпостройки'),
      'paving' => tr3('院子硬化', 'Аула төсемі', 'Мощение двора'),
      'well' => tr3('水井', 'Құдық', 'Колодец'),
      'septic' => tr3('化粪池', 'Септик', 'Септик'),
      _ => key,
    };

String unitName(String unit) => switch (unit) {
      'm' => unitM,
      'm2' => unitM2,
      'm3' => unitM3,
      't' => tr3('吨', 'т', 'т'),
      'pcs' => unitPcs,
      _ => unit,
    };

String currencySymbol(Currency c) => c == Currency.cny ? '¥' : '₸';

String currencyName(Currency c) =>
    c == Currency.cny ? tr3('人民币 ¥', 'Юань ¥', 'Юань ¥') : tr3('坚戈 ₸', 'Теңге ₸', 'Тенге ₸');

/// The currency used when the design has not chosen one.
Currency get languageCurrency => isKk ? Currency.kzt : Currency.cny;

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
      FuelKind.coal => tr3('煤', 'Көмір', 'Уголь'),
      FuelKind.gas => tr3('天然气', 'Газ', 'Газ'),
      FuelKind.electricity => tr3('电', 'Электр', 'Электрика'),
      FuelKind.wood => tr3('木柴', 'Отын', 'Дрова'),
    };

String fuelUnit(FuelKind f) => switch (f) {
      FuelKind.coal || FuelKind.wood => tr3('吨', 'т', 'т'),
      FuelKind.gas => unitM3,
      FuelKind.electricity => tr3('度', 'кВт·сағ', 'кВт·ч'),
    };

String stageName(BuildStage s) {
  if (s.custom) return s.name;
  final n = stageNames[s.key]!;
  return s.name.isNotEmpty ? s.name : tr(n.$1, n.$2);
}

String statusName(StageStatus s) => switch (s) {
      StageStatus.todo => tr3('未开始', 'Басталмаған', 'Не начато'),
      StageStatus.doing => tr3('进行中', 'Жүріп жатыр', 'В работе'),
      StageStatus.done => tr3('已完成', 'Аяқталды', 'Завершено'),
    };
