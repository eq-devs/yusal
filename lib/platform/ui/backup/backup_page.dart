import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/settings.dart';
import '../../../core/document/house_document.dart';
import '../../../core/serialization/house_codec.dart';
import '../../../storage/project_store.dart';
import '../../data/repositories.dart';
import '../../domain/models.dart';
import '../l10n.dart';
import '../scope.dart';
import '../theme.dart';
import '../widgets.dart';

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

/// Compares the local design with its cloud copy.
BackupState backupState(
    String localUpdatedAt, BackupRecord? cloud, String? lastSynced) {
  if (cloud == null) return BackupState.none;
  if (cloud.designUpdatedAt == localUpdatedAt) return BackupState.inSync;
  final localChanged = lastSynced == null || localUpdatedAt != lastSynced;
  final cloudChanged =
      lastSynced == null || cloud.designUpdatedAt != lastSynced;
  if (localChanged && cloudChanged) return BackupState.diverged;
  return localChanged ? BackupState.localNewer : BackupState.cloudNewer;
}

class _Row {
  _Row(this.entry, this.cloud, this.mark);
  final ProjectEntry? entry;
  final BackupRecord? cloud;
  final String? mark;
}

/// Account backup and restore of local designs. Local saving keeps working
/// offline; a failed upload changes nothing locally; conflicts are never
/// resolved silently.
class BackupPage extends StatelessWidget {
  const BackupPage({super.key, this.highlight});
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    AppScope.watch(context);
    final t = YTokens.of(context);
    final store = context.projectStore;
    return PageScaffold(
        title: tr3('备份与恢复', 'Сақтық көшірме', 'Резервные копии'),
        body: OnChange(
            builder: (context) => context.repos.currentAccount == null
                ? EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: tr3(
                        '登录后可以把设计备份到账号',
                        'Кіргеннен кейін сақтауға болады',
                        'Войдите, чтобы сохранять проекты в аккаунт'),
                    action: FilledButton(
                        onPressed: () => requireLogin(context),
                        child: Text(tr3('登录', 'Кіру', 'Войти'))))
                : Live<List<_Row>>(
                    load: (r) async {
                      final local = await store.listProjects();
                      final cloud = {
                        for (final b in await r.backups()) b.projectId: b
                      };
                      return [
                        for (final e in local)
                          _Row(e, cloud.remove(e.id),
                              await BackupMarks.read(e.id)),
                        for (final b in cloud.values) _Row(null, b, null),
                      ];
                    },
                    builder: (context, rows) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Hint(tr3(
                                  '本地保存和自动保存照常工作，不登录也能离线编辑。备份是手动的，不是实时同步；两边都改过时会让你选择，不会静默覆盖。',
                                  'Жергілікті сақтау әрдайым жұмыс істейді. Көшірме қолмен жасалады.',
                                  'Локальное сохранение работает всегда. Копия делается вручную, конфликты решаете вы.')),
                              const SizedBox(height: 16),
                              if (rows.isEmpty)
                                EmptyState(
                                    icon: Icons.folder_open,
                                    title: tr3(
                                        '还没有设计', 'Жоба жоқ', 'Нет проектов')),
                              for (final row in rows)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _BackupTile(
                                        row: row,
                                        highlighted:
                                            row.entry?.id == highlight)),
                              if (context.mock != null &&
                                  rows.any((r) =>
                                      r.cloud != null && r.entry != null)) ...[
                                const SizedBox(height: 12),
                                Text('Dev', style: TextStyle(color: t.faint)),
                                TextButton(
                                    onPressed: () {
                                      final row = rows.firstWhere((r) =>
                                          r.cloud != null && r.entry != null);
                                      context.mock!.touchBackupFromOtherDevice(
                                          row.entry!.id,
                                          row.cloud!.houseText,
                                          DateTime.now()
                                              .toUtc()
                                              .toIso8601String());
                                    },
                                    child: Text(tr3(
                                        '模拟另一台设备修改了云端备份',
                                        'Басқа құрылғыдан өзгерту',
                                        'Имитировать изменение с другого устройства'))),
                              ],
                            ]))));
  }
}

class _BackupTile extends StatelessWidget {
  const _BackupTile({required this.row, required this.highlighted});
  final _Row row;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final t = YTokens.of(context);
    final e = row.entry, cloud = row.cloud;
    final repos = context.repos;
    final store = context.projectStore;
    final state = e == null
        ? null
        : backupState(e.document.meta.updatedAt, cloud, row.mark);
    final name = e?.document.meta.name ?? cloud!.name;

    late Future<void> Function() resolveConflict;

    Future<void> upload({bool force = false}) async {
      final doc = e!.document;
      try {
        await repos.upload(
            projectId: e.id,
            name: doc.meta.name,
            houseText: encodeHouse(doc),
            designUpdatedAt: doc.meta.updatedAt,
            expectedPreviousUpdatedAt: force ? null : row.mark);
        await BackupMarks.write(e.id, doc.meta.updatedAt);
        if (context.mounted)
          toast(context, tr3('已备份', 'Сақталды', 'Сохранено'));
      } on ApiFailure catch (f) {
        if (!context.mounted) return;
        if (f.code == ApiCodes.conflict) {
          await resolveConflict();
        } else {
          toast(context,
              '${failureText(f)} · ${tr3('本地设计未受影响，待重试', 'Жергілікті жоба сақталды', 'Локальный проект не затронут')}');
        }
      }
    }

    /// Restores the cloud copy as a new local design; nothing is overwritten.
    Future<void> restoreAsCopy({required bool copy}) async {
      final c = await repos.backup(cloud!.projectId);
      if (c == null) return;
      final loaded = loadHouse(utf8.encode(c.houseText));
      if (!loaded.isSuccess) {
        if (context.mounted)
          toast(
              context,
              tr3(
                  '此备份的文件版本不受支持，无法恢复；原文件未改动。',
                  'Бұл нұсқа қолдау көрсетілмейді.',
                  'Версия файла не поддерживается; ничего не изменено.'));
        return;
      }
      final doc = loaded.document!;
      final id = await store.createProject(copy
          ? composeDocument(
              Meta(
                  name:
                      '${doc.meta.name}（${tr3('云端副本', 'бұлт көшірмесі', 'копия из облака')}）',
                  createdAt: doc.meta.createdAt,
                  updatedAt: doc.meta.updatedAt),
              extractDesignState(doc))
          : doc);
      if (!copy) await BackupMarks.write(id, doc.meta.updatedAt);
      PlatformReload.of(context)?.bump();
      if (context.mounted)
        toast(context, tr3('已恢复到本设备', 'Қалпына келтірілді', 'Восстановлено'));
    }

    resolveConflict = () async {
      final choice = await pickOne<String>(
          context,
          tr3('本地和云端都改过', 'Екі жақта да өзгерген',
              'Изменено и здесь, и в облаке'),
          [
            (
              'local',
              tr3(
                  '用本机版本覆盖云端（本机 ${e!.document.meta.updatedAt.substring(0, 16)}）',
                  'Бұлтқа осы құрылғыны жазу',
                  'Записать в облако версию с этого устройства')
            ),
            (
              'copy',
              tr3(
                  '把云端版本恢复为副本（云端 ${fmtDay(cloud?.backedUpAt)}）',
                  'Бұлт нұсқасын көшірме етіп алу',
                  'Восстановить облачную версию как копию')
            ),
          ]);
      if (choice == 'local') await upload(force: true);
      if (choice == 'copy') await restoreAsCopy(copy: true);
    };

    final (label, color) = switch (state) {
      null => (tr3('仅在云端', 'Тек бұлтта', 'Только в облаке'), t.info),
      BackupState.none => (tr3('未备份', 'Сақталмаған', 'Нет копии'), t.muted),
      BackupState.inSync => (
          tr3('已备份 · ${fmtDay(cloud?.backedUpAt)}', 'Сақталған', 'Сохранено'),
          t.ok
        ),
      BackupState.localNewer => (
          tr3('本机有新修改', 'Жаңа өзгерістер', 'Есть новые изменения'),
          t.warn
        ),
      BackupState.cloudNewer => (
          tr3('云端较新', 'Бұлттағысы жаңа', 'В облаке новее'),
          t.info
        ),
      BackupState.diverged => (
          tr3('两边都改过', 'Екі жақта өзгерген', 'Конфликт версий'),
          t.crit
        ),
    };
    return YCard(
        color: highlighted ? t.accentSoft : null,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(e == null ? Icons.cloud_outlined : Icons.home_outlined),
            const SizedBox(width: 12),
            Expanded(
                child: Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15))),
            StatusPill(label, color: color),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (e != null && state != BackupState.inSync)
              OutlinedButton(
                  onPressed: state == BackupState.diverged
                      ? resolveConflict
                      : () => upload(),
                  child: Text(state == BackupState.diverged
                      ? tr3('选择保留哪个', 'Таңдау', 'Выбрать версию')
                      : tr3('备份', 'Сақтау', 'Сохранить копию'))),
            if (cloud != null && e == null)
              OutlinedButton(
                  onPressed: () => restoreAsCopy(copy: false),
                  child: Text(
                      tr3('恢复到本设备', 'Осы құрылғыға', 'Восстановить сюда'))),
            if (cloud != null && e != null && state != BackupState.inSync)
              TextButton(
                  onPressed: () => restoreAsCopy(copy: true),
                  child: Text(tr3('恢复云端为副本', 'Көшірме ретінде',
                      'Облачную копию — как новый проект'))),
          ]),
        ]));
  }
}

/// Lets the backup page tell the design list that designs were added.
class PlatformReload extends InheritedWidget {
  const PlatformReload(
      {super.key, required this.notifier, required super.child});
  final ReloadNotifier notifier;
  static ReloadNotifier? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlatformReload>()?.notifier;
  @override
  bool updateShouldNotify(PlatformReload old) => false;
}

class ReloadNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}
