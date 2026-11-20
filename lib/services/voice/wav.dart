import 'dart:typed_data';

/// The samples of a PCM16 WAV file: what the `record` plugin writes.
class WavPcm {
  const WavPcm(this.samples, this.sampleRate, this.channels);
  final Int16List samples;
  final int sampleRate, channels;

  /// Reads the `fmt ` and `data` chunks; null when [bytes] is not a 16-bit
  /// PCM WAV. A `data` size the recorder left unset (0 or past the end) is
  /// read as "to the end of the file".
  static WavPcm? parse(Uint8List bytes) {
    if (bytes.length < 12) return null;
    final view = ByteData.sublistView(bytes);
    String tag(int at) => String.fromCharCodes(bytes, at, at + 4);
    if (tag(0) != 'RIFF' || tag(8) != 'WAVE') return null;
    int? rate, channels, bits, format;
    var at = 12;
    while (at + 8 <= bytes.length) {
      final id = tag(at);
      final size = view.getUint32(at + 4, Endian.little);
      final body = at + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = view.getUint16(body, Endian.little);
        channels = view.getUint16(body + 2, Endian.little);
        rate = view.getUint32(body + 4, Endian.little);
        bits = view.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        // 1 = PCM, 0xFFFE = WAVE_FORMAT_EXTENSIBLE (PCM inside).
        if (rate == null || bits != 16 || (format != 1 && format != 0xFFFE)) {
          return null;
        }
        var end = body + size;
        if (size == 0 || end > bytes.length) end = bytes.length;
        final count = (end - body) ~/ 2;
        final samples = Int16List(count);
        for (var i = 0; i < count; i++) {
          samples[i] = view.getInt16(body + i * 2, Endian.little);
        }
        return WavPcm(samples, rate, channels ?? 1);
      }
      at = body + size + (size.isOdd ? 1 : 0);
    }
    return null;
  }
}
