part of '../gemini_service.dart';

Future<({Uint8List bytes, String mimeType})> _prepareHandwrittenModeInput({
  required Uint8List imageBytes,
  required String? imagePath,
}) async {
  if (imagePath != null && imagePath.trim().isNotEmpty) {
    debugPrint('SCAN_PATH handwritten=true imagePath=true');
  } else {
    debugPrint('SCAN_PATH handwritten=true imagePath=false');
  }
  final imagePrepStopwatch = Stopwatch()..start();
  final prepared = await GeminiService._prepareAiImagePayloadForQuality(
    imageBytes,
  );
  imagePrepStopwatch.stop();
  debugPrint(
    'SCAN_TIMING image_prep_ms=${imagePrepStopwatch.elapsedMilliseconds}',
  );
  return prepared;
}

Future<({ReceiptData data, int apiCalls})> _applyHandwrittenModePostProcess({
  required ReceiptData data,
  required GeminiSettings settings,
  required String effectiveModel,
  required Uint8List aiImageBytes,
  required String aiMimeType,
  required int apiCalls,
}) async {
  // Keep handwritten mode single-pass by default for predictable behavior.
  debugPrint('SCAN_INVOICE handwritten_fallback=skipped');
  debugPrint('SCAN_RESCUE handwritten=skipped');
  return (data: data, apiCalls: apiCalls);
}

