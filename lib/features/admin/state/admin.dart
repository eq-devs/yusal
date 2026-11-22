import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/admin/repository/admin_repository.dart';
import 'package:yusal/shared/model/admin_models.dart';

/// The first screen: what waits for a moderator, and the numbers.
final adminWorkbenchProvider =
    FutureProvider.autoDispose<(AdminTodo, AdminDashboard)>((ref) {
  final admin = ref.watch(adminRepositoryProvider);
  return (admin.todo(), admin.dashboard()).wait;
});

/// One account as the back office sees it.
final accountDetailProvider = FutureProvider.autoDispose
    .family<AccountDetail, String>((ref, accountId) =>
        ref.watch(adminRepositoryProvider).accountDetail(accountId));

/// Everyone with a back-office role.
final adminTeamProvider = FutureProvider.autoDispose<List<AdminUserRow>>(
    (ref) => ref.watch(adminRepositoryProvider).team());

/// How often and when pushes may go out.
final pushPolicyProvider = FutureProvider.autoDispose<PushPolicy>(
    (ref) => ref.watch(adminRepositoryProvider).pushPolicy());

/// Pages 1…[pages] of a back-office list, in order, as one list, and
/// whether there are more. A list's query lives in [load], so each list
/// gets its own provider, made by its widget; asking for another page
/// invalidates it, keeping the list on screen while it loads.
AutoDisposeFutureProvider<(List<T>, bool)> pagedListProvider<T>(
        Future<Paged<T>> Function(int page) load, int Function() pages) =>
    FutureProvider.autoDispose<(List<T>, bool)>((ref) async {
      final out = <T>[];
      var more = false;
      final last = pages();
      for (var p = 1; p <= last; p++) {
        final page = await load(p);
        out.addAll(page.items);
        more = page.hasMore;
        if (!more) break;
      }
      return (out, more);
    });
