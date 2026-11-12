import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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

/// Which account each local design belongs to, so one phone shared by
/// several accounts does not show one person's drafts to the next.
abstract class ProjectOwners {
  Future<Map<String, String>> load();
  Future<void> save(Map<String, String> owners);
}

/// Owners kept in shared preferences; failures leave designs unowned.
class PrefsProjectOwners implements ProjectOwners {
  static const _key = 'project-owners';
  @override
  Future<Map<String, String>> load() async {
    try {
      final text = (await SharedPreferences.getInstance()).getString(_key);
      return text == null
          ? {}
          : (jsonDecode(text) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, String> owners) async {
    try {
      await (await SharedPreferences.getInstance())
          .setString(_key, jsonEncode(owners));
    } catch (_) {}
  }
}

class ProjectStore {
  ProjectStore(
      {ProjectFileSystem? fileSystem,
      this.previewRenderer,
      this.owners})
      : files = fileSystem ?? ProjectFiles();
  final ProjectFileSystem files;
  final Future<List<int>?> Function(HouseDocument)? previewRenderer;
  /// Null keeps no owners: every design is listed (tests, tools).
  final ProjectOwners? owners;

  /// The signed-in account, read on every listing. Null shows the designs
  /// made while signed out. A design made signed out joins the first
  /// account that signs in on this device; after that only it sees it.
  String? Function()? currentOwner;
  final Map<String, String> corruptProjects = {};
  List<ProjectEntry> _entries = [];

  /// The index is rebuildable; failure must not hide readable source files.
  String? indexWarning;

  Future<void> _index() async {
    try {
      await files.writeIndex(jsonEncode([
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
      indexWarning = null;
    } catch (_) {
      indexWarning = 'INDEX_WRITE_FAILED';
    }
  }

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
    final owners = this.owners;
    if (owners != null) {
      final me = currentOwner?.call();
      final owned = await owners.load();
      var claimed = false;
      list.removeWhere((e) {
        if (owned[e.id] == null && me != null) {
          owned[e.id] = me;
          claimed = true;
        }
        return owned[e.id] != me;
      });
      corruptProjects
          .removeWhere((id, _) => owned[id] != null && owned[id] != me);
      if (claimed) await owners.save(owned);
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
    final me = currentOwner?.call(), owners = this.owners;
    if (me != null && owners != null)
      await owners.save({...await owners.load(), id: me});
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
