import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yusal/storage/project_file_system.dart';

class ProjectFiles implements ProjectFileSystem {
  @override
  Future<List<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs
        .getKeys()
        .where((k) => k.startsWith('house:'))
        .map((k) => k.substring(6))
        .toList();
  }

  @override
  Future<String?> read(String id) async =>
      (await SharedPreferences.getInstance()).getString('house:$id');
  @override
  Future<void> write(String id, String text) async {
    if (!await (await SharedPreferences.getInstance())
        .setString('house:$id', text)) {
      throw StateError('无法保存');
    }
  }

  @override
  Future<List<int>?> readPreview(String id) async {
    final text =
        (await SharedPreferences.getInstance()).getString('preview:$id');
    return text == null ? null : base64Decode(text);
  }

  @override
  Future<void> writePreview(String id, List<int> bytes) async {
    if (!await (await SharedPreferences.getInstance())
        .setString('preview:$id', base64Encode(bytes))) {
      throw const StorageFailure('IO_ERROR', 'Preview write failed');
    }
  }

  @override
  Future<String?> readIndex() async =>
      (await SharedPreferences.getInstance()).getString('house-index');
  @override
  Future<void> writeIndex(String text) async {
    if (!await (await SharedPreferences.getInstance())
        .setString('house-index', text)) {
      throw const StorageFailure('IO_ERROR', 'Index write failed');
    }
  }

  @override
  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('house:$id');
    await prefs.remove('preview:$id');
  }
}
