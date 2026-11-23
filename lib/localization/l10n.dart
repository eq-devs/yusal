import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/service/api/api_failure.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/model/rules.dart';

/// Names of codes and common words of the platform in Chinese, Kazakh and
/// Russian.

String tradeName(String code) => switch (code) {
      'mason' => tr3('瓦工／砌墙', 'Қалаушы', 'Каменщик', 'Mason'),
      'concrete' => tr3('混凝土工', 'Бетоншы', 'Бетонщик', 'Concrete worker'),
      'rebar' => tr3('钢筋工', 'Арматурашы', 'Арматурщик', 'Rebar worker'),
      'carpenter' => tr3('木工／模板', 'Ағаш ұстасы', 'Плотник', 'Carpenter'),
      'roofer' => tr3('屋面', 'Шатыршы', 'Кровельщик', 'Roofer'),
      'electrician' => tr3('电工', 'Электрик', 'Электрик', 'Electrician'),
      'plumber' => tr3('水暖工', 'Сантехник', 'Сантехник', 'Plumber'),
      'welder' => tr3('焊工', 'Дәнекерлеуші', 'Сварщик', 'Welder'),
      'plasterer' => tr3('抹灰／装修', 'Сылақшы', 'Штукатур', 'Plasterer'),
      'tiler' => tr3('瓷砖', 'Плиткашы', 'Плиточник', 'Tiler'),
      'laborer' => tr3('小工／杂工', 'Көмекші жұмысшы', 'Разнорабочий', 'Labourer'),
      'general' => tr3('整体施工', 'Толық құрылыс', 'Генподряд', 'General contractor'),
      _ => code,
    };

String regionName(String code) => switch (code) {
      'almaty' => tr3('阿拉木图', 'Алматы', 'Алматы', 'Almaty'),
      'talgar' => tr3('塔尔加尔', 'Талғар', 'Талгар', 'Talgar'),
      'kaskelen' => tr3('卡斯克连', 'Қаскелең', 'Каскелен', 'Kaskelen'),
      'esik' => tr3('伊塞克', 'Есік', 'Есик', 'Esik'),
      'konaev' => tr3('科纳耶夫', 'Қонаев', 'Конаев', 'Konaev'),
      'otegen' => tr3('乌特根巴特尔', 'Өтеген батыр', 'Отеген батыр', 'Otegen Batyr'),
      '' => '',
      _ => code,
    };

/// "Талгар · северная часть": the region and the place inside it, once.
/// People often start the place with the town's own name ("Талгар, северная
/// часть", or just "Есик"); then it is not printed a second time.
String placeText(String region, String locality) {
  final r = regionName(region);
  final l = locality.trim();
  if (l.isEmpty) return r;
  if (r.isEmpty || l.toLowerCase().startsWith(r.toLowerCase())) return l;
  return '$r · $l';
}

/// Square and cubic metres: Cyrillic "м" outside Chinese.
String get sqm => isKk ? 'м²' : 'm²';
String get sqm3 => isKk ? 'м³' : 'm³';

String unitLabel(String code) => switch (code) {
      'total' => tr3('总价', 'жалпы', 'итого', 'total'),
      'day' => tr3('天', 'күн', 'день', 'day'),
      'm3' => sqm3,
      'm2' => sqm,
      'm' => tr3('米', 'м', 'м', 'm'),
      'pcs' => tr3('个', 'дана', 'шт.', 'pcs'),
      't' => tr3('吨', 'т', 'т', 't'),
      'hour' => tr3('小时', 'сағ', 'час', 'hour'),
      _ => code,
    };

/// "per m³" style suffix; empty for totals.
String perUnit(String code) => code == 'total' ? '' : ' / ${unitLabel(code)}';

String stageLabel(String code) => switch (code) {
      'found' => tr3('基础', 'Іргетас', 'Фундамент', 'Foundation'),
      'walls' => tr3('墙体与楼板', 'Қабырға және плита', 'Стены и перекрытия', 'Walls and floors'),
      'roof' => tr3('屋顶', 'Шатыр', 'Кровля', 'Roofing'),
      'openings' => tr3('门窗', 'Есік-терезе', 'Окна и двери', 'Windows and doors'),
      'mep' => tr3('水电暖', 'Су, электр, жылу', 'Инженерные сети', 'Utilities'),
      'finish' => tr3('地面与装修', 'Еден және әрлеу', 'Полы и отделка', 'Floors and finishes'),
      'site' => tr3('院子与附属', 'Аула', 'Участок', 'Site'),
      _ => tr3('其他', 'Басқа', 'Другое', 'Other'),
    };

String demandTypeName(DemandType t) => switch (t) {
      DemandType.hire => tr3('招人干活', 'Жұмысшы іздеу', 'Найм рабочих', 'Hiring workers'),
      DemandType.contract => tr3('找人承包', 'Мердігер іздеу', 'Подряд', 'Contract'),
    };

String demandStatusName(DemandStatus s) => switch (s) {
      DemandStatus.draft => tr3('草稿', 'Жоба', 'Черновик', 'Draft'),
      DemandStatus.pendingReview => tr3('待审核', 'Тексерілуде', 'На проверке', 'Under review'),
      DemandStatus.open => tr3('招募中', 'Қабылдануда', 'Идёт набор', 'Hiring'),
      DemandStatus.paused => tr3('暂停', 'Тоқтатылған', 'Пауза', 'Paused'),
      DemandStatus.found => tr3('已找到人', 'Адам табылды', 'Исполнитель найден', 'Someone was found'),
      DemandStatus.expired => tr3('已到期', 'Мерзімі өтті', 'Истекло', 'Expired'),
      DemandStatus.closed => tr3('已关闭', 'Жабылды', 'Закрыто', 'Closed'),
      DemandStatus.rejected =>
        tr3('审核未通过／下架', 'Қабылданбады', 'Отклонено / снято', 'Rejected / taken down'),
    };

String applicationStatusName(ApplicationStatus s) => switch (s) {
      ApplicationStatus.submitted => tr3('已提交', 'Жіберілді', 'Отправлено', 'Sent'),
      ApplicationStatus.withdrawn => tr3('已撤回', 'Қайтарылды', 'Отозвано', 'Withdrawn'),
      ApplicationStatus.notSelected => tr3('未选用', 'Таңдалмады', 'Не выбрано', 'Not chosen'),
      ApplicationStatus.pendingConfirm =>
        tr3('待对方确认', 'Растауды күтуде', 'Ждёт подтверждения', 'Awaiting confirmation'),
      ApplicationStatus.cooperating =>
        tr3('已形成合作', 'Келісім жасалды', 'Сотрудничество', 'Cooperation'),
    };

String cooperationStatusName(Cooperation c) => switch (c.status) {
      CooperationStatus.pending =>
        tr3('待双方确认', 'Екі жақ растауын күтуде', 'Ждёт подтверждения сторон', 'Awaiting both sides'),
      CooperationStatus.confirmed => switch (c.endPhase) {
          EndPhase.none => tr3('已确认合作', 'Келісім расталды', 'Подтверждено', 'Confirmed'),
          EndPhase.disputed =>
            tr3('结束有异议', 'Аяқтауға қарсылық', 'Спор о завершении', 'Completion disputed'),
          EndPhase.asked =>
            tr3('结束待确认', 'Аяқтау расталуда', 'Завершение ждёт ответа', 'Completion awaiting reply'),
        },
      CooperationStatus.ended => switch (c.endKind) {
          EndKind.unilateral =>
            tr3('单方报告结束', 'Бір жақ аяқтады', 'Завершено одной стороной', 'Finished by one side'),
          EndKind.cancelled => tr3('已取消', 'Тоқтатылды', 'Отменено', 'Cancelled'),
          EndKind.disputed =>
            tr3('争议结束', 'Даулы аяқталды', 'Завершено со спором', 'Finished with a dispute'),
          _ => tr3('双方确认结束', 'Екі жақ аяқтады', 'Завершено сторонами', 'Finished by both sides'),
        },
      CooperationStatus.notFormed => tr3('未成立', 'Жасалмады', 'Не состоялось', "Didn't happen"),
    };

String materialName(MaterialMode m) => switch (m) {
      MaterialMode.labourOnly => tr3('仅人工', 'Тек жұмыс', 'Только работа', 'Labour only'),
      MaterialMode.labourAndMaterial =>
        tr3('包工包料', 'Жұмыс пен материал', 'Работа и материалы', 'Labour and materials'),
      MaterialMode.undecided => tr3('待商定', 'Келісіледі', 'Обсуждается', 'To be agreed'),
    };

String pricingName(PricingMode p) => switch (p) {
      PricingMode.perQuantity => tr3('按量报价', 'Көлем бойынша', 'По объёму', 'By quantity'),
      PricingMode.lumpSum => tr3('总价', 'Жалпы баға', 'Общая сумма', 'Lump sum'),
      PricingMode.siteConfirm =>
        tr3('需现场确认', 'Орында нақтыланады', 'Уточнить на месте', 'Confirm on site'),
    };

String payModeName(PayMode p) => switch (p) {
      PayMode.daily => tr3('按天', 'Күнделікті', 'Подённо', 'By the day'),
      PayMode.piece => tr3('计件', 'Көлемге қарай', 'Сдельно', 'Piecework'),
      PayMode.other => tr3('其他', 'Басқа', 'Другое', 'Other'),
    };

String settleName(String code) => switch (code) {
      'daily' => tr3('日结', 'Күн сайын', 'Ежедневно', 'Daily'),
      'weekly' => tr3('周结', 'Апта сайын', 'Еженедельно', 'Weekly'),
      'monthly' => tr3('月结', 'Ай сайын', 'Ежемесячно', 'Monthly'),
      _ => tr3('完工结', 'Біткенде', 'По завершении', 'On completion'),
    };

String scopeKindName(ScopeKind k) => switch (k) {
      ScopeKind.whole => tr3('整栋', 'Толық үй', 'Весь дом', 'Whole house'),
      ScopeKind.stages => tr3('施工阶段', 'Кезеңдер', 'Этапы', 'Stages'),
      ScopeKind.custom => tr3('自定义分项', 'Жеке жұмыстар', 'Отдельные работы', 'Separate jobs'),
    };

String qtySourceName(QtySource s) => switch (s) {
      QtySource.design => tr3('来自设计', 'Жобадан', 'Из проекта', 'From a design'),
      QtySource.manual => tr3('手填', 'Қолмен', 'Вручную', 'By hand'),
      QtySource.siteMeasure => tr3('现场测量', 'Орында өлшенеді', 'Замер на месте', 'On-site measure'),
    };

String availabilityName(ServiceProfile p) => switch (p.availability) {
      Availability.now => tr3('现在可接', 'Қазір бос', 'Свободен сейчас', 'Available now'),
      Availability.fromDate => tr3('${fmtDay(p.availableFrom)} 后可接',
          '${fmtDay(p.availableFrom)} кейін', 'С ${fmtDay(p.availableFrom)}', 'From ${fmtDay(p.availableFrom)}'),
      Availability.notTaking => tr3('暂不接活', 'Қазір алмайды', 'Не берёт заказы', 'Not taking orders'),
    };

String proRoleName(ProRole r) => switch (r) {
      ProRole.worker => tr3('工人', 'Жұмысшы', 'Рабочий', 'Worker'),
      ProRole.contractor => tr3('包工头 / 施工队', 'Мердігер', 'Прораб / бригада', 'Foreman / crew'),
      ProRole.engineer => tr3('工程师 / 设计师', 'Инженер', 'Инженер / дизайнер', 'Engineer / designer'),
    };

String postTagName(String code) => switch (code) {
      'one_floor' => tr3('一层', 'Бір қабат', 'Один этаж', 'One floor'),
      'two_floors' => tr3('两层', 'Екі қабат', 'Два этажа', 'Two floors'),
      'brick' => tr3('砖混', 'Кірпіш', 'Кирпич', 'Brick'),
      'wood' => tr3('木结构', 'Ағаш', 'Дерево', 'Timber'),
      'sip' => tr3('SIP 板', 'SIP', 'SIP-панели', 'SIP panels'),
      'garage' => tr3('带车库', 'Гараж', 'С гаражом', 'With a garage'),
      'budget' => tr3('经济型', 'Үнемді', 'Бюджетный', 'Budget'),
      'large' => tr3('大户型', 'Үлкен', 'Большой', 'Large'),
      _ => code,
    };

String feedSortName(FeedSort s) => switch (s) {
      FeedSort.newest => tr3('最新', 'Жаңа', 'Новые', 'Newest'),
      FeedSort.popular => tr3('最热', 'Танымал', 'Популярные', 'Popular'),
      FeedSort.topRated => tr3('评分最高', 'Үздік', 'Лучшие', 'Top rated'),
    };

String profileKindName(ProfileKind k) => switch (k) {
      ProfileKind.individual => tr3('个人', 'Жеке', 'Частный мастер', 'Independent pro'),
      ProfileKind.team => tr3('团队', 'Бригада', 'Бригада', 'Crew'),
    };

String outcomeName(OutcomeKind o) => switch (o) {
      OutcomeKind.platformConfirmed =>
        tr3('平台内双方确认合作', 'Платформада расталды', 'Подтверждено на платформе', 'Confirmed on the platform'),
      OutcomeKind.selfReportedYusal =>
        tr3('通过 Yusal 联系成功', 'Yusal арқылы табылды', 'Нашёл через Yusal', 'Found through Yusal'),
      OutcomeKind.otherChannel =>
        tr3('通过其他渠道找到', 'Басқа жолмен табылды', 'Нашёл в другом месте', 'Found elsewhere'),
      OutcomeKind.notFound => tr3('尚未找到', 'Әлі табылмады', 'Пока не нашёл', 'Not found yet'),
      OutcomeKind.notNeeded => tr3('暂不需要', 'Қажет емес', 'Больше не нужно', 'No longer needed'),
    };

String dimensionName(String d) => switch (d) {
      'payment' => tr3('按时付款', 'Уақтылы төлем', 'Оплата вовремя', 'Pays on time'),
      'scope' => tr3('范围清晰', 'Нақты көлем', 'Понятный объём', 'Clear scope'),
      'communication' => tr3('沟通', 'Байланыс', 'Общение', 'Communication'),
      'quality' => tr3('施工质量', 'Жұмыс сапасы', 'Качество работ', 'Work quality'),
      'time' => tr3('按时完成', 'Уақтылы', 'Сроки', 'Timeliness'),
      'site' => tr3('现场整洁', 'Таза алаң', 'Порядок на объекте', 'Tidy site'),
      _ => tr3('施工体验', 'Жұмыс сапасы', 'Качество работы', 'Quality of work'),
    };

String compareIssueText(CompareIssue i) => switch (i) {
      CompareIssue.versions => tr3(
          '报价依据的需求版本不同，不能直接比较。',
          'Ұсыныстар тапсырыстың әр нұсқасына негізделген.',
          'Предложения основаны на разных версиях заявки.',
          'The quotes are based on different versions of the request.'),
      CompareIssue.materials => tr3(
          '有的仅人工、有的包工包料，价格不能直接比较。',
          'Біреуі тек жұмыс, біреуі материалмен — бағаны тікелей салыстыруға болмайды.',
          'Одни только за работу, другие с материалами — цены несопоставимы.',
          "Some are labour only, others include materials; the prices aren't comparable."),
      CompareIssue.siteConfirm => tr3(
          '部分报价需现场确认，还没有确定价格。',
          'Кейбір ұсыныстар орында нақтыланады.',
          'Часть предложений требует замера на месте.',
          'Some quotes need an on-site measure.'),
      CompareIssue.units => tr3(
          '同一分项使用了不同计价单位。',
          'Бір жұмысқа әр түрлі бірлік қолданылған.',
          'Для одной работы указаны разные единицы.',
          'Different units are given for the same job.'),
      CompareIssue.outdated => tr3(
          '需求已修改，部分报价待重新确认。',
          'Тапсырыс өзгерді, кейбір ұсыныстар қайта расталуы керек.',
          'Заявка изменилась, часть предложений нужно подтвердить заново.',
          'The request changed; some quotes need to be confirmed again.'),
    };

String noticeText(AppNotification n) {
  final t = n.title.isEmpty
      ? ''
      : appLang == AppLang.zh
          ? '「${n.title}」'
          : '“${n.title}”';
  return switch (n.kind) {
    NoticeKind.newApplication =>
      tr3('$t 收到新的报名／报价', '$t жаңа өтінім келді', '$t новый отклик', 'New response $t'),
    NoticeKind.postLiked =>
      tr3('有人赞了你的房子 $t', '$t үйіңіз ұнады', 'Ваш дом $t понравился', 'Someone liked your house $t'),
    NoticeKind.milestoneRequested => tr3('$t 师傅申请节点验收',
        '$t кезеңді қабылдау сұралды', '$t мастер просит принять этап', '$t: the pro asks you to accept a stage'),
    NoticeKind.milestoneAnswered => tr3('$t 房主回复了节点验收',
        '$t кезең бойынша жауап', '$t владелец ответил по этапу', '$t: the owner replied about the stage'),
    NoticeKind.workLogged => tr3('$t 今天的记工已提交，请确认', '$t бүгінгі жұмыс жазылды',
        '$t записан рабочий день, подтвердите',
        "$t: today's work day was logged; please confirm"),
    NoticeKind.postReused => tr3(
        '有人用你的房子 $t 开始了自己的设计',
        '$t жобаңыз негізінде жаңа үй басталды',
        'По вашему дому $t начали новый проект',
        'Someone started a design from your house $t'),
    NoticeKind.postCommented =>
      tr3('你的房子 $t 收到新点评', '$t жаңа пікір', 'Новый отзыв о доме $t', 'New review of your house $t'),
    NoticeKind.commentReplied =>
      tr3('$t 有人回复了你的点评', '$t пікіріңізге жауап', 'Ответ на ваш отзыв: $t', '$t: someone replied to your review'),
    NoticeKind.commentHelpful => tr3(
        '作者觉得你对 $t 的点评有用',
        '$t авторы пікіріңізді пайдалы деді',
        'Автор $t отметил ваш отзыв полезным',
        'The author of $t found your review helpful'),
    NoticeKind.confirmRequest => tr3('$t 对方发起合作约定，请确认', '$t келісімді растаңыз',
        '$t вам предложили соглашение',
        "$t: you've been offered an agreement; please confirm"),
    NoticeKind.cooperationConfirmed => tr3(
        '$t 合作已双方确认', '$t келісім расталды', '$t сотрудничество подтверждено', '$t: cooperation confirmed by both sides'),
    NoticeKind.cooperationDeclined => tr3(
        '$t 合作未成立', '$t келісім жасалмады', '$t сотрудничество не состоялось', "$t: the cooperation didn't happen"),
    NoticeKind.agreementChange =>
      tr3('$t 合作约定有变更', '$t келісім өзгерді', '$t изменение соглашения', '$t: the agreement changed'),
    NoticeKind.endRequest =>
      tr3('$t 对方请求结束合作', '$t аяқтау сұралды', '$t запрос на завершение', '$t: the other side asks to finish'),
    NoticeKind.ended =>
      tr3('$t 合作已结束', '$t келісім аяқталды', '$t сотрудничество завершено', '$t: cooperation finished'),
    NoticeKind.reviewReceived =>
      tr3('$t 收到评价，提交你的评价后双方公开', '$t пікір келді', '$t вам оставили отзыв', '$t: you got a review; post yours and both go public'),
    NoticeKind.demandExpiring =>
      tr3('$t 即将到期', '$t мерзімі бітуде', '$t скоро истекает', '$t expires soon'),
    NoticeKind.demandExpired =>
      tr3('$t 已到期，可续期或关闭', '$t мерзімі өтті', '$t срок истёк', '$t has expired; extend or close it'),
    NoticeKind.outcomeFollowUp => tr3('$t 找到合适的人了吗？', '$t адам таптыңыз ба?',
        '$t удалось найти исполнителя?',
        '$t: did you find the right person?'),
    NoticeKind.reviewApproved =>
      tr3('$t 已通过审核，开始招募', '$t тексеруден өтті', '$t прошло проверку', '$t passed review; hiring has started'),
    NoticeKind.reviewRejected =>
      tr3('$t 审核未通过，请查看原因', '$t қабылданбады', '$t не прошло проверку', "$t didn't pass review; see the reason"),
    NoticeKind.demandChanged => tr3(
        '$t 需求已修改，请重新确认你的报名／报价', '$t тапсырыс өзгерді', '$t заявка изменилась', '$t: the request changed; please confirm your response again'),
    NoticeKind.applicationNotSelected =>
      tr3('$t 发布者暂未选用你的报名', '$t сіз таңдалмадыңыз', '$t ваш отклик не выбран', "$t: the poster didn't choose your response"),
    NoticeKind.contentRemoved => tr3(
        '$t 因违反社区规范被处理，可申诉',
        '$t ереже бұзғаны үшін алынды, шағым беруге болады',
        '$t снято за нарушение правил, можно обжаловать',
        '$t was taken down for breaking the rules; you can appeal'),
    NoticeKind.reportResolved => tr3(
        '你对 $t 的举报已处理，谢谢',
        '$t шағымыңыз қаралды, рақмет',
        'Ваша жалоба на $t рассмотрена, спасибо',
        'Your report about $t was handled, thank you'),
    NoticeKind.accountRestricted => tr3(
        '你的账号已被限制发布与联系，可申诉',
        'Аккаунтыңыз шектелді, шағым беруге болады',
        'Ваш аккаунт ограничен, можно обжаловать',
        'Your account is restricted from posting and contacting; you can appeal'),
    NoticeKind.accountRestored => tr3('你的账号已恢复正常', 'Аккаунтыңыз қалпына келді',
        'Ограничения с аккаунта сняты',
        'Your account is back to normal'),
    NoticeKind.appealAnswered => tr3('你对 $t 的申诉有了结果',
        '$t шағымыңызға жауап келді', 'Есть ответ на ваше обжалование $t', 'Your appeal about $t has a result'),
    NoticeKind.verificationApproved =>
      tr3('$t 已通过实名核验', '$t тексеруден өтті', '$t прошёл проверку', '$t passed identity verification'),
    NoticeKind.verificationRejected => tr3(
        '$t 核验未通过，请查看原因',
        '$t тексеруден өтпеді, себебін қараңыз',
        '$t не прошёл проверку, см. причину',
        "$t didn't pass verification; see the reason"),
    NoticeKind.newDemandMatch => tr3('有符合你订阅条件的新需求 $t',
        'Сізге сай жаңа тапсырыс: $t', 'Новая заявка по вашей подписке: $t', 'New request matching your subscription: $t'),
  };
}

String reasonCodeText(String code) => switch (code) {
      'contact' => tr3('正文包含联系方式，请通过平台沟通', 'Мәтінде байланыс деректері бар',
          'В тексте есть контакты, общайтесь через приложение',
          'The text has contacts; talk through the app'),
      'fake' =>
        tr3('信息不真实或无法核实', 'Ақпарат шынайы емес', 'Недостоверная информация', 'False information'),
      'illegal' =>
        tr3('包含违规内容', 'Ережеге қайшы мазмұн', 'Запрещённое содержание', 'Prohibited content'),
      'incomplete' => tr3('信息不完整，请补充地点、范围和预算', 'Ақпарат толық емес',
          'Не хватает данных: место, объём, бюджет',
          'Missing details: place, scope, budget'),
      'duplicate' =>
        tr3('重复发布', 'Қайталанған жарияланым', 'Повторная публикация', 'Duplicate post'),
      'abuse' =>
        tr3('辱骂、骚扰或歧视', 'Балағат не қудалау', 'Оскорбления или преследование', 'Abuse or harassment'),
      'spam' => tr3('广告或引流', 'Жарнама не спам', 'Реклама или спам', 'Advertising or spam'),
      'ok' => tr3(
          '经核查未发现问题', 'Тексеруде бұзушылық табылмады', 'Нарушений не найдено', 'No violation found'),
      _ => code,
    };

/// A reason as the reader should see it: preset codes are translated.
String reasonText(String reason) =>
    reason.startsWith('code:') ? reasonCodeText(reason.substring(5)) : reason;

String failureText(Object e) {
  if (e is! ApiFailure) {
    return tr3('出了点问题，请重试', 'Қате шықты, қайталаңыз', 'Что-то пошло не так', 'Something went wrong');
  }
  return switch (e.code) {
    ApiCodes.notSignedIn => tr3('请先登录', 'Алдымен кіріңіз', 'Сначала войдите', 'Sign in first'),
    ApiCodes.badCode => tr3('验证码不正确', 'Код қате', 'Неверный код', 'Wrong code'),
    ApiCodes.badPhone =>
      tr3('请输入完整手机号', 'Толық нөмірді енгізіңіз', 'Введите полный номер', 'Enter the full number'),
    ApiCodes.forbidden => tr3('没有权限进行这个操作', 'Рұқсат жоқ', 'Нет доступа', 'No access'),
    ApiCodes.notFound =>
      tr3('内容不存在或已下架', 'Табылмады не алынып тасталды', 'Не найдено или снято', 'Not found or taken down'),
    ApiCodes.invalidState => tr3('当前状态不能进行这个操作，请刷新', 'Қазіргі күйде болмайды',
        'Сейчас это действие недоступно',
        "This action isn't available right now"),
    ApiCodes.invalidInput =>
      tr3('请检查填写内容', 'Толтыруды тексеріңіз', 'Проверьте заполнение', 'Check the form'),
    ApiCodes.notAccepting => tr3('这个需求暂不接收新的报名／报价',
        'Бұл тапсырыс жаңа өтінім қабылдамайды', 'Заявка не принимает отклики', "The request isn't accepting responses"),
    ApiCodes.ownDemand => tr3(
        '不能报名自己发布的需求',
        'Өз тапсырысыңызға өтінім беруге болмайды',
        'Нельзя откликнуться на свою заявку',
        "You can't respond to your own request"),
    ApiCodes.blocked =>
      tr3('你们之间已拉黑，无法联系', 'Бұғатталған', 'Связь заблокирована', 'Contact blocked'),
    ApiCodes.rateLimited =>
      tr3('发送太频繁，请稍后再试', 'Тым жиі, кейінірек', 'Слишком часто, подождите', 'Too often; please wait'),
    ApiCodes.network =>
      tr3('网络不可用，请稍后重试', 'Желі жоқ, кейінірек', 'Нет сети, повторите позже', 'No network; try again later'),
    ApiCodes.restricted =>
      tr3('账号受限，暂时不能发布或联系', 'Аккаунт шектелген', 'Аккаунт ограничен', 'Account restricted'),
    ApiCodes.conflict => tr3(
        '云端备份在别处被修改，请选择保留哪个版本',
        'Бұлттағы көшірме басқа жерде өзгерді',
        'Копия в облаке изменена в другом месте',
        'The cloud copy was changed elsewhere'),
    ApiCodes.emailTaken => tr3('这个邮箱已注册，请直接登录', 'Бұл пошта тіркелген, кіріңіз',
        'Эта почта уже зарегистрирована, войдите',
        'This email is already registered; sign in'),
    ApiCodes.badCredentials =>
      tr3('邮箱或密码不正确', 'Пошта не құпиясөз қате', 'Неверная почта или пароль', 'Wrong email or password'),
    ApiCodes.providerTaken => tr3(
        '这个账号已经绑定在另一个 Yusal 账号上',
        'Бұл кіру басқа Yusal аккаунтына тіркелген',
        'Этот вход уже привязан к другому аккаунту Yusal',
        'This sign-in is already linked to another Yusal account'),
    ApiCodes.providerLinked => tr3(
        '已经绑定了同类账号，请先解绑',
        'Осы түрі қосылған, алдымен ажыратыңыз',
        'Такой вход уже привязан, сначала отвяжите',
        'This sign-in is already linked; unlink it first'),
    ApiCodes.lastMethod => tr3(
        '至少要保留一种登录方式',
        'Кемінде бір кіру тәсілі қалуы керек',
        'Должен остаться хотя бы один способ входа',
        'At least one sign-in method must remain'),
    ApiCodes.noEmail => tr3('账号没有邮箱，无法设置密码', 'Аккаунтта пошта жоқ',
        'У аккаунта нет почты для пароля',
        'The account has no email for a password'),
    _ => tr3('出了点问题，请重试', 'Қате шықты', 'Что-то пошло не так', 'Something went wrong'),
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
      BudgetMode.askQuote => tr3('请报价', 'Баға ұсыныңыз', 'Ждём предложений', 'Waiting for quotes'),
    };

String fmtDay(DateTime? d) {
  if (d == null) return tr3('待协商', 'Келісіледі', 'По договорённости', 'By agreement');
  String two(int n) => n.toString().padLeft(2, '0');
  // Day first, as dates are written in Kazakhstan.
  if (isWestern) return '${two(d.day)}.${two(d.month)}.${d.year}';
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

String fmtTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.hour)}:${two(d.minute)}';
}

/// "3 天前" style age.
String ago(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return tr3('刚刚', 'жаңа ғана', 'только что', 'just now');
  if (d.inHours < 1) {
    return tr3('${d.inMinutes} 分钟前', '${d.inMinutes} мин бұрын',
        '${d.inMinutes} мин назад',
        '${d.inMinutes} min ago');
  }
  if (d.inDays < 1) {
    return tr3(
        '${d.inHours} 小时前', '${d.inHours} сағ бұрын', '${d.inHours} ч назад', '${d.inHours} h ago');
  }
  return tr3(
      '${d.inDays} 天前', '${d.inDays} күн бұрын', '${d.inDays} дн. назад', '${d.inDays} d ago');
}

String numText(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(2);

String deletedName(Account? a) => a == null || a.deleted
    ? tr3('已注销用户', 'Жойылған пайдаланушы', 'Удалённый пользователь', 'Deleted user')
    : a.displayName;

/// Inspection points: foundation, walls, roof, finish.
String milestoneName(String key) => switch (key) {
      'foundation' => tr3('基础', 'Іргетас', 'Фундамент', 'Foundation'),
      'walls' => tr3('主体', 'Қабырғалар', 'Стены', 'Walls'),
      'roof' => tr3('屋顶', 'Шатыр', 'Кровля', 'Roofing'),
      'finish' => tr3('完工', 'Аяқтау', 'Сдача', 'Handover'),
      final k when k.startsWith('c:') => k.substring(2),
      final k => k,
    };

/// What the owner checks at each point, unless the agreement says more.
String milestoneCriteria(String key) => switch (key) {
      'foundation' => tr3(
          '尺寸与图纸一致、养护满 7 天',
          'Өлшемдер сызбаға сай, 7 күн күтім',
          'Размеры по чертежу, уход 7 дней',
          'Dimensions as drawn, 7 days curing'),
      'walls' =>
        tr3('墙体到顶、过梁就位', 'Қабырғалар тұрғызылды', 'Стены до верха, перемычки', 'Walls to the top, lintels'),
      'roof' =>
        tr3('封顶、防水完成', 'Шатыр мен гидрооқшаулау', 'Кровля и гидроизоляция', 'Roof and waterproofing'),
      'finish' => tr3('清理完毕、双方确认', 'Тазаланды, екі жақ растады',
          'Уборка, подтверждение сторон',
          'Cleanup, both sides confirm'),
      _ => '',
    };

String milestoneStatusName(MilestoneStatus s) => switch (s) {
      MilestoneStatus.planned => tr3('未开始', 'Басталмады', 'Не начат', 'Not started'),
      MilestoneStatus.requested =>
        tr3('待验收', 'Қабылдау күтілуде', 'Ждёт приёмки', 'Awaiting acceptance'),
      MilestoneStatus.accepted => tr3('已验收', 'Қабылданды', 'Принят', 'Accepted'),
      MilestoneStatus.disputed => tr3('有问题', 'Ескерту бар', 'Есть замечания', 'Has issues'),
    };

String feedbackTopicName(String k) => switch (k) {
      'layout' => tr3('布局', 'Жоспар', 'Планировка', 'Layout'),
      'light' => tr3('采光朝向', 'Жарық', 'Свет и ориентация', 'Light and orientation'),
      'cost' => tr3('造价', 'Құны', 'Стоимость', 'Cost'),
      'structure' => tr3('结构', 'Құрылым', 'Конструкция', 'Structure'),
      'look' => tr3('外观', 'Сыртқы түрі', 'Внешний вид', 'Appearance'),
      'warmth' => tr3('保暖', 'Жылу', 'Утепление', 'Insulation'),
      _ => k,
    };
