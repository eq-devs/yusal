import 'dart:convert';
import 'package:yusal/features/home/repository/post_repository.dart';
import 'package:flutter/material.dart';
import 'package:yusal/service/settings/settings.dart';
import 'package:yusal/features/editor/engine/core/document/house_document.dart';
import 'package:yusal/features/editor/engine/core/serialization/house_codec.dart';
import 'package:yusal/features/editor/page.dart';
import 'package:yusal/service/storage/project_store.dart';
import 'package:yusal/features/shared/model/models.dart';
import 'package:yusal/features/backup/page.dart';
import 'package:yusal/features/shared/ui/scope.dart';
import 'package:yusal/features/shell/page.dart';

/// "Start from this one": copies a public design into my houses, opens it
/// in the design tool and tells the author. No sign-in needed; only the
/// public plan is copied (no notes, specs or budget).
Future<String?> startFromPost(BuildContext context, HousePost post,
    {bool openEditor = true}) async {
  final plan = await attempt(
      context, () => context.read(postRepositoryProvider).reusePost(post.id));
  if (plan == null || !context.mounted) return null;
  final loaded = loadHouse(utf8.encode(plan));
  final doc = loaded.document;
  if (doc == null) {
    toast(context,
        tr3('这套设计暂时无法复制', 'Көшіру мүмкін болмады', 'Не удалось скопировать'));
    return null;
  }
  final now = DateTime.now().toUtc().toIso8601String();
  final copy = composeDocument(
      Meta(
          name: tr3('基于「${post.title}」的房子', '«${post.title}» негізіндегі үй',
              'Дом на основе «${post.title}»'),
          createdAt: now,
          updatedAt: now),
      extractDesignState(doc));
  final store = context.projectStore;
  final id = await store.createProject(copy);
  if (!context.mounted) return id;
  PlatformReload.of(context)?.bump();
  final nav = ShellNav.maybeOf(context);
  nav?.go(ShellTab.houses);
  toast(
      context,
      tr3('已复制到“我的房子”，改一下尺寸和房间，造价会自动更新', '«Үйлерім» ішіне көшірілді',
          'Скопировано в «Мои дома»'));
  if (openEditor) {
    final drafting = nav?.drafting ?? Theme.of(context);
    final opened = await store.openProject(id);
    if (!context.mounted) return id;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Theme(
            data: drafting,
            child:
                HouseEditor(entry: ProjectEntry(id, opened), store: store))));
    if (context.mounted) PlatformReload.of(context)?.bump();
  }
  return id;
}
