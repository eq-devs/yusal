import '../document/house_document.dart';
import 'cost_estimate.dart';

/// The building schedule: what each built-in stage covers, what to check
/// before moving on, planned dates and the budget of each stage. Pure
/// Dart; dates are calendar days without time zones.

/// Name of each built-in stage, (Chinese, Kazakh).
const stageNames = {
  'prep': ('准备与手续', 'Дайындық және құжаттар'),
  'found': ('基础', 'Іргетас'),
  'walls': ('墙体与楼板', 'Қабырға және плиталар'),
  'roof': ('屋顶', 'Шатыр'),
  'openings': ('门窗', 'Есік-терезе'),
  'mep': ('水电暖', 'Су, электр, жылу'),
  'finish': ('地面与装修', 'Еден және әрлеу'),
  'site': ('院子与附属', 'Аула және қосалқы құрылыс'),
  'handover': ('验收入住', 'Қабылдау және кіру'),
};

/// What to check in each built-in stage, (Chinese, Kazakh).
const stageChecks = <String, List<(String, String)>>{
  'prep': [
    ('办好宅基地和建房手续', 'Жер учаскесі мен құрылыс рұқсатын рәсімдеу'),
    ('挖 1.5 m 探坑看土层和地下水', '1,5 м шұңқыр қазып, топырақ пен жер асты суын қарау'),
    ('和施工队签书面合同，写清单价和工期', 'Құрылысшымен баға мен мерзімі жазылған жазбаша келісімшарт'),
    ('接通临时水电', 'Уақытша су мен электр қосу'),
    ('放线定位，复核长宽和对角线', 'Белгілеу, ұзындық, ен және диагональды тексеру'),
  ],
  'found': [
    ('基槽挖到设计深度，槽底夯实', 'Ор жобалық тереңдікке дейін қазылып, табаны тығыздалды'),
    ('砂砾石垫层分层夯实', 'Құм-қиыршық қабат-қабатымен тығыздалды'),
    ('钢筋绑扎完成后拍照留底', 'Арматура байланғаннан кейін суретке түсірілді'),
    ('核对预埋套管位置', 'Гильзалардың орны тексерілді'),
    ('浇筑后养护不少于 7 天', 'Құйылғаннан кейін кемінде 7 күн күтім'),
    ('外侧 XPS 和防水做完再回填', 'Сыртқы XPS пен гидрооқшау біткен соң ғана көму'),
  ],
  'walls': [
    ('第一皮砌块找平', 'Бірінші қатар блок деңгеймен қаланды'),
    ('每层设圈梁或配筋带', 'Әр қабатта белдеу не арматуралы белбеу'),
    ('门窗洞口上方放过梁', 'Есік-терезе ойығының үстінде аркалық'),
    ('检查墙体垂直度', 'Қабырғаның тіктігі тексерілді'),
  ],
  'roof': [
    ('屋面板或屋架完成', 'Жабын плитасы не шатыр қаңқасы дайын'),
    ('隔汽层和保温层连续不断', 'Бу оқшаулағыш пен жылытқыш үзіліссіз'),
    ('防水或屋面瓦完成', 'Гидрооқшау не жабын төселді'),
    ('装好天沟和落水管', 'Науа мен су құбыры орнатылды'),
  ],
  'openings': [
    ('窗框装在靠近保温层的位置', 'Терезе жақтауы жылытқышқа жақын орнатылды'),
    ('缝隙用预压膨胀密封带', 'Саңылау кеңейетін лентамен бітелді'),
    ('入户门密封检查', 'Кіреберіс есіктің тығыздығы тексерілді'),
  ],
  'mep': [
    ('配电箱和回路按图纸', 'Электр қалқаны мен желілер сызба бойынша'),
    ('给水管打压试验', 'Су құбыры қысыммен сыналды'),
    ('暖气系统试水', 'Жылу жүйесі сумен сыналды'),
    ('检查排水坡度', 'Кәріз еңісі тексерілді'),
    ('隐蔽工程封闭前拍照', 'Жасырын жұмыстар жабылмас бұрын суретке түсірілді'),
  ],
  'finish': [
    ('墙面抹灰', 'Қабырға сылағы'),
    ('地面找平或地暖', 'Еден тегістеу не жылы еден'),
    ('卫生间和厨房二次防水', 'Жуыну бөлмесі мен ас үйде екінші гидрооқшау'),
    ('涂料和地面面层', 'Бояу және еден жабыны'),
  ],
  'site': [
    ('院墙和大门', 'Қоршау және қақпа'),
    ('房子四周做散水', 'Үйдің айналасына отмостка'),
    ('附属建筑', 'Қосалқы құрылыстар'),
  ],
  'handover': [
    ('全屋检查一遍：门窗、水电、暖气', 'Бүкіл үйді тексеру: есік-терезе, су, электр, жылу'),
    ('图纸、合同和照片归档', 'Сызба, келісімшарт және суреттерді сақтау'),
    ('入住', 'Үйге кіру'),
  ],
};

/// Cost stages paid within each schedule stage.
const stageCosts = {
  'found': ['found'],
  'walls': ['walls'],
  'roof': ['roof'],
  'openings': ['openings'],
  'mep': ['mep'],
  'finish': ['finish'],
  'site': ['site'],
};

/// A stage with its planned dates; null when no start is known yet.
typedef PlannedStage = ({BuildStage stage, DateTime? start, DateTime? end});

DateTime? parseDay(String? text) {
  if (text == null) return null;
  final parts = text.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]),
      m = int.tryParse(parts[1]),
      d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  final day = DateTime.utc(y, m, d);
  return day.month == m && day.day == d ? day : null;
}

String formatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// Dates of [stages] in order: each starts on its own date or when the
/// previous one ends.
List<PlannedStage> planStages(List<BuildStage> stages) {
  final out = <PlannedStage>[];
  DateTime? next;
  for (final s in stages) {
    final start = parseDay(s.start) ?? next;
    final end = start?.add(Duration(days: s.days));
    out.add((stage: s, start: start, end: end));
    next = end;
  }
  return out;
}

/// Budget of each schedule stage from the estimate, labour included and
/// the contingency spread evenly.
Map<String, double> stageBudgets(CostEstimate estimate) {
  final share = 1 + estimate.contingencyPct / 100;
  return {
    for (final e in stageCosts.entries)
      e.key: e.value.fold(0.0, (s, k) => s + estimate.stageTotal(k)) * share
  };
}

/// Share of the work done: finished stages count fully, stages under way
/// by their ticked checks.
double progress(List<BuildStage> stages) {
  if (stages.isEmpty) return 0;
  var done = 0.0;
  for (final s in stages) {
    if (s.status == StageStatus.done) {
      done += 1;
    } else if (s.status == StageStatus.doing) {
      final n = stageChecks[s.key]?.length ?? 0;
      done += n == 0 ? 0.5 : (s.checks.where((c) => c < n).length / n) * 0.9;
    }
  }
  return done / stages.length;
}
