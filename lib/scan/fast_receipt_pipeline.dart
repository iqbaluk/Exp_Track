import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../gemini_service.dart';
import 'ocr_rule_extractors.dart';

class FastReceiptPipeline {
  static Future<ReceiptData?> tryExtract({
    required String imagePath,
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
}
