// ============================================================
// Exp_Track - Final Version (Steps 1-4 with smart filenames)
// ============================================================
// - Manual entry always works
// - Photo capture (camera or gallery) is optional
// - Gemini scan auto-fills fields with graceful failure handling
// - Save persists to local SQLite + smart-named photo file
// - Recent Entries with detail view (edit/delete)
// - Export menu sends CSV + photos via Android share sheet
//   (OneDrive, WhatsApp, Gmail, Drive, anything you have installed)
// ============================================================

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'database_service.dart';
import 'export_service.dart';
import 'gemini_service.dart';
import 'utils/text_normalizers.dart';

part 'pages/splash_page.dart';
part 'pages/project_list_page.dart';
part 'pages/receipt_entry_page.dart';
part 'pages/receipt_intake_page.dart';
part 'pages/receipt_entry/receipt_entry_save_controller.dart';
part 'pages/receipt_entry/receipt_entry_duplicate_dialogs.dart';
part 'pages/receipt_entry/receipt_entry_scan_controller.dart';
part 'pages/receipt_entry/receipt_entry_scan_fast_controller.dart';
part 'pages/receipt_entry/receipt_entry_scan_quality_controller.dart';
part 'pages/receipt_entry/receipt_entry_view_sections.dart';
part 'pages/gemini_settings_page.dart';
part 'pages/receipt_history_page.dart';
part 'pages/reports_hub_page.dart';
part 'pages/combined_report_page.dart';
part 'pages/monthly_activity_report_page.dart';
part 'utils/helpers.dart';
part 'pages/receipt_detail_page.dart';
part 'pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    debugPrint('Could not load .env file: $e');
  }
  runApp(const ReceiptScannerApp());
}

class ReceiptScannerApp extends StatelessWidget {
  const ReceiptScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF0F766E),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFD2F0EB),
      onPrimaryContainer: Color(0xFF032C28),
      secondary: Color(0xFFC2410C),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFFFE1D2),
      onSecondaryContainer: Color(0xFF3F1300),
      tertiary: Color(0xFF0E7490),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFD4F0F8),
      onTertiaryContainer: Color(0xFF0A2B35),
      error: Color(0xFFB42318),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF410002),
      surface: Color(0xFFFCFEFD),
      onSurface: Color(0xFF0F172A),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF2F7F7),
      surfaceContainer: Color(0xFFE8F2F2),
      surfaceContainerHigh: Color(0xFFDDEBEC),
      surfaceContainerHighest: Color(0xFFD2E3E4),
      onSurfaceVariant: Color(0xFF334155),
      outline: Color(0xFF64748B),
      outlineVariant: Color(0xFFCBD5E1),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF111827),
      onInverseSurface: Color(0xFFF1F5F9),
      inversePrimary: Color(0xFF71D1C8),
    );
    final textTheme = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
    ).textTheme.apply(
          bodyColor: colorScheme.onSurface,
          displayColor: colorScheme.onSurface,
        );

    return MaterialApp(
      title: 'Exp_Track',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: colorScheme.surfaceContainerLow,
        textTheme: textTheme.copyWith(
          titleLarge: textTheme.titleLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
          titleMedium: textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colorScheme.onSurface,
          ),
          bodyLarge: textTheme.bodyLarge?.copyWith(
            fontSize: 16,
            height: 1.35,
            color: colorScheme.onSurface,
          ),
          bodyMedium: textTheme.bodyMedium?.copyWith(
            fontSize: 14.5,
            height: 1.35,
            color: colorScheme.onSurface,
          ),
          labelLarge: textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          centerTitle: false,
          elevation: 0.5,
          scrolledUnderElevation: 1.2,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: colorScheme.onPrimary,
          ),
          iconTheme: IconThemeData(color: colorScheme.onPrimary),
        ),
        cardTheme: CardThemeData(
          color: colorScheme.surfaceContainerLowest,
          elevation: 0.6,
          shadowColor: colorScheme.shadow.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: colorScheme.surfaceContainerLowest,
          labelStyle: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
          hintStyle: TextStyle(color: colorScheme.outline),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.error, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.primary,
            side: BorderSide(color: colorScheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: colorScheme.surfaceContainerLowest,
          textStyle: TextStyle(color: colorScheme.onSurface, fontSize: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 4,
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titleTextStyle: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
          contentTextStyle: TextStyle(
            fontSize: 15,
            color: colorScheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        dividerTheme: DividerThemeData(
          space: 0,
          thickness: 1,
          color: colorScheme.outlineVariant,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: colorScheme.tertiary,
          foregroundColor: colorScheme.onTertiary,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colorScheme.inverseSurface,
          contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      home: const StartupSplashPage(),
    );
  }
}

enum PhotoSaveSizeMode { balanced, compact }

class AppPhotoSaveSettings {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyPhotoSaveSize = 'photo_save_size_mode';

  static Future<PhotoSaveSizeMode> getMode() async {
    final raw = await _storage.read(key: _keyPhotoSaveSize);
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'compact':
        return PhotoSaveSizeMode.compact;
      case 'balanced':
      default:
        return PhotoSaveSizeMode.balanced;
    }
  }

  static Future<void> setMode(PhotoSaveSizeMode mode) async {
    await _storage.write(
      key: _keyPhotoSaveSize,
      value: mode == PhotoSaveSizeMode.compact ? 'compact' : 'balanced',
    );
  }

  static int imageQuality(PhotoSaveSizeMode mode) {
    return mode == PhotoSaveSizeMode.compact ? 60 : 75;
  }

  static double maxWidth(PhotoSaveSizeMode mode) {
    return mode == PhotoSaveSizeMode.compact ? 1400 : 1900;
  }
}

enum DocumentEdgeMode { auto, manual }

class AppDocumentCaptureSettings {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyDocumentEdgeMode = 'document_edge_mode';

  static Future<DocumentEdgeMode> getMode() async {
    final raw = await _storage.read(key: _keyDocumentEdgeMode);
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'manual':
        return DocumentEdgeMode.manual;
      case 'auto':
      default:
        return DocumentEdgeMode.auto;
    }
  }

  static Future<void> setMode(DocumentEdgeMode mode) async {
    await _storage.write(
      key: _keyDocumentEdgeMode,
      value: mode == DocumentEdgeMode.manual ? 'manual' : 'auto',
    );
  }
}

class ActivationStatus {
  final bool isActive;
  final String message;
  final DateTime? expiryDate;
  final String? plan;
  final String? companyCode;

  const ActivationStatus({
    required this.isActive,
    required this.message,
    this.expiryDate,
    this.plan,
    this.companyCode,
  });
}

class ActivationLicenseService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyActivation = 'activation_key_v1';
  // Development bypass - set false before production release.
  static const bool developmentBypass = true;

  // Replace this with your real public key(s), keyed by "kid".
  // Value must be raw 32-byte Ed25519 public key in base64url/base64.
  static const Map<String, String> _publicKeysByKid = {
    'k1': 'uSv5mEKgejBynQkJjFJsorTc6G0p8rjcdqLCspWPqxk',
  };

  static Future<void> saveActivationKey(String rawKey) async {
    await _storage.write(key: _keyActivation, value: rawKey.trim());
  }

  static Future<void> clearActivationKey() async {
    await _storage.delete(key: _keyActivation);
  }

  static Future<String?> readActivationKey() async {
    final raw = await _storage.read(key: _keyActivation);
    final value = raw?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  static Future<bool> canWriteData() async {
    if (developmentBypass) return true;
    final profile = await DatabaseService.getCompanyProfile();
    final companyCode = profile?.companyCode.trim() ?? '';
    if (companyCode.isEmpty) return false;
    final status = await evaluate(companyCodeOverride: companyCode);
    return status.isActive;
  }

  static Future<ActivationStatus> evaluate({
    String? keyOverride,
    String? companyCodeOverride,
  }) async {
    if (developmentBypass) {
      return const ActivationStatus(
        isActive: true,
        message: 'Activation bypass enabled (development)',
      );
    }
    try {
      final raw = (keyOverride ?? await readActivationKey())?.trim() ?? '';
      if (raw.isEmpty) {
        debugPrint('ACTIVATION_FAIL reason=empty_key');
        return const ActivationStatus(
          isActive: false,
          message: 'Not activated',
        );
      }

      final envelope = jsonDecode(raw);
      if (envelope is! Map<String, dynamic>) {
        debugPrint('ACTIVATION_FAIL reason=envelope_not_map');
        return const ActivationStatus(
          isActive: false,
          message: 'Invalid activation format',
        );
      }

      final payloadB64 = (envelope['payload_b64'] ?? '').toString().trim();
      final sigB64 = (envelope['sig_b64'] ?? '').toString().trim();
      final alg = (envelope['alg'] ?? '').toString().trim();
      if (payloadB64.isEmpty || sigB64.isEmpty || alg != 'Ed25519') {
        debugPrint('ACTIVATION_FAIL reason=bad_envelope_fields alg=$alg');
        return const ActivationStatus(
          isActive: false,
          message: 'Invalid activation payload',
        );
      }

      final payloadBytes = _decodeB64(payloadB64);
      final signatureBytes = _decodeB64(sigB64);
      final payloadJson = jsonDecode(utf8.decode(payloadBytes));
      if (payloadJson is! Map<String, dynamic>) {
        debugPrint('ACTIVATION_FAIL reason=payload_not_map');
        return const ActivationStatus(
          isActive: false,
          message: 'Invalid activation data',
        );
      }

      final kid = (payloadJson['kid'] ?? '').toString().trim();
      final pubRaw = _publicKeysByKid[kid];
      if (pubRaw == null || pubRaw.startsWith('REPLACE_WITH_')) {
        debugPrint('ACTIVATION_FAIL reason=public_key_not_configured kid=$kid');
        return const ActivationStatus(
          isActive: false,
          message: 'Public key not configured',
        );
      }
      final publicKey = SimplePublicKey(
        _decodeB64(pubRaw),
        type: KeyPairType.ed25519,
      );
      final verified = await Ed25519().verify(
        payloadBytes,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
      if (!verified) {
        debugPrint('ACTIVATION_FAIL reason=signature_mismatch kid=$kid');
        return const ActivationStatus(
          isActive: false,
          message: 'Invalid activation signature',
        );
      }

      final payloadCompany =
          (payloadJson['company_code'] ?? '').toString().trim();
      final appCompany = (companyCodeOverride ??
              (await DatabaseService.getCompanyProfile())?.companyCode ??
              '')
          .trim();
      if (payloadCompany.isEmpty || appCompany.isEmpty) {
        debugPrint(
            'ACTIVATION_FAIL reason=company_missing payload="$payloadCompany" app="$appCompany"');
        return const ActivationStatus(
          isActive: false,
          message: 'Company code is missing',
        );
      }
      if (payloadCompany != appCompany) {
        debugPrint(
            'ACTIVATION_FAIL reason=company_mismatch payload="$payloadCompany" app="$appCompany"');
        return const ActivationStatus(
          isActive: false,
          message: 'Activation does not match company code',
        );
      }

      final exp = (payloadJson['exp'] ?? '').toString().trim();
      final expiryDate = DateTime.tryParse(exp);
      if (expiryDate == null) {
        debugPrint('ACTIVATION_FAIL reason=bad_exp exp="$exp"');
        return const ActivationStatus(
          isActive: false,
          message: 'Invalid activation expiry date',
        );
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final expiryDay =
          DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
      if (expiryDay.isBefore(today)) {
        debugPrint(
            'ACTIVATION_FAIL reason=expired exp=${Receipt.formatDate(expiryDay)}');
        return ActivationStatus(
          isActive: false,
          message: 'Activation expired on ${Receipt.formatDate(expiryDay)}',
          expiryDate: expiryDay,
          plan: (payloadJson['plan'] ?? '').toString().trim(),
          companyCode: payloadCompany,
        );
      }

      debugPrint(
          'ACTIVATION_OK kid=$kid company="$payloadCompany" exp=${Receipt.formatDate(expiryDay)}');
      return ActivationStatus(
        isActive: true,
        message: 'Activated until ${Receipt.formatDate(expiryDay)}',
        expiryDate: expiryDay,
        plan: (payloadJson['plan'] ?? '').toString().trim(),
        companyCode: payloadCompany,
      );
    } catch (_) {
      debugPrint('ACTIVATION_FAIL reason=exception');
      return const ActivationStatus(
        isActive: false,
        message: 'Invalid activation key',
      );
    }
  }

  static List<int> _decodeB64(String value) {
    var v = value.trim().replaceAll('\n', '').replaceAll('\r', '');
    v = v.replaceAll('-', '+').replaceAll('_', '/');
    final rem = v.length % 4;
    if (rem > 0) {
      v = '$v${'=' * (4 - rem)}';
    }
    return base64.decode(v);
  }
}

class DocumentCaptureService {
  static Future<XFile?> captureCorrected({
    required bool allowGalleryImport,
  }) async {
    final started = Stopwatch()..start();
    final mode = await AppPhotoSaveSettings.getMode();
    final edgeMode = await AppDocumentCaptureSettings.getMode();
    final quality = mode == PhotoSaveSizeMode.compact ? 60 : 75;
    final width = AppPhotoSaveSettings.maxWidth(mode);

    XFile? result;
    try {
      // Import from gallery should preserve source readability.
      // Scanner auto-enhancement can over-brighten some receipts and blur text.
      if (allowGalleryImport) {
        final picker = ImagePicker();
        result = await picker.pickImage(
          source: ImageSource.gallery,
          // Keep gallery import at original quality/resolution to preserve text detail.
          imageQuality: null,
          maxWidth: null,
        );
      } else if (edgeMode == DocumentEdgeMode.auto) {
        final paths = await CunningDocumentScanner.getPictures(
          noOfPages: 1,
          isGalleryImportAllowed: allowGalleryImport,
          iosScannerOptions: IosScannerOptions(
            imageFormat: IosImageFormat.jpg,
            jpgCompressionQuality: quality / 100.0,
          ),
        );
        if (paths != null && paths.isNotEmpty) {
          final first = paths.first.trim();
          if (first.isNotEmpty) {
            result = XFile(first);
          }
        }
      } else {
        final picker = ImagePicker();
        result = await picker.pickImage(
          source: allowGalleryImport ? ImageSource.gallery : ImageSource.camera,
          imageQuality: quality,
          maxWidth: width,
        );
      }
      return result;
    } finally {
      started.stop();
      debugPrint(
        'DOC_CAPTURE_MS=${started.elapsedMilliseconds} edge_mode=${edgeMode.name} gallery=$allowGalleryImport',
      );
    }
  }
}

void goToHomePage(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const ProjectListPage()),
    (route) => false,
  );
}

Widget buildPageTitleBanner(
  BuildContext context, {
  required String title,
  required IconData icon,
  bool useLogo = true,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      gradient: AppDecor.heroGradient(colorScheme),
      borderRadius: BorderRadius.circular(16),
      boxShadow: AppDecor.softShadow(colorScheme),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: colorScheme.onPrimary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: useLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset(
                      'assets/app_logo.png',
                      fit: BoxFit.cover,
                    ),
                  )
                : Icon(icon, color: colorScheme.onPrimary),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      ],
    ),
  );
}

Future<void> openInAppPrintPreview(
  BuildContext context, {
  required String title,
  required String fileName,
  required Uint8List pdfBytes,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => _InAppPrintPreviewPage(
        title: title,
        fileName: fileName,
        pdfBytes: pdfBytes,
      ),
    ),
  );
}

class _InAppPrintPreviewPage extends StatefulWidget {
  final String title;
  final String fileName;
  final Uint8List pdfBytes;

  const _InAppPrintPreviewPage({
    required this.title,
    required this.fileName,
    required this.pdfBytes,
  });

  @override
  State<_InAppPrintPreviewPage> createState() => _InAppPrintPreviewPageState();
}

class _InAppPrintPreviewPageState extends State<_InAppPrintPreviewPage> {
  bool _printing = false;

  Future<void> _directPrint() async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final printer = await Printing.pickPrinter(context: context);
      if (printer == null) return;
      final printed = await Printing.directPrintPdf(
        printer: printer,
        name: widget.fileName,
        onLayout: (_) async => widget.pdfBytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(printed ? 'Print job sent.' : 'Print not completed.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close preview',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Print',
            onPressed: _printing ? null : _directPrint,
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: PdfPreview(
        allowPrinting: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        pdfFileName: widget.fileName,
        build: (_) async => widget.pdfBytes,
      ),
    );
  }
}

class AppDecor {
  static LinearGradient heroGradient(ColorScheme colorScheme) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        colorScheme.primary,
        Color.lerp(colorScheme.primary, colorScheme.tertiary, 0.45)!,
        colorScheme.tertiary,
      ],
    );
  }

  static List<BoxShadow> softShadow(ColorScheme colorScheme) {
    return [
      BoxShadow(
        color: colorScheme.shadow.withValues(alpha: 0.08),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];
  }
}
