/// Lightweight typed view over a decoded JSON object from the shop API.
///
/// The shop API has ~60 response shapes (see miniapp/src/api.ts); instead of a
/// model class per shape, screens read fields through these null-safe getters.
extension type const J(Map<String, dynamic> raw) {
  static const empty = J(<String, dynamic>{});

  static J from(Object? v) => v is Map ? J(Map<String, dynamic>.from(v)) : empty;

  static List<J> list(Object? v) => v is List ? v.map(J.from).toList() : const [];

  bool has(String k) => raw[k] != null;

  Object? operator [](String k) => raw[k];

  String? str(String k) {
    final v = raw[k];
    if (v == null) return null;
    final s = v.toString();
    return s;
  }

  /// Non-empty trimmed string, or null.
  String? text(String k) {
    final s = str(k)?.trim();
    return s == null || s.isEmpty ? null : s;
  }

  String s(String k, [String fallback = '']) => str(k) ?? fallback;

  int? intOrNull(String k) {
    final v = raw[k];
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  int i(String k, [int fallback = 0]) => intOrNull(k) ?? fallback;

  double? numOrNull(String k) {
    final v = raw[k];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  double d(String k, [double fallback = 0]) => numOrNull(k) ?? fallback;

  bool b(String k, [bool fallback = false]) {
    final v = raw[k];
    if (v is bool) return v;
    if (v is num) return v != 0;
    return fallback;
  }

  bool? boolOrNull(String k) {
    final v = raw[k];
    return v is bool ? v : null;
  }

  J obj(String k) => J.from(raw[k]);

  J? objOrNull(String k) => raw[k] is Map ? J.from(raw[k]) : null;

  List<J> objs(String k) => J.list(raw[k]);

  List<String> strs(String k) {
    final v = raw[k];
    return v is List ? v.map((e) => '$e').toList() : const [];
  }

  List<num> nums(String k) {
    final v = raw[k];
    return v is List ? v.whereType<num>().toList() : const [];
  }

  DateTime? date(String k) {
    final v = str(k);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Returns a copy with [patch] merged over the current fields.
  J merge(Map<String, dynamic> patch) => J({...raw, ...patch});
}
