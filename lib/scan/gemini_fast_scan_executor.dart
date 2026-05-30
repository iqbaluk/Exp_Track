part of '../gemini_service.dart';

Future<({Uint8List bytes, String mimeType})> _prepareFastModeInput({
  required Uint8List imageBytes,
  required Uint8List? fastPreparedBytes,
}) async {
  if (fastPreparedBytes != null && fastPreparedBytes.isNotEmpty) {
    debugPrint('SCAN_TIMING image_prep_ms=0 source=cached');
    debugPrint(
      'SCAN_PATH fastMode=true payload_bytes=${fastPreparedBytes.length} ocr_fallback=false',
    );
    return (bytes: fastPreparedBytes, mimeType: 'image/jpeg');
  }
  final imagePrepStopwatch = Stopwatch()..start();
  final prepared = await GeminiService._prepareAiImagePayloadForFast(imageBytes);
  imagePrepStopwatch.stop();
  debugPrint(
    'SCAN_TIMING image_prep_ms=${imagePrepStopwatch.elapsedMilliseconds}',
  );
  debugPrint(
    'SCAN_PATH fastMode=true payload_bytes=${prepared.bytes.length} ocr_fallback=false',
  );
  return prepared;
}

ReceiptData _applyFastModePostProcess(ReceiptData data) {
  debugPrint('FAST_RETRY triggered=false');
  debugPrint('SCAN_INVOICE fallback_call=disabled_single_pass_fast');
  debugPrint('SCAN_RESCUE disabled_single_pass_fast');
  final invoice = data.invoiceNumber?.trim();
  if (invoice == null || invoice.isEmpty) {
    return data;
  }

  final isDigitsOnly = RegExp(r'^\d+$').hasMatch(invoice);
  // Allow short numeric invoice-book serials (e.g. 12, 219) when model has
  // already linked them to invoice context. We only clear known payment/auth
  // tokens via shared sanitization/prompt constraints.
  if (isDigitsOnly) return data;

  return data;
}
