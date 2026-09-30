import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../core/document/house_document.dart';
import '../core/serialization/house_codec.dart';
import 'project_file_system.dart';
export 'project_file_system.dart';
import 'project_files_web.dart' if (dart.library.io) 'project_files_io.dart';

class ProjectEntry {
  const ProjectEntry(this.id, this.document, {this.preview});
  final String id;
  final HouseDocument document;
  final List<int>? preview;
}

class ProjectStore {
  ProjectStore({ProjectFileSystem? fileSystem, this.previewRenderer})
      : files = fileSystem ?? ProjectFiles();
  final ProjectFileSystem files;
  final Future<List<int>?> Function(HouseDocument)? previewRenderer;
  final Map<String, String> corruptProjects = {};
  List<ProjectEntry> _entries = [];

  Future<void> _index() => files.writeIndex(jsonEncode([
        for (final entry in _entries)
          {
            'projectId': entry.id,
            'name': entry.document.meta.name,
            'updatedAt': entry.document.meta.updatedAt,
            'hasPreview': entry.preview != null
          },
        for (final entry in corruptProjects.entries)
          {'projectId': entry.key, 'failure': entry.value},
      ]));

  Future<HouseDocument> openProject(String id) async {
    final text = await files.read(id);
    if (text == null)
      throw const StorageFailure('NOT_FOUND', 'Project document is missing');
    final result = loadHouse(utf8.encode(text));
    if (!result.isSuccess)
      throw const StorageFailure('IO_ERROR', 'Project document is invalid');
    return result.document!;
  }

  Future<List<ProjectEntry>> rebuildIndex() => listProjects();
  Future<List<ProjectEntry>> listProjects() async {
    final list = <ProjectEntry>[];
    corruptProjects.clear();
    for (final id in await files.ids()) {
      try {
        final text = await files.read(id);
        if (text == null) {
          corruptProjects[id] = '设计文件缺失或超过大小限制';
          continue;
        }
        final loaded = loadHouse(utf8.encode(text));
        if (loaded.isSuccess) {
          List<int>? preview;
          try {
            preview = await files.readPreview(id);
          } catch (_) {/* Preview is optional. */}
          list.add(ProjectEntry(id, loaded.document!, preview: preview));
        } else {
          corruptProjects[id] = '文件内容有误，无法打开';
        }
      } catch (_) {
        corruptProjects[id] = '无法读取设计文件';
      }
    }
    list.sort((a, b) => DateTime.parse(b.document.meta.updatedAt)
        .compareTo(DateTime.parse(a.document.meta.updatedAt)));
    _entries = list;
    await _index();
    return list;
  }

  Future<String> createProject(HouseDocument doc) async {
    final id = const Uuid().v4();
    await files.write(id, encodeHouse(doc));
    final preview = await _preview(id, doc);
    _entries.add(ProjectEntry(id, doc, preview: preview));
    await _index();
    return id;
  }

  Future<HouseDocument> saveProject(String id, HouseDocument doc) async {
    final timestamp = DateTime.now().toUtc().toIso8601String();
    final saved = composeDocument(
        Meta(
            name: doc.meta.name,
            createdAt: doc.meta.createdAt,
            updatedAt: timestamp),
        extractDesignState(doc));
    await files.write(id, encodeHouse(saved));
    _entries.removeWhere((e) => e.id == id);
    final preview = await _preview(id, saved);
    _entries.add(ProjectEntry(id, saved, preview: preview));
    await _index();
    return saved;
  }

  Future<List<int>?> _preview(String id, HouseDocument doc) async {
    try {
      final bytes = await previewRenderer?.call(doc);
      if (bytes != null) await files.writePreview(id, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteProject(String id) async {
    await files.delete(id);
    _entries.removeWhere((e) => e.id == id);
    corruptProjects.remove(id);
    await _index();
  }
}
