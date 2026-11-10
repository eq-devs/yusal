import '../../../app/settings.dart';
import '../../../core/commands/house_templates.dart';
import '../../domain/models.dart';
import 'mock_backend.dart';
import '../../snapshot/design_snapshot.dart';

/// Ids of the seeded demo accounts; developer tools sign in as them.
abstract final class SeedIds {
  static const owner = 'acc_owner';
  static const owner2 = 'acc_owner2';
  static const mason = 'acc_mason';
  static const team = 'acc_team';
  static const electrician = 'acc_elec';
  static const roofTeam = 'acc_roof';
  static const admin = 'acc_admin';
}

/// Demo data for the pilot region (Almaty surroundings): two owners, two
/// workers, two teams, open demands of both types, quotes to compare, a
/// chat and one finished cooperation with reviews.
/// Demo text in the language the app was opened in, so a Kazakh or Russian
/// speaker does not meet a feed written in Chinese. The seed is built once,
/// when the backend starts.
String _l(String zh, String kk, String ru) => tr3(zh, kk, ru);

void seedMockData(MockBackend b) {
  final now = b.now;
  DateTime ago(int days, [int hours = 0]) =>
      now.subtract(Duration(days: days, hours: hours));

  void account(String id, String phone, String name, {bool admin = false}) =>
      b.accounts[id] = Account(
          id: id,
          phone: phone,
          displayName: name,
          createdAt: ago(60),
          isAdmin: admin);
  account(SeedIds.owner, '+77010000001', 'Айгерім');
  account(SeedIds.owner2, '+77010000002', 'Динара');
  account(SeedIds.mason, '+77010000003', 'Болат');
  account(SeedIds.team, '+77010000004', 'Нұрлан');
  account(SeedIds.electrician, '+77010000005', 'Ерлан');
  account(SeedIds.roofTeam, '+77010000006', 'Самат');
  account(SeedIds.admin, '+77010000009',
      _l('Yusal 审核', 'Yusal модераторы', 'Модератор Yusal'),
      admin: true);

  b.profiles['prof_mason'] = ServiceProfile(
      id: 'prof_mason',
      ownerId: SeedIds.mason,
      kind: ProfileKind.individual,
      name: _l('Болат · 瓦工', 'Болат · қалаушы', 'Болат · каменщик'),
      trades: const ['mason', 'plasterer'],
      regions: const ['talgar', 'almaty'],
      availability: Availability.now,
      availabilityConfirmedAt: ago(1),
      experienceYears: 12,
      refPrices: [
        RefPrice(
            amount: 6000,
            unit: 'm3',
            scope: _l('仅人工，砌块墙每立方米起', 'тек жұмыс, блок қабырғаның текше метрі',
                'только работа, кладка блоков за м³')),
        RefPrice(
            amount: 18000,
            unit: 'day',
            scope: _l('日薪，含自带小工具', 'күндік ақы, өз құралымен',
                'за день, со своим инструментом')),
      ],
      bio: _l(
          '砌墙、抹灰十二年，做过二十多栋乡村住宅。可带一名小工。',
          'Он екі жыл қабырға қалап, сылақ жасаймын, жиырмадан астам ауыл үйін салдым. Бір көмекшімен келе аламын.',
          'Двенадцать лет кладу стены и штукатурю, построил больше двадцати сельских домов. Могу прийти с подсобником.'),
      works: [
        Work(
            id: 'w1',
            title: _l(
                '塔尔加尔 两层砖房外墙',
                'Талғар: екі қабатты кірпіш үйдің сыртқы қабырғалары',
                'Талгар: наружные стены двухэтажного кирпичного дома'),
            source: WorkSource.uploaded,
            photoCount: 4),
      ]);
  b.profiles['prof_team'] = ServiceProfile(
      id: 'prof_team',
      ownerId: SeedIds.team,
      kind: ProfileKind.team,
      role: ProRole.contractor,
      name: _l('Нұрлан Құрылыс 施工队', 'Нұрлан Құрылыс бригадасы',
          'Бригада «Нұрлан Құрылыс»'),
      trades: const ['general', 'mason', 'concrete', 'rebar'],
      regions: const ['almaty', 'talgar', 'kaskelen', 'esik'],
      availability: Availability.fromDate,
      availableFrom: now.add(const Duration(days: 10)),
      availabilityConfirmedAt: ago(3),
      experienceYears: 8,
      teamSize: 7,
      refPrices: [
        RefPrice(
            amount: 7000,
            unit: 'm3',
            scope: _l('仅人工，砌墙', 'тек жұмыс, қабырға қалау',
                'только работа, кладка стен')),
        RefPrice(
            amount: 45000,
            unit: 'm3',
            scope: _l('包工包料，基础混凝土', 'жұмыс пен материал, іргетас бетоны',
                'работа и материалы, бетон фундамента')),
      ],
      bio: _l(
          '七人施工队，承接基础、主体、砌墙。报价写清范围和不包含项。',
          'Жеті адамдық бригада: іргетас, қаңқа, қабырға қалау. Ұсыныста не кіретіні мен не кірмейтінін анық жазамыз.',
          'Бригада из семи человек: фундамент, коробка, кладка. В предложении чётко пишем, что входит и что нет.'));
  b.profiles['prof_elec'] = ServiceProfile(
      id: 'prof_elec',
      ownerId: SeedIds.electrician,
      kind: ProfileKind.individual,
      name: _l('Ерлан · 电工', 'Ерлан · электрик', 'Ерлан · электрик'),
      trades: const ['electrician'],
      regions: const ['almaty', 'konaev'],
      availability: Availability.now,
      availabilityConfirmedAt: ago(0, 5),
      experienceYears: 6,
      refPrices: [
        RefPrice(
            amount: 4500,
            unit: 'pcs',
            scope: _l('仅人工，每个点位', 'тек жұмыс, әр нүкте үшін',
                'только работа, за точку'))
      ]);
  b.profiles['prof_roof'] = ServiceProfile(
      id: 'prof_roof',
      ownerId: SeedIds.roofTeam,
      kind: ProfileKind.team,
      role: ProRole.contractor,
      name: _l('Алатау 屋面队', 'Алатау шатыр бригадасы',
          'Кровельная бригада «Алатау»'),
      trades: const ['roofer', 'carpenter', 'general'],
      regions: const ['esik', 'talgar', 'almaty'],
      availability: Availability.notTaking,
      availabilityConfirmedAt: ago(20),
      teamSize: 4,
      bio: _l('木屋架、金属瓦屋面。', 'Ағаш шатыр қаңқасы, металл жабынқыш.',
          'Деревянные стропила, кровля из металлочерепицы.'));

  // Demands.
  b.demands['dem_wall'] = Demand(
      id: 'dem_wall',
      ownerId: SeedIds.owner,
      type: DemandType.contract,
      status: DemandStatus.open,
      createdAt: ago(4),
      publishedAt: ago(4),
      expiresAt: now.add(const Duration(days: 26)),
      shareToken: 'share_wall',
      followUpsSent: 1,
      versions: [
        DemandVersion(
            no: 1,
            title: _l('120 平米住宅砌墙', '120 м² үйдің қабырғасын қалау',
                'Кладка стен дома 120 м²'),
            snapshotId: 'snap_aigerim',
            trades: const ['mason'],
            region: 'talgar',
            locality: _l('塔尔加尔 · 北区', 'Талғар, солтүстік бөлігі',
                'Талгар, северная часть'),
            exactAddress: 'Талгар, ул. Абая 12',
            budget: const Budget(
                mode: BudgetMode.range,
                min: 1200000,
                max: 1600000,
                materials: MaterialMode.labourOnly),
            createdAt: ago(4),
            startDate: now.add(const Duration(days: 14)),
            durationDays: 25,
            description: _l(
                '一层住宅，外墙 300 加气块，内墙 200。基础已完成，材料业主提供。',
                'Бір қабатты үй: сыртқы қабырға — 300 мм газоблок, ішкісі — 200 мм. Іргетас дайын, материалды иесі береді.',
                'Одноэтажный дом: наружные стены из газоблока 300 мм, внутренние 200 мм. Фундамент готов, материалы даёт владелец.'),
            contract: ContractTerms(
                scopeKind: ScopeKind.stages,
                stages: const ['walls'],
                quantities: [
                  QtyItem(
                      name: _l('外墙砌筑', 'Сыртқы қабырға қалау',
                          'Кладка наружных стен'),
                      quantity: 62.5,
                      unit: 'm3',
                      source: QtySource.manual,
                      stage: 'walls'),
                  QtyItem(
                      name: _l('内墙砌筑', 'Ішкі қабырға қалау',
                          'Кладка внутренних стен'),
                      quantity: 21,
                      unit: 'm3',
                      source: QtySource.manual,
                      stage: 'walls'),
                ],
                materials: MaterialMode.labourOnly,
                targetDays: 25,
                quoteDeadline: now.add(const Duration(days: 6))),
            photoCount: 2),
      ]);
  b.demands['dem_hire'] = Demand(
      id: 'dem_hire',
      ownerId: SeedIds.owner,
      type: DemandType.hire,
      status: DemandStatus.open,
      createdAt: ago(1),
      publishedAt: ago(1),
      expiresAt: now.add(const Duration(days: 29)),
      shareToken: 'share_hire',
      versions: [
        DemandVersion(
            no: 1,
            title: _l('找两名瓦工，按天结算', 'Екі қалаушы керек, күндік төлем',
                'Нужны два каменщика, оплата по дням'),
            trades: const ['mason'],
            region: 'kaskelen',
            locality: _l('卡斯克连', 'Қаскелең', 'Каскелен'),
            budget: const Budget(
                mode: BudgetMode.fixed, amount: 20000, basis: 'day'),
            createdAt: ago(1),
            startDate: now.add(const Duration(days: 5)),
            durationDays: 10,
            description: _l(
                '围墙和附属房砌砖，约 10 天。',
                'Қоршау мен қосалқы құрылыстың кірпішін қалау, шамамен 10 күн.',
                'Кладка забора и хозпостройки, около 10 дней.'),
            hire: const HireTerms(
                headcount: 2,
                payMode: PayMode.daily,
                wage: 20000,
                days: 10,
                foodLodging: true,
                toolsByEmployer: true,
                settleCycle: 'weekly')),
      ]);
  b.demands['dem_rebar'] = Demand(
      id: 'dem_rebar',
      ownerId: SeedIds.team,
      type: DemandType.hire,
      status: DemandStatus.open,
      publisherRole: PublisherRole.contractor,
      createdAt: ago(2),
      publishedAt: ago(2),
      expiresAt: now.add(const Duration(days: 28)),
      shareToken: 'share_rebar',
      followUpsSent: 0,
      versions: [
        DemandVersion(
            no: 1,
            title: _l('钢筋工 × 3 · 阿拉木图', 'Арматурашы × 3 · Алматы',
                'Арматурщики × 3 · Алматы'),
            trades: const ['rebar'],
            region: 'almaty',
            locality: _l('阿拉木图 · 阿拉套区', 'Алматы, Алатау ауданы',
                'Алматы, Алатауский район'),
            budget: const Budget(mode: BudgetMode.askQuote),
            createdAt: ago(2),
            description: _l(
                '分包项目：两栋住宅的条形基础绑扎，工资面议。',
                'Қосалқы мердігерлік: екі үйдің таспалы іргетасының арматурасын байлау, ақысы келісім бойынша.',
                'Субподряд: вязка арматуры ленточного фундамента двух домов, оплата по договорённости.'),
            hire: const HireTerms(
                headcount: 3,
                payMode: PayMode.piece,
                wageUnit: 't',
                settleCycle: 'onFinish')),
      ]);
  b.demands['dem_roof'] = Demand(
      id: 'dem_roof',
      ownerId: SeedIds.owner2,
      type: DemandType.contract,
      status: DemandStatus.open,
      createdAt: ago(0, 6),
      publishedAt: ago(0, 6),
      expiresAt: now.add(const Duration(days: 30)),
      shareToken: 'share_roof',
      versions: [
        DemandVersion(
            no: 1,
            title: _l('双坡屋面 · 金属瓦', 'Қос беткейлі шатыр · металл жабынқыш',
                'Двускатная кровля · металлочерепица'),
            trades: const ['roofer', 'carpenter'],
            region: 'esik',
            locality: _l('伊塞克', 'Есік', 'Есик'),
            budget: const Budget(
                mode: BudgetMode.askQuote,
                materials: MaterialMode.labourAndMaterial),
            createdAt: ago(0, 6),
            description: _l(
                '12 × 10 米住宅，木屋架 + 金属瓦，请包工包料报价。',
                '12 × 10 м үй, ағаш қаңқа + металл жабынқыш. Жұмыс пен материалды қоса бағалаңыз.',
                'Дом 12 × 10 м, деревянные стропила и металлочерепица. Нужна цена с работой и материалами.'),
            contract: ContractTerms(
                scopeKind: ScopeKind.stages,
                stages: const ['roof'],
                quantities: [
                  QtyItem(
                      name: _l('屋面面积', 'Шатыр ауданы', 'Площадь кровли'),
                      quantity: null,
                      unit: 'm2',
                      source: QtySource.siteMeasure,
                      stage: 'roof'),
                ],
                materials: MaterialMode.labourAndMaterial,
                targetDays: 15)),
      ]);
  // An earlier demand with a finished cooperation.
  b.demands['dem_found'] = Demand(
      id: 'dem_found',
      ownerId: SeedIds.owner2,
      type: DemandType.contract,
      status: DemandStatus.found,
      outcome: OutcomeKind.platformConfirmed,
      createdAt: ago(50),
      publishedAt: ago(50),
      expiresAt: ago(20),
      shareToken: 'share_found',
      followUpsSent: 2,
      versions: [
        DemandVersion(
            no: 1,
            title: _l('条形基础施工', 'Таспалы іргетас құю', 'Ленточный фундамент'),
            trades: const ['concrete', 'rebar'],
            region: 'esik',
            locality: _l('伊塞克', 'Есік', 'Есик'),
            budget: const Budget(
                mode: BudgetMode.fixed,
                amount: 2100000,
                materials: MaterialMode.labourAndMaterial),
            createdAt: ago(50),
            contract: const ContractTerms(
                scopeKind: ScopeKind.stages, stages: ['found'])),
      ]);

  // Quotes on the wall demand: different material scopes, so the comparison
  // warns.
  b.applications['app_team_wall'] = Application(
      id: 'app_team_wall',
      demandId: 'dem_wall',
      profileId: 'prof_team',
      applicantId: SeedIds.team,
      status: ApplicationStatus.submitted,
      createdAt: ago(3),
      versions: [
        ApplicationVersion(
            no: 1,
            demandVersionNo: 1,
            createdAt: ago(3),
            scopeText: _l(
                '外墙与内墙砌筑，含构造柱模板',
                'Сыртқы және ішкі қабырғаларды қалау, бағандардың қалыбымен',
                'Кладка наружных и внутренних стен, с опалубкой колонн'),
            materials: MaterialMode.labourOnly,
            pricing: PricingMode.perQuantity,
            lines: [
              QuoteLine(
                  name: _l(
                      '外墙砌筑', 'Сыртқы қабырға қалау', 'Кладка наружных стен'),
                  quantity: 62.5,
                  unit: 'm3',
                  unitPrice: 7000),
              QuoteLine(
                  name: _l(
                      '内墙砌筑', 'Ішкі қабырға қалау', 'Кладка внутренних стен'),
                  quantity: 21,
                  unit: 'm3',
                  unitPrice: 6500),
            ],
            durationDays: 22,
            includes: _l('砂浆搅拌、脚手架', 'Ерітінді дайындау, тіреуіш мінбелер',
                'Замес раствора, леса'),
            excludes: _l('材料、运输、垃圾清运', 'Материал, тасымал, қоқыс шығару',
                'Материалы, доставка, вывоз мусора'),
            validUntil: now.add(const Duration(days: 20))),
      ]);
  b.applications['app_mason_wall'] = Application(
      id: 'app_mason_wall',
      demandId: 'dem_wall',
      profileId: 'prof_mason',
      applicantId: SeedIds.mason,
      status: ApplicationStatus.submitted,
      createdAt: ago(2),
      versions: [
        ApplicationVersion(
            no: 1,
            demandVersionNo: 1,
            createdAt: ago(2),
            scopeText: _l('全部砌墙，两人施工', 'Барлық қабырғаны қалау, екі адам',
                'Вся кладка, работаем вдвоём'),
            materials: MaterialMode.labourOnly,
            pricing: PricingMode.lumpSum,
            lumpSum: 1350000,
            durationDays: 30,
            includes:
                _l('砌筑、灰缝', 'Қалау, жіктерді өңдеу', 'Кладка, расшивка швов'),
            excludes: _l('构造柱、圈梁、材料', 'Бағандар, белдеу, материал',
                'Колонны, армопояс, материалы')),
      ]);
  b.applications['app_mason_hire'] = Application(
      id: 'app_mason_hire',
      demandId: 'dem_hire',
      profileId: 'prof_mason',
      applicantId: SeedIds.mason,
      status: ApplicationStatus.submitted,
      createdAt: ago(0, 20),
      versions: [
        ApplicationVersion(
            no: 1,
            demandVersionNo: 1,
            createdAt: ago(0, 20),
            availableFrom: now.add(const Duration(days: 5)),
            acceptsOffer: true,
            headcountOffered: 1,
            note: _l('可以带自己的瓦刀和水平尺。', 'Өз қалағым мен деңгейіммен келемін.',
                'Приду со своей кельмой и уровнем.')),
      ]);
  b.notice(SeedIds.owner, NoticeKind.newApplication, RefType.demand, 'dem_wall',
      title: _l('120 平米住宅砌墙', '120 м² үйдің қабырғасын қалау',
          'Кладка стен дома 120 м²'));
  b.notice(SeedIds.owner, NoticeKind.newApplication, RefType.demand, 'dem_hire',
      title: _l('找两名瓦工，按天结算', 'Екі қалаушы керек, күндік төлем',
          'Нужны два каменщика, оплата по дням'));

  // A finished cooperation with both reviews in.
  b.applications['app_team_found'] = Application(
      id: 'app_team_found',
      demandId: 'dem_found',
      profileId: 'prof_team',
      applicantId: SeedIds.team,
      status: ApplicationStatus.cooperating,
      createdAt: ago(48),
      versions: [
        ApplicationVersion(
            no: 1,
            demandVersionNo: 1,
            createdAt: ago(48),
            scopeText: _l('条形基础，包工包料', 'Таспалы іргетас, жұмыс пен материал',
                'Ленточный фундамент, работа и материалы'),
            materials: MaterialMode.labourAndMaterial,
            pricing: PricingMode.lumpSum,
            lumpSum: 2100000,
            durationDays: 12),
      ]);
  b.cooperations['coop_found'] = Cooperation(
      id: 'coop_found',
      demandId: 'dem_found',
      applicationId: 'app_team_found',
      ownerId: SeedIds.owner2,
      providerId: SeedIds.team,
      profileId: 'prof_team',
      status: CooperationStatus.ended,
      endKind: EndKind.mutual,
      endedAt: ago(25),
      createdAt: ago(45),
      agreements: [
        Agreement(
            version: 1,
            scope: _l('条形基础施工，包工包料', 'Таспалы іргетас құю, жұмыс пен материал',
                'Устройство ленточного фундамента, работа и материалы'),
            demandVersionNo: 1,
            proposedBy: SeedIds.owner2,
            confirmedBy: const {SeedIds.owner2, SeedIds.team},
            status: AgreementStatus.active,
            createdAt: ago(45),
            amount: 2100000,
            paymentTerms: _l(
                '开工 30%，完工验收 70%',
                'Басында 30 %, қабылдағаннан кейін 70 %',
                '30 % при старте, 70 % после приёмки'),
            materialsResponsibility: _l(
                '施工队采购全部材料',
                'Барлық материалды бригада сатып алады',
                'Все материалы закупает бригада')),
      ]);
  b.profiles['prof_team'] = b.profiles['prof_team']!.copyWith(works: [
    Work(
        id: 'w2',
        title: _l('条形基础施工', 'Таспалы іргетас құю', 'Ленточный фундамент'),
        source: WorkSource.platform,
        cooperationId: 'coop_found'),
    Work(
        id: 'w3',
        title: _l('卡斯克连 别墅主体', 'Қаскелең: коттедждің қаңқасы',
            'Каскелен: коробка коттеджа'),
        source: WorkSource.uploaded,
        photoCount: 6),
  ]);
  for (final (id, author, target, s, text) in [
    (
      'rev1',
      SeedIds.owner2,
      SeedIds.team,
      5,
      _l('按约定工期完成，现场干净。', 'Келісілген мерзімде бітірді, алаң таза.',
          'Закончили в срок, на площадке чисто.')
    ),
    (
      'rev2',
      SeedIds.team,
      SeedIds.owner2,
      5,
      _l('付款准时，范围清楚。', 'Ақысын уақытында төледі, жұмыс көлемі анық.',
          'Платит вовремя, объём работ понятный.')
    ),
  ]) {
    b.reviews[id] = Review(
        id: id,
        cooperationId: 'coop_found',
        authorId: author,
        targetId: target,
        scores: {for (final d in reviewDimensions) d: s},
        text: text,
        createdAt: ago(24));
  }

  // A conversation about the wall quote.
  final conv =
      b.openOrCreate(SeedIds.owner, SeedIds.team, demandId: 'dem_wall');
  b.messagesById['msg_s1'] = ChatMessage(
      id: 'msg_s1',
      conversationId: conv.id,
      senderId: SeedIds.team,
      kind: MessageKind.quoteCard,
      refId: 'app_team_wall',
      sentAt: ago(3));
  b.messagesById['msg_s2'] = ChatMessage(
      id: 'msg_s2',
      conversationId: conv.id,
      senderId: SeedIds.team,
      kind: MessageKind.text,
      text: _l(
          '您好，报价按图纸工程量算的，构造柱模板已包含。可以先来现场看一下吗？',
          'Сәлеметсіз бе! Бағаны сызбадағы көлем бойынша есептедім, бағандардың қалыбы кіреді. Алдымен орнын көруге бола ма?',
          'Здравствуйте! Цену посчитал по объёмам из чертежа, опалубка колонн входит. Можно сначала посмотреть участок?'),
      sentAt: ago(3));
  b.messagesById['msg_s3'] = ChatMessage(
      id: 'msg_s3',
      conversationId: conv.id,
      senderId: SeedIds.owner,
      kind: MessageKind.text,
      text: _l(
          '周六上午可以。', 'Сенбі күні таңертең болады.', 'В субботу утром можно.'),
      sentAt: ago(2, 20));
  b.messagesById['msg_s4'] = ChatMessage(
      id: 'msg_s4',
      conversationId: conv.id,
      senderId: SeedIds.team,
      kind: MessageKind.text,
      text: _l('好的，周六 10 点到。', 'Жақсы, сенбіде сағат 10-да келемін.',
          'Хорошо, буду в субботу в 10.'),
      sentAt: ago(0, 2));

  // Snapshots and house posts: the feed everyone sees first.
  final demoFacts = <String, DesignExtract>{};
  DesignSnapshot snap(String id, String owner, String project, String name,
      String summary, List<QtyItem> lines) {
    var counter = 0;
    final kind = id == 'snap_erlan' || id == 'snap_dinara' ? 'two' : 'three';
    final doc = createTemplate(
        kind, ago(6).toUtc().toIso8601String(), () => 'demo${counter++}');
    final facts = extractDesign(doc, snapshotStages);
    demoFacts[id] = facts;
    final frozen = buildSnapshot(
        projectId: project,
        doc: doc,
        stages: snapshotStages,
        lines: lines,
        summary: tr3(
            '${facts.width / 1000} × ${facts.depth / 1000} 米 · ${facts.floors} 层 · 建筑面积 ${facts.buildingArea.toStringAsFixed(0)} ㎡',
            '${facts.width / 1000} × ${facts.depth / 1000} м · ${facts.floors} қабат · ${facts.buildingArea.toStringAsFixed(0)} м²',
            '${facts.width / 1000} × ${facts.depth / 1000} м · этажей: ${facts.floors} · ${facts.buildingArea.toStringAsFixed(0)} м²'));
    return DesignSnapshot(
        id: id,
        ownerId: owner,
        projectId: project,
        projectName: name,
        designUpdatedAt: doc.meta.updatedAt,
        extractedAt: ago(6),
        stages: snapshotStages,
        lines: lines,
        summary: frozen.summary,
        planJson: frozen.planJson);
  }

  const q = QtySource.design;
  b.snapshots['snap_aigerim'] = snap(
      'snap_aigerim',
      SeedIds.owner,
      'seed_p1',
      _l('塔尔加尔一层砖房', 'Талғардағы бір қабатты кірпіш үй',
          'Одноэтажный кирпичный дом в Талгаре'),
      _l('12 × 11 m，一层，130 m²，4 个房间', '12 × 11 м, бір қабат, 130 м², 4 бөлме',
          '12 × 11 м, один этаж, 130 м², 4 комнаты'),
      [
        QtyItem(
            name: _l('条形基础混凝土', 'Таспалы іргетас бетоны',
                'Бетон ленточного фундамента'),
            quantity: 28,
            unit: 'm3',
            source: q,
            stage: 'found'),
        QtyItem(
            name: _l('外墙砌筑', 'Сыртқы қабырға қалау', 'Кладка наружных стен'),
            quantity: 62,
            unit: 'm3',
            source: q,
            stage: 'walls'),
        QtyItem(
            name: _l('内墙砌筑', 'Ішкі қабырға қалау', 'Кладка внутренних стен'),
            quantity: 21,
            unit: 'm3',
            source: q,
            stage: 'walls'),
        QtyItem(
            name: _l('屋面', 'Шатыр', 'Кровля'),
            quantity: 168,
            unit: 'm2',
            source: q,
            stage: 'roof'),
      ]);
  b.snapshots['snap_dinara'] = snap(
      'snap_dinara',
      SeedIds.owner2,
      'seed_p2',
      _l('卡斯克连两层别墅', 'Қаскелеңдегі екі қабатты коттедж',
          'Двухэтажный коттедж в Каскелене'),
      _l(
          '14 × 12 m，两层，290 m²，7 个房间，带车库',
          '14 × 12 м, екі қабат, 290 м², 7 бөлме, гаражы бар',
          '14 × 12 м, два этажа, 290 м², 7 комнат, с гаражом'),
      [
        QtyItem(
            name: _l('条形基础混凝土', 'Таспалы іргетас бетоны',
                'Бетон ленточного фундамента'),
            quantity: 46,
            unit: 'm3',
            source: q,
            stage: 'found'),
        QtyItem(
            name: _l('外墙砌筑', 'Сыртқы қабырға қалау', 'Кладка наружных стен'),
            quantity: 128,
            unit: 'm3',
            source: q,
            stage: 'walls'),
        QtyItem(
            name: _l('楼板', 'Аражабын плитасы', 'Перекрытие'),
            quantity: 168,
            unit: 'm2',
            source: q,
            stage: 'walls'),
        QtyItem(
            name: _l('屋面', 'Шатыр', 'Кровля'),
            quantity: 210,
            unit: 'm2',
            source: q,
            stage: 'roof'),
      ]);
  b.snapshots['snap_team'] = snap(
      'snap_team',
      SeedIds.team,
      'seed_p3',
      _l('伊西克紧凑型住宅', 'Есіктегі шағын үй', 'Компактный дом в Есике'),
      _l('10 × 9 m，一层，86 m²，3 个房间', '10 × 9 м, бір қабат, 86 м², 3 бөлме',
          '10 × 9 м, один этаж, 86 м², 3 комнаты'),
      [
        QtyItem(
            name: _l('条形基础混凝土', 'Таспалы іргетас бетоны',
                'Бетон ленточного фундамента'),
            quantity: 19,
            unit: 'm3',
            source: q,
            stage: 'found'),
        QtyItem(
            name: _l('外墙砌筑', 'Сыртқы қабырға қалау', 'Кладка наружных стен'),
            quantity: 44,
            unit: 'm3',
            source: q,
            stage: 'walls'),
        QtyItem(
            name: _l('屋面', 'Шатыр', 'Кровля'),
            quantity: 118,
            unit: 'm2',
            source: q,
            stage: 'roof'),
      ]);
  b.snapshots['snap_erlan'] = snap(
      'snap_erlan',
      SeedIds.electrician,
      'seed_p4',
      _l('阿拉木图郊区一层半', 'Алматы маңындағы мансардалы үй',
          'Дом с мансардой под Алматы'),
      _l(
          '11 × 10 m，一层加阁楼，150 m²，5 个房间',
          '11 × 10 м, бір қабат пен мансарда, 150 м², 5 бөлме',
          '11 × 10 м, этаж с мансардой, 150 м², 5 комнат'),
      [
        QtyItem(
            name: _l('条形基础混凝土', 'Таспалы іргетас бетоны',
                'Бетон ленточного фундамента'),
            quantity: 25,
            unit: 'm3',
            source: q,
            stage: 'found'),
        QtyItem(
            name: _l('外墙砌筑', 'Сыртқы қабырға қалау', 'Кладка наружных стен'),
            quantity: 58,
            unit: 'm3',
            source: q,
            stage: 'walls'),
        QtyItem(
            name: _l('屋面', 'Шатыр', 'Кровля'),
            quantity: 172,
            unit: 'm2',
            source: q,
            stage: 'roof'),
      ]);

  HousePost post(String id, String owner, String snapId, String title,
          String story, String region,
          {required double area,
          required int floors,
          required int rooms,
          required int cost,
          required int days,
          List<String> tags = const [],
          bool open = true,
          List<String> focus = const [],
          int likes = 0}) =>
      HousePost(
          id: id,
          ownerId: owner,
          projectId: b.snapshots[snapId]!.projectId,
          snapshotId: snapId,
          title: title,
          story: story,
          region: region,
          createdAt: ago(days),
          updatedAt: ago(days),
          area: demoFacts[snapId]!.buildingArea,
          floors: demoFacts[snapId]!.floors,
          rooms: demoFacts[snapId]!.rooms,
          estimatedCost: cost,
          tags: tags,
          openForBuilders: open,
          focus: focus,
          likeCount: likes);
  b.posts['post_aigerim'] = post(
      'post_aigerim',
      SeedIds.owner,
      'snap_aigerim',
      _l('给父母盖的一层砖房', 'Ата-анама арналған бір қабатты кірпіш үй',
          'Одноэтажный кирпичный дом для родителей'),
      _l(
          '父母年纪大了，想要一层、没有台阶的房子。客厅朝南，两个卧室朝东。基础已经打好，现在找砌墙的师傅。',
          'Ата-анам қартайды, сондықтан бір қабатты, баспалдақсыз үй керек. Қонақ бөлме оңтүстікке, екі жатын бөлме шығысқа қарайды. Іргетас құйылды, енді қабырға қалайтын шебер іздеп жүрмін.',
          'Родители уже в возрасте, поэтому дом в один этаж и без ступенек. Гостиная смотрит на юг, две спальни — на восток. Фундамент залит, теперь ищу каменщиков.'),
      'talgar',
      area: 130,
      floors: 1,
      rooms: 4,
      cost: 18500000,
      days: 6,
      tags: const ['one_floor', 'brick'],
      likes: 3);
  b.posts['post_dinara'] = post(
      'post_dinara',
      SeedIds.owner2,
      'snap_dinara',
      _l('两层别墅，带车库和露台', 'Гаражы мен террасасы бар екі қабатты үй',
          'Двухэтажный дом с гаражом и террасой'),
      _l(
          '一家五口住。一楼公共空间，二楼四个卧室。想明年春天开工，先听听大家的意见，预算是不是合理。',
          'Бес адамдық отбасыға арналған. Бірінші қабатта ортақ бөлмелер, екіншіде төрт жатын бөлме. Келесі көктемде бастағымыз келеді; алдымен пікіріңізді білгіміз келеді: бюджет шындыққа жанаса ма?',
          'Для семьи из пяти человек. На первом этаже общие комнаты, на втором четыре спальни. Хотим начать весной; сначала послушаем мнения — реален ли бюджет?'),
      'kaskelen',
      area: 290,
      floors: 2,
      rooms: 7,
      cost: 52000000,
      days: 12,
      tags: const ['two_floors', 'garage', 'large'],
      open: false,
      focus: const ['cost', 'layout'],
      likes: 5);
  b.posts['post_team'] = post(
      'post_team',
      SeedIds.team,
      'snap_team',
      _l('120 平米紧凑型住宅方案（可承建）', '120 м² шағын үй жобасы (салып береміз)',
          'Проект компактного дома 120 м² (можем построить)'),
      _l(
          '我们施工队做过三栋这个户型，工期 70 天左右。分享出来给预算有限的家庭参考，欢迎直接联系。',
          'Біздің бригада осындай үш үй салды, мерзімі шамамен 70 күн. Бюджеті шектеулі отбасыларға үлгі ретінде бөлісіп отырмыз, тікелей жазыңыз.',
          'Наша бригада построила три таких дома, срок около 70 дней. Делимся для семей с небольшим бюджетом — пишите напрямую.'),
      'esik',
      area: 86,
      floors: 1,
      rooms: 3,
      cost: 11800000,
      days: 20,
      tags: const ['one_floor', 'budget'],
      open: false,
      likes: 2);
  b.posts['post_erlan'] = post(
      'post_erlan',
      SeedIds.electrician,
      'snap_erlan',
      _l('一层半带阁楼，自己画的第一版', 'Мансардалы үй, өзім сызған алғашқы нұсқа',
          'Дом с мансардой, мой первый вариант'),
      _l(
          '第一次用软件画房子，阁楼想做两个孩子的房间。不确定楼梯位置合不合理，请大家看看。',
          'Үйді бағдарламада бірінші рет сыздым, мансардаға екі балалар бөлмесін жасағым келеді. Баспалдақтың орны дұрыс па, білмеймін — қарап беріңізші.',
          'Впервые рисую дом в программе, в мансарде хочу сделать две детские. Не уверен, что лестница стоит удачно — посмотрите, пожалуйста.'),
      'almaty',
      area: 150,
      floors: 2,
      rooms: 5,
      cost: 23000000,
      days: 2,
      tags: const ['brick'],
      open: false,
      focus: const ['layout', 'structure'],
      likes: 1);
  b.likes['post_aigerim'] = {SeedIds.mason, SeedIds.team, SeedIds.owner2};
  b.likes['post_dinara'] = {
    SeedIds.mason,
    SeedIds.team,
    SeedIds.owner,
    SeedIds.roofTeam,
    SeedIds.electrician
  };
  b.likes['post_team'] = {SeedIds.owner, SeedIds.owner2};
  b.likes['post_erlan'] = {SeedIds.owner};

  void cmt(String id, String postId, String author, String text, int days,
      {int? rating, String? topic, String? parent, bool helpful = false}) {
    b.commentsById[id] = PostComment(
        id: id,
        postId: postId,
        authorId: author,
        text: text,
        createdAt: ago(days),
        rating: rating,
        topic: topic,
        parentId: parent,
        helpful: helpful);
    final p = b.posts[postId]!;
    b.posts[postId] = p.copyWith(
        commentCount: p.commentCount + 1,
        ratingSum: p.ratingSum + (rating ?? 0),
        ratingCount: p.ratingCount + (rating == null ? 0 : 1));
  }

  cmt(
      'cmt1',
      'post_aigerim',
      SeedIds.mason,
      _l(
          '布局很实用。外墙 300 加气块冬天够用，建议内墙也做 200。',
          'Жоспары ыңғайлы. Сыртқы қабырғаға 300 мм газоблок қыста жетеді, ішкісін де 200 мм еткен дұрыс.',
          'Планировка практичная. Газоблока 300 мм снаружи на зиму хватит, внутренние стены советую тоже делать 200.'),
      5,
      rating: 5);
  cmt(
      'cmt2',
      'post_aigerim',
      SeedIds.team,
      _l(
          '基础 28 方混凝土对 120 平米来说偏少，建议复核一下地基宽度。',
          '120 м² үйге 28 м³ бетон аздау сияқты, іргетастың енін қайта тексеріп көріңіз.',
          '28 м³ бетона на фундамент для 120 м² маловато, проверьте ширину ленты.'),
      4,
      rating: 4);
  cmt(
      'cmt3',
      'post_dinara',
      SeedIds.roofTeam,
      _l(
          '双坡屋面 210 平米，金属瓦大概 3 周。预算里屋面部分合理。',
          '210 м² қос беткейлі шатырды металл жабынқышпен шамамен 3 аптада жабамыз. Бюджеттегі шатыр бөлігі орынды.',
          'Двускатная кровля 210 м² из металлочерепицы — примерно 3 недели. Кровля в бюджете посчитана разумно.'),
      10,
      rating: 4,
      topic: 'cost');
  cmt(
      'cmt4',
      'post_dinara',
      SeedIds.owner,
      _l(
          '很漂亮，二楼卫生间最好和一楼上下对齐，省管道。',
          'Өте әдемі. Екінші қабаттағы санторапты біріншінің үстіне қойған дұрыс, құбыр үнемделеді.',
          'Очень красиво. Санузел на втором этаже лучше поставить над нижним — сэкономите на трубах.'),
      9,
      rating: 5,
      topic: 'layout',
      helpful: true);
  cmt(
      'cmt4r',
      'post_dinara',
      SeedIds.owner2,
      _l(
          '好建议，我把二楼卫生间挪到楼梯旁边。',
          'Жақсы кеңес, екінші қабаттағы санторапты баспалдақтың жанына жылжытамын.',
          'Хороший совет, перенесу санузел второго этажа к лестнице.'),
      8,
      parent: 'cmt4');
  cmt(
      'cmt5',
      'post_erlan',
      SeedIds.owner2,
      _l(
          '楼梯放客厅角落会更省空间。',
          'Баспалдақты қонақ бөлменің бұрышына қойса, орын үнемделеді.',
          'Лестница в углу гостиной сэкономит место.'),
      1,
      topic: 'layout');
  cmt(
      'cmt6',
      'post_erlan',
      SeedIds.mason,
      _l(
          '阁楼层高要留够 2.4 米的地方才能放床，屋架坡度可能要调陡。',
          'Мансардада кереует қоятын жерде биіктік 2,4 м болуы керек, шатыр еңісін тіктеу қажет болуы мүмкін.',
          'В мансарде там, где встанут кровати, нужна высота 2,4 м — возможно, скат придётся сделать круче.'),
      1,
      topic: 'structure');

  // One report waiting for the moderator.
  b.reportsById['rep_seed'] = Report(
      id: 'rep_seed',
      reporterId: SeedIds.mason,
      target: ReportTarget.demand,
      targetId: 'dem_rebar',
      reason: _l('工资信息不清楚', 'Жалақы туралы ақпарат түсініксіз',
          'Непонятно, сколько платят'),
      createdAt: ago(1));
}
