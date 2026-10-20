import 'package:flutter/material.dart';
import '../app/settings.dart';
import '../core/analysis/build_schedule.dart';
import '../core/document/house_document.dart';

/// Chinese / Kazakh names for the planning pages: utility points, plot
/// items, estimate lines and units, fuels and building stages.

String utilityName(UtilityKind kind) => switch (kind) {
      UtilityKind.panel => tr('配电箱', 'Электр қалқаны'),
      UtilityKind.socket => tr('插座', 'Розетка'),
      UtilityKind.lightSwitch => tr('开关', 'Ажыратқыш'),
      UtilityKind.light => tr('灯', 'Шам'),
      UtilityKind.vent => tr('排气扇', 'Сорғыш желдеткіш'),
      UtilityKind.water => tr('给水点', 'Су нүктесі'),
      UtilityKind.drain => tr('排水点', 'Кәріз нүктесі'),
      UtilityKind.radiator => tr('暖气片', 'Радиатор'),
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
      0 => tr('电', 'Электр'),
      1 => tr('水', 'Су'),
      _ => tr('暖', 'Жылу'),
    };

String siteName(SiteKind kind) => switch (kind) {
      SiteKind.barn => tr('牲畜棚', 'Мал қорасы'),
      SiteKind.bathhouse => tr('澡堂', 'Монша'),
      SiteKind.garage => tr('车库', 'Гараж'),
      SiteKind.toilet => tr('室外厕所', 'Аула дәретханасы'),
      SiteKind.shed => tr('储物棚', 'Қойма'),
      SiteKind.greenhouse => tr('温室', 'Жылыжай'),
      SiteKind.well => tr('水井', 'Құдық'),
      SiteKind.septic => tr('化粪池', 'Септик'),
      SiteKind.garden => tr('菜园', 'Бақша'),
      SiteKind.yard => tr('硬化院子', 'Төселген аула'),
      SiteKind.gate => tr('大门', 'Қақпа'),
      SiteKind.custom => tr('其他', 'Басқа'),
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
      'found' => tr('基础', 'Іргетас'),
      'walls' => tr('墙体与楼板', 'Қабырға және плиталар'),
      'roof' => tr('屋顶', 'Шатыр'),
      'openings' => tr('门窗', 'Есік-терезе'),
      'mep' => tr('水电暖', 'Су, электр, жылу'),
      'finish' => tr('地面与装修', 'Еден және әрлеу'),
      'site' => tr('院子与附属', 'Аула және қосалқы құрылыс'),
      _ => tr('其他', 'Басқа'),
    };

String costLineName(String key) => switch (key) {
      'excavation' => tr('挖土', 'Топырақ қазу'),
      'cushion' => tr('砂砾石垫层', 'Құм-қиыршық төсеме'),
      'concrete' => tr('基础混凝土 (含损耗 3%)', 'Іргетас бетоны (+3%)'),
      'rebar' => tr('基础钢筋', 'Іргетас арматурасы'),
      'formwork' => tr('模板', 'Қалып'),
      'xps' => tr('基础外侧 XPS', 'Іргетас сыртындағы XPS'),
      'dampproof' => tr('水平防水', 'Көлденең гидрооқшау'),
      'blind' => tr('保温散水', 'Жылы отмостка'),
      'masonryExt' => tr('外墙砌体', 'Сыртқы қабырға қалауы'),
      'masonryInt' => tr('内墙砌体', 'Ішкі қабырға қалауы'),
      'wallIns' => tr('外墙保温', 'Қабырға жылытқышы'),
      'facade' => tr('外墙饰面', 'Қасбет әрлеуі'),
      'floorSlab' => tr('楼板', 'Қабатаралық плита'),
      'roofSlab' => tr('屋面板 (含钢筋)', 'Жабын плитасы (арматурамен)'),
      'roofMembrane' => tr('屋面防水', 'Шатыр гидрооқшауы'),
      'roofIns' => tr('屋面保温', 'Шатыр жылытқышы'),
      'parapetWp' => tr('女儿墙上翻防水', 'Парапет гидрооқшауы'),
      'roofCover' => tr('屋面瓦', 'Шатыр жабыны'),
      'roofFrame' => tr('屋架与挂瓦条', 'Шатыр қаңқасы және тақтайлар'),
      'atticIns' => tr('顶棚保温', 'Төбе жылытқышы'),
      'windows' => tr('窗 (三玻 PVC)', 'Терезе (үш әйнекті ПВХ)'),
      'doorEntry' => tr('入户门', 'Кіреберіс есік'),
      'doorsInt' => tr('室内门', 'Ішкі есік'),
      'elecPoint' => tr('电气点位', 'Электр нүктелері'),
      'cable' => tr('电线', 'Электр сымы'),
      'pipe' => tr('水管与暖气管', 'Су және жылу құбыры'),
      'radiator' => tr('暖气片', 'Радиатор'),
      'boiler' => tr('锅炉', 'Қазандық'),
      'sanitary' => tr('洁具', 'Санжабдық'),
      'groundFloor' => tr('首层地坪', 'Бірінші қабат едені'),
      'finishArea' => tr('室内装修', 'Ішкі әрлеу'),
      'fence' => tr('院墙', 'Қоршау'),
      'gate' => tr('大门', 'Қақпа'),
      'outbuilding' => tr('附属建筑', 'Қосалқы құрылыстар'),
      'paving' => tr('院子硬化', 'Аула төсемі'),
      'well' => tr('水井', 'Құдық'),
      'septic' => tr('化粪池', 'Септик'),
      _ => key,
    };

String unitName(String unit) => switch (unit) {
      'm' => unitM,
      'm2' => unitM2,
      'm3' => unitM3,
      't' => tr('吨', 'т'),
      'pcs' => unitPcs,
      _ => unit,
    };

String currencySymbol(Currency c) => c == Currency.cny ? '¥' : '₸';

String currencyName(Currency c) =>
    c == Currency.cny ? tr('人民币 ¥', 'Юань ¥') : tr('坚戈 ₸', 'Теңге ₸');

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
      FuelKind.coal => tr('煤', 'Көмір'),
      FuelKind.gas => tr('天然气', 'Газ'),
      FuelKind.electricity => tr('电', 'Электр'),
      FuelKind.wood => tr('木柴', 'Отын'),
    };

String fuelUnit(FuelKind f) => switch (f) {
      FuelKind.coal || FuelKind.wood => tr('吨', 'т'),
      FuelKind.gas => unitM3,
      FuelKind.electricity => tr('度', 'кВт·сағ'),
    };

String stageName(BuildStage s) {
  if (s.custom) return s.name;
  final n = stageNames[s.key]!;
  return s.name.isNotEmpty ? s.name : tr(n.$1, n.$2);
}

String statusName(StageStatus s) => switch (s) {
      StageStatus.todo => tr('未开始', 'Басталмаған'),
      StageStatus.doing => tr('进行中', 'Жүріп жатыр'),
      StageStatus.done => tr('已完成', 'Аяқталды'),
    };
