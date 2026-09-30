/// Platform boundary; tests can supply an in-memory implementation.
abstract interface class ProjectFileSystem {
  Future<List<String>> ids();
  Future<String?> read(String id);
  Future<void> write(String id, String text);
  Future<void> delete(String id);
  Future<List<int>?> readPreview(String id);
  Future<void> writePreview(String id, List<int> bytes);
  Future<String?> readIndex();
  Future<void> writeIndex(String text);
}

class StorageFailure implements Exception {
  const StorageFailure(this.code, this.details);
  final String code, details;
  String get message => switch (code) {
        'NO_SPACE' => '存储空间不足，无法保存',
        'PERMISSION_DENIED' => '没有权限读取或保存设计',
        'NOT_FOUND' => '找不到这个设计',
        _ => '暂时无法读写设计，请稍后重试',
      };
  @override
  String toString() => '$code: $details';
}
