import '../core/serialization/house_codec.dart';

Future<LoadResult> loadHouseStream(Stream<List<int>> source,
    {int? length}) async {
  LoadResult tooLarge() => const LoadResult.failure(LoadFailure(
      'file', [LoadError('FILE_TOO_LARGE', '', '文件超过 10 MiB，无法打开')]));
  if (length != null && length > maxHouseBytes) return tooLarge();
  final bytes = <int>[];
  await for (final chunk in source) {
    if (bytes.length + chunk.length > maxHouseBytes) return tooLarge();
    bytes.addAll(chunk);
  }
  return loadHouse(bytes);
}
