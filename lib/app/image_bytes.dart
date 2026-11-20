import 'dart:typed_data';

/// Picture bytes for [MemoryImage] / [Image.memory], without copying when
/// they already are a [Uint8List]. Those compare images by the identity of
/// their bytes, so a copy made on every build decodes the picture again on
/// every rebuild; the same list is decoded once and then comes from cache.
Uint8List imageBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
