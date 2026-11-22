import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yusal/features/backup/repository/backup_repository.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'package:yusal/features/shared/model/models.dart';

/// What this device last synced per design, so a cloud copy changed on
/// another device is recognised instead of overwritten.
abstract final class BackupMarks {
  static String _key(String id) => 'backup-synced-$id';
  static Future<String?> read(String id) async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key(id));
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String id, String updatedAt) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_key(id), updatedAt);
    } catch (_) {/* Marks are a convenience. */}
  }
}

/// One design on the backup page: on this device, in the cloud, or both,
/// with what this device last synced.
class BackupRow {
  BackupRow(this.entry, this.cloud, this.mark);
  final ProjectEntry? entry;
  final BackupRecord? cloud;
  final String? mark;
}

/// Local designs side by side with their cloud backups. A restore writes
/// to this device only, which the backend does not report: the page
/// reloads it by hand.
final backupRowsProvider =
    FutureProvider.autoDispose<List<BackupRow>>((ref) async {
  final store = ref.watch(projectStoreProvider);
  final repo = ref.watch(backupRepositoryProvider);
  final local = await store.listProjects();
  final cloud = {for (final b in await repo.backups()) b.projectId: b};
  return [
    for (final e in local)
      BackupRow(e, cloud.remove(e.id), await BackupMarks.read(e.id)),
    for (final b in cloud.values) BackupRow(null, b, null),
  ];
});
