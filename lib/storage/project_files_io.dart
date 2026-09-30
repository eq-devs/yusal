import 'dart:io';
import 'dart:convert';
import 'project_file_system.dart';
import 'package:path_provider/path_provider.dart';

class ProjectFiles implements ProjectFileSystem {
  bool cleaned = false;
  Future<Directory> root() async {
    final dir = Directory(
        '${(await getApplicationDocumentsDirectory()).path}/projects');
    await dir.create(recursive: true);
    if (!cleaned) {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File && entity.path.endsWith('.tmp'))
          await entity.delete();
      }
      cleaned = true;
    }
    return dir;
  }

  Future<List<String>> ids() async {
    final dir = await root();
    final result = <String>[];
    await for (final entity in dir.list()) {
      if (entity is Directory)
        result.add(entity.path.split(Platform.pathSeparator).last);
    }
    return result;
  }

  Future<String?> read(String id) async {
    final file = File('${(await root()).path}/$id/document.house');
    if (!await file.exists()) return null;
    if (await file.length() > 10485760) return null;
    final bytes = <int>[];
    await for (final chunk in file.openRead()) {
      if (bytes.length + chunk.length > 10485760)
        throw const StorageFailure('IO_ERROR', 'Project exceeds 10 MiB');
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes);
  }

  Future<void> write(String id, String text) async {
    final directory = Directory('${(await root()).path}/$id');
    await directory.create(recursive: true);
    final temp = File('${directory.path}/document.house.tmp');
    try {
      await temp.writeAsString(text, flush: true);
      await temp.rename('${directory.path}/document.house');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<List<int>?> readPreview(String id) async {
    final file = File('${(await root()).path}/$id/preview.webp');
    if (!await file.exists() || await file.length() > 1048576) return null;
    return file.readAsBytes();
  }

  Future<void> writePreview(String id, List<int> bytes) async {
    final directory = Directory('${(await root()).path}/$id');
    final temp = File('${directory.path}/preview.webp.tmp');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename('${directory.path}/preview.webp');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<String?> readIndex() async {
    final file = File('${(await root()).path}/index.json');
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> writeIndex(String text) async {
    final directory = await root();
    final temp = File('${directory.path}/index.json.tmp');
    try {
      await temp.writeAsString(text, flush: true);
      await temp.rename('${directory.path}/index.json');
    } catch (_) {
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final dir = Directory('${(await root()).path}/$id');
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
