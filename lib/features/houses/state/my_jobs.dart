import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/apply/repository/application_repository.dart';
import 'package:yusal/features/coop/repository/cooperation_repository.dart';
import 'package:yusal/features/demand/repository/demand_repository.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/shared/state/session.dart';

/// What "我接的活" shows: my quotes, the cooperations where I am the pro,
/// and the titles of the demands they belong to.
class MyJobs {
  MyJobs(this.me, this.apps, this.coops, this.titles);
  final String me;
  final List<Application> apps;
  final List<Cooperation> coops;
  final Map<String, String> titles;
}

final myJobsProvider = FutureProvider.autoDispose<MyJobs>((ref) async {
  final demands = ref.watch(demandRepositoryProvider);
  final me = ref.watch(sessionProvider).currentAccount!.id;
  final apps = await ref.watch(applicationRepositoryProvider).myApplications();
  final coops =
      (await ref.watch(cooperationRepositoryProvider).myCooperations())
          .where((c) => c.providerId == me)
          .toList();
  final titles = <String, String>{};
  for (final id in {
    ...apps.map((a) => a.demandId),
    ...coops.map((c) => c.demandId)
  }) {
    try {
      titles[id] = (await demands.demand(id))?.current.title ?? '';
    } catch (_) {
      titles[id] = '';
    }
  }
  return MyJobs(me, apps, coops, titles);
});

/// One cooperation, for its site page.
final siteCooperationProvider = FutureProvider.autoDispose
    .family<Cooperation?, String>(
        (ref, id) => ref.watch(cooperationRepositoryProvider).cooperation(id));
