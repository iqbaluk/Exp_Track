part of '../../main.dart';

extension _ReceiptEntryScanController on _ReceiptEntryPageState {
  Future<void> _scanWithGeminiMode(String scanMode) async {
    debugPrint('SCAN_BUTTON mode=$scanMode');
    if (_imageBytes == null) {
      _showStatus(
        'Please add a photo first using Take Photo or Gallery.',
        isError: true,
      );
      return;
    }

    final hasGeminiSettings = await GeminiService.hasUsableSettings();
    if (!hasGeminiSettings) {
      _showStatus(
        'Gemini API key not set. Open Operation actions > Gemini settings. Manual entry still works.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    final profile = await DatabaseService.getCompanyProfile();
    final missingCompanyInfo = profile == null ||
        profile.clientName.trim().isEmpty ||
        profile.companyCode.trim().isEmpty ||
        profile.businessNature.trim().isEmpty ||
        profile.businessDescription.trim().isEmpty;
    if (missingCompanyInfo) {
      _showStatus(
        'Company info is required before scan. Open Management > Company info and complete all fields.',
        isError: true,
        duration: const Duration(seconds: 7),
      );
      return;
    }
    final hint = _scanHintController.text.trim();

    _setActiveScanMode(scanMode);
    _setScanningState(true);
    debugPrint(
      'SCAN_IMAGE_FINGERPRINT mode=$scanMode file="${_imageFilePath ?? ''}" raw=${_fingerprintBytes(_imageBytes)} fast=${_fingerprintBytes(_fastScanBytes)}',
    );
    ScanResult result;
    try {
      result = await GeminiService.scanReceipt(
        _imageBytes!,
        imagePath: _imageFilePath,
        scanModeOverride: scanMode,
        qualityUserHint: hint.isEmpty ? null : hint,
        fastPreparedBytes: (scanMode == GeminiService.scanModeFast ||
                scanMode == GeminiService.scanModeFastV2)
            ? _fastScanBytes
            : null,
      );
    } finally {
      if (mounted) {
        _setScanningState(false);
        _setActiveScanMode(null);
      }
    }
    if (!mounted) return;
    _mutateEntryState(() {
      _lastScanTelemetry = GeminiService.lastScanTelemetry();
    });

    if (!result.success) {
      _showStatus(
        'Auto-scan unavailable ? please enter manually. (${result.errorMessage})',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }

    final uiApplyStopwatch = Stopwatch()..start();
    var effectiveData = result.data!;
    if (_looksLikeBuyerNameVariant(
      effectiveData.supplier,
      profile.clientName,
    )) {
      final warnings = <String>[
        ...effectiveData.extractionWarnings,
        'Supplier matched buyer name variant; cleared for manual review',
      ];
      effectiveData = ReceiptData(
        date: effectiveData.date,
        invoiceNumber: effectiveData.invoiceNumber,
        supplier: null,
        vat: effectiveData.vat,
        gross: effectiveData.gross,
        paidAmount: effectiveData.paidAmount,
        net: effectiveData.net,
        rawNotes: effectiveData.rawNotes,
        extractionWarnings: warnings,
      );
      debugPrint(
        'SCAN_SUPPLIER_GUARD mode=$scanMode buyer_match=true buyer="${profile.clientName}"',
      );
    }
    debugPrint(
      'SCAN_PARSED date=${effectiveData.date?.toIso8601String()} invoice="${effectiveData.invoiceNumber}" supplier="${effectiveData.supplier}" gross=${effectiveData.gross} vat=${effectiveData.vat} paid=${effectiveData.paidAmount} net=${effectiveData.net}',
    );

    final categoryMessage = _applyScanData(
      effectiveData,
      mergeOnly: false,
    );
    uiApplyStopwatch.stop();
    debugPrint(
      'SCAN_UI_APPLY mode=$scanMode apply_ms=${uiApplyStopwatch.elapsedMilliseconds}',
    );
    final missing = _missingFieldsAfterScan();
    final warnings = effectiveData.extractionWarnings
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty)
        .toList();
    final handwritingWarnings =
        warnings.where((w) => w.toLowerCase().contains('handwritten')).toList();
    final baseMessage = categoryMessage ?? 'Scan complete. Review fields.';
    final warningSuffix =
        warnings.isEmpty ? '' : ' Check: ${warnings.join(' | ')}.';
    if (missing.isNotEmpty) {
      _showStatus(
        '$baseMessage Please enter manually: ${missing.join(', ')}.$warningSuffix',
        isError: true,
        duration: const Duration(seconds: 8),
      );
      return;
    }
    final speedHint = scanMode == GeminiService.scanModeFast
        ? ' If any value looks wrong, tap Quality scan.'
        : '';
    _showStatus(
      '$baseMessage$warningSuffix$speedHint',
      isError: handwritingWarnings.isNotEmpty,
      duration: const Duration(seconds: 8),
    );
  }

  List<String> _missingFieldsAfterScan() {
    final missing = <String>[];
    if (_selectedDate == null) missing.add('Invoice date');
    if (_invoiceNumberController.text.trim().isEmpty) {
      missing.add('Invoice number');
    }
    if (_supplierController.text.trim().isEmpty) missing.add('Supplier');
    final gross = double.tryParse(_grossController.text.trim()) ?? 0;
    if (gross <= 0) missing.add('Gross amount');
    return missing;
  }

  String? _applyScanData(
    ReceiptData data, {
    required bool mergeOnly,
  }) {
    _applyScanStateMutations(
      data: data,
      mergeOnly: mergeOnly,
      suggestion: null,
      onCategoryApplied: (category, confidence) {},
      onCategoryKept: () {},
    );
    return null;
  }

  void _applyScanStateMutations({
    required ReceiptData data,
    required bool mergeOnly,
    required ({String category, double confidence})? suggestion,
    required void Function(String category, double confidence)
        onCategoryApplied,
    required VoidCallback onCategoryKept,
  }) {
    _mutateEntryState(() {
      if (!mergeOnly) {
        // Reset scan-populated fields in the same mutation to avoid stale data
        // and reduce extra rebuild work.
        _selectedDate = null;
        _invoiceNumberController.clear();
        _supplierController.clear();
        _selectedCategory = _resolveDefaultCategory(fallback: _selectedCategory);
        _vatController.clear();
        _grossController.clear();
        _paidController.clear();
        _netController.clear();
        _notesController.clear();
      }

      if (data.date != null && (!mergeOnly || _isDateUntouched())) {
        _selectedDate = data.date!;
      }
      if (data.invoiceNumber != null &&
          (!mergeOnly || _invoiceNumberController.text.isEmpty)) {
        _invoiceNumberController.text = data.invoiceNumber!;
      }
      if (data.supplier != null &&
          (!mergeOnly || _supplierController.text.isEmpty)) {
        _supplierController.text = data.supplier!;
      }
      if (data.vat != null && (!mergeOnly || _vatController.text.isEmpty)) {
        _vatController.text = data.vat!.toStringAsFixed(2);
      }
      if (data.gross != null && (!mergeOnly || _grossController.text.isEmpty)) {
        _grossController.text = data.gross!.toStringAsFixed(2);
      }
      if (data.paidAmount != null &&
          (!mergeOnly || _paidController.text.isEmpty)) {
        _paidController.text = data.paidAmount!.toStringAsFixed(2);
      }
      if (data.net != null &&
          data.gross == null &&
          data.paidAmount == null &&
          (!mergeOnly || _netController.text.isEmpty)) {
        _netController.text = data.net!.toStringAsFixed(2);
      }
      if (data.rawNotes != null &&
          (!mergeOnly || _notesController.text.isEmpty)) {
        _notesController.text = data.rawNotes!;
      }

      if (suggestion != null) {
        if (!mergeOnly || _selectedCategory == null) {
          _selectedCategory = suggestion.category;
          onCategoryApplied(suggestion.category, suggestion.confidence);
        } else {
          onCategoryKept();
        }
      }
    });
  }


  String _fingerprintBytes(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return 'none';
    final take = bytes.length < 16 ? bytes.length : 16;
    var acc = 0;
    for (var i = 0; i < take; i++) {
      acc = (acc + bytes[i]) % 100000;
    }
    return 'len=${bytes.length},sig=$acc';
  }

  bool _isDateUntouched() {
    return _selectedDate == null;
  }

  bool _looksLikeBuyerNameVariant(String? supplier, String buyerName) {
    final s = _normalizeCompanyText(supplier ?? '');
    final b = _normalizeCompanyText(buyerName);
    if (s.isEmpty || b.isEmpty) return false;
    if (s == b) return true;
    if (s.length >= 6 && b.length >= 6 && (s.contains(b) || b.contains(s))) {
      return true;
    }

    final distance = _levenshteinDistance(s, b);
    final threshold = (b.length * 0.22).round().clamp(2, 6);
    return distance <= threshold;
  }

  String _normalizeCompanyText(String value) {
    var v = value.toLowerCase();
    v = v.replaceAll(RegExp(r'\b(ltd|limited|llp|plc|co|company)\b'), ' ');
    v = v.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return v.trim();
  }

  int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.generate(b.length + 1, (i) => i);
    final curr = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      for (var j = 0; j <= b.length; j++) {
        prev[j] = curr[j];
      }
    }
    return prev[b.length];
  }
}
