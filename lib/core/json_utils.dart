import 'dart:convert';

/// Decodes [json] to a Map, returning an empty map on failure.
Map<String, dynamic> jsonDecodeSafe(String json) {
  try {
    final decoded = jsonDecode(json);
    if (decoded is Map) return decoded.cast<String, dynamic>();
  } catch (_) {}
  return <String, dynamic>{};
}

/// Encodes [value] to a pretty-printed JSON string.
String jsonEncodePretty(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(value);
}
