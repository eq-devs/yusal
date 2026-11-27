import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/features/shared/model/models.dart';

/// The design behind a plan cover, keyed by (snapshot id, post id, demand
/// id). Null when it cannot be read: the cover then shows its paper.
final coverSnapshotProvider = FutureProvider.autoDispose
    .family<DesignSnapshot?, (String, String?, String?)>((ref, key) async {
  final (snapshotId, postId, demandId) = key;
  try {
    return await ref
        .watch(snapshotRepositoryProvider)
        .snapshot(snapshotId, postId: postId, demandId: demandId);
  } catch (_) {
    return null;
  }
});
