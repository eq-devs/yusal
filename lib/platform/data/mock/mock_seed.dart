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
      role: ProRole.contractor,
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
      role: ProRole.contractor,
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
            snapshotId: 'snap_aigerim',
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

  // Snapshots and house posts: the feed everyone sees first.
  final demoFacts = <String, DesignExtract>{};
  DesignSnapshot snap(String id, String owner, String project, String name,
      String summary, List<QtyItem> lines) {
    var counter = 0;
    final kind = id == 'snap_erlan' || id == 'snap_dinara' ? 'two' : 'three';
    final doc = createTemplate(kind, ago(6).toUtc().toIso8601String(), () => 'demo${counter++}');
    final facts = extractDesign(doc, snapshotStages);
    demoFacts[id] = facts;
    final frozen = buildSnapshot(projectId: project, doc: doc, stages: snapshotStages,
        lines: lines, summary: '${facts.width / 1000} × ${facts.depth / 1000} m · ${facts.floors} floors · DEMO');
    return DesignSnapshot(id: id, ownerId: owner, projectId: project,
        projectName: '$name · DEMO', designUpdatedAt: doc.meta.updatedAt,
        extractedAt: ago(6), stages: snapshotStages, lines: lines,
        summary: frozen.summary, planJson: frozen.planJson);
  }
  const q = QtySource.design;
  b.snapshots['snap_aigerim'] = snap('snap_aigerim', SeedIds.owner, 'seed_p1',
      '塔尔加尔一层砖房', '12 × 11 m，一层，130 m²，4 个房间', const [
    QtyItem(
        name: '条形基础混凝土', quantity: 28, unit: 'm3', source: q, stage: 'found'),
    QtyItem(name: '外墙砌筑', quantity: 62, unit: 'm3', source: q, stage: 'walls'),
    QtyItem(name: '内墙砌筑', quantity: 21, unit: 'm3', source: q, stage: 'walls'),
    QtyItem(name: '屋面', quantity: 168, unit: 'm2', source: q, stage: 'roof'),
  ]);
  b.snapshots['snap_dinara'] = snap('snap_dinara', SeedIds.owner2, 'seed_p2',
      '卡斯克连两层别墅', '14 × 12 m，两层，290 m²，7 个房间，带车库', const [
    QtyItem(
        name: '条形基础混凝土', quantity: 46, unit: 'm3', source: q, stage: 'found'),
    QtyItem(name: '外墙砌筑', quantity: 128, unit: 'm3', source: q, stage: 'walls'),
    QtyItem(name: '楼板', quantity: 168, unit: 'm2', source: q, stage: 'walls'),
    QtyItem(name: '屋面', quantity: 210, unit: 'm2', source: q, stage: 'roof'),
  ]);
  b.snapshots['snap_team'] = snap('snap_team', SeedIds.team, 'seed_p3',
      '伊西克紧凑型住宅', '10 × 9 m，一层，86 m²，3 个房间', const [
    QtyItem(
        name: '条形基础混凝土', quantity: 19, unit: 'm3', source: q, stage: 'found'),
    QtyItem(name: '外墙砌筑', quantity: 44, unit: 'm3', source: q, stage: 'walls'),
    QtyItem(name: '屋面', quantity: 118, unit: 'm2', source: q, stage: 'roof'),
  ]);
  b.snapshots['snap_erlan'] = snap('snap_erlan', SeedIds.electrician, 'seed_p4',
      '阿拉木图郊区一层半', '11 × 10 m，一层加阁楼，150 m²，5 个房间', const [
    QtyItem(
        name: '条形基础混凝土', quantity: 25, unit: 'm3', source: q, stage: 'found'),
    QtyItem(name: '外墙砌筑', quantity: 58, unit: 'm3', source: q, stage: 'walls'),
    QtyItem(name: '屋面', quantity: 172, unit: 'm2', source: q, stage: 'roof'),
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
          likeCount: likes);
  b.posts['post_aigerim'] = post('post_aigerim', SeedIds.owner, 'snap_aigerim',
      '给父母盖的一层砖房', '父母年纪大了，想要一层、没有台阶的房子。客厅朝南，两个卧室朝东。基础已经打好，现在找砌墙的师傅。', 'talgar',
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
      '两层别墅，带车库和露台',
      '一家五口住。一楼公共空间，二楼四个卧室。想明年春天开工，先听听大家的意见，预算是不是合理。',
      'kaskelen',
      area: 290,
      floors: 2,
      rooms: 7,
      cost: 52000000,
      days: 12,
      tags: const ['two_floors', 'garage', 'large'],
      likes: 5);
  b.posts['post_team'] = post(
      'post_team',
      SeedIds.team,
      'snap_team',
      '86 平米紧凑型住宅方案（可承建）',
      '我们施工队做过三栋这个户型，工期 70 天左右。分享出来给预算有限的家庭参考，欢迎直接联系。',
      'esik',
      area: 86,
      floors: 1,
      rooms: 3,
      cost: 11800000,
      days: 20,
      tags: const ['one_floor', 'budget'],
      open: false,
      likes: 2);
  b.posts['post_erlan'] = post('post_erlan', SeedIds.electrician, 'snap_erlan',
      '一层半带阁楼，自己画的第一版', '第一次用软件画房子，阁楼想做两个孩子的房间。不确定楼梯位置合不合理，请大家看看。', 'almaty',
      area: 150,
      floors: 2,
      rooms: 5,
      cost: 23000000,
      days: 2,
      tags: const ['brick'],
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
      {int? rating}) {
    b.commentsById[id] = PostComment(
        id: id,
        postId: postId,
        authorId: author,
        text: text,
        createdAt: ago(days),
        rating: rating);
    final p = b.posts[postId]!;
    b.posts[postId] = p.copyWith(
        commentCount: p.commentCount + 1,
        ratingSum: p.ratingSum + (rating ?? 0),
        ratingCount: p.ratingCount + (rating == null ? 0 : 1));
  }

  cmt('cmt1', 'post_aigerim', SeedIds.mason, '布局很实用。外墙 300 加气块冬天够用，建议内墙也做 200。',
      5,
      rating: 5);
  cmt('cmt2', 'post_aigerim', SeedIds.team,
      '基础 28 方混凝土对 130 平米来说偏少，建议复核一下地基宽度。', 4,
      rating: 4);
  cmt('cmt3', 'post_dinara', SeedIds.roofTeam,
      '双坡屋面 210 平米，金属瓦大概 3 周。预算里屋面部分合理。', 10,
      rating: 4);
  cmt('cmt4', 'post_dinara', SeedIds.owner, '很漂亮，二楼卫生间最好和一楼上下对齐，省管道。', 9,
      rating: 5);
  cmt('cmt5', 'post_erlan', SeedIds.owner2, '楼梯放客厅角落会更省空间。', 1);

  // One report waiting for the moderator.
  b.reportsById['rep_seed'] = Report(
      id: 'rep_seed',
      reporterId: SeedIds.mason,
      target: ReportTarget.demand,
      targetId: 'dem_rebar',
      reason: '工资信息不清楚',
      createdAt: ago(1));
}
