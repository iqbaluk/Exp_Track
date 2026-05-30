part of '../main.dart';

class ReceiptEntryPage extends StatefulWidget {
  final Project project;
  final Uint8List? initialImageBytes;
  final String? initialImageName;
  final String? initialImagePath;
  final Uint8List? initialFastScanBytes;

  const ReceiptEntryPage({
    super.key,
    required this.project,
    this.initialImageBytes,
    this.initialImageName,
    this.initialImagePath,
    this.initialFastScanBytes,
  });

  @override
  State<ReceiptEntryPage> createState() => _ReceiptEntryPageState();
}

class _ReceiptEntryPageState extends State<ReceiptEntryPage> {
  final _formKey = GlobalKey<FormState>();

  DateTime? _selectedDate;
  final _invoiceNumberController = TextEditingController();
  final _supplierController = TextEditingController();
  String? _selectedCategory;
  final _vatController = TextEditingController();
  final _grossController = TextEditingController();
  final _paidController = TextEditingController();
  final _netController = TextEditingController();
  final _notesController = TextEditingController();
  final _scanHintController = TextEditingController();

  Uint8List? _imageBytes;
  Uint8List? _fastScanBytes;
  String? _imageFileName;
  String? _imageFilePath;

  bool _isScanning = false;
  String? _activeScanMode;
  bool _isSaving = false;
  bool _canWriteData = false;
  bool _isAutoAmountUpdate = false;
  bool _showScanHint = false;
  double? _lastCategoryConfidence;
  bool _categoryNeedsReview = false;
  bool _categoryReviewConfirmed = false;
  ScanTelemetry? _lastScanTelemetry;

  String? _statusMessage;
  bool _statusIsError = false;

  List<Receipt> _recentReceipts = [];
  List<String> _categories = DatabaseService.defaultCategories;
  Map<String, String> _subcategoryToMain = {};
  Map<String, List<String>> _headKeywordPhrases = {};
  int _totalReceiptCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.project.name;
    _imageBytes = widget.initialImageBytes;
    _imageFileName = widget.initialImageName;
    _imageFilePath = widget.initialImagePath;
    _fastScanBytes = widget.initialFastScanBytes;
    _grossController.addListener(_syncAmountFields);
    _vatController.addListener(_syncAmountFields);
    _paidController.addListener(_syncAmountFields);
    _loadCategories();
    _loadRecent();
    _loadWriteAccess();
    if (_imageBytes != null && _fastScanBytes == null) {
      _prepareFastScanCache();
    }
  }

  Future<void> _loadWriteAccess() async {
    final canWrite = await ActivationLicenseService.canWriteData();
    if (!mounted) return;
    setState(() => _canWriteData = canWrite);
  }

  @override
  void dispose() {
    _invoiceNumberController.dispose();
    _supplierController.dispose();
    _vatController.dispose();
    _grossController.dispose();
    _paidController.dispose();
    _netController.dispose();
    _notesController.dispose();
    _scanHintController.dispose();
    super.dispose();
  }

  Future<void> _loadRecent() async {
    try {
      final today = DateTime.now();
      final dayStart = DateTime(today.year, today.month, today.day);
      final todayReceipts = await DatabaseService.getByScanDateRange(
        dayStart,
        dayStart,
        projectId: widget.project.id,
      );
      if (!mounted) return;
      setState(() {
        _recentReceipts = todayReceipts;
        _totalReceiptCount = todayReceipts.length;
      });
    } catch (e) {
      debugPrint('Failed to load recent: $e');
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await DatabaseService.getMainCategories();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _selectedCategory =
            _resolveDefaultCategory(fallback: _selectedCategory);
      });
    } catch (e) {
      debugPrint('Failed to load categories: $e');
    }
  }

  String? _resolveDefaultCategory({String? fallback}) {
    final fallbackValue = fallback?.trim();
    if (fallbackValue != null &&
        fallbackValue.isNotEmpty &&
        _categories.contains(fallbackValue)) {
      return fallbackValue;
    }
    for (final category in _categories) {
      final key = category.toLowerCase();
      if (key.contains('general') || key.contains('misc')) return category;
    }
    return _categories.isNotEmpty ? _categories.first : null;
  }

  void _syncAmountFields() {
    if (_isAutoAmountUpdate) return;
    final gross = double.tryParse(_grossController.text) ?? 0;
    final vat = double.tryParse(_vatController.text) ?? 0;
    var paid = double.tryParse(_paidController.text);

    _isAutoAmountUpdate = true;
    try {
      if (paid == null && gross > 0) {
        paid = gross;
        _paidController.text = gross.toStringAsFixed(2);
      }
      if (gross > 0) {
        _netController.text = (gross - vat).toStringAsFixed(2);
      } else if (_netController.text.trim().isEmpty) {
        _netController.clear();
      }
    } finally {
      _isAutoAmountUpdate = false;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  void _showStatus(String message, {bool isError = false, Duration? duration}) {
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
    Future.delayed(duration ?? const Duration(seconds: 4), () {
      if (mounted && _statusMessage == message) {
        setState(() => _statusMessage = null);
      }
    });
  }

  // ---- Image picking ----

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await DocumentCaptureService.captureCorrected(
        allowGalleryImport: false,
      );
      if (photo != null) await _setImage(photo);
    } catch (e) {
      _showStatus(
        'Could not capture document. Retake in better light and keep full page in frame.',
        isError: true,
      );
    }
  }

  Future<void> _pickFromGallery() async {
    await _openIntakePage();
  }

  Future<void> _setImage(XFile file) async {
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFileName = file.name;
      _imageFilePath = file.path;
    });
    _showStatus('Image loaded. You can scan with Gemini.');
    _prepareFastScanCache();
  }

  Future<void> _openIntakePage() async {
    try {
      final selected = await Navigator.of(context).push<IntakeImageSelection>(
        MaterialPageRoute(builder: (_) => const ReceiptIntakePage()),
      );
      if (!mounted || selected == null) return;
      setState(() {
        _imageBytes = selected.bytes;
        _fastScanBytes = selected.fastScanBytes;
        _imageFileName = selected.name;
        _imageFilePath = selected.path;
      });
      _showStatus('Image loaded from intake. You can scan with Gemini.');
      _prepareFastScanCache();
    } catch (e) {
      _showStatus('Could not open intake page: $e', isError: true);
    }
  }

  Future<void> _prepareFastScanCache() async {
    final source = _imageBytes;
    if (source == null) return;
    final prepared = await GeminiService.prepareFastScanPayload(source);
    if (!mounted) return;
    setState(() {
      _fastScanBytes = prepared;
    });
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _fastScanBytes = null;
      _imageFileName = null;
      _imageFilePath = null;
    });
  }

  Future<void> _openScanImageViewer() async {
    if (_imageBytes == null) return;
    final action = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (value) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Scan image quality check'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close',
              onPressed: () => Navigator.of(value).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 6.0,
              child: Image.memory(
                _imageBytes!,
                fit: BoxFit.contain,
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(value).pop('camera'),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(value).pop('gallery'),
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Gallery'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(value).pop('use'),
                      icon: const Icon(Icons.check),
                      label: const Text('Use this'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || action == null || action == 'use') return;
    if (_isScanning) return;
    if (action == 'camera') {
      await _takePhoto();
    } else if (action == 'gallery') {
      await _pickFromGallery();
    }
  }
  // Gemini scan flow extracted to receipt_entry/receipt_entry_scan_controller.dart.

  Future<bool> _confirmLowCategoryConfidenceBeforeSave() async {
    return true;
  }

  void _setSavingState(bool value) {
    if (!mounted) return;
    setState(() => _isSaving = value);
  }

  void _setScanningState(bool value) {
    if (!mounted) return;
    setState(() => _isScanning = value);
  }

  void _setActiveScanMode(String? mode) {
    if (!mounted) return;
    setState(() => _activeScanMode = mode);
  }

  void _mutateEntryState(VoidCallback mutate) {
    if (!mounted) return;
    setState(mutate);
  }

  // Save flow and duplicate dialogs were extracted into
  // receipt_entry/receipt_entry_save_controller.dart and
  // receipt_entry/receipt_entry_duplicate_dialogs.dart.

  void _clearForm({bool silent = false, bool keepCategory = false}) {
    final retainedCategory = keepCategory ? _selectedCategory : null;
    setState(() {
      _selectedDate = null;
      _invoiceNumberController.clear();
      _supplierController.clear();
      _selectedCategory = retainedCategory;
      _vatController.clear();
      _grossController.clear();
      _paidController.clear();
      _netController.clear();
      _notesController.clear();
      _scanHintController.clear();
      _lastCategoryConfidence = null;
      _categoryNeedsReview = false;
      _categoryReviewConfirmed = false;
      _imageBytes = null;
      _fastScanBytes = null;
      _imageFileName = null;
    });
    if (!silent) _showStatus('Form cleared');
  }

  // ---- Export ----

  Future<void> _showExportMenu() async {
    // Step 1: pick range
    final range = await _pickExportRange(
      context,
      title: 'Export - pick range',
      includeTodayWeek: true,
    );
    if (range == null || !mounted) return;

    // Step 2: pick what to include
    final contentChoice = await showDialog<ExportContent>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('What to include?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.csvOnly),
            child: const ListTile(
              leading: Icon(Icons.description),
              title: Text('CSV only (the table)'),
              subtitle: Text('Best for accountant via WhatsApp'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.both),
            child: const ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('CSV + photos ZIP'),
              subtitle: Text('CSV attached separately, photos zipped'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ExportContent.photosOnly),
            child: const ListTile(
              leading: Icon(Icons.photo_library),
              title: Text('Photos only (ZIP)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (contentChoice == null || !mounted) return;

    // Step 3: pick which date to filter by
    final basisChoice = await showDialog<DateBasis>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filter by which date?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DateBasis.scanDate),
            child: const ListTile(
              leading: Icon(Icons.qr_code_scanner),
              title: Text('Scan date'),
              subtitle: Text(
                  'When I added it to the app\n(default ? catches backdated entries)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              isThreeLine: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, DateBasis.invoiceDate),
            child: const ListTile(
              leading: Icon(Icons.receipt_long),
              title: Text('Invoice date'),
              subtitle: Text(
                  'Date on the receipt itself\n(best for VAT periods / accountant)'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              isThreeLine: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (basisChoice == null || !mounted) return;

    _showStatus('Building export...', duration: const Duration(seconds: 3));

    final result = await ExportService.exportAndShare(
      range,
      content: contentChoice,
      dateBasis: basisChoice,
      projectId: widget.project.id,
      projectName: widget.project.name,
    );

    if (!mounted) return;

    if (result.success) {
      _showStatus(
        'Sharing ${result.recordCount} receipts'
        '${result.photoCount > 0 ? " + ${result.photoCount} photos" : ""}.'
        ' Pick OneDrive / WhatsApp / etc.',
        duration: const Duration(seconds: 6),
      );
    } else {
      _showStatus(result.errorMessage ?? 'Export failed', isError: true);
    }
  }

  // ---- Detail navigation ----

  Future<void> _openDetail(Receipt receipt) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (value) => ReceiptDetailPage(receipt: receipt),
      ),
    );
    if (changed == true) {
      await _loadRecent();
    }
  }

  Future<void> _openReports() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (value) => ReportsHubPage(initialProject: widget.project),
      ),
    );
  }

  Future<void> _openInvoiceList() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (value) => const ReceiptHistoryPage(),
      ),
    );
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: 'Intake',
            onPressed: _isScanning ? null : _openIntakePage,
          ),
          IconButton(
            icon: const Icon(Icons.home_outlined),
            tooltip: 'Home',
            onPressed: () => goToHomePage(context),
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'Invoice list',
            onPressed: _openInvoiceList,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Reports',
            onPressed: _openReports,
          ),
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            tooltip: 'Export / Share',
            onPressed: _showExportMenu,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Clear form',
            onPressed: () => _clearForm(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 132),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildPageTitleBanner(
                  context,
                  title: 'Receipt entry and scan',
                  icon: Icons.document_scanner_outlined,
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.business_center_outlined,
                        size: 18,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Operation:',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.project.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_statusMessage != null) _buildStatusBanner(),
                if (_lastScanTelemetry != null) _buildScanDebugBadge(),
                _buildSectionHeader('1. Receipt Photo (optional)'),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isScanning ? null : _takePhoto,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Take Photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isScanning ? null : _pickFromGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Gallery'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildImagePreview(),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _isScanning
                      ? null
                      : () => setState(() => _showScanHint = !_showScanHint),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Hint for scan',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          _showScanHint
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showScanHint)
                  TextField(
                    controller: _scanHintController,
                    maxLength: 120,
                    enabled: !_isScanning,
                    decoration: const InputDecoration(
                      labelText: 'Hint for scan',
                      hintText:
                          'What is missing in Fast scan? (e.g. date dd/mm/yy bottom-left, VAT in summary)',
                      helperText:
                          'Tell AI exactly what Fast scan missed and where it appears on invoice.',
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_imageBytes == null || _isScanning)
                            ? null
                            : _scanWithGeminiQuality,
                        icon: _isScanning &&
                                _activeScanMode ==
                                    GeminiService.scanModeAccurate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.high_quality),
                        label: Text(
                          _isScanning &&
                                  _activeScanMode ==
                                      GeminiService.scanModeAccurate
                              ? 'Scanning...'
                              : 'Quality',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.secondaryContainer,
                          foregroundColor: colorScheme.onSecondaryContainer,
                          disabledBackgroundColor:
                              colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (_imageBytes == null || _isScanning)
                            ? null
                            : _scanWithGeminiFast,
                        icon: _isScanning &&
                                _activeScanMode == GeminiService.scanModeFast
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.bolt),
                        label: Text(
                          _isScanning &&
                                  _activeScanMode == GeminiService.scanModeFast
                              ? 'Scanning...'
                              : 'Fast',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colorScheme.tertiaryContainer,
                          foregroundColor: colorScheme.onTertiaryContainer,
                          disabledBackgroundColor:
                              colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Manual entry below always works, with or without scan.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _buildSectionHeader('2. Receipt Details'),
                const SizedBox(height: 2),
                MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumn = constraints.maxWidth >= 360;
                      final gap = twoColumn ? 10.0 : 12.0;
                      final fieldStyle = TextStyle(
                        fontSize: twoColumn ? 18 : 17,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      );

                      final dateField = InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Invoice date *',
                            suffixIcon: Icon(Icons.calendar_today, size: 18),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _selectedDate == null
                                  ? 'dd/mm/yyyy'
                                  : DateFormat('dd/MM/yyyy')
                                      .format(_selectedDate!),
                              maxLines: 1,
                              style: fieldStyle.copyWith(
                                color: _selectedDate == null
                                    ? Theme.of(context).colorScheme.outline
                                    : fieldStyle.color,
                              ),
                            ),
                          ),
                        ),
                      );

                      final supplierField = TextFormField(
                        controller: _supplierController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Supplier *',
                          hintText: 'e.g. B&Q, Travis Perkins',
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Please enter supplier'
                            : null,
                      );

                      final invoiceField = TextFormField(
                        controller: _invoiceNumberController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Invoice no.',
                          hintText: 'INV-1024',
                        ),
                        textCapitalization: TextCapitalization.characters,
                      );

                      final vatField = TextFormField(
                        controller: _vatController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'VAT',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      );

                      final grossField = TextFormField(
                        controller: _grossController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Gross *',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Please enter gross amount';
                          }
                          if (double.tryParse(v) == null) {
                            return 'Enter a valid number';
                          }
                          return null;
                        },
                      );

                      final paidField = TextFormField(
                        controller: _paidController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Paid',
                          hintText: 'Defaults to Gross',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          if (double.tryParse(v) == null) {
                            return 'Enter a valid number';
                          }
                          return null;
                        },
                      );

                      final netField = TextFormField(
                        controller: _netController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Net',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                      );

                      final notesField = TextFormField(
                        controller: _notesController,
                        style: fieldStyle,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                          hintText: 'Optional',
                        ),
                        maxLines: 2,
                      );

                      if (!twoColumn) {
                        return Column(
                          children: [
                            dateField,
                            SizedBox(height: gap),
                            invoiceField,
                            SizedBox(height: gap),
                            supplierField,
                            SizedBox(height: gap),
                            Row(
                              children: [
                                Expanded(child: netField),
                                const SizedBox(width: 10),
                                Expanded(child: vatField),
                                const SizedBox(width: 10),
                                Expanded(child: grossField),
                              ],
                            ),
                            SizedBox(height: gap),
                            paidField,
                            SizedBox(height: gap),
                            notesField,
                          ],
                        );
                      }

                      return Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 11, child: dateField),
                              const SizedBox(width: 10),
                              Expanded(flex: 12, child: invoiceField),
                            ],
                          ),
                          SizedBox(height: gap),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: supplierField),
                            ],
                          ),
                          SizedBox(height: gap),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: netField),
                              const SizedBox(width: 10),
                              Expanded(child: vatField),
                              const SizedBox(width: 10),
                              Expanded(child: grossField),
                            ],
                          ),
                          SizedBox(height: gap),
                          paidField,
                          SizedBox(height: gap),
                          notesField,
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                _buildRecentEntries(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
          child: SizedBox(
            height: _canWriteData ? 52 : 76,
            child: Column(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        (_isSaving || !_canWriteData) ? null : _saveRecord,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save to Database',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                if (!_canWriteData)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Activation required: save is disabled.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  // View section builders extracted to receipt_entry/receipt_entry_view_sections.dart.
}
