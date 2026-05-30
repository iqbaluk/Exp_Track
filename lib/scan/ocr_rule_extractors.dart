class OcrRuleExtractors {
  static final RegExp _lineSplitRegex = RegExp(r'[\r\n]+');
  static final RegExp _multiSpaceRegex = RegExp(r'\s+');
  static final RegExp _hasDigitRegex = RegExp(r'\d');
  static final RegExp _hasLetterRegex = RegExp(r'[A-Za-z]');
  static final RegExp _dmyRegex = RegExp(r'\b(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})\b');
  static final RegExp _supplierDateRegex = RegExp(r'\d{2}/\d{2}/\d{2,4}');
  static final RegExp _summaryDateRegex =
      RegExp(r'\b\d{1,2}[\/-]\d{1,2}[\/-]\d{2,4}\b');
  static final RegExp _invoiceLabelRegex = RegExp(
    r'(?:(?:invoice|invoce|invoie|inv)\s*(?:no|ne|nr|num|number|#)|inv\s*#)',
    caseSensitive: false,
  );
  static final RegExp _invoiceValueRegex = RegExp(
    r'([A-Z0-9][A-Z0-9/_-]{4,40})',
    caseSensitive: false,
  );
  static final RegExp _invoiceBlockedRegex = RegExp(
    r'(vat\s*no|company\s*no|tel|phone|route|pod|account\s*no)',
    caseSensitive: false,
  );
  static final RegExp _invoiceGlobalRegex = RegExp(
    r'(?:invoice|invoce|invoie|inv)\s*(?:no|ne|nr|num|number|#)\s*[:#-]?\s*([A-Z0-9][A-Z0-9/_-]{4,40})',
    caseSensitive: false,
  );
  static final RegExp _grossLabelRegex = RegExp(
    r'(?:grand\s*total|total\s*amount|amount\s*due|total)\s*[:#-]?\s*[A-Z\xC2\xA3$]*\s*([0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _grossCurrencyRegex =
      RegExp(r'[\xC2\xA3$]\s*([0-9]+(?:\.[0-9]{1,2})?)');
  static final RegExp _paidRegex = RegExp(
    r'(?:paid|payd|pd|amount\s*paid|total\s*paid|card\s*payment|cash\s*payment)\s*[:#-]?\s*[A-Z\xC2\xA3$]*\s*([0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );
  static final RegExp _vatRegex = RegExp(
    r'(?:vat(?:\s*@\s*\d+%?)?|tax)\s*[:#-]?\s*[A-Z\xC2\xA3$]*\s*([0-9]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  static List<String> splitLines(String text) => text
      .split(_lineSplitRegex)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  static String? extractInvoice(String text) {
    return extractInvoiceFromLines(splitLines(text), rawText: text);
  }

  static String? extractInvoiceFromLines(List<String> lines, {String? rawText}) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();
      if (!(lower.contains('inv') || lower.contains('invoice'))) continue;
      if (!_invoiceLabelRegex.hasMatch(line) || _invoiceBlockedRegex.hasMatch(line)) {
        continue;
      }

      final sameLine = _invoiceValueRegex.firstMatch(line)?.group(1);
      final cleanedSame = _sanitizeInvoice(sameLine);
      if (_looksLikeInvoice(cleanedSame)) return cleanedSame;

      if (i + 1 < lines.length) {
        final next = lines[i + 1];
        if (_invoiceBlockedRegex.hasMatch(next)) continue;
        final nextVal = _invoiceValueRegex.firstMatch(next)?.group(1);
        final cleanedNext = _sanitizeInvoice(nextVal);
        if (_looksLikeInvoice(cleanedNext)) return cleanedNext;
      }
    }

    final source = rawText ?? lines.join('\n');
    final global = _sanitizeInvoice(_invoiceGlobalRegex.firstMatch(source)?.group(1));
    if (_looksLikeInvoice(global)) return global;

    return null;
  }

  static DateTime? extractDate(String text) {
    final match = _dmyRegex.firstMatch(text);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);
    final rawYear = int.tryParse(match.group(3)!);
    if (day == null || month == null || rawYear == null) return null;
    final year = rawYear < 100 ? (2000 + rawYear) : rawYear;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static double? extractGross(String text) {
    return extractGrossFromLines(splitLines(text), rawText: text);
  }

  static double? extractGrossFromLines(List<String> lines, {String? rawText}) {
    double? best;

    final start = lines.isEmpty ? 0 : (lines.length * 0.8).floor();
    final candidateLines = lines.sublist(start.clamp(0, lines.length));
    final tailText = candidateLines.join('\n');
    for (final m in _grossLabelRegex.allMatches(tailText)) {
      final v = double.tryParse(m.group(1) ?? '');
      if (v == null || v <= 0) continue;
      if (best == null || v > best) best = v;
    }
    if (best != null) return best;

    for (final m in _grossCurrencyRegex.allMatches(tailText)) {
      final v = double.tryParse(m.group(1) ?? '');
      if (v == null || v <= 0) continue;
      if (best == null || v > best) best = v;
    }
    if (best != null) return best;

    final fallbackSource = rawText ?? lines.join('\n');
    for (final m in _grossLabelRegex.allMatches(fallbackSource)) {
      final v = double.tryParse(m.group(1) ?? '');
      if (v == null || v <= 0) continue;
      if (best == null || v > best) best = v;
    }
    return null;
  }

  static double? extractPaid(String text) {
    final m = _paidRegex.firstMatch(text);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static double? extractVat(String text) {
    final m = _vatRegex.firstMatch(text);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static String? extractSupplier(String text) {
    return extractSupplierFromLines(splitLines(text));
  }

  static String? extractSupplierFromLines(List<String> lines) {
    for (final line in lines.take(12)) {
      final lower = line.toLowerCase();
      if (lower.contains('invoice')) continue;
      if (lower.contains('vat no')) continue;
      if (_supplierDateRegex.hasMatch(line)) continue;
      if (line.length >= 4 && _hasLetterRegex.hasMatch(line)) {
        return line;
      }
    }
    return null;
  }

  static String? summarizeLineItems(String text) {
    return summarizeLineItemsFromLines(splitLines(text));
  }

  static String? summarizeLineItemsFromLines(List<String> lines) {
    final items = <String>[];
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('invoice')) continue;
      if (lower.contains('total')) continue;
      if (lower.contains('vat')) continue;
      if (_summaryDateRegex.hasMatch(line)) {
        continue;
      }
      if (_hasLetterRegex.hasMatch(line) && line.length > 4) {
        final cleaned = line.replaceAll(_multiSpaceRegex, ' ');
        items.add(cleaned);
      }
      if (items.length >= 3) break;
    }
    if (items.isEmpty) return null;
    return items.join(', ');
  }

  static bool isUsableFastExtraction({
    DateTime? date,
    String? supplier,
    double? gross,
    String? invoice,
  }) {
    var score = 0;
    if (date != null) score++;
    if ((supplier?.trim().isNotEmpty ?? false)) score++;
    if ((gross ?? 0) > 0) score++;
    if ((invoice?.trim().isNotEmpty ?? false)) score++;
    return score >= 2;
  }

  static String? _sanitizeInvoice(String? value) {
    final cleaned = value?.trim().replaceAll(_multiSpaceRegex, '');
    if (cleaned == null || cleaned.isEmpty) return null;
    return cleaned;
  }

  static bool _looksLikeInvoice(String? value) {
    if (value == null || value.length < 5) return false;
    return _hasDigitRegex.hasMatch(value);
  }
}
