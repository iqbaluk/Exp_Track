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
    final businessNature = profile.businessNature.trim();
    final businessDescription = profile.businessDescription.trim();
    _subcategoryToMain = const {};
    _headKeywordPhrases = const {};
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
        businessNature: businessNature,
        businessDescription: businessDescription,
        scanModeOverride: scanMode,
        qualityUserHint: hint.isEmpty ? null : hint,
        fastPreparedBytes:
            scanMode == GeminiService.scanModeFast ? _fastScanBytes : null,
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

    // Always reset scan-populated fields first to avoid mixing stale values
    // from previous/manual entries when current scan misses a field.
    _mutateEntryState(() {
      _selectedDate = null;
      _invoiceNumberController.clear();
      _supplierController.clear();
      _selectedCategory = _resolveDefaultCategory(fallback: _selectedCategory);
      _vatController.clear();
      _grossController.clear();
      _paidController.clear();
      _netController.clear();
      _notesController.clear();
      _lastCategoryConfidence = null;
      _categoryNeedsReview = false;
      _categoryReviewConfirmed = false;
    });

    final effectiveData = result.data!;
    debugPrint(
      'SCAN_PARSED date=${effectiveData.date?.toIso8601String()} invoice="${effectiveData.invoiceNumber}" supplier="${effectiveData.supplier}" subcat="${effectiveData.category}" conf=${effectiveData.categoryConfidence} reason="${effectiveData.categoryReason}" gross=${effectiveData.gross} vat=${effectiveData.vat} paid=${effectiveData.paidAmount} net=${effectiveData.net}',
    );

    final categoryMessage = _applyScanData(
      effectiveData,
      mergeOnly: false,
      businessNature: businessNature,
      businessDescription: businessDescription,
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
    final lowConfidence = (_lastCategoryConfidence ?? 100) < 60;
    _showStatus(
      '$baseMessage$warningSuffix',
      isError: handwritingWarnings.isNotEmpty || lowConfidence,
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
    String? businessNature,
    String? businessDescription,
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

      if (suggestion != null && (!mergeOnly || _selectedCategory != null)) {
        _lastCategoryConfidence = suggestion.confidence;
        _categoryNeedsReview = suggestion.confidence < 80;
        _categoryReviewConfirmed = !_categoryNeedsReview;
      } else {
        _lastCategoryConfidence = null;
        _categoryNeedsReview = false;
        _categoryReviewConfirmed = true;
      }
    });
  }

  String? _matchConfiguredCategory(String? rawCategory) {
    if (rawCategory == null) return null;
    final cleaned = rawCategory.trim();
    if (cleaned.isEmpty) return null;

    for (final category in _categories) {
      if (category.toLowerCase() == cleaned.toLowerCase()) {
        return category;
      }
    }

    final loose = cleaned.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    for (final category in _categories) {
      final candidate =
          category.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (candidate == loose) return category;
    }
    return null;
  }

  ({String category, double confidence})? _categorySuggestionFromScan(
    ReceiptData data, {
    String? businessNature,
    String? businessDescription,
  }) {
    final motorMain = _findMotorTravelMain();
    if (motorMain != null && _looksLikeMotorExpense(data)) {
      final confidence =
          (data.categoryConfidence ?? 82).clamp(70, 100).toDouble();
      debugPrint(
        'SCAN_CATEGORY_OVERRIDE reason=contextual_match mapped_main="$motorMain" confidence=$confidence',
      );
      return (category: motorMain, confidence: confidence);
    }

    final raw = data.category?.trim();
    final keywordMatch = _matchHeadByKeywords(data);
    final aiConfidenceRaw = (data.categoryConfidence ?? 0).toDouble();

    if (keywordMatch != null &&
        (keywordMatch.score >= 2 || aiConfidenceRaw < 80)) {
      final confidence =
          (70 + (keywordMatch.score * 8)).clamp(70, 96).toDouble();
      debugPrint(
        'SCAN_CATEGORY_KEYWORDS matched_head="${keywordMatch.head}" score=${keywordMatch.score} confidence=$confidence',
      );
      return (category: keywordMatch.head, confidence: confidence);
    }

    if (raw != null && raw.isNotEmpty) {
      final mappedMain = _mapSubcategoryToMain(raw);
      if (mappedMain != null) {
        final aiConfidence = (data.categoryConfidence ?? 70).toDouble();
        final confidence = aiConfidence.clamp(60, 100).toDouble();
        final otherMain = _findGeneralExpensesMain();
        if (aiConfidence < 60 && otherMain != null) {
          debugPrint(
            'SCAN_CATEGORY_SAFEGUARD low_confidence=$aiConfidence mapped_main="$mappedMain" fallback_main="$otherMain"',
          );
          return (
            category: otherMain,
            confidence: aiConfidence.clamp(40, 59).toDouble()
          );
        }
        debugPrint(
          'SCAN_CATEGORY_MAP raw_subcategory="$raw" mapped_main="$mappedMain" confidence=$confidence',
        );
        return (category: mappedMain, confidence: confidence);
      }

      // Graceful fallback if model returns a main head directly.
      final aiCategory = _matchConfiguredCategory(raw);
      if (aiCategory != null) {
        final confidence =
            (data.categoryConfidence ?? 75).clamp(55, 100).toDouble();
        return (category: aiCategory, confidence: confidence);
      }
    }

    final general = _findGeneralExpensesMain();
    if (general != null) {
      final confidence =
          (data.categoryConfidence ?? 55).clamp(0, 100).toDouble();
      debugPrint(
        'SCAN_CATEGORY_MAP raw_subcategory="${data.category}" mapped_main_fallback="$general" confidence=$confidence',
      );
      return (category: general, confidence: confidence);
    }
    return null;
  }

  String? _findGeneralExpensesMain() {
    for (final category in _categories) {
      final key = category.toLowerCase();
      if (key.contains('miscellaneous')) {
        return category;
      }
    }
    for (final category in _categories) {
      final key = category.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (key == 'generalexpenses' || key.contains('generalexpense')) {
        return category;
      }
    }
    for (final category in _categories) {
      final key = category.toLowerCase();
      if (key.contains('other')) return category;
    }
    return _categories.isNotEmpty ? _categories.first : null;
  }

  String? _findMotorTravelMain() {
    for (final category in _categories) {
      final key = category.toLowerCase();
      if (key.contains('motor, travel & subsistence') ||
          key.contains('motor') ||
          key.contains('travel')) {
        return category;
      }
    }
    return null;
  }

  bool _looksLikeMotorExpense(ReceiptData data) {
    final text = [
      data.supplier ?? '',
      data.category ?? '',
      data.categoryReason ?? '',
      data.rawNotes ?? '',
    ].join(' ').toLowerCase();
    if (text.trim().isEmpty) return false;
    const strongMotorTerms = [
      'maserati',
      'garage',
      'autocentre',
      'autocenter',
      'motor',
      'steering',
      'gearbox',
      'clutch',
      'brake',
      'tyre',
      'tire',
      'mot',
      'vehicle repair',
      'windscreen',
      'car parts',
      'engine',
      'suspension',
      'exhaust',
      'battery',
      'spark plug',
      'oil filter',
      'dealership',
      'auto',
      'automotive',
      'mechanic',
    ];
    return strongMotorTerms.any(text.contains);
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

  String? _mapSubcategoryToMain(String rawSubcategory) {
    if (_subcategoryToMain.isEmpty) return null;
    final key = rawSubcategory.trim().toLowerCase();
    final exact = _subcategoryToMain[key];
    if (exact != null) return _matchConfiguredCategory(exact);

    final normKey = _normalizeCategoryKey(rawSubcategory);
    if (normKey.isNotEmpty) {
      final normExact = _subcategoryToMain[normKey];
      if (normExact != null) return _matchConfiguredCategory(normExact);
    }

    final rawTokens = _tokenize(key);
    if (rawTokens.isEmpty) return null;
    double bestScore = 0;
    String? bestMain;

    for (final entry in _subcategoryToMain.entries) {
      final candidateTokens = _tokenize(entry.key);
      if (candidateTokens.isEmpty) continue;
      final overlap = rawTokens.intersection(candidateTokens).length;
      var score = overlap / rawTokens.length;
      final candidateKey = entry.key;
      if (normKey.isNotEmpty && candidateKey.contains(normKey)) {
        score += 0.25;
      }
      if (key.isNotEmpty && candidateKey.contains(key)) {
        score += 0.15;
      }
      if (score > bestScore) {
        bestScore = score;
        bestMain = entry.value;
      }
    }

    if (bestMain != null && bestScore >= 0.30) {
      debugPrint(
        'SCAN_CATEGORY_MAP_FUZZY raw="$rawSubcategory" best_main="$bestMain" score=${bestScore.toStringAsFixed(2)}',
      );
      return _matchConfiguredCategory(bestMain);
    }
    return null;
  }

  String _normalizeCategoryKey(String text) {
    return text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }

  Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .split(' ')
        .map((t) => t.trim())
        .where((t) => t.length >= 3)
        .toSet();
  }

  ({String head, int score})? _matchHeadByKeywords(ReceiptData data) {
    if (_headKeywordPhrases.isEmpty) return null;
    final text = [
      data.supplier ?? '',
      data.rawNotes ?? '',
      data.categoryReason ?? '',
    ].join(' ').toLowerCase();
    if (text.trim().isEmpty) return null;

    var bestHead = '';
    var bestScore = 0;
    for (final entry in _headKeywordPhrases.entries) {
      var score = 0;
      for (final phrase in entry.value) {
        if (phrase.isEmpty) continue;
        if (text.contains(phrase)) score++;
      }
      if (score > bestScore) {
        bestScore = score;
        bestHead = entry.key;
      }
    }
    if (bestHead.isEmpty || bestScore <= 0) return null;
    final mapped = _matchConfiguredCategory(bestHead);
    if (mapped == null) return null;
    return (head: mapped, score: bestScore);
  }

  bool _isDateUntouched() {
    return _selectedDate == null;
  }
}
