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
  bool failIndex = false;
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
    if (failIndex) throw const StorageFailure('NO_SPACE', 'Index full');
    index = text;
  }
}

class MemoryOwners implements ProjectOwners {
  Map<String, String> map = {};
  @override
  Future<Map<String, String>> load() async => {...map};
  @override
  Future<void> save(Map<String, String> owners) async => map = {...owners};
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
  test('each account lists only its own designs', () async {
    String? me;
    final store = ProjectStore(fileSystem: MemoryFiles(), owners: MemoryOwners())
      ..currentOwner = () => me;
    final guest = await store.createProject(doc);
    me = 'aigerim';
    final mine = await store.createProject(doc);
    // The design made signed out joins the first account that signs in.
    expect({for (final e in await store.listProjects()) e.id}, {guest, mine});
    me = 'bolat';
    expect(await store.listProjects(), isEmpty);
    final his = await store.createProject(doc);
    expect([for (final e in await store.listProjects()) e.id], [his]);
    me = null;
    expect(await store.listProjects(), isEmpty);
    me = 'aigerim';
    expect((await store.listProjects()).length, 2);
  });

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
  test('index failure leaves saved documents readable with a warning',
      () async {
    final files = MemoryFiles()..failIndex = true;
    final store = ProjectStore(fileSystem: files);
    final id = await store.createProject(doc);
    expect(store.indexWarning, isNotNull);
    expect((await store.listProjects()).single.id, id);
    await store.saveProject(id, doc);
    expect((await store.openProject(id)).meta.name, doc.meta.name);
    files.failIndex = false;
    await store.rebuildIndex();
    expect(store.indexWarning, isNull);
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
