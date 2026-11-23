import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/profile/repository/profile_repository.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/shared/state/session.dart';

/// Whether the signed-in account has a pro profile (and so a "my work" tab).
final isProProvider = FutureProvider.autoDispose<bool>((ref) async =>
    ref.watch(sessionProvider).currentAccount != null &&
    (await ref.watch(profileRepositoryProvider).myProfiles()).isNotEmpty);

/// My cooperations with their demands' titles. [retry] is bumped by the
/// page's refresh button.
final myCooperationsProvider = FutureProvider.autoDispose
    .family<List<(Cooperation, String)>, int>((ref, retry) async {
  final demands = ref.watch(demandRepositoryProvider);
  final cooperations =
      await ref.watch(cooperationRepositoryProvider).myCooperations();
  final titles = <String, String>{};
  await Future.wait(cooperations.map((c) => c.demandId).toSet().map((id) async {
    try {
      titles[id] = (await demands.demand(id))?.current.title ??
          tr3('需求已不可见', 'Тапсырыс қолжетімсіз', 'Заявка недоступна', 'Request unavailable');
    } catch (_) {
      titles[id] = tr3('标题暂不可用', 'Атауы уақытша қолжетімсіз',
          'Название временно недоступно',
          'Title temporarily unavailable');
    }
  }));
  return [for (final c in cooperations) (c, titles[c.demandId]!)];
});
