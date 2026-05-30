import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../gemini_service.dart';
import 'ocr_rule_extractors.dart';

class FastReceiptPipeline {
  static Future<ReceiptData?> tryExtract({
    required String imagePath,
    required List<String> categories,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);
      final text = recognized.text.trim();
      if (text.isEmpty) return null;
      final lines = OcrRuleExtractors.splitLines(text);

      final invoice = OcrRuleExtractors.extractInvoiceFromLines(
        lines,
        rawText: text,
      );
      final date = OcrRuleExtractors.extractDate(text);
      final supplier = OcrRuleExtractors.extractSupplierFromLines(lines);
      final gross = OcrRuleExtractors.extractGrossFromLines(
        lines,
        rawText: text,
      );
      final paid = OcrRuleExtractors.extractPaid(text);
      final vat = OcrRuleExtractors.extractVat(text);
      final notes = OcrRuleExtractors.summarizeLineItemsFromLines(lines);
      final category = _mapCategory(text, categories);

      final usable = OcrRuleExtractors.isUsableFastExtraction(
        date: date,
        supplier: supplier,
        gross: gross,
        invoice: invoice,
      );
      if (!usable) return null;

      return ReceiptData(
        date: date,
        invoiceNumber: invoice,
        supplier: supplier,
        category: category,
        categoryConfidence: category == null ? null : 72,
        vat: vat,
        gross: gross,
        paidAmount: paid,
        net: null,
        rawNotes: notes,
        extractionWarnings: const ['Fast local OCR path'],
      );
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  static String? _mapCategory(String text, List<String> categories) {
    final lower = text.toLowerCase();

    bool has(List<String> words) => words.any(lower.contains);

    final feeAndCharges =
        _find(categories, const ['fee & charges', 'fee', 'charges']);
    final otherExp = _find(categories, const ['other exp']);
    final purchases = _find(categories, const ['purchases', 'purchase']);
    final travel = _find(categories, const ['travel']);
    final motor = _find(categories, const ['motor']);

    if (has(const ['bank fee', 'service charge', 'processing fee'])) {
      return feeAndCharges;
    }
    if (has(const [
      'tesco',
      'asda',
      'sainsbury',
      'aldi',
      'lidl',
      'waitrose',
      'morrisons'
    ])) {
      return otherExp ?? purchases;
    }
    if (has(const ['fuel', 'petrol', 'diesel'])) {
      return motor ?? travel ?? purchases;
    }
    if (has(const ['parts', 'wholesale', 'trade supply'])) {
      return purchases;
    }

    return null;
  }

  static String? _find(List<String> categories, List<String> candidates) {
    for (final option in categories) {
      final lower = option.toLowerCase();
      for (final candidate in candidates) {
        if (lower.contains(candidate)) return option;
      }
    }
    return null;
  }
}
