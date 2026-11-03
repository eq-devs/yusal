import '../../domain/models.dart';
import 'mock_backend.dart';

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
  account(SeedIds.admin, '+77010000009', 'Yusal 审核', admin: true);

  b.profiles['prof_mason'] = ServiceProfile(
      id: 'prof_mason',
      ownerId: SeedIds.mason,
      kind: ProfileKind.individual,
      name: 'Болат · 瓦工',
      trades: const ['mason', 'plasterer'],
      regions: const ['talgar', 'almaty'],
      availability: Availability.now,
      availabilityConfirmedAt: ago(1),
      experienceYears: 12,
      refPrices: const [
        RefPrice(amount: 6000, unit: 'm3', scope: '仅人工，砌块墙每立方米起'),
        RefPrice(amount: 18000, unit: 'day', scope: '日薪，含自带小工具'),
      ],
      bio: '砌墙、抹灰十二年，做过二十多栋乡村住宅。可带一名小工。',
      works: const [
        Work(
            id: 'w1',
            title: '塔尔加尔 两层砖房外墙',
            source: WorkSource.uploaded,
            photoCount: 4),
      ]);
  b.profiles['prof_team'] = ServiceProfile(
      id: 'prof_team',
      ownerId: SeedIds.team,
      kind: ProfileKind.team,
      name: 'Нұрлан Құрылыс 施工队',
      trades: const ['general', 'mason', 'concrete', 'rebar'],
      regions: const ['almaty', 'talgar', 'kaskelen', 'esik'],
      availability: Availability.fromDate,
      availableFrom: now.add(const Duration(days: 10)),
      availabilityConfirmedAt: ago(3),
      experienceYears: 8,
      teamSize: 7,
      refPrices: const [
        RefPrice(amount: 7000, unit: 'm3', scope: '仅人工，砌墙'),
        RefPrice(amount: 45000, unit: 'm3', scope: '包工包料，基础混凝土'),
      ],
      bio: '七人施工队，承接基础、主体、砌墙。报价写清范围和不包含项。');
  b.profiles['prof_elec'] = ServiceProfile(
      id: 'prof_elec',
      ownerId: SeedIds.electrician,
      kind: ProfileKind.individual,
      name: 'Ерлан · 电工',
      trades: const ['electrician'],
      regions: const ['almaty', 'konaev'],
      availability: Availability.now,
      availabilityConfirmedAt: ago(0, 5),
      experienceYears: 6,
      refPrices: const [
        RefPrice(amount: 4500, unit: 'pcs', scope: '仅人工，每个点位')
      ]);
  b.profiles['prof_roof'] = ServiceProfile(
      id: 'prof_roof',
      ownerId: SeedIds.roofTeam,
      kind: ProfileKind.team,
      name: 'Алатау 屋面队',
      trades: const ['roofer', 'carpenter', 'general'],
      regions: const ['esik', 'talgar', 'almaty'],
      availability: Availability.notTaking,
      availabilityConfirmedAt: ago(20),
      teamSize: 4,
      bio: '木屋架、金属瓦屋面。');

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
            title: '130 平米住宅砌墙',
            trades: const ['mason'],
            region: 'talgar',
            locality: '塔尔加尔 · 北区',
            exactAddress: 'Талгар, ул. Абая 12',
            budget: const Budget(
                mode: BudgetMode.range,
                min: 1200000,
                max: 1600000,
                materials: MaterialMode.labourOnly),
            createdAt: ago(4),
            startDate: now.add(const Duration(days: 14)),
            durationDays: 25,
            description: '一层住宅，外墙 300 加气块，内墙 200。基础已完成，材料业主提供。',
            contract: ContractTerms(
                scopeKind: ScopeKind.stages,
                stages: const ['walls'],
                quantities: const [
                  QtyItem(
                      name: '外墙砌筑',
                      quantity: 62.5,
                      unit: 'm3',
                      source: QtySource.manual,
                      stage: 'walls'),
                  QtyItem(
                      name: '内墙砌筑',
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
            title: '找两名瓦工，按天结算',
            trades: const ['mason'],
            region: 'kaskelen',
            locality: '卡斯克连',
            budget: const Budget(
                mode: BudgetMode.fixed, amount: 20000, basis: 'day'),
            createdAt: ago(1),
            startDate: now.add(const Duration(days: 5)),
            durationDays: 10,
            description: '围墙和附属房砌砖，约 10 天。',
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
            title: '钢筋工 × 3 · 阿拉木图',
            trades: const ['rebar'],
            region: 'almaty',
            locality: '阿拉木图 · 阿拉套区',
            budget: const Budget(mode: BudgetMode.askQuote),
            createdAt: ago(2),
            description: '分包项目：两栋住宅的条形基础绑扎，工资面议。',
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
            title: '双坡屋面 · 金属瓦',
            trades: const ['roofer', 'carpenter'],
            region: 'esik',
            locality: '伊塞克',
            budget: const Budget(
                mode: BudgetMode.askQuote,
                materials: MaterialMode.labourAndMaterial),
            createdAt: ago(0, 6),
            description: '12 × 10 米住宅，木屋架 + 金属瓦，请包工包料报价。',
            contract: const ContractTerms(
                scopeKind: ScopeKind.stages,
                stages: ['roof'],
                quantities: [
                  QtyItem(
                      name: '屋面面积',
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
            title: '条形基础施工',
            trades: const ['concrete', 'rebar'],
            region: 'esik',
            locality: '伊塞克',
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
            scopeText: '外墙与内墙砌筑，含构造柱模板',
            materials: MaterialMode.labourOnly,
            pricing: PricingMode.perQuantity,
            lines: const [
              QuoteLine(
                  name: '外墙砌筑', quantity: 62.5, unit: 'm3', unitPrice: 7000),
              QuoteLine(
                  name: '内墙砌筑', quantity: 21, unit: 'm3', unitPrice: 6500),
            ],
            durationDays: 22,
            includes: '砂浆搅拌、脚手架',
            excludes: '材料、运输、垃圾清运',
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
            scopeText: '全部砌墙，两人施工',
            materials: MaterialMode.labourOnly,
            pricing: PricingMode.lumpSum,
            lumpSum: 1350000,
            durationDays: 30,
            includes: '砌筑、灰缝',
            excludes: '构造柱、圈梁、材料'),
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
            note: '可以带自己的瓦刀和水平尺。'),
      ]);
  b.notice(SeedIds.owner, NoticeKind.newApplication, RefType.demand, 'dem_wall',
      title: '130 平米住宅砌墙');
  b.notice(SeedIds.owner, NoticeKind.newApplication, RefType.demand, 'dem_hire',
      title: '找两名瓦工，按天结算');

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
            scopeText: '条形基础，包工包料',
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
            scope: '条形基础施工，包工包料',
            demandVersionNo: 1,
            proposedBy: SeedIds.owner2,
            confirmedBy: const {SeedIds.owner2, SeedIds.team},
            status: AgreementStatus.active,
            createdAt: ago(45),
            amount: 2100000,
            paymentTerms: '开工 30%，完工验收 70%',
            materialsResponsibility: '施工队采购全部材料'),
      ]);
  b.profiles['prof_team'] = b.profiles['prof_team']!.copyWith(works: const [
    Work(
        id: 'w2',
        title: '条形基础施工',
        source: WorkSource.platform,
        cooperationId: 'coop_found'),
    Work(
        id: 'w3',
        title: '卡斯克连 别墅主体',
        source: WorkSource.uploaded,
        photoCount: 6),
  ]);
  for (final (id, author, target, s, text) in [
    ('rev1', SeedIds.owner2, SeedIds.team, 5, '按约定工期完成，现场干净。'),
    ('rev2', SeedIds.team, SeedIds.owner2, 5, '付款准时，范围清楚。'),
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
      text: '您好，报价按图纸工程量算的，构造柱模板已包含。可以先来现场看一下吗？',
      sentAt: ago(3));
  b.messagesById['msg_s3'] = ChatMessage(
      id: 'msg_s3',
      conversationId: conv.id,
      senderId: SeedIds.owner,
      kind: MessageKind.text,
      text: '周六上午可以。',
      sentAt: ago(2, 20));
  b.messagesById['msg_s4'] = ChatMessage(
      id: 'msg_s4',
      conversationId: conv.id,
      senderId: SeedIds.team,
      kind: MessageKind.text,
      text: '好的，周六 10 点到。',
      sentAt: ago(0, 2));

  // One report waiting for the moderator.
  b.reportsById['rep_seed'] = Report(
      id: 'rep_seed',
      reporterId: SeedIds.mason,
      target: ReportTarget.demand,
      targetId: 'dem_rebar',
      reason: '工资信息不清楚',
      createdAt: ago(1));
}
