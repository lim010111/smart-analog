DateTime requireIsoDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Missing or invalid "$key" in response payload.');
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('Invalid ISO datetime for "$key": $value');
  }
  return parsed;
}

String requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Missing or invalid "$key" in response payload.');
  }
  return value;
}

String requireNonEmptyString(Map<String, dynamic> json, String key) {
  final value = requireString(json, key);
  if (value.trim().isEmpty) {
    throw FormatException('Missing or invalid "$key" in response payload.');
  }
  return value;
}

String? optionalString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  final value = json[key];
  if (value is! String) {
    throw FormatException('Invalid "$key" in response payload.');
  }
  return value;
}

String? optionalStringOrNumberAsString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  final value = json[key];
  if (value is String) {
    return value;
  }
  if (value is num) {
    return value.toString();
  }
  throw FormatException('Invalid "$key" in response payload.');
}

bool requireBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) {
    throw FormatException('Missing or invalid "$key" in response payload.');
  }
  return value;
}

int requireInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num && value == value.toInt()) {
    return value.toInt();
  }
  throw FormatException('Missing or invalid "$key" in response payload.');
}

List<String> requireStringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Missing or invalid "$key" in response payload.');
  }
  if (value.any((item) => item is! String)) {
    throw FormatException('"$key" must contain only strings.');
  }
  return value.cast<String>();
}

List<Map<String, dynamic>> requireObjectList(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('Missing or invalid "$key" in response payload.');
  }
  if (value.any((item) => item is! Map<String, dynamic>)) {
    throw FormatException('"$key" must contain only objects.');
  }
  return value.cast<Map<String, dynamic>>();
}
