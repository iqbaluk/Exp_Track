part of '../gemini_service.dart';

Future<({Uint8List bytes, String mimeType})> _prepareQualityModeInput({
  required Uint8List imageBytes,
  required String? imagePath,
}) async {
  if (imagePath != null && imagePath.trim().isNotEmpty) {
    debugPrint('SCAN_PATH local_ocr=disabled imagePath=true');
  } else {
    debugPrint('SCAN_PATH local_ocr=disabled fastMode=false');
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

Future<({ReceiptData data, int apiCalls})> _applyQualityModePostProcess({
  required ReceiptData data,
  required GeminiSettings settings,
  required String effectiveModel,
  required Uint8List aiImageBytes,
  required String aiMimeType,
  required int apiCalls,
}) async {
  var patchedData = data;
  var callCount = apiCalls;

  final invoiceMissing = patchedData.invoiceNumber == null ||
      patchedData.invoiceNumber!.trim().isEmpty;
  final dateMissing = patchedData.date == null;
  final supplierMissing =
      patchedData.supplier == null || patchedData.supplier!.trim().isEmpty;
  final grossMissing = patchedData.gross == null || patchedData.gross! <= 0;
  final coreMissingCount = [
    invoiceMissing,
    dateMissing,
    supplierMissing,
    grossMissing
  ].where((v) => v).length;
  final hasCriticalWarning = patchedData.extractionWarnings.any((w) {
    final lw = w.toLowerCase();
    return lw.contains('invoice number not detected') ||
        lw.contains('low image quality') ||
        lw.contains('unclear') ||
        lw.contains('not visible');
  });
  final veryLowConfidence = grossMissing || coreMissingCount >= 3;
  final strongPrimary = !invoiceMissing &&
      !dateMissing &&
      !supplierMissing &&
      !grossMissing &&
      !hasCriticalWarning;
  final baseRescueNeeded = GeminiService._needsLowQualityRescue(patchedData) ||
      dateMissing ||
      hasCriticalWarning;

  if (!strongPrimary && (invoiceMissing || baseRescueNeeded)) {
    var shouldRunInvoiceFallback = invoiceMissing || dateMissing;
    var shouldRunRescue = baseRescueNeeded;

    // Cap to one extra call by default; allow two only on very low confidence.
    if (shouldRunInvoiceFallback && shouldRunRescue && !veryLowConfidence) {
      shouldRunRescue = false;
    }

    debugPrint(
      'SCAN_PARALLEL invoiceFallback=$shouldRunInvoiceFallback dateMissing=$dateMissing rescue=$shouldRunRescue coreMissing=$coreMissingCount veryLowConfidence=$veryLowConfidence',
    );

    final invoiceFuture = shouldRunInvoiceFallback
        ? GeminiService._extractInvoiceNumberFallback(
            apiKey: settings.apiKey,
            modelName: effectiveModel,
            imageBytes: aiImageBytes,
            imageMimeType: aiMimeType,
            timeoutSeconds: 6,
          )
        : Future<String?>.value(null);
    if (shouldRunInvoiceFallback) callCount++;

    final rescueFuture = shouldRunRescue
        ? GeminiService._rescueLowQualityExtraction(
            apiKey: settings.apiKey,
            modelName: effectiveModel,
            imageBytes: aiImageBytes,
            imageMimeType: aiMimeType,
            ocrText: null,
            timeoutSeconds: 7,
          )
        : Future<ReceiptData?>.value(null);
    if (shouldRunRescue) callCount++;

    final fallbackStopwatch = Stopwatch()..start();
    final parallelResults = await Future.wait<Object?>([
      invoiceFuture,
      rescueFuture,
    ]);
    fallbackStopwatch.stop();
    debugPrint(
      'SCAN_TIMING fallback_rescue_ms=${fallbackStopwatch.elapsedMilliseconds}',
    );
    final fallbackInvoiceNumber = parallelResults[0] as String?;
    final rescue = parallelResults[1] as ReceiptData?;

    if (fallbackInvoiceNumber != null && fallbackInvoiceNumber.isNotEmpty) {
      debugPrint('SCAN_INVOICE source=fallback_model');
      patchedData = patchedData.copyWith(invoiceNumber: fallbackInvoiceNumber);
    } else {
      debugPrint('SCAN_INVOICE source=fallback_model_none');
    }

    if (rescue != null) {
      debugPrint('SCAN_RESCUE merged=true');
      patchedData = GeminiService._mergePrimaryWithRescue(patchedData, rescue);
    } else {
      debugPrint('SCAN_RESCUE merged=false');
    }
  } else {
    debugPrint('SCAN_INVOICE fallback_call=skipped');
    debugPrint('SCAN_RESCUE skipped');
  }

  return (data: patchedData, apiCalls: callCount);
}
