import 'dart:convert';

/// Readers for yusal-api JSON: times as UTC ISO-8601, enums by name,
/// bytes as base64. Field names are the models' names in snake_case.

DateTime? jsonTimeOrNull(Object? v) =>
    v == null ? null : DateTime.parse(v as String);

DateTime jsonTime(Object? v) => DateTime.parse(v! as String);

String? ts(DateTime? t) => t?.toUtc().toIso8601String();

List<String> jsonStrings(Object? v) =>
    [for (final s in v as List? ?? const []) s as String];

List<Map<String, dynamic>> jsonMaps(Object? v) =>
    [for (final m in v as List? ?? const []) m as Map<String, dynamic>];

int? jsonInt(Object? v) => (v as num?)?.toInt();

T jsonEnum<T extends Enum>(List<T> values, Object? v, T fallback) {
  for (final e in values) {
    if (e.name == v) return e;
  }
  return fallback;
}

/// Photos arrive as `/media/<id>` paths (bytes looked up in [media], which
/// the backend fills before mapping) or, from older records, as base64.
List<List<int>> jsonPhotos(Object? v,
        [Map<String, List<int>> media = const {}]) =>
    [
      for (final p in (v as List? ?? const []).cast<String>())
        if (!p.startsWith('/media/'))
          base64Decode(p)
        else if (media[p] != null)
          media[p]!
    ];

List<String> photosJson(List<List<int>> p) =>
    [for (final b in p) base64Encode(b)];

Map<String, dynamic> dropNulls(Map<String, dynamic> m) =>
    m..removeWhere((_, v) => v == null);

extension JsonString on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}
