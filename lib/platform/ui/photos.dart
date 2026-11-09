import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../app/settings.dart';
import 'scope.dart';
import 'theme.dart';

/// Most photos one site entry or inspection request can carry.
const maxSitePhotos = 9;

/// Picks site photos from the gallery or files and shrinks them to about
/// 1280 px JPEG so a day's log stays small. Returns what could be read.
Future<List<List<int>>> pickPhotos(BuildContext context,
    {int max = maxSitePhotos}) async {
  final List<XFile> files;
  try {
    files = await openFiles(acceptedTypeGroups: [
      const XTypeGroup(
          label: 'images',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'heic'],
          mimeTypes: ['image/*'],
          uniformTypeIdentifiers: ['public.image']),
    ]);
  } catch (_) {
    if (context.mounted)
      toast(
          context,
          tr3('无法打开相册', 'Галереяны ашу мүмкін емес',
              'Не удалось открыть галерею'));
    return const [];
  }
  final out = <List<int>>[];
  var skipped = 0;
  for (final f in files.take(max)) {
    try {
      final raw = await f.readAsBytes();
      out.add(await shrinkPhoto(raw));
    } catch (_) {
      skipped++;
    }
  }
  // Say what was left out instead of silently dropping photos.
  final over = files.length > max ? files.length - max : 0;
  if (context.mounted && (skipped > 0 || over > 0)) {
    toast(
        context,
        [
          if (skipped > 0)
            tr3('$skipped 张照片无法读取或太大', '$skipped фото оқылмады не тым үлкен',
                '$skipped фото не удалось прочитать или они слишком большие'),
          if (over > 0)
            tr3('这次只能再加 $max 张，$over 张没有加入',
                'Тағы $max фото ғана қосуға болады, $over қосылмады',
                'Можно добавить ещё $max фото, $over не добавлено'),
        ].join(' · '));
  }
  return out;
}

/// The server refuses photos above 1 MB (yusal-api `maxPhotoBytes`).
const maxPhotoBytes = 1 << 20;

/// JPEG at most 1280 px on the long side (smaller again if that is still
/// over [maxPhotoBytes]); the original if compression is not available on
/// this platform and the file is small enough to upload.
Future<List<int>> shrinkPhoto(Uint8List raw) async {
  try {
    for (final (side, quality) in const [(1280, 78), (960, 60)]) {
      final small = await FlutterImageCompress.compressWithList(raw,
          minWidth: side, minHeight: side, quality: quality);
      if (small.isEmpty) break;
      if (small.length <= maxPhotoBytes) return small;
    }
  } catch (e) {
    if (kDebugMode) debugPrint('photo compress: $e');
  }
  if (raw.length > maxPhotoBytes) throw StateError('too large');
  return raw;
}

/// A row of photo thumbnails; tap opens the photo full screen. With
/// [onRemove] each thumbnail gets a remove button (while composing).
class PhotoStrip extends StatelessWidget {
  const PhotoStrip(
      {super.key, required this.photos, this.size = 64, this.onRemove});
  final List<List<int>> photos;
  final double size;
  final void Function(int index)? onRemove;
  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final t = YTokens.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (var i = 0; i < photos.length; i++)
        Stack(clipBehavior: Clip.none, children: [
          InkWell(
              onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(
                      insetPadding: const EdgeInsets.all(12),
                      child: InteractiveViewer(
                          child: Image.memory(Uint8List.fromList(photos[i]))))),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(Uint8List.fromList(photos[i]),
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: size,
                          height: size,
                          color: t.surface,
                          child: Icon(Icons.broken_image_outlined,
                              color: t.muted))))),
          if (onRemove != null)
            Positioned(
                right: -6,
                top: -6,
                child: Material(
                    color: t.ink,
                    shape: const CircleBorder(),
                    child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onRemove!(i),
                        child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: Icon(Icons.close, size: 14, color: t.bg))))),
        ]),
    ]);
  }
}
