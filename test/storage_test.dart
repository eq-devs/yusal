import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:yusal/core/commands/room_commands.dart';
import 'package:yusal/storage/project_store.dart';
import 'package:yusal/storage/house_import.dart';
import 'package:yusal/core/house_core.dart';

class MemoryFiles implements ProjectFileSystem {
  final documents = <String, String>{};
  String? index;
  final previews = <String, List<int>>{};
  bool failWrites = false;
  int writeCount = 0;
  @override
  Future<List<String>> ids() async => documents.keys.toList();
  @override
  Future<String?> read(String id) async => documents[id];
  @override
  Future<void> write(String id, String text) async {
    if (failWrites) throw const StorageFailure('NO_SPACE', 'Injected failure');
    writeCount++;
    documents[id] = text;
  }

  @override
  Future<void> delete(String id) async {
    documents.remove(id);
  }

  @override
  Future<List<int>?> readPreview(String id) async => previews[id];
  @override
  Future<void> writePreview(String id, List<int> bytes) async {
    previews[id] = bytes;
  }

  @override
  Future<String?> readIndex() async => index;
  @override
  Future<void> writeIndex(String text) async {
    index = text;
  }
}

void main() {
  var sequence = 0;
  final doc = createHouse(
      name: '存储测试',
      width: 12000,
      depth: 10000,
      columns: 2,
      rows: 2,
      timestamp: '2026-09-30T00:00:00Z',
      newId: () => 'id${sequence++}');
  test('project round trip, index and deletion', () async {
    final files = MemoryFiles(),
        store = ProjectStore(fileSystem: MemoryFiles());
    final tested = ProjectStore(fileSystem: files);
    final id = await tested.createProject(doc);
    expect(await tested.openProject(id), doc);
    expect((jsonDecode(files.index!) as List).length, 1);
    expect((await tested.listProjects()).single.id, id);
    await tested.deleteProject(id);
    expect(await tested.listProjects(), isEmpty);
    expect(await store.listProjects(), isEmpty);
  });
  test('corrupt projects are visible and deletable', () async {
    final files = MemoryFiles()..documents['broken'] = '{bad json';
    final store = ProjectStore(fileSystem: files);
    expect(await store.listProjects(), isEmpty);
    expect(store.corruptProjects.keys, contains('broken'));
    await store.deleteProject('broken');
    expect(store.corruptProjects, isEmpty);
  });
  test('failed writes keep the last saved document', () async {
    final files = MemoryFiles();
    final store = ProjectStore(fileSystem: files);
    final id = await store.createProject(doc);
    final before = files.documents[id];
    files.failWrites = true;
    await expectLater(
        store.saveProject(id, doc), throwsA(isA<StorageFailure>()));
    expect(files.documents[id], before);
  });
  test('thumbnail failure never loses a saved document', () async {
    final files = MemoryFiles();
    final store = ProjectStore(
        fileSystem: files,
        previewRenderer: (_) async => throw StateError('codec unavailable'));
    final id = await store.createProject(doc);
    expect(await store.openProject(id), doc);
    await store.saveProject(id, doc);
    expect(
        (await store.listProjects()).single.document.meta.name, doc.meta.name);
  });
  test('known oversized imports are rejected without reading their stream',
      () async {
    var read = false;
    Stream<List<int>> source() async* {
      read = true;
      yield [0];
    }

    final result = await loadHouseStream(source(), length: maxHouseBytes + 1);
    expect(read, isFalse);
    expect(result.failure!.stage, 'file');
    expect(result.failure!.errors.single.code, 'FILE_TOO_LARGE');
  });
  test('stream imports enforce the hard limit and accept valid UTF-8',
      () async {
    final oversized = await loadHouseStream(
        Stream.value(List<int>.filled(maxHouseBytes + 1, 0)));
    expect(oversized.failure!.errors.single.code, 'FILE_TOO_LARGE');
    final loaded =
        await loadHouseStream(Stream.value(utf8.encode(encodeHouse(doc))));
    expect(loaded.document, doc);
  });
}
