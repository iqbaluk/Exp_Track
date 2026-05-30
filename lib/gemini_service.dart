// ============================================================
// Gemini Service - Isolated, failure-safe API wrapper
// ============================================================
// This file is the ONLY place that talks to Gemini.
// If anything in here fails, the rest of the app keeps working.
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;
import 'utils/ai_extraction_helpers.dart';

part 'scan/gemini_fast_scan_executor.dart';
part 'scan/gemini_quality_scan_executor.dart';

/// The result of a scan attempt - either success with data, or failure with reason.
class ScanResult {
  final bool success;
  final ReceiptData? data;
  final String? errorMessage;

  ScanResult.success(this.data)
      : success = true,
        errorMessage = null;

  ScanResult.failure(this.errorMessage)
      : success = false,
        data = null;
}

/// The data Gemini extracts from a receipt image.
/// All fields are nullable - Gemini may not find every field on every receipt.
class ReceiptData {
  final DateTime? date;
  final String? invoiceNumber;
  final String? supplier;
  final String? category;
  final double? categoryConfidence;
  final String? categoryReason;
  final double? vat;
  final double? gross;
  final double? paidAmount;
  final double? net;
  final String? rawNotes;
  final List<String> extractionWarnings;

  ReceiptData({
    this.date,
    this.invoiceNumber,
    this.supplier,
    this.category,
    this.categoryConfidence,
    this.categoryReason,
    this.vat,
    this.gross,
    this.paidAmount,
    this.net,
    this.rawNotes,
    this.extractionWarnings = const [],
  });

  ReceiptData copyWith({
    DateTime? date,
    String? invoiceNumber,
    String? supplier,
    String? category,
    double? categoryConfidence,
    String? categoryReason,
    double? vat,
    double? gross,
    double? paidAmount,
    double? net,
    String? rawNotes,
    List<String>? extractionWarnings,
  }) {
    return ReceiptData(
      date: date ?? this.date,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      supplier: supplier ?? this.supplier,
      category: category ?? this.category,
      categoryConfidence: categoryConfidence ?? this.categoryConfidence,
      categoryReason: categoryReason ?? this.categoryReason,
      vat: vat ?? this.vat,
      gross: gross ?? this.gross,
      paidAmount: paidAmount ?? this.paidAmount,
      net: net ?? this.net,
      rawNotes: rawNotes ?? this.rawNotes,
      extractionWarnings: extractionWarnings ?? this.extractionWarnings,
    );
  }
}

/// Saved Gemini settings.
///
/// Gemini is the only supported AI provider in this app. The key can come from
/// secure device storage, or fall back to the developer .env file.
class GeminiSettings {
  final String apiKey;
  final String model;
  final String scanMode;
  final bool hasSavedApiKey;
  final bool usesEnvKey;

  const GeminiSettings({
    required this.apiKey,
    required this.model,
    required this.scanMode,
    required this.hasSavedApiKey,
    required this.usesEnvKey,
  });

  bool get hasUsableKey => GeminiService.isUsableApiKey(apiKey);
}

class GeminiSettingsCheckResult {
  final bool success;
  final String? workingModel;
  final bool usedFallback;
  final String? errorMessage;

  const GeminiSettingsCheckResult.success({
    required this.workingModel,
    required this.usedFallback,
  })  : success = true,
        errorMessage = null;

  const GeminiSettingsCheckResult.failure(this.errorMessage)
      : success = false,
        workingModel = null,
        usedFallback = false;
}

class ScanTelemetry {
  final String mode;
  final String model;
  final int apiCalls;
  final bool success;

  const ScanTelemetry({
    required this.mode,
    required this.model,
    required this.apiCalls,
    required this.success,
  });
}

class GeminiService {
  static const String _propertyBusinessClassificationGuide = '''
Property-business classification rules (applies when business profile indicates property buy/renovate/sell):
1) If a cost is directly tied to a specific property purchase, renovation, legal compliance, or sale transaction, treat it as a direct project cost (not office overhead).
2) Merchant type alone is not sufficient; prioritize line-item/service meaning and property/address context.
3) For professional services tied to a specific property/project (e.g., Party Wall services, structural/survey tied to one address), prefer acquisition/selling or direct project cost style subcategories over generic indirect/professional overhead.
4) Prefer precise extraction of invoice facts; avoid guessed classifications.
''';
  static const String defaultModel = 'gemini-2.5-flash-lite';
  static const List<String> selectableModels = [
    'gemini-3.5-flash',
    'gemini-3.1-pro-preview',
    'gemini-3.1-flash-lite',
    'gemini-2.5-pro',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-1.5-pro',
    'gemini-1.5-flash',
  ];
  static const List<String> fallbackModels = [
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-1.5-flash',
  ];
  static const _apiKeyStorageKey = 'gemini_api_key';
  static const _modelStorageKey = 'gemini_model';
  static const _scanModeStorageKey = 'gemini_scan_mode';
  static const _modelOptionsStorageKey = 'gemini_model_options_json';
  static const _lastScanModelStorageKey = 'gemini_last_scan_model';
  static ScanTelemetry? _lastScanTelemetry;
  static const String scanModeFast = 'fast';
  static const String scanModeAccurate = 'accurate';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  // Dev-only compile-time fallback key. Keep empty for production builds.
  static const String _builtInDevApiKey =
      String.fromEnvironment('GEMINI_API_KEY_DEV', defaultValue: '');
  static const bool strictPrivacyGuard = true;
  static final RegExp _emailRegex = RegExp(
    r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
    caseSensitive: false,
  );
  static final RegExp _phoneRegex = RegExp(
    r'(\+?\d[\d\s().-]{7,}\d)',
    caseSensitive: false,
  );
  static final RegExp _addressLineRegex = RegExp(
    r'\b(\d+\s+[a-z0-9][a-z0-9\s,.-]{4,}|postcode|post code|road|street|avenue|lane|drive|flat|unit)\b',
    caseSensitive: false,
  );

  static bool isUsableApiKey(String key) {
    final trimmed = key.trim();
    return trimmed.isNotEmpty && trimmed != 'YOUR_GEMINI_API_KEY_HERE';
  }

  /// Returns true if Gemini API key looks usable.
  /// We check this before showing the scan button as enabled.
  static bool isConfigured() {
    final key = _envApiKey();
    return isUsableApiKey(key);
  }

  static Future<bool> hasUsableSettings() async {
    final settings = await loadSettings();
    return settings.hasUsableKey;
  }

  static Future<String?> savedApiKey() async {
    try {
      final key = await _storage.read(key: _apiKeyStorageKey);
      final trimmed = key?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  static Future<String> savedModel() async {
    try {
      final model = (await _storage.read(key: _modelStorageKey))?.trim() ?? '';
      return model.isEmpty ? defaultModel : model;
    } catch (_) {
      return defaultModel;
    }
  }

  static Future<String> savedScanMode() async {
    try {
      final mode =
          (await _storage.read(key: _scanModeStorageKey))?.trim() ?? '';
      if (mode == scanModeAccurate) return scanModeAccurate;
      return scanModeFast;
    } catch (_) {
      return scanModeFast;
    }
  }

  static Future<List<String>> savedModelOptions() async {
    try {
      final raw = (await _storage.read(key: _modelOptionsStorageKey)) ?? '';
      if (raw.trim().isEmpty) return List<String>.from(selectableModels);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return List<String>.from(selectableModels);
      final values = decoded
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      if (values.isEmpty) return List<String>.from(selectableModels);
      return values;
    } catch (_) {
      return List<String>.from(selectableModels);
    }
  }

  static Future<void> saveModelOptions(List<String> options) async {
    final sanitized = options
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (sanitized.isEmpty) {
      await _storage.delete(key: _modelOptionsStorageKey);
      return;
    }
    await _storage.write(
      key: _modelOptionsStorageKey,
      value: jsonEncode(sanitized),
    );
  }

  static Future<String?> lastScanModel() async {
    try {
      final model =
          (await _storage.read(key: _lastScanModelStorageKey))?.trim() ?? '';
      return model.isEmpty ? null : model;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _recordLastScanModel(String model) async {
    final trimmed = model.trim();
    if (trimmed.isEmpty) return;
    try {
      await _storage.write(key: _lastScanModelStorageKey, value: trimmed);
    } catch (_) {
      // Non-blocking telemetry hint; ignore storage failures.
    }
  }

  static ScanTelemetry? lastScanTelemetry() => _lastScanTelemetry;

  static void _recordScanTelemetry({
    required String mode,
    required String model,
    required int apiCalls,
    required bool success,
  }) {
    _lastScanTelemetry = ScanTelemetry(
      mode: mode,
      model: model,
      apiCalls: apiCalls < 0 ? 0 : apiCalls,
      success: success,
    );
  }

  static String _envApiKey() {
    try {
      final candidates = <String>[
        dotenv.env['GEMINI_API_KEY'] ?? '',
        dotenv.env['OPENAI_API_KEY'] ?? '',
        _builtInDevApiKey,
      ];
      for (final candidate in candidates) {
        final key = candidate.trim();
        if (isUsableApiKey(key)) return key;
      }
      return '';
    } catch (_) {
      final fallback = _builtInDevApiKey.trim();
      return isUsableApiKey(fallback) ? fallback : '';
    }
  }

  static Future<GeminiSettings> loadSettings() async {
    final storedKey = await savedApiKey();
    final model = await savedModel();
    final scanMode = await savedScanMode();
    if (storedKey != null && isUsableApiKey(storedKey)) {
      return GeminiSettings(
        apiKey: storedKey,
        model: model,
        scanMode: scanMode,
        hasSavedApiKey: true,
        usesEnvKey: false,
      );
    }

    final envKey = _envApiKey();
    return GeminiSettings(
      apiKey: envKey,
      model: model,
      scanMode: scanMode,
      hasSavedApiKey: false,
      usesEnvKey: isUsableApiKey(envKey),
    );
  }

  static Future<void> saveSettings({
    required String apiKey,
    required String model,
    String? scanMode,
  }) async {
    final trimmedKey = apiKey.trim();
    final trimmedModel = model.trim().isEmpty ? defaultModel : model.trim();
    if (trimmedKey.isEmpty) {
      await _storage.delete(key: _apiKeyStorageKey);
    } else {
      if (!isUsableApiKey(trimmedKey)) {
        throw ArgumentError('Enter a valid Gemini API key.');
      }
      await _storage.write(key: _apiKeyStorageKey, value: trimmedKey);
    }
    await _storage.write(key: _modelStorageKey, value: trimmedModel);
    final normalizedMode =
        scanMode == scanModeAccurate ? scanModeAccurate : scanModeFast;
    await _storage.write(key: _scanModeStorageKey, value: normalizedMode);
  }

  static Future<void> resetSettings() async {
    await _storage.delete(key: _apiKeyStorageKey);
    await _storage.delete(key: _modelStorageKey);
    await _storage.delete(key: _scanModeStorageKey);
  }

  static Future<ScanResult> testSettings({
    String? apiKey,
    String? model,
  }) async {
    final settings = await loadSettings();
    final key =
        (apiKey?.trim().isNotEmpty ?? false) ? apiKey!.trim() : settings.apiKey;
    final selectedModel =
        (model?.trim().isNotEmpty ?? false) ? model!.trim() : settings.model;

    if (!isUsableApiKey(key)) {
      return ScanResult.failure('Gemini API key is not set.');
    }

    return _testModelConnection(apiKey: key, model: selectedModel);
  }

  static Future<GeminiSettingsCheckResult> checkSettings({
    String? apiKey,
    String? model,
  }) async {
    final settings = await loadSettings();
    final key =
        (apiKey?.trim().isNotEmpty ?? false) ? apiKey!.trim() : settings.apiKey;
    final selectedModel =
        (model?.trim().isNotEmpty ?? false) ? model!.trim() : settings.model;

    if (!isUsableApiKey(key)) {
      return const GeminiSettingsCheckResult.failure(
        'Gemini API key is not set.',
      );
    }

    final candidates = <String>[
      selectedModel,
      ...fallbackModels,
    ]
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final failures = <String>[];
    for (final candidate in candidates) {
      final result = await _testModelConnection(
        apiKey: key,
        model: candidate,
      );
      if (result.success) {
        return GeminiSettingsCheckResult.success(
          workingModel: candidate,
          usedFallback: candidate != selectedModel,
        );
      }
      failures.add('$candidate: ${result.errorMessage ?? 'failed'}');
    }

    return GeminiSettingsCheckResult.failure(
      'No tested Gemini model worked. ${failures.last}',
    );
  }

  static Future<ScanResult> _testModelConnection({
    required String apiKey,
    required String model,
  }) async {
    try {
      final testModel = GenerativeModel(
        model: model,
        apiKey: apiKey,
        generationConfig: GenerationConfig(temperature: 0),
      );
      final response = await testModel.generateContent([
        Content.text('Reply with OK only.'),
      ]).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          'Gemini test took too long to respond (>15s)',
        ),
      );
      final text = response.text?.trim() ?? '';
      if (text.isEmpty) {
        return ScanResult.failure('Gemini returned an empty test response.');
      }
      return ScanResult.success(null);
    } on TimeoutException catch (e) {
      return ScanResult.failure('Timeout: ${e.message}');
    } on Exception catch (e) {
      return ScanResult.failure('Gemini test failed: ${e.toString()}');
    } catch (e) {
      return ScanResult.failure('Unexpected test error: ${e.toString()}');
    }
  }

  /// Send an image to Gemini and try to extract receipt fields.
  /// Returns a ScanResult that always tells you what happened.
  /// Never throws - all errors are caught and reported via ScanResult.
  static Future<ScanResult> scanReceipt(
    Uint8List imageBytes, {
    String? imagePath,
    String? businessNature,
    String? businessDescription,
    String? scanModeOverride,
    String? qualityUserHint,
    Uint8List? fastPreparedBytes,
  }) async {
    // ---- Pre-flight checks ----
    final settings = await loadSettings();
    final mode = (scanModeOverride?.trim().isNotEmpty ?? false)
        ? scanModeOverride!.trim()
        : settings.scanMode;
    final fastMode = mode == scanModeFast;
    final effectiveModel = _resolveModelForMode(
      configuredModel: settings.model,
      fastMode: fastMode,
    );
    var apiCalls = 0;
    if (effectiveModel != settings.model) {
      debugPrint(
        'SCAN_MODEL_ROUTING configured=${settings.model} mode=$mode effective=$effectiveModel',
      );
    }
    debugPrint(
      'SCAN_START mode=$mode fastMode=$fastMode model=$effectiveModel imageBytes=${imageBytes.length}',
    );
    if (!settings.hasUsableKey) {
      _recordScanTelemetry(
        mode: mode,
        model: effectiveModel,
        apiCalls: apiCalls,
        success: false,
      );
      return ScanResult.failure(
        'Gemini API key not set. Open Operation actions > Gemini settings.',
      );
    }

    if (imageBytes.isEmpty) {
      _recordScanTelemetry(
        mode: mode,
        model: effectiveModel,
        apiCalls: apiCalls,
        success: false,
      );
      return ScanResult.failure('No image data to scan.');
    }

    // Sanity check on image size (Gemini has a 20MB limit)
    if (imageBytes.length > 19 * 1024 * 1024) {
      _recordScanTelemetry(
        mode: mode,
        model: effectiveModel,
        apiCalls: apiCalls,
        success: false,
      );
      return ScanResult.failure(
        'Image too large (${(imageBytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
        'Please use a smaller photo.',
      );
    }

    try {
      final totalStopwatch = Stopwatch()..start();
      String aiMimeType = 'image/jpeg';
      Uint8List aiImageBytes = imageBytes;
      debugPrint('SCAN_TIMING ocr_ms=0');
      if (fastMode) {
        final prepared = await _prepareFastModeInput(
          imageBytes: imageBytes,
          fastPreparedBytes: fastPreparedBytes,
        );
        aiImageBytes = prepared.bytes;
        aiMimeType = prepared.mimeType;
      } else {
        final prepared = await _prepareQualityModeInput(
          imageBytes: imageBytes,
          imagePath: imagePath,
        );
        aiImageBytes = prepared.bytes;
        aiMimeType = prepared.mimeType;
      }

      // ---- Build the model ----
      final model = GenerativeModel(
        model: effectiveModel,
        apiKey: settings.apiKey,
        generationConfig: GenerationConfig(
          temperature: fastMode ? 0.0 : 0.1, // Fast single-pass deterministic
          responseMimeType: 'application/json', // Force JSON response
        ),
      );

      // ---- Build the prompt ----
      final businessContextLine = [
        businessNature?.trim() ?? '',
        businessDescription?.trim() ?? '',
      ].where((v) => v.isNotEmpty).join(' | ');
      final prompt = fastMode
          ? _buildFastPrompt(
              businessContextLine: businessContextLine,
              userHint: qualityUserHint,
            )
          : _buildQualityPromptCompact(
              businessContextLine: businessContextLine,
              userHint: qualityUserHint,
            );
      debugPrint(
        'SCAN_PROMPT mode=$mode model=$effectiveModel context_len=${businessContextLine.length} hint_len=${qualityUserHint?.length ?? 0}',
      );

      // ---- Send the image with a timeout ----
      final primaryStopwatch = Stopwatch()..start();
      apiCalls++;
      final fastTimeoutSeconds =
          fastMode ? _fastTimeoutForModel(effectiveModel) : 25;
      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(aiMimeType, aiImageBytes),
        ]),
      ]).timeout(
        Duration(seconds: fastTimeoutSeconds),
        onTimeout: () => throw TimeoutException(
          fastMode
              ? 'Gemini took too long to respond (>${fastTimeoutSeconds}s)'
              : 'Gemini took too long to respond (>25s)',
        ),
      );
      primaryStopwatch.stop();
      debugPrint(
        'SCAN_TIMING primary_ms=${primaryStopwatch.elapsedMilliseconds} payload_bytes=${aiImageBytes.length}',
      );

      // ---- Parse the response ----
      final text = response.text;
      if (text == null || text.trim().isEmpty) {
        debugPrint('SCAN_RESULT empty_response');
        _recordScanTelemetry(
          mode: mode,
          model: effectiveModel,
          apiCalls: apiCalls,
          success: false,
        );
        return ScanResult.failure('Gemini returned an empty response.');
      }
      final rawPreview =
          text.length > 1500 ? '${text.substring(0, 1500)}...' : text;
      debugPrint('SCAN_RAW_RESPONSE mode=$mode text=$rawPreview');

      final parsed = _parseJsonResponse(text);
      if (!parsed.success || parsed.data == null) {
        debugPrint('SCAN_RESULT parse_failed');
        _recordScanTelemetry(
          mode: mode,
          model: effectiveModel,
          apiCalls: apiCalls,
          success: false,
        );
        return parsed;
      }

      var patchedData = parsed.data!;
      if (fastMode) {
        patchedData = _applyFastModePostProcess(patchedData);
        final needsAmountRescue = _needsFastAmountRescue(patchedData);
        debugPrint(
          'FAST_AMOUNT_RESCUE needed=$needsAmountRescue gross=${patchedData.gross} vat=${patchedData.vat} net=${patchedData.net} paid=${patchedData.paidAmount}',
        );
        if (needsAmountRescue) {
          apiCalls++;
          final rescue = await _rescueLowQualityExtraction(
            apiKey: settings.apiKey,
            modelName: effectiveModel,
            imageBytes: aiImageBytes,
            imageMimeType: aiMimeType,
            ocrText: null,
            businessNature: businessNature,
            businessDescription: businessDescription,
            timeoutSeconds: 8,
          );
          if (rescue != null) {
            final merged = _mergeFastAmountsWithRescue(patchedData, rescue);
            final replaced = merged.gross != patchedData.gross ||
                merged.vat != patchedData.vat ||
                merged.net != patchedData.net ||
                merged.paidAmount != patchedData.paidAmount;
            patchedData = merged;
            debugPrint('FAST_AMOUNT_RESCUE merged=$replaced');
          } else {
            debugPrint('FAST_AMOUNT_RESCUE merged=false');
          }
        }
      } else {
        final qualityResult = await _applyQualityModePostProcess(
          data: patchedData,
          settings: settings,
          effectiveModel: effectiveModel,
          aiImageBytes: aiImageBytes,
          aiMimeType: aiMimeType,
          businessNature: businessNature,
          businessDescription: businessDescription,
          apiCalls: apiCalls,
        );
        patchedData = qualityResult.data;
        apiCalls = qualityResult.apiCalls;
      }

      debugPrint('SCAN_RESULT success');
      totalStopwatch.stop();
      debugPrint(
          'SCAN_API_CALLS count=$apiCalls mode=$mode model=$effectiveModel');
      debugPrint('SCAN_TIMING total_ms=${totalStopwatch.elapsedMilliseconds}');
      if (fastMode) {
        debugPrint(
            'FAST_TIMING total_ms=${totalStopwatch.elapsedMilliseconds}');
      }
      _recordScanTelemetry(
        mode: mode,
        model: effectiveModel,
        apiCalls: apiCalls,
        success: true,
      );
      await _recordLastScanModel(effectiveModel);
      return ScanResult.success(patchedData);
    } on TimeoutException catch (e) {
      debugPrint('SCAN_RESULT timeout ${e.message}');
      _recordScanTelemetry(
        mode: mode,
        model: effectiveModel,
        apiCalls: apiCalls,
        success: false,
      );
      return ScanResult.failure('Timeout: ${e.message}');
    } on Exception catch (e) {
      debugPrint('SCAN_RESULT exception ${e.toString()}');
      // Catch all other exceptions (network, API, parsing, etc.)
      _recordScanTelemetry(
        mode: mode,
        model: effectiveModel,
        apiCalls: apiCalls,
        success: false,
      );
      return ScanResult.failure('Scan failed: ${e.toString()}');
    } catch (e) {
      debugPrint('SCAN_RESULT unexpected ${e.toString()}');
      // Final safety net - even non-Exception throwables
      _recordScanTelemetry(
        mode: mode,
        model: effectiveModel,
        apiCalls: apiCalls,
        success: false,
      );
      return ScanResult.failure('Unexpected error: ${e.toString()}');
    }
  }

  static Future<Uint8List> prepareFastScanPayload(
      Uint8List originalBytes) async {
    final prepared = await _prepareAiImagePayloadForFast(originalBytes);
    return prepared.bytes;
  }

  /// Parse the JSON Gemini sent us into a ReceiptData object.
  /// Defensive: any parsing failure returns a useful error message.
  static ScanResult _parseJsonResponse(String text) {
    try {
      // Strip any markdown code fences just in case Gemini ignores our instruction
      String cleaned = text.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.replaceAll(RegExp(r'^```(?:json)?\s*'), '');
        cleaned = cleaned.replaceAll(RegExp(r'\s*```$'), '');
      }
      cleaned = _normalizeJsonCandidate(cleaned);
      if (!cleaned.trimLeft().startsWith('{')) {
        final extracted = _extractFirstJsonObject(cleaned);
        if (extracted != null) {
          cleaned = extracted;
        }
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      // ---- Date ----
      DateTime? date;
      final dateStr = json['date']?.toString();
      if (dateStr != null && dateStr.toLowerCase() != 'null') {
        date = _parseFlexibleUkDate(dateStr);
      }

      // ---- Strings ----
      String? invoiceNumber = cleanNullableString(
        json['invoice_number'] ??
            json['invoiceNumber'] ??
            json['invoice_no'] ??
            json['inv_no'] ??
            json['inv_number'] ??
            json['receipt_no'] ??
            json['receipt_number'] ??
            json['order_no'] ??
            json['order_number'] ??
            json['doc_no'] ??
            json['doc_ref'] ??
            json['document_no'] ??
            json['document_ref'] ??
            json['reference'] ??
            json['reference_no'] ??
            json['ref_no'] ??
            json['tax_invoice_no'],
      );
      if (invoiceNumber != null &&
          invoiceNumber.trim().toUpperCase() == 'NOT_FOUND') {
        invoiceNumber = null;
      }
      String? supplier = cleanNullableString(
        json['supplier'] ?? json['vendor'] ?? json['supplier_name'],
      );
      String? notes = cleanNullableString(
        json['notes'] ??
            json['line_item_summary'] ??
            json['item_summary'] ??
            json['description'] ??
            json['item_description'],
      );
      final paymentContext = cleanNullableString(
        json['payment_context'] ??
            json['paymentContext'] ??
            json['payment_line'] ??
            json['payment_summary'],
      );
      final extractionWarnings = List<String>.from(
        _parseWarnings(json['extraction_warnings'] ?? json['warnings']),
      );

      if (strictPrivacyGuard) {
        invoiceNumber = _sanitizeInvoiceNumber(invoiceNumber);
        supplier = _sanitizeSupplier(supplier);
        notes = _sanitizeNotes(notes);
      }

      // Phase 1: Head/category extraction is intentionally disabled.
      const String? category = null;
      const double? categoryConfidence = null;
      const String? categoryReason = null;

      // ---- Numbers ----
      double? vat =
          parseLooseDouble(json['vat'] ?? json['vat_amount'] ?? json['tax']);
      double? gross = parseLooseDouble(
        json['gross'] ??
            json['total'] ??
            json['total_amount'] ??
            json['invoice_total'],
      );
      double? paidAmount = parseLooseDouble(
        json['paid_amount'] ?? json['paidAmount'] ?? json['amount_paid'],
      );
      double? net = parseLooseDouble(json['net']);
      final rawSubtotal = parseLooseDouble(
        json['raw_subtotal_before_discounts'] ??
            json['raw_subtotal'] ??
            json['subtotal_before_discounts'],
      );
      final rawTotalPayable = parseLooseDouble(
        json['raw_total_payable'] ??
            json['total_payable'] ??
            json['amount_due'] ??
            json['to_pay'],
      );
      final totalDiscounts = _sumDiscountLines(json['discount_lines']);
      final paymentTotal = _sumPaymentMethods(json['payment_methods']);

      // Hybrid normalization with consistency guard.
      // Keep paid_amount separate from gross to preserve partial/rounded payments.
      final hasVatNet = vat != null && net != null;
      final grossConsistentWithVatNet =
          gross != null && hasVatNet && (gross - (vat! + net!)).abs() <= 1.0;
      if (rawTotalPayable != null && rawTotalPayable > 0) {
        if (gross == null || gross <= 0) {
          gross = rawTotalPayable;
        } else {
          final rawConsistentWithVatNet =
              hasVatNet && (rawTotalPayable - (vat! + net!)).abs() <= 1.0;
          final payableCloseToGross = (gross - rawTotalPayable).abs() <= 1.0 ||
              (gross - rawTotalPayable).abs() <=
                  (gross.abs() * 0.08).clamp(1.0, 50.0);
          if (rawConsistentWithVatNet || payableCloseToGross) {
            gross = rawTotalPayable;
          } else if (!grossConsistentWithVatNet && hasVatNet) {
            // If neither total matches VAT+NET, keep the larger plausible
            // number to avoid collapsing invoice totals to tiny OCR fragments.
            gross = gross > rawTotalPayable ? gross : rawTotalPayable;
            extractionWarnings.add(
              'Gross/payable mismatch detected; using conservative total',
            );
          } else {
            // Gross already consistent with VAT+NET; keep it.
            extractionWarnings.add(
              'Ignored conflicting payable total from OCR/AI',
            );
          }
        }
      } else if (gross == null && rawSubtotal != null && totalDiscounts > 0) {
        final derivedPayable = rawSubtotal - totalDiscounts;
        if (derivedPayable > 0) {
          gross = derivedPayable;
        }
      }

      if (paymentTotal > 0) {
        paidAmount = paymentTotal;
      }

      if ((paidAmount == null || paidAmount <= 0) &&
          paymentContext != null &&
          paymentContext.trim().isNotEmpty) {
        final paidFromContext = _extractPaidAmountByRegex(paymentContext);
        if (paidFromContext != null && paidFromContext > 0) {
          paidAmount = paidFromContext;
        }
      }

      // If payable/gross is still missing but payment total is explicit,
      // use payment total as gross fallback.
      if ((gross == null || gross <= 0) && paymentTotal > 0) {
        gross = paymentTotal;
      }

      // If paid amount is missing, default paid = gross.
      if (paidAmount == null && gross != null) {
        paidAmount = gross;
      }

      // Net must be invoice net (gross - VAT), never derived from paid amount.
      if (gross != null) {
        net = gross - (vat ?? 0);
      } else if (net == null && paidAmount != null && vat != null) {
        // Fallback only when gross is missing.
        net = paidAmount - vat;
      }

      return ScanResult.success(
        ReceiptData(
          date: date,
          invoiceNumber: invoiceNumber,
          supplier: supplier,
          category: category,
          categoryConfidence: categoryConfidence,
          categoryReason: categoryReason,
          vat: vat,
          gross: gross,
          paidAmount: paidAmount,
          net: net,
          rawNotes: notes,
          extractionWarnings: extractionWarnings,
        ),
      );
    } catch (e) {
      debugPrint('SCAN_PARSE error=${e.toString()}');
      return ScanResult.failure(
        'Could not parse Gemini response: ${e.toString()}',
      );
    }
  }

  static String _normalizeJsonCandidate(String value) {
    return value
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'");
  }

  static String? _extractFirstJsonObject(String value) {
    final start = value.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inQuotes = false;
    var escaped = false;
    for (var i = start; i < value.length; i++) {
      final char = value[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == '\\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inQuotes = !inQuotes;
        continue;
      }
      if (inQuotes) continue;
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return value.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  static String? _sanitizeInvoiceNumber(String? value) {
    if (value == null) return null;
    var cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    cleaned = cleaned.replaceAll(RegExp(r'[^A-Za-z0-9\\-_/]'), '');
    if (cleaned.isEmpty) return null;
    // Invoice IDs can be long alphanumeric values and may look "phone-like".
    // Do not apply phone-number PII filtering to invoice numbers.
    if (_emailRegex.hasMatch(cleaned) || _addressLineRegex.hasMatch(cleaned)) {
      return null;
    }
    // Reject obvious OCR fragments/non-invoice tokens that often appear
    // when the model returns part of the label (e.g. "oice").
    final lower = cleaned.toLowerCase();
    const blocked = <String>{
      'invoice',
      'nvoice',
      'oice',
      'inv',
      'number',
      'no',
      'ne',
      'nr',
      'date',
      'total',
      'gross',
      'vat',
      'bill',
      'doc',
      'ref',
      'auth',
      'authcode',
      'aid',
      'pan',
      'merchant',
      'icc',
      'visa',
      'debit',
    };
    if (blocked.contains(lower)) return null;
    if (lower.startsWith('a000000')) return null; // AID-like token
    return cleaned;
  }

  static String? _sanitizeSupplier(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    if (_containsSensitiveData(cleaned)) return null;
    return cleaned;
  }

  static String? _sanitizeNotes(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    if (_containsSensitiveData(cleaned)) return null;
    return cleaned;
  }

  static bool _containsSensitiveData(String value) {
    return _emailRegex.hasMatch(value) ||
        _phoneRegex.hasMatch(value) ||
        _addressLineRegex.hasMatch(value);
  }

  static Future<String?> _extractInvoiceNumberFallback({
    required String apiKey,
    required String modelName,
    required Uint8List imageBytes,
    String imageMimeType = 'image/jpeg',
    int timeoutSeconds = 18,
  }) async {
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0,
          responseMimeType: 'application/json',
        ),
      );

      final response = await model.generateContent([
        Content.multi([
          TextPart(
            '''
You are extracting ONLY the invoice number from this invoice/receipt image.

Rules:
- Scan the full document, including order details, boxed sections, margins, and footer.
- Preferred labels: Invoice No, Invoice Number, Invoice Ne (OCR typo), Inv No, Inv Nr, Invoice #, Tax Invoice No, Document No, Bill No, Doc Ref.
- If label has joined value (Invoice No:BNZ2024085940), return the value part.
- Ignore non-invoice labels: VAT No, Company No, Tel, Account No, Customer Ref, Route, POD.
- Return strict JSON only:
{
  "extracted_invoice_number": "alphanumeric identifier or NOT_FOUND"
}
''',
          ),
          DataPart('image/jpeg', imageBytes),
        ]),
      ]).timeout(Duration(seconds: timeoutSeconds));

      final raw = response.text?.trim() ?? '';
      if (raw.isEmpty) return null;

      String? extracted;
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        extracted = cleanNullableString(
          map['extracted_invoice_number'] ?? map['invoice_number'],
        );
      } catch (_) {
        extracted = null;
      }

      if (extracted != null && extracted.toUpperCase() == 'NOT_FOUND') {
        extracted = null;
      }

      final candidate = _extractInvoiceNumberFromOcrText(extracted ?? raw);
      if (candidate == null || candidate.isEmpty) return null;

      return candidate;
    } catch (_) {
      return null;
    }
  }

  static String? _extractInvoiceNumberByRegex(String text) {
    // PATCH-2026-05-21: Harden invoice regex for OCR typos like "Invoice Ne"
    // and joined labels like "InvoiceNo:BNZ...". This block can be reverted
    // independently if extraction quality drops.
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return null;
    final compact = normalized.replaceAll(' ', '');

    const invoiceLabelPattern =
        r'(?:invoice|invoce|invoie|invoic|inv0ice|inv)\s*(?:no|ne|nr|num|number|#)';
    final patterns = <RegExp>[
      RegExp(
        '$invoiceLabelPattern\\.?\\s*[:#-]*\\s*([A-Z0-9][A-Z0-9/_-]{3,})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:tax\s*(?:invoice|invoce|invoie|invoic)\s*(?:no|ne|nr|num|number|#)\.?|doc(?:ument)?\s*(?:ref|no|ne|nr|num|number)\.?|bill\s*(?:no|ne|nr|num|number)\.?)\s*[:#-]*\s*([A-Z0-9][A-Z0-9/_-]{3,})',
        caseSensitive: false,
      ),
    ];

    for (final input in [normalized, compact]) {
      for (final regex in patterns) {
        final match = regex.firstMatch(input);
        if (match == null) continue;
        final candidate = _normalizeInvoiceCandidate(match.group(1));
        if (_isLikelyInvoiceNumberCandidate(candidate)) {
          return _sanitizeInvoiceNumber(candidate);
        }
      }
    }

    return null;
  }

  static String? _extractInvoiceNumberFromOcrText(String text) {
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return _sanitizeInvoiceNumber(_extractInvoiceNumberByRegex(text));
    }

    final labelOnLineRegex = RegExp(
      r'((?:invoice|invoce|invoie|invoic)\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|inv\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|tax\s*(?:invoice|invoce|invoie|invoic)(?:\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#))?|doc(?:ument)?\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|ref)|bill\s*(?:no\.?|ne\.?|nr\.?|num\.?|number))',
      caseSensitive: false,
    );
    final negativeLabelRegex = RegExp(
      r'(vat\s*no|company\s*no|tel|telephone|account\s*no|customer\s*ref|route|pod)',
      caseSensitive: false,
    );
    final sameLineCaptureRegex = RegExp(
      r'(?:(?:invoice|invoce|invoie|invoic)\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|inv\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#)|tax\s*(?:invoice|invoce|invoie|invoic)(?:\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|#))?|doc(?:ument)?\s*(?:no\.?|ne\.?|nr\.?|num\.?|number|ref)|bill\s*(?:no\.?|ne\.?|nr\.?|num\.?|number))\s*[:#-]*\s*([A-Z0-9][A-Z0-9 /_-]{3,40})',
      caseSensitive: false,
    );
    final nextLineCandidateRegex = RegExp(
      r'^[A-Z0-9][A-Z0-9 /_-]{3,40}$',
      caseSensitive: false,
    );
    final invoiceOnlyLineRegex = RegExp(
      r'^(?:invoice|inv)\.?\s*$',
      caseSensitive: false,
    );
    final labelTailOnlyLineRegex = RegExp(
      r'^(?:no|ne|nr|num|number|#)\.?\s*[:#-]?\s*$',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!labelOnLineRegex.hasMatch(line)) continue;
      if (negativeLabelRegex.hasMatch(line)) continue;

      final sameLine = sameLineCaptureRegex.firstMatch(line)?.group(1);
      final normalizedSameLine = _normalizeInvoiceCandidate(sameLine);
      final sanitizedSameLine = _sanitizeInvoiceNumber(normalizedSameLine);
      if (_isLikelyInvoiceNumberCandidate(sanitizedSameLine)) {
        return sanitizedSameLine;
      }

      if (i + 1 < lines.length) {
        final nextLine = lines[i + 1];
        if (!negativeLabelRegex.hasMatch(nextLine) &&
            nextLineCandidateRegex.hasMatch(nextLine)) {
          final normalizedNext = _normalizeInvoiceCandidate(nextLine);
          final sanitizedNext = _sanitizeInvoiceNumber(normalizedNext);
          if (_isLikelyInvoiceNumberCandidate(sanitizedNext)) {
            return sanitizedNext;
          }
        }
      }
    }

    // Handle split labels across multiple lines in high-res OCR output:
    // Invoice
    // Ne:
    // BNZ2024085940
    for (var i = 0; i < lines.length; i++) {
      if (!invoiceOnlyLineRegex.hasMatch(lines[i])) continue;
      if (i + 2 >= lines.length) continue;
      final mid = lines[i + 1];
      final valueLine = lines[i + 2];
      if (!labelTailOnlyLineRegex.hasMatch(mid)) continue;
      if (negativeLabelRegex.hasMatch(valueLine)) continue;
      if (!nextLineCandidateRegex.hasMatch(valueLine)) continue;
      final normalized = _normalizeInvoiceCandidate(valueLine);
      final sanitized = _sanitizeInvoiceNumber(normalized);
      if (_isLikelyInvoiceNumberCandidate(sanitized)) {
        return sanitized;
      }
    }

    final normalizedGlobal = _normalizeInvoiceCandidate(
      _extractInvoiceNumberByRegex(text),
    );
    final sanitizedGlobal = _sanitizeInvoiceNumber(normalizedGlobal);
    if (_isLikelyInvoiceNumberCandidate(sanitizedGlobal)) {
      return sanitizedGlobal;
    }

    return null;
  }

  static String? _extractInvoiceNumberDeterministic(String? text) {
    if (text == null) return null;
    final lines = text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final labelRegex = RegExp(
      r'(?:(?:invoice|invoce|invoie|invoic|inv0ice|inv)\s*(?:no|ne|nr|num|number|#))',
      caseSensitive: false,
    );
    final sameLineRegex = RegExp(
      r'(?:(?:invoice|invoce|invoie|invoic|inv0ice|inv)\s*(?:no|ne|nr|num|number|#))\s*[:#-]*\s*([A-Z0-9][A-Z0-9/_-]{2,40})',
      caseSensitive: false,
    );
    final blockedLineRegex = RegExp(
      r'(vat\s*no|company\s*no|route|pod|tel|phone|account\s*no|customer\s*ref)',
      caseSensitive: false,
    );

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!labelRegex.hasMatch(line)) continue;
      if (blockedLineRegex.hasMatch(line)) continue;

      final same = sameLineRegex.firstMatch(line)?.group(1)?.trim();
      final sanitizedSame = _sanitizeInvoiceNumber(same);
      if (_isLikelyInvoiceNumberCandidate(sanitizedSame)) {
        return sanitizedSame;
      }

      if (i + 1 < lines.length) {
        final next = lines[i + 1];
        if (blockedLineRegex.hasMatch(next)) continue;
        final m = RegExp(r'^([A-Z0-9][A-Z0-9/_-]{2,40})$', caseSensitive: false)
            .firstMatch(next);
        final nextValue = m?.group(1)?.trim();
        final sanitizedNext = _sanitizeInvoiceNumber(nextValue);
        if (_isLikelyInvoiceNumberCandidate(sanitizedNext)) {
          return sanitizedNext;
        }
      }
    }

    return null;
  }

  static String? _normalizeInvoiceCandidate(String? value) {
    if (value == null) return null;
    final cleaned = value.trim();
    if (cleaned.isEmpty) return null;
    return cleaned.replaceAll(RegExp(r'\s+'), '');
  }

  static bool _isLikelyInvoiceNumberCandidate(String? value) {
    final candidate = _sanitizeInvoiceNumber(value);
    if (candidate == null || candidate.length < 5) return false;

    final lower = candidate.toLowerCase();
    const blocked = <String>{
      'invoice',
      'nvoice',
      'oice',
      'inv',
      'number',
      'no',
      'ne',
      'nr',
      'date',
      'total',
      'gross',
      'vat',
      'bill',
      'doc',
      'ref',
    };
    if (blocked.contains(lower)) return false;

    return RegExp(r'\d').hasMatch(candidate);
  }

  static double? _extractPaidAmountByRegex(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final candidateRegex = RegExp(
      r'(?:total\s*to\s*pay|amount\s*paid|amt\s*paid|paid|pd|payd|pald|paymt|paid\s*cash|paid\s*card|card\s*payment|cash\s*payment|visa\s*debit\s*sale|mastercard)\s*[:#-]?\s*(?:gbp|£)?\s*([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );

    final matches = candidateRegex.allMatches(normalized).toList();
    if (matches.isEmpty) return null;

    double? bestAmount;
    var bestScore = -1;

    for (final m in matches) {
      final amount = double.tryParse(m.group(1) ?? '');
      if (amount == null || amount <= 0) continue;

      final start = m.start;
      final end = m.end;
      final left = normalized.substring(start > 40 ? start - 40 : 0, start);
      final right = normalized.substring(
          end, (end + 40) < normalized.length ? end + 40 : normalized.length);
      final around = '$left ${m.group(0) ?? ''} $right'.toLowerCase();

      // Ignore memo-style phrases that are not payment amount labels.
      if (RegExp(r'\bpaid\s+(?:to|by|for)\b').hasMatch(around)) {
        continue;
      }

      var score = 0;
      if (RegExp(r'total\s*to\s*pay|amount\s*paid|amt\s*paid')
          .hasMatch(around)) {
        score += 4;
      }
      if (RegExp(r'paid\s*cash|paid\s*card|card\s*payment|cash\s*payment')
          .hasMatch(around)) {
        score += 3;
      }
      if (RegExp(r'visa\s*debit\s*sale|mastercard').hasMatch(around)) {
        score += 2;
      }
      if (RegExp(
              r'\b(total|vat|balance\s*due|amount\s*due|invoice\s*value|gross)\b')
          .hasMatch(around)) {
        score += 1;
      }

      // Tie-breaker: prefer larger plausible paid amount in ambiguous cases.
      if (score > bestScore ||
          (score == bestScore && (bestAmount == null || amount > bestAmount))) {
        bestScore = score;
        bestAmount = amount;
      }
    }

    return bestAmount;
  }

  static double? _extractBalanceDueByRegex(String text) {
    final normalized = text.replaceAll('\n', ' ');
    final dueRegex = RegExp(
      r'(?:balance\s*due|amount\s*due|outstanding)\s*[:#-]?\s*(?:gbp|Â£)?\s*([0-9]+(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    final match = dueRegex.firstMatch(normalized);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  static Future<_OcrSnapshot?> _extractOcrSnapshotFromImagePath(
      String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await recognizer.processImage(inputImage);
      final fullText = recognized.text.trim();
      if (fullText.isEmpty) return null;

      var maxRight = 0.0;
      var maxBottom = 0.0;
      for (final block in recognized.blocks) {
        final box = block.boundingBox;
        if (box.right > maxRight) maxRight = box.right;
        if (box.bottom > maxBottom) maxBottom = box.bottom;
      }

      final topRightBlocks = <String>[];
      if (maxRight > 0 && maxBottom > 0) {
        final minLeft = maxRight * 0.52;
        final maxTop = maxBottom * 0.46;
        for (final block in recognized.blocks) {
          final box = block.boundingBox;
          if (box.left >= minLeft && box.top <= maxTop) {
            final t = block.text.trim();
            if (t.isNotEmpty) {
              topRightBlocks.add(t);
            }
          }
        }
      }

      return _OcrSnapshot(
        fullText: fullText,
        topRightHeaderText: topRightBlocks.join('\n').trim(),
      );
    } catch (_) {
      return null;
    } finally {
      await recognizer.close();
    }
  }

  static List<String> _parseWarnings(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      return value
          .map((item) => cleanNullableString(item))
          .whereType<String>()
          .toList();
    }
    final single = cleanNullableString(value);
    return single == null ? const [] : <String>[single];
  }

  static bool _needsLowQualityRescue(ReceiptData data) {
    final missingDate = data.date == null;
    final missingSupplier =
        data.supplier == null || data.supplier!.trim().isEmpty;
    final missingGross = data.gross == null || data.gross! <= 0;
    final missingCriticalCount = [
      missingDate,
      missingSupplier,
      missingGross,
    ].where((v) => v).length;
    return missingGross || missingCriticalCount >= 2;
  }

  static bool _needsFastAmountRescue(ReceiptData data) {
    final gross = data.gross;
    final vat = data.vat;
    final net = data.net;
    final paid = data.paidAmount;
    if (gross == null || gross <= 0) return false;

    if (vat != null && gross + 0.01 < vat) return true;
    if (net != null && net < -0.01) return true;
    if (paid != null && paid > gross * 1.25) return true;
    if (paid != null && paid < 0) return true;
    if (vat != null && net != null) {
      final delta = (gross - (vat + net)).abs();
      if (delta > 1.5) return true;
    }
    return false;
  }

  static bool _amountsAreReasonable(ReceiptData data) {
    final gross = data.gross;
    final vat = data.vat;
    final net = data.net;
    final paid = data.paidAmount;
    if (gross == null || gross <= 0) return false;
    if (vat != null && gross + 0.01 < vat) return false;
    if (net != null && net < -0.01) return false;
    if (paid != null && paid > gross * 1.25) return false;
    if (paid != null && paid < 0) return false;
    if (vat != null && net != null && (gross - (vat + net)).abs() > 1.5) {
      return false;
    }
    return true;
  }

  static ReceiptData _mergeFastAmountsWithRescue(
    ReceiptData primary,
    ReceiptData rescue,
  ) {
    final primaryOk = _amountsAreReasonable(primary);
    final rescueOk = _amountsAreReasonable(rescue);
    if (!rescueOk) return primary;

    final shouldReplace = !primaryOk ||
        (primary.gross != null &&
            rescue.gross != null &&
            (rescue.gross! - primary.gross!).abs() > 1.0);
    if (!shouldReplace) return primary;

    final mergedWarnings = <String>{
      ...primary.extractionWarnings,
      ...rescue.extractionWarnings,
      'Fast amount rescue applied',
    }.toList();

    return primary.copyWith(
      vat: rescue.vat ?? primary.vat,
      gross: rescue.gross ?? primary.gross,
      paidAmount: rescue.paidAmount ?? primary.paidAmount,
      net: rescue.net ?? primary.net,
      extractionWarnings: mergedWarnings,
    );
  }

  static ReceiptData _mergePrimaryWithRescue(
    ReceiptData primary,
    ReceiptData rescue,
  ) {
    final mergedWarnings = <String>{
      ...primary.extractionWarnings,
      ...rescue.extractionWarnings,
      'Low-quality rescue pass applied',
    }.toList();
    return ReceiptData(
      date: primary.date ?? rescue.date,
      invoiceNumber: (primary.invoiceNumber?.trim().isNotEmpty ?? false)
          ? primary.invoiceNumber
          : rescue.invoiceNumber,
      supplier: (primary.supplier?.trim().isNotEmpty ?? false)
          ? primary.supplier
          : rescue.supplier,
      category: (primary.category?.trim().isNotEmpty ?? false)
          ? primary.category
          : rescue.category,
      categoryConfidence:
          primary.categoryConfidence ?? rescue.categoryConfidence,
      vat: primary.vat ?? rescue.vat,
      gross: primary.gross ?? rescue.gross,
      paidAmount: primary.paidAmount ?? rescue.paidAmount,
      net: primary.net ?? rescue.net,
      rawNotes: (primary.rawNotes?.trim().isNotEmpty ?? false)
          ? primary.rawNotes
          : rescue.rawNotes,
      extractionWarnings: mergedWarnings,
    );
  }

  static Future<ReceiptData?> _rescueLowQualityExtraction({
    required String apiKey,
    required String modelName,
    required Uint8List imageBytes,
    String imageMimeType = 'image/jpeg',
    String? ocrText,
    String? businessNature,
    String? businessDescription,
    int timeoutSeconds = 18,
  }) async {
    try {
      final model = GenerativeModel(
        model: modelName,
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0,
          responseMimeType: 'application/json',
        ),
      );

      final context = [
        businessNature?.trim() ?? '',
        businessDescription?.trim() ?? '',
      ].where((v) => v.isNotEmpty).join(' | ');
      final ocrHint = (ocrText?.trim().isNotEmpty ?? false)
          ? '\nOCR text hint (may be noisy):\n${ocrText!.trim()}'
          : '';

      final prompt = '''
Rescue extraction mode for low-sharp receipt images.
Goal: recover missing critical fields with conservative confidence.
${context.isEmpty ? '' : 'Business profile context: $context'}

Return strict JSON only:
{
  "date": "YYYY-MM-DD or null",
  "invoice_number": "string or null",
  "supplier": "string or null",
  "vat": "number or null",
  "gross": "number or null",
  "paid_amount": "number or null",
  "net": "number or null",
  "notes": "string or null",
  "extraction_warnings": "array of strings"
}

Rules:
- Prioritize accuracy over completeness; do not guess.
- If unclear, return null for field.
- Use invoice labels and nearby totals to infer values.
- For grocery/retail receipts, treat TOTAL TO PAY / AMOUNT DUE as gross (final invoice total after discounts/savings), not pre-discount TOTAL.
- If document includes an outstanding/balance phrase (e.g. "to pay a further", "balance due"), do not replace invoice gross with that remainder.
- For paid_amount, also use handwritten labels if legible: paid, pd, payd, amt paid, paid cash, paid card.
- Notes must be short summary of line items only; do not include supplier/date/payment text.
- Add warning "Low image quality" if text appears blurry/uncertain.
$ocrHint
''';

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(imageMimeType, imageBytes),
        ]),
      ]).timeout(Duration(seconds: timeoutSeconds));

      final text = response.text?.trim() ?? '';
      if (text.isEmpty) return null;
      final parsed = _parseJsonResponse(text);
      if (!parsed.success || parsed.data == null) return null;
      return parsed.data;
    } catch (_) {
      return null;
    }
  }

  static Future<({Uint8List bytes, String mimeType})>
      _prepareAiImagePayloadForQuality(
    Uint8List originalBytes,
  ) async {
    const maxWidth = 2200;
    const jpegQuality = 82;
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      final width = decoded.width;
      final height = decoded.height;
      if (width <= maxWidth) {
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      const targetWidth = maxWidth;
      final targetHeight = (height * targetWidth / width).round();
      final resizedImage = img.copyResize(
        decoded,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.average,
      );
      final resized = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: jpegQuality),
      );
      if (resized.length >= originalBytes.length) {
        debugPrint(
          'SCAN_IMAGE downscaled=false reason=larger_payload src_bytes=${originalBytes.length} out_bytes=${resized.length}',
        );
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      debugPrint(
        'SCAN_IMAGE downscaled=true source=${width}x$height target=${targetWidth}x$targetHeight src_bytes=${originalBytes.length} out_bytes=${resized.length}',
      );
      return (bytes: resized, mimeType: 'image/jpeg');
    } catch (_) {
      return (bytes: originalBytes, mimeType: 'image/jpeg');
    }
  }

  static Future<({Uint8List bytes, String mimeType})>
      _prepareAiImagePayloadForFast(
    Uint8List originalBytes,
  ) async {
    // Keep fast mode sharp enough for small totals/invoice numbers.
    const maxWidth = 2000;
    const jpegQuality = 86;
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      final width = decoded.width;
      final height = decoded.height;
      if (width <= maxWidth) {
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      const targetWidth = maxWidth;
      final targetHeight = (height * targetWidth / width).round();
      final resizedImage = img.copyResize(
        decoded,
        width: targetWidth,
        height: targetHeight,
        interpolation: img.Interpolation.average,
      );
      final resized = Uint8List.fromList(
        img.encodeJpg(resizedImage, quality: jpegQuality),
      );
      if (resized.length >= originalBytes.length) {
        debugPrint(
          'SCAN_IMAGE fast_downscaled=false reason=larger_payload src_bytes=${originalBytes.length} out_bytes=${resized.length}',
        );
        return (bytes: originalBytes, mimeType: 'image/jpeg');
      }
      debugPrint(
        'SCAN_IMAGE fast_downscaled=true source=${width}x$height target=${targetWidth}x$targetHeight src_bytes=${originalBytes.length} out_bytes=${resized.length}',
      );
      return (bytes: resized, mimeType: 'image/jpeg');
    } catch (_) {
      return (bytes: originalBytes, mimeType: 'image/jpeg');
    }
  }

  static String _buildFastPrompt({
    required String businessContextLine,
    String? userHint,
  }) {
    final contextLine = businessContextLine.isEmpty
        ? ''
        : 'Business profile context: $businessContextLine\n';
    final hint = (userHint?.trim().isNotEmpty ?? false)
        ? '\n- User hint: ${userHint!.trim()}'
        : '';
    final lowerCtx = businessContextLine.toLowerCase();
    final isPropertyBusiness = lowerCtx.contains('property') &&
        (lowerCtx.contains('renovat') ||
            lowerCtx.contains('residential') ||
            lowerCtx.contains('buy') ||
            lowerCtx.contains('sell'));
    final propertyGuide = isPropertyBusiness
        ? '\n- Property classification rules:\n$_propertyBusinessClassificationGuide'
        : '';
    final specialRulesBlock = _buildDynamicSpecialInstructionsBlock(
      businessContextLine: businessContextLine,
      includePropertyRules: isPropertyBusiness,
      userHint: userHint,
    );
    return '''
JSON only:
{"date":"YYYY-MM-DD or null","invoice_number":"string or null","supplier":"string or null","vat":"number or null","gross":"number or null","paid_amount":"number or null","payment_context":"string or null","net":"number or null","raw_subtotal_before_discounts":"number or null","discount_lines":"array","raw_total_payable":"number or null","payment_methods":"array","currency":"ISO-3 string","is_foreign_currency":"boolean","notes":"string or null","extraction_warnings":"array"}
${contextLine}
SPECIAL HANDLING RULES:
$specialRulesBlock

Rules:
- Extract values exactly as visible; do not perform math.
- UK date normalization: DD/MM/YYYY, DD/MM/YY, DD MMM YY/YYYY -> YYYY-MM-DD.
- invoice_number must be tied to an explicit invoice label only: Invoice No, Invoice Number, Inv No, Inv #, Tax Invoice No, Document No, Bill No, Doc Ref (including OCR typos like Invoce/Invoice Ne).
- If no explicit invoice label is visible, set invoice_number=null.
- Never use numbers from merchant/auth/payment/card/AID/PAN/ICC/reference lines as invoice_number.
- For discount receipts, gross and raw_total_payable must be final payable amount (TOTAL TO PAY/AMOUNT DUE), not pre-discount total.
- If invoice shows both full total and remaining balance (e.g. "Total to Pay 1200" and "To pay on completion a further 80"), set gross/raw_total_payable=1200 and paid_amount=1120; do not set gross=80.
- Set paid_amount only when explicit payment evidence exists (card/cash/payment line or handwritten paid total). Otherwise null.
- Include tender lines in payment_methods when visible.
- Convert money fields to plain numbers (strip symbols/commas).
- Detect currency symbol and return ISO code in currency; set is_foreign_currency=true for non-GBP, else false and default currency=GBP.
- Use business profile as primary intent; merchant type alone is not sufficient.
- If business context is property-focused, apply property-focused accounting intent first.
- notes must be a short purchased-items summary only (comma-separated, max ~8 words), never supplier/date/payment text.
- If at least two item lines are visible, do not return notes as null.
$propertyGuide
$hint
''';
  }

  static int _fastTimeoutForModel(String model) {
    final m = model.toLowerCase();
    if (m.contains('pro') || m.contains('preview')) return 22;
    if (m.contains('3.5')) return 16;
    if (m.contains('2.5-flash')) return 12;
    return 14;
  }

  static String _resolveModelForMode({
    required String configuredModel,
    required bool fastMode,
  }) {
    if (!fastMode) return configuredModel;
    final lower = configuredModel.toLowerCase();
    if (lower.contains('pro') || lower.contains('preview')) {
      return 'gemini-2.5-flash-lite';
    }
    return configuredModel;
  }

  static String _buildQualityPromptCompact({
    required String businessContextLine,
    String? userHint,
  }) {
    final contextLine = businessContextLine.isEmpty
        ? ''
        : 'Business profile context: $businessContextLine\n';
    final hint = (userHint?.trim().isNotEmpty ?? false)
        ? 'User hint: ${userHint!.trim()}\n'
        : '';
    final lowerCtx = businessContextLine.toLowerCase();
    final isPropertyBusiness = lowerCtx.contains('property') &&
        (lowerCtx.contains('renovat') ||
            lowerCtx.contains('residential') ||
            lowerCtx.contains('buy') ||
            lowerCtx.contains('sell'));
    final propertyGuide = isPropertyBusiness
        ? '\nProperty classification rules:\n$_propertyBusinessClassificationGuide\n'
        : '';
    final specialRulesBlock = _buildDynamicSpecialInstructionsBlock(
      businessContextLine: businessContextLine,
      includePropertyRules: isPropertyBusiness,
      userHint: userHint,
    );
    return '''
You extract structured data from a UK receipt/invoice image. Return ONLY valid JSON.
${contextLine}
SPECIAL HANDLING RULES:
$specialRulesBlock

${hint}${propertyGuide}Schema:
{"date":"YYYY-MM-DD or null","invoice_number":"string or null","supplier":"string or null","vat":"number or null","gross":"number or null","paid_amount":"number or null","payment_context":"string or null","net":"number or null","notes":"string or null","extraction_warnings":"array"}
Rules:
- Invoice number is critical. Scan full page (header/body/footer/boxes/margins).
- Invoice labels: Invoice No/Number/Inv No/Inv #/Document No/Bill No/Ref No/Doc Ref (incl OCR typos: Invoce/Invoice Ne).
- Exclude non-invoice IDs: VAT No, Company No, Tel/Phone, Account No, Customer Ref, Route, POD, AID, Auth Code, PAN, Merchant, ICC.
- Date normalize to YYYY-MM-DD. Parse UK-first: DD/MM/YYYY, DD/MM/YY, DD MMM YY/YYYY.
- Money fields must be plain numbers.
- Gross = final payable amount. If discounts/savings exist, use TOTAL TO PAY/AMOUNT DUE (post-discount).
- If both full total and outstanding balance are shown, gross is the full invoice total (not outstanding remainder).
- paid_amount only from explicit payment evidence (payment/tender lines).
- net is net-before-VAT where visible; do not derive from paid_amount.
- Use business profile as primary intent; merchant type alone is not sufficient.
- If business context is property-focused, apply property-focused accounting intent first.
- Notes must summarize purchased items only.
- Do not output personal names, addresses, email, phone.
- If a field is unclear, return null (no guessing).
- If invoice number missing/unclear, set null and include "Invoice number not detected" in extraction_warnings.
''';
  }

  static String _buildDynamicSpecialInstructionsBlock({
    required String businessContextLine,
    required bool includePropertyRules,
    required String? userHint,
  }) {
    final lines = <String>[
      '- Use business profile as primary intent signal: $businessContextLine',
      '- Merchant type alone is insufficient; prioritize line-item meaning and transaction intent.',
    ];
    final hint = userHint?.trim();
    if (hint != null && hint.isNotEmpty) {
      lines.add('- User scan hint: $hint');
    }
    if (includePropertyRules) {
      lines.add('- Property-focused business context applies.');
    }
    return lines.join('\n');
  }

  static DateTime? _parseFlexibleUkDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;

    // YYYY/MM/DD or YYYY-MM-DD or YYYY.MM.DD
    final ymd =
        RegExp(r'^(\d{4})[\/\-.](\d{1,2})[\/\-.](\d{1,2})$').firstMatch(value);
    if (ymd != null) {
      final year = int.tryParse(ymd.group(1)!);
      final month = int.tryParse(ymd.group(2)!);
      final day = int.tryParse(ymd.group(3)!);
      if (year != null &&
          month != null &&
          day != null &&
          month >= 1 &&
          month <= 12 &&
          day >= 1 &&
          day <= 31) {
        try {
          return DateTime(year, month, day);
        } catch (_) {
          return null;
        }
      }
    }

    final m = RegExp(r'^(\d{1,2})[\/\-.](\d{1,2})[\/\-.](\d{2,4})$')
        .firstMatch(value);
    if (m == null) return null;
    final p1 = int.tryParse(m.group(1)!);
    final p2 = int.tryParse(m.group(2)!);
    var year = int.tryParse(m.group(3)!);
    if (p1 == null || p2 == null || year == null) return null;
    if (year < 100) {
      year = year >= 70 ? 1900 + year : 2000 + year;
    }
    int day;
    int month;
    // If clearly US (MM/DD) or clearly UK (DD/MM), resolve deterministically.
    if (p1 > 12 && p2 <= 12) {
      day = p1;
      month = p2; // UK DD/MM
    } else if (p2 > 12 && p1 <= 12) {
      month = p1;
      day = p2; // US MM/DD
    } else {
      // Ambiguous (both <=12): default to UK DD/MM for existing behavior.
      day = p1;
      month = p2;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static double _sumDiscountLines(dynamic value) {
    if (value is! List) return 0;
    var total = 0.0;
    for (final item in value) {
      final v = parseLooseDouble(item);
      if (v == null || v == 0) continue;
      if (v < 0) {
        total += v.abs();
      }
    }
    return total;
  }

  static double _sumPaymentMethods(dynamic value) {
    if (value is! List) return 0;
    var total = 0.0;
    for (final item in value) {
      if (item is! Map) continue;
      final amount = parseLooseDouble(item['amount']);
      if (amount == null || amount <= 0) continue;
      total += amount;
    }
    return total;
  }
}

class _OcrSnapshot {
  final String fullText;
  final String? topRightHeaderText;

  const _OcrSnapshot({
    required this.fullText,
    this.topRightHeaderText,
  });
}
