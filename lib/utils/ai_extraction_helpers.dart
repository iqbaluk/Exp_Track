String? cleanNullableString(dynamic value) {
  if (value == null) return null;
  final text = value.toString().trim();
  if (text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}

double? parseLooseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  var raw = value.toString().trim();
  if (raw.isEmpty || raw.toLowerCase() == 'null') return null;

  var isNegative = false;
  if (raw.startsWith('(') && raw.endsWith(')')) {
    isNegative = true;
    raw = raw.substring(1, raw.length - 1);
  }

  raw = raw
      .replaceAll('Â£', '')
      .replaceAll('£', '')
      .replaceAll(r'$', '')
      .replaceAll(',', '')
      .replaceAll(RegExp(r'\s+'), '');

  raw = raw.replaceAll(RegExp(r'[^0-9.\-+]'), '');
  if (raw.isEmpty) return null;

  if (raw.length > 1) {
    final first = raw[0];
    final body = raw.substring(1).replaceAll(RegExp(r'[\-+]'), '');
    raw = '$first$body';
  }

  final firstDot = raw.indexOf('.');
  if (firstDot >= 0) {
    final head = raw.substring(0, firstDot + 1);
    final tail = raw.substring(firstDot + 1).replaceAll('.', '');
    raw = '$head$tail';
  }

  var parsed = double.tryParse(raw);
  if (parsed == null) return null;
  if (isNegative && parsed > 0) parsed = -parsed;
  return parsed;
}
