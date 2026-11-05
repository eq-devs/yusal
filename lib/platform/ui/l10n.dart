import '../../app/settings.dart';
import '../data/repositories.dart';
import '../domain/models.dart';
import '../domain/rules.dart';

/// Names of codes and common words of the platform in Chinese, Kazakh and
/// Russian.

String tradeName(String code) => switch (code) {
      'mason' => tr3('瓦工／砌墙', 'Қалаушы', 'Каменщик'),
      'concrete' => tr3('混凝土工', 'Бетоншы', 'Бетонщик'),
      'rebar' => tr3('钢筋工', 'Арматурашы', 'Арматурщик'),
      'carpenter' => tr3('木工／模板', 'Ағаш ұстасы', 'Плотник'),
      'roofer' => tr3('屋面', 'Шатыршы', 'Кровельщик'),
      'electrician' => tr3('电工', 'Электрик', 'Электрик'),
      'plumber' => tr3('水暖工', 'Сантехник', 'Сантехник'),
      'welder' => tr3('焊工', 'Дәнекерлеуші', 'Сварщик'),
      'plasterer' => tr3('抹灰／装修', 'Сылақшы', 'Штукатур'),
      'tiler' => tr3('瓷砖', 'Плиткашы', 'Плиточник'),
      'laborer' => tr3('小工／杂工', 'Көмекші жұмысшы', 'Разнорабочий'),
      'general' => tr3('整体施工', 'Толық құрылыс', 'Генподряд'),
      _ => code,
    };

String regionName(String code) => switch (code) {
      'almaty' => tr3('阿拉木图', 'Алматы', 'Алматы'),
      'talgar' => tr3('塔尔加尔', 'Талғар', 'Талгар'),
      'kaskelen' => tr3('卡斯克连', 'Қаскелең', 'Каскелен'),
      'esik' => tr3('伊塞克', 'Есік', 'Есик'),
      'konaev' => tr3('科纳耶夫', 'Қонаев', 'Конаев'),
      'otegen' => tr3('乌特根巴特尔', 'Өтеген батыр', 'Отеген батыр'),
      '' => '',
      _ => code,
    };

String unitLabel(String code) => switch (code) {
      'total' => tr3('总价', 'жалпы', 'итого'),
      'day' => tr3('天', 'күн', 'день'),
      'm3' => 'm³',
      'm2' => 'm²',
      'm' => tr3('米', 'м', 'м'),
      'pcs' => tr3('个', 'дана', 'шт.'),
      't' => tr3('吨', 'т', 'т'),
      'hour' => tr3('小时', 'сағ', 'час'),
      _ => code,
    };

/// "per m³" style suffix; empty for totals.
String perUnit(String code) => code == 'total' ? '' : ' / ${unitLabel(code)}';

String stageLabel(String code) => switch (code) {
      'found' => tr3('基础', 'Іргетас', 'Фундамент'),
      'walls' => tr3('墙体与楼板', 'Қабырға және плита', 'Стены и перекрытия'),
      'roof' => tr3('屋顶', 'Шатыр', 'Кровля'),
      'openings' => tr3('门窗', 'Есік-терезе', 'Окна и двери'),
      'mep' => tr3('水电暖', 'Су, электр, жылу', 'Инженерные сети'),
      'finish' => tr3('地面与装修', 'Еден және әрлеу', 'Полы и отделка'),
      'site' => tr3('院子与附属', 'Аула', 'Участок'),
      _ => tr3('其他', 'Басқа', 'Другое'),
    };

String demandTypeName(DemandType t) => switch (t) {
      DemandType.hire => tr3('招人干活', 'Жұмысшы іздеу', 'Найм рабочих'),
      DemandType.contract => tr3('找人承包', 'Мердігер іздеу', 'Подряд'),
    };

String demandStatusName(DemandStatus s) => switch (s) {
      DemandStatus.draft => tr3('草稿', 'Жоба', 'Черновик'),
      DemandStatus.pendingReview => tr3('待审核', 'Тексерілуде', 'На проверке'),
      DemandStatus.open => tr3('招募中', 'Қабылдануда', 'Идёт набор'),
      DemandStatus.paused => tr3('暂停', 'Тоқтатылған', 'Пауза'),
      DemandStatus.found => tr3('已找到人', 'Адам табылды', 'Исполнитель найден'),
      DemandStatus.expired => tr3('已到期', 'Мерзімі өтті', 'Истекло'),
      DemandStatus.closed => tr3('已关闭', 'Жабылды', 'Закрыто'),
      DemandStatus.rejected =>
        tr3('审核未通过／下架', 'Қабылданбады', 'Отклонено / снято'),
    };

String applicationStatusName(ApplicationStatus s) => switch (s) {
      ApplicationStatus.submitted => tr3('已提交', 'Жіберілді', 'Отправлено'),
      ApplicationStatus.withdrawn => tr3('已撤回', 'Қайтарылды', 'Отозвано'),
      ApplicationStatus.notSelected => tr3('未选用', 'Таңдалмады', 'Не выбрано'),
      ApplicationStatus.pendingConfirm =>
        tr3('待对方确认', 'Растауды күтуде', 'Ждёт подтверждения'),
      ApplicationStatus.cooperating =>
        tr3('已形成合作', 'Келісім жасалды', 'Сотрудничество'),
    };

String cooperationStatusName(Cooperation c) => switch (c.status) {
      CooperationStatus.pending =>
        tr3('待双方确认', 'Екі жақ растауын күтуде', 'Ждёт подтверждения сторон'),
      CooperationStatus.confirmed => c.endRequest == null
          ? tr3('已确认合作', 'Келісім расталды', 'Подтверждено')
          : c.endRequest!.dispute != null
              ? tr3('结束有异议', 'Аяқтауға қарсылық', 'Спор о завершении')
              : tr3('结束待确认', 'Аяқтау расталуда', 'Завершение ждёт ответа'),
      CooperationStatus.ended => switch (c.endKind) {
          EndKind.unilateral =>
            tr3('单方报告结束', 'Бір жақ аяқтады', 'Завершено одной стороной'),
          EndKind.cancelled => tr3('已取消', 'Тоқтатылды', 'Отменено'),
          EndKind.disputed =>
            tr3('争议结束', 'Даулы аяқталды', 'Завершено со спором'),
          _ => tr3('双方确认结束', 'Екі жақ аяқтады', 'Завершено сторонами'),
        },
      CooperationStatus.notFormed => tr3('未成立', 'Жасалмады', 'Не состоялось'),
    };

String materialName(MaterialMode m) => switch (m) {
      MaterialMode.labourOnly => tr3('仅人工', 'Тек жұмыс', 'Только работа'),
      MaterialMode.labourAndMaterial =>
        tr3('包工包料', 'Жұмыс пен материал', 'Работа и материалы'),
      MaterialMode.undecided => tr3('待商定', 'Келісіледі', 'Обсуждается'),
    };

String pricingName(PricingMode p) => switch (p) {
      PricingMode.perQuantity => tr3('按量报价', 'Көлем бойынша', 'По объёму'),
      PricingMode.lumpSum => tr3('总价', 'Жалпы баға', 'Общая сумма'),
      PricingMode.siteConfirm =>
        tr3('需现场确认', 'Орында нақтыланады', 'Уточнить на месте'),
    };

String payModeName(PayMode p) => switch (p) {
      PayMode.daily => tr3('按天', 'Күнделікті', 'Подённо'),
      PayMode.piece => tr3('计件', 'Көлемге қарай', 'Сдельно'),
      PayMode.other => tr3('其他', 'Басқа', 'Другое'),
    };

String settleName(String code) => switch (code) {
      'daily' => tr3('日结', 'Күн сайын', 'Ежедневно'),
      'weekly' => tr3('周结', 'Апта сайын', 'Еженедельно'),
      'monthly' => tr3('月结', 'Ай сайын', 'Ежемесячно'),
      _ => tr3('完工结', 'Біткенде', 'По завершении'),
    };

String scopeKindName(ScopeKind k) => switch (k) {
      ScopeKind.whole => tr3('整栋', 'Толық үй', 'Весь дом'),
      ScopeKind.stages => tr3('施工阶段', 'Кезеңдер', 'Этапы'),
      ScopeKind.custom => tr3('自定义分项', 'Жеке жұмыстар', 'Отдельные работы'),
    };

String qtySourceName(QtySource s) => switch (s) {
      QtySource.design => tr3('来自设计', 'Жобадан', 'Из проекта'),
      QtySource.manual => tr3('手填', 'Қолмен', 'Вручную'),
      QtySource.siteMeasure => tr3('现场测量', 'Орында өлшенеді', 'Замер на месте'),
    };

String availabilityName(ServiceProfile p) => switch (p.availability) {
      Availability.now => tr3('现在可接', 'Қазір бос', 'Свободен сейчас'),
      Availability.fromDate => tr3('${fmtDay(p.availableFrom)} 后可接',
          '${fmtDay(p.availableFrom)} кейін', 'С ${fmtDay(p.availableFrom)}'),
      Availability.notTaking => tr3('暂不接活', 'Қазір алмайды', 'Не берёт заказы'),
    };

String proRoleName(ProRole r) => switch (r) {
      ProRole.worker => tr3('工人', 'Жұмысшы', 'Рабочий'),
      ProRole.contractor => tr3('包工头 / 施工队', 'Мердігер', 'Прораб / бригада'),
      ProRole.engineer => tr3('工程师 / 设计师', 'Инженер', 'Инженер / дизайнер'),
    };

String postTagName(String code) => switch (code) {
      'one_floor' => tr3('一层', 'Бір қабат', 'Один этаж'),
      'two_floors' => tr3('两层', 'Екі қабат', 'Два этажа'),
      'brick' => tr3('砖混', 'Кірпіш', 'Кирпич'),
      'wood' => tr3('木结构', 'Ағаш', 'Дерево'),
      'sip' => tr3('SIP 板', 'SIP', 'SIP-панели'),
      'garage' => tr3('带车库', 'Гараж', 'С гаражом'),
      'budget' => tr3('经济型', 'Үнемді', 'Бюджетный'),
      'large' => tr3('大户型', 'Үлкен', 'Большой'),
      _ => code,
    };

String feedSortName(FeedSort s) => switch (s) {
      FeedSort.newest => tr3('最新', 'Жаңа', 'Новые'),
      FeedSort.popular => tr3('最热', 'Танымал', 'Популярные'),
      FeedSort.topRated => tr3('评分最高', 'Үздік', 'Лучшие'),
    };

String profileKindName(ProfileKind k) => switch (k) {
      ProfileKind.individual => tr3('个人', 'Жеке', 'Частный мастер'),
      ProfileKind.team => tr3('团队', 'Бригада', 'Бригада'),
    };

String outcomeName(OutcomeKind o) => switch (o) {
      OutcomeKind.platformConfirmed =>
        tr3('平台内双方确认合作', 'Платформада расталды', 'Подтверждено на платформе'),
      OutcomeKind.selfReportedYusal =>
        tr3('通过 Yusal 联系成功', 'Yusal арқылы табылды', 'Нашёл через Yusal'),
      OutcomeKind.otherChannel =>
        tr3('通过其他渠道找到', 'Басқа жолмен табылды', 'Нашёл в другом месте'),
      OutcomeKind.notFound => tr3('尚未找到', 'Әлі табылмады', 'Пока не нашёл'),
      OutcomeKind.notNeeded => tr3('暂不需要', 'Қажет емес', 'Больше не нужно'),
    };

String dimensionName(String d) => switch (d) {
      'payment' => tr3('按时付款', 'Уақтылы төлем', 'Оплата вовремя'),
      'scope' => tr3('范围清晰', 'Нақты көлем', 'Понятный объём'),
      'communication' => tr3('沟通', 'Байланыс', 'Общение'),
      'quality' => tr3('施工质量', 'Жұмыс сапасы', 'Качество работ'),
      'time' => tr3('按时完成', 'Уақтылы', 'Сроки'),
      'site' => tr3('现场整洁', 'Таза алаң', 'Порядок на объекте'),
      _ => tr3('施工体验', 'Жұмыс сапасы', 'Качество работы'),
    };

String compareIssueText(CompareIssue i) => switch (i) {
      CompareIssue.versions => tr3(
          '报价依据的需求版本不同，不能直接比较。',
          'Ұсыныстар тапсырыстың әр нұсқасына негізделген.',
          'Предложения основаны на разных версиях заявки.'),
      CompareIssue.materials => tr3(
          '有的仅人工、有的包工包料，价格不能直接比较。',
          'Біреуі тек жұмыс, біреуі материалмен — бағаны тікелей салыстыруға болмайды.',
          'Одни только за работу, другие с материалами — цены несопоставимы.'),
      CompareIssue.siteConfirm => tr3(
          '部分报价需现场确认，还没有确定价格。',
          'Кейбір ұсыныстар орында нақтыланады.',
          'Часть предложений требует замера на месте.'),
      CompareIssue.units => tr3(
          '同一分项使用了不同计价单位。',
          'Бір жұмысқа әр түрлі бірлік қолданылған.',
          'Для одной работы указаны разные единицы.'),
      CompareIssue.outdated => tr3(
          '需求已修改，部分报价待重新确认。',
          'Тапсырыс өзгерді, кейбір ұсыныстар қайта расталуы керек.',
          'Заявка изменилась, часть предложений нужно подтвердить заново.'),
    };

String noticeText(AppNotification n) {
  final t = n.title.isEmpty ? '' : '「${n.title}」';
  return switch (n.kind) {
    NoticeKind.newApplication =>
      tr3('$t 收到新的报名／报价', '$t жаңа өтінім келді', '$t новый отклик'),
    NoticeKind.postLiked =>
      tr3('有人赞了你的房子 $t', '$t үйіңіз ұнады', 'Ваш дом $t понравился'),
    NoticeKind.milestoneRequested => tr3('$t 师傅申请节点验收',
        '$t кезеңді қабылдау сұралды', '$t мастер просит принять этап'),
    NoticeKind.milestoneAnswered => tr3('$t 房主回复了节点验收',
        '$t кезең бойынша жауап', '$t владелец ответил по этапу'),
    NoticeKind.workLogged => tr3('$t 今天的记工已提交，请确认', '$t бүгінгі жұмыс жазылды',
        '$t записан рабочий день, подтвердите'),
    NoticeKind.postReused => tr3(
        '有人用你的房子 $t 开始了自己的设计',
        '$t жобаңыз негізінде жаңа үй басталды',
        'По вашему дому $t начали новый проект'),
    NoticeKind.postCommented =>
      tr3('你的房子 $t 收到新点评', '$t жаңа пікір', 'Новый отзыв о доме $t'),
    NoticeKind.commentReplied =>
      tr3('$t 有人回复了你的点评', '$t пікіріңізге жауап', 'Ответ на ваш отзыв: $t'),
    NoticeKind.commentHelpful => tr3('作者觉得你对 $t 的点评有用',
        '$t авторы пікіріңізді пайдалы деді', 'Автор $t отметил ваш отзыв полезным'),
    NoticeKind.confirmRequest => tr3('$t 对方发起合作约定，请确认', '$t келісімді растаңыз',
        '$t вам предложили соглашение'),
    NoticeKind.cooperationConfirmed => tr3(
        '$t 合作已双方确认', '$t келісім расталды', '$t сотрудничество подтверждено'),
    NoticeKind.cooperationDeclined => tr3(
        '$t 合作未成立', '$t келісім жасалмады', '$t сотрудничество не состоялось'),
    NoticeKind.agreementChange =>
      tr3('$t 合作约定有变更', '$t келісім өзгерді', '$t изменение соглашения'),
    NoticeKind.endRequest =>
      tr3('$t 对方请求结束合作', '$t аяқтау сұралды', '$t запрос на завершение'),
    NoticeKind.ended =>
      tr3('$t 合作已结束', '$t келісім аяқталды', '$t сотрудничество завершено'),
    NoticeKind.reviewReceived =>
      tr3('$t 收到评价，提交你的评价后双方公开', '$t пікір келді', '$t вам оставили отзыв'),
    NoticeKind.demandExpiring =>
      tr3('$t 即将到期', '$t мерзімі бітуде', '$t скоро истекает'),
    NoticeKind.demandExpired =>
      tr3('$t 已到期，可续期或关闭', '$t мерзімі өтті', '$t срок истёк'),
    NoticeKind.outcomeFollowUp => tr3('$t 找到合适的人了吗？', '$t адам таптыңыз ба?',
        '$t удалось найти исполнителя?'),
    NoticeKind.reviewApproved =>
      tr3('$t 已通过审核，开始招募', '$t тексеруден өтті', '$t прошло проверку'),
    NoticeKind.reviewRejected =>
      tr3('$t 审核未通过，请查看原因', '$t қабылданбады', '$t не прошло проверку'),
    NoticeKind.demandChanged => tr3(
        '$t 需求已修改，请重新确认你的报名／报价', '$t тапсырыс өзгерді', '$t заявка изменилась'),
    NoticeKind.applicationNotSelected =>
      tr3('$t 发布者暂未选用你的报名', '$t сіз таңдалмадыңыз', '$t ваш отклик не выбран'),
  };
}

String failureText(Object e) {
  if (e is! ApiFailure)
    return tr3('出了点问题，请重试', 'Қате шықты, қайталаңыз', 'Что-то пошло не так');
  return switch (e.code) {
    ApiCodes.notSignedIn => tr3('请先登录', 'Алдымен кіріңіз', 'Сначала войдите'),
    ApiCodes.badCode => tr3('验证码不正确', 'Код қате', 'Неверный код'),
    ApiCodes.badPhone =>
      tr3('请输入完整手机号', 'Толық нөмірді енгізіңіз', 'Введите полный номер'),
    ApiCodes.forbidden => tr3('没有权限进行这个操作', 'Рұқсат жоқ', 'Нет доступа'),
    ApiCodes.notFound =>
      tr3('内容不存在或已下架', 'Табылмады не алынып тасталды', 'Не найдено или снято'),
    ApiCodes.invalidState => tr3('当前状态不能进行这个操作，请刷新', 'Қазіргі күйде болмайды',
        'Сейчас это действие недоступно'),
    ApiCodes.invalidInput =>
      tr3('请检查填写内容', 'Толтыруды тексеріңіз', 'Проверьте заполнение'),
    ApiCodes.notAccepting => tr3('这个需求暂不接收新的报名／报价',
        'Бұл тапсырыс жаңа өтінім қабылдамайды', 'Заявка не принимает отклики'),
    ApiCodes.ownDemand => tr3(
        '不能报名自己发布的需求',
        'Өз тапсырысыңызға өтінім беруге болмайды',
        'Нельзя откликнуться на свою заявку'),
    ApiCodes.blocked =>
      tr3('你们之间已拉黑，无法联系', 'Бұғатталған', 'Связь заблокирована'),
    ApiCodes.rateLimited =>
      tr3('发送太频繁，请稍后再试', 'Тым жиі, кейінірек', 'Слишком часто, подождите'),
    ApiCodes.network =>
      tr3('网络不可用，请稍后重试', 'Желі жоқ, кейінірек', 'Нет сети, повторите позже'),
    ApiCodes.restricted =>
      tr3('账号受限，暂时不能发布或联系', 'Аккаунт шектелген', 'Аккаунт ограничен'),
    ApiCodes.conflict => tr3(
        '云端备份在别处被修改，请选择保留哪个版本',
        'Бұлттағы көшірме басқа жерде өзгерді',
        'Копия в облаке изменена в другом месте'),
    _ => tr3('出了点问题，请重试', 'Қате шықты', 'Что-то пошло не так'),
  };
}

/// 1250000 → "1 250 000 ₸".
String money(num? value, {String unit = 'total'}) {
  if (value == null) return '—';
  final digits = value.round().abs().toString();
  final b = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
    b.write(digits[i]);
  }
  return '$b ₸${perUnit(unit)}';
}

String budgetText(Budget b) => switch (b.mode) {
      BudgetMode.fixed => money(b.amount, unit: b.basis),
      BudgetMode.range =>
        '${money(b.min).replaceAll(' ₸', '')} – ${money(b.max, unit: b.basis)}',
      BudgetMode.askQuote => tr3('请报价', 'Баға ұсыныңыз', 'Ждём предложений'),
    };

String fmtDay(DateTime? d) {
  if (d == null) return tr3('待协商', 'Келісіледі', 'По договорённости');
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String fmtTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

/// "3 天前" style age.
String ago(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return tr3('刚刚', 'жаңа ғана', 'только что');
  if (d.inHours < 1)
    return tr3('${d.inMinutes} 分钟前', '${d.inMinutes} мин бұрын',
        '${d.inMinutes} мин назад');
  if (d.inDays < 1)
    return tr3(
        '${d.inHours} 小时前', '${d.inHours} сағ бұрын', '${d.inHours} ч назад');
  return tr3(
      '${d.inDays} 天前', '${d.inDays} күн бұрын', '${d.inDays} дн. назад');
}

String numText(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

String deletedName(Account? a) => a == null || a.deleted
    ? tr3('已注销用户', 'Жойылған пайдаланушы', 'Удалённый пользователь')
    : a.displayName;

/// Inspection points: foundation, walls, roof, finish.
String milestoneName(String key) => switch (key) {
      'foundation' => tr3('基础', 'Іргетас', 'Фундамент'),
      'walls' => tr3('主体', 'Қабырғалар', 'Стены'),
      'roof' => tr3('屋顶', 'Шатыр', 'Кровля'),
      'finish' => tr3('完工', 'Аяқтау', 'Сдача'),
      final k when k.startsWith('c:') => k.substring(2),
      final k => k,
    };

/// What the owner checks at each point, unless the agreement says more.
String milestoneCriteria(String key) => switch (key) {
      'foundation' => tr3(
          '尺寸与图纸一致、养护满 7 天',
          'Өлшемдер сызбаға сай, 7 күн күтім',
          'Размеры по чертежу, уход 7 дней'),
      'walls' =>
        tr3('墙体到顶、过梁就位', 'Қабырғалар тұрғызылды', 'Стены до верха, перемычки'),
      'roof' =>
        tr3('封顶、防水完成', 'Шатыр мен гидрооқшаулау', 'Кровля и гидроизоляция'),
      'finish' => tr3('清理完毕、双方确认', 'Тазаланды, екі жақ растады',
          'Уборка, подтверждение сторон'),
      _ => '',
    };

String milestoneStatusName(MilestoneStatus s) => switch (s) {
      MilestoneStatus.planned => tr3('未开始', 'Басталмады', 'Не начат'),
      MilestoneStatus.requested =>
        tr3('待验收', 'Қабылдау күтілуде', 'Ждёт приёмки'),
      MilestoneStatus.accepted => tr3('已验收', 'Қабылданды', 'Принят'),
      MilestoneStatus.disputed => tr3('有问题', 'Ескерту бар', 'Есть замечания'),
    };

String feedbackTopicName(String k) => switch (k) {
      'layout' => tr3('布局', 'Жоспар', 'Планировка'),
      'light' => tr3('采光朝向', 'Жарық', 'Свет и ориентация'),
      'cost' => tr3('造价', 'Құны', 'Стоимость'),
      'structure' => tr3('结构', 'Құрылым', 'Конструкция'),
      'look' => tr3('外观', 'Сыртқы түрі', 'Внешний вид'),
      'warmth' => tr3('保暖', 'Жылу', 'Утепление'),
      _ => k,
    };
