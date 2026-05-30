part of '../main.dart';

class ReceiptDetailPage extends StatefulWidget {
  final Receipt receipt;
  const ReceiptDetailPage({super.key, required this.receipt});

  @override
  State<ReceiptDetailPage> createState() => _ReceiptDetailPageState();
}

class _ReceiptDetailPageState extends State<ReceiptDetailPage> {
  late Receipt _current;

  int? _projectId;
  late DateTime _date;
  late TextEditingController _invoiceNumber;
  late TextEditingController _supplier;
  late TextEditingController _vat;
  late TextEditingController _gross;
  late TextEditingController _paid;
  late TextEditingController _net;
  late TextEditingController _notes;
  List<Project> _projects = [];

  bool _editing = false;
  bool _saving = false;
  bool _didUpdate = false;
  bool _isAutoAmountUpdate = false;

  @override
  void initState() {
    super.initState();
    _current = widget.receipt;
    _projectId = _current.projectId;
    _date = _current.date;
    _invoiceNumber = TextEditingController(text: _current.invoiceNumber ?? '');
    _supplier = TextEditingController(text: _current.supplier);
    _vat = TextEditingController(text: _current.vat.toStringAsFixed(2));
    _gross = TextEditingController(text: _current.gross.toStringAsFixed(2));
    _paid = TextEditingController(text: _current.paidAmount.toStringAsFixed(2));
    _net = TextEditingController(text: _current.net.toStringAsFixed(2));
    _notes = TextEditingController(text: _current.notes ?? '');
    _gross.addListener(_syncAmountFields);
    _vat.addListener(_syncAmountFields);
    _paid.addListener(_syncAmountFields);
    _loadProjects();
  }

  @override
  void dispose() {
    _invoiceNumber.dispose();
    _supplier.dispose();
    _vat.dispose();
    _gross.dispose();
    _paid.dispose();
    _net.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _syncAmountFields() {
    if (_isAutoAmountUpdate) return;
    final gross = double.tryParse(_gross.text) ?? 0;
    final vat = double.tryParse(_vat.text) ?? 0;
    var paid = double.tryParse(_paid.text);

    _isAutoAmountUpdate = true;
    try {
      if (paid == null && gross > 0) {
        paid = gross;
        _paid.text = gross.toStringAsFixed(2);
      }
      if (gross > 0) {
        _net.text = (gross - vat).toStringAsFixed(2);
      } else if (_net.text.trim().isEmpty) {
        _net.clear();
      }
    } finally {
      _isAutoAmountUpdate = false;
    }
  }

  Future<void> _loadProjects() async {
    try {
      final projects = await DatabaseService.getProjects();
      if (!mounted) return;
      setState(() {
        _projects = projects;
        if (_projectId == null && projects.isNotEmpty) {
          _projectId = projects.first.id;
        }
      });
    } catch (e) {
      debugPrint('Failed to load projects: $e');
    }
  }

  Future<void> _save() async {
    final newSupplier = _supplier.text.trim();
    final newInvoiceNumber = _invoiceNumber.text.trim();
    final newVat = double.tryParse(_vat.text) ?? 0;
    final newGross = double.tryParse(_gross.text) ?? 0;
    final parsedPaid = double.tryParse(_paid.text);
    final newPaid =
        (parsedPaid != null && parsedPaid > 0) ? parsedPaid : newGross;
    final newNet = double.tryParse(_net.text) ?? 0;
    final notesWithFlag = _buildNotesWithPaymentMismatch(
      existingNotes: _notes.text.trim(),
      gross: newGross,
      paid: newPaid,
    );
    final newProjectId = _projectId ?? _current.projectId;

    if (!_isAmountsBalanced(net: newNet, vat: newVat, gross: newGross)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unbalanced entry: Net + VAT must equal Gross. '
            'Current total is ${(newNet + newVat).toStringAsFixed(2)} '
            'vs Gross ${newGross.toStringAsFixed(2)}.',
          ),
        ),
      );
      return;
    }

    if (newInvoiceNumber.isNotEmpty) {
      final existingBySupplier = await DatabaseService.findByInvoiceSupplier(
        invoiceNumber: newInvoiceNumber,
        supplier: newSupplier,
        projectId: newProjectId,
        excludeId: _current.id,
      );
      if (existingBySupplier != null) {
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingBySupplier,
        );
        return;
      }
      final existingInvoice = await DatabaseService.findByInvoiceSignature(
        invoiceNumber: newInvoiceNumber,
        date: _date,
        projectId: newProjectId,
        excludeId: _current.id,
      );
      if (existingInvoice != null) {
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingInvoice,
        );
        return;
      }
    }

    // Check for duplicate against OTHER receipts (not self)
    setState(() => _saving = true);
    try {
      final dupes = await DatabaseService.findPossibleDuplicates(
        invoiceNumber: newInvoiceNumber,
        supplier: newSupplier,
        date: _date,
        gross: newGross,
        projectId: newProjectId,
        excludeId: _current.id,
      );
      if (dupes.isNotEmpty) {
        if (!mounted) return;
        setState(() => _saving = false);
        final hardDuplicate = dupes.any(
          (receipt) => _isExactInvoiceDuplicate(
            receipt,
            invoiceNumber: newInvoiceNumber,
            supplier: newSupplier,
          ),
        );
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: Icon(Icons.warning_amber,
                color: Colors.orange.shade700, size: 32),
            title: Text(
              hardDuplicate
                  ? 'Duplicate receipt found'
                  : 'Edit creates a duplicate',
            ),
            content: Text(
              hardDuplicate
                  ? 'A receipt with the same invoice no and supplier already exists. These changes were not saved.'
                  : 'Saving these changes would match an existing receipt with the same supplier, date, and gross amount (#${dupes.first.scanNo?.toString().padLeft(5, '0') ?? dupes.first.id}). These changes were not saved.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
            ],
          ),
        );
        if (ok != true) return;
        setState(() => _saving = true);
      }
    } catch (e) {
      debugPrint('Duplicate check failed: $e');
    }

    try {
      final projectChanged = newProjectId != _current.projectId;
      final updated = _current.copyWith(
        projectId: newProjectId,
        date: _date,
        category: _current.category,
        invoiceNumber: newInvoiceNumber.isEmpty ? '' : newInvoiceNumber,
        supplier: newSupplier,
        vat: newVat,
        gross: newGross,
        paidAmount: newPaid,
        net: newNet,
        notes: notesWithFlag,
      );
      await DatabaseService.updateReceipt(updated);
      if (!mounted) return;
      if (projectChanged) {
        Navigator.pop(context, true);
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      // Reload from DB so we get the renamed photo path
      final fresh = await DatabaseService.getById(_current.id!);
      if (fresh != null) {
        setState(() {
          _current = fresh;
          _editing = false;
          _didUpdate = true;
        });
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Updated')),
      );
    } catch (e) {
      if (!mounted) return;
      if (_isDuplicateSignatureError(e)) {
        Receipt? existingInvoice;
        if (newInvoiceNumber.isNotEmpty) {
          existingInvoice = await DatabaseService.findByInvoiceSupplier(
            invoiceNumber: newInvoiceNumber,
            supplier: newSupplier,
            projectId: newProjectId,
            excludeId: _current.id,
          );
          existingInvoice ??= await DatabaseService.findByInvoiceSignature(
            invoiceNumber: newInvoiceNumber,
            date: _date,
            projectId: newProjectId,
            excludeId: _current.id,
          );
        }
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingInvoice,
        );
      } else if (_isSupplierDateGrossDuplicateError(e)) {
        final dupes = await DatabaseService.findPossibleDuplicates(
          invoiceNumber: newInvoiceNumber,
          supplier: newSupplier,
          date: _date,
          gross: newGross,
          projectId: newProjectId,
          excludeId: _current.id,
        );
        if (!mounted) return;
        await _showSupplierDateGrossDuplicateBlockedDialog(
          context,
          existing: dupes.isEmpty ? null : dupes.first,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _projectNameById(int? id) {
    if (id == null) return 'Unassigned';
    for (final project in _projects) {
      if (project.id == id) return project.name;
    }
    return 'Operation $id';
  }

  Future<void> _shareInvoice() async {
    try {
      final csvFile = await _buildSingleInvoiceCsv(_current);
      final filesToShare = <XFile>[
        XFile(csvFile.path, mimeType: 'text/csv'),
      ];
      final photoPath = _current.photoPath;
      if (photoPath != null && photoPath.trim().isNotEmpty) {
        final file = File(photoPath);
        if (await file.exists()) {
          filesToShare.add(XFile(file.path, mimeType: 'image/jpeg'));
        }
      }
      await Share.shareXFiles(
        filesToShare,
        subject:
            'Invoice #${(_current.scanNo ?? _current.id ?? 0).toString().padLeft(5, '0')}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  Future<File> _buildSingleInvoiceCsv(Receipt receipt) async {
    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final scanNo =
        (receipt.scanNo ?? receipt.id ?? 0).toString().padLeft(5, '0');
    final filename = 'invoice_${scanNo}_$ts.csv';
    final path = p.join(dir.path, filename);
    final csv = StringBuffer();
    csv.writeln(
      'ScanNo,Operation,InvoiceDate,ScanDate,InvoiceNo,Category,Supplier,Net,VAT,Gross,Paid,Savings,Notes,PhotoFile',
    );
    final photoFile = receipt.photoPath == null
        ? ''
        : receipt.photoPath!.split('/').last.split('\\').last;
    final values = [
      scanNo,
      _csvEscape(_projectNameById(receipt.projectId)),
      Receipt.formatDate(receipt.date),
      Receipt.formatDate(receipt.createdAt),
      _csvEscape(receipt.invoiceNumber ?? ''),
      _csvEscape(receipt.category),
      _csvEscape(receipt.supplier),
      receipt.net.toStringAsFixed(2),
      receipt.vat.toStringAsFixed(2),
      receipt.gross.toStringAsFixed(2),
      receipt.paidAmount.toStringAsFixed(2),
      receipt.savingsAmount.toStringAsFixed(2),
      _csvEscape(receipt.notes ?? ''),
      _csvEscape(photoFile),
    ];
    csv.writeln(values.join(','));
    return File(path).writeAsString(csv.toString());
  }

  String _csvEscape(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this receipt?'),
        content: Text(
          '${_current.supplier} Â·${_current.gross.toStringAsFixed(2)}\\n\\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await DatabaseService.deleteReceipt(_current);
        if (!mounted) return;
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _openPhotoViewer(String photoPath) async {
    final file = File(photoPath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo file missing')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('Image viewer'),
          ),
          body: SafeArea(
            child: Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5.0,
                child: Image.file(
                  file,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scanLabel = _current.scanNo != null
        ? '#${_current.scanNo!.toString().padLeft(5, '0')}'
        : '#${_current.id}';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _didUpdate);
      },
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              icon: const Icon(Icons.home_outlined),
              tooltip: 'Home',
              onPressed: () => goToHomePage(context),
            ),
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: 'Upload/share invoice',
              onPressed: _shareInvoice,
            ),
            if (!_editing)
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit',
                onPressed: () => setState(() => _editing = true),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete',
              onPressed: _confirmDelete,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            _editing ? 132 : 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildPageTitleBanner(
                context,
                title: 'Receipt details $scanLabel',
                icon: Icons.receipt_long,
              ),
              const SizedBox(height: 12),
              if (_current.photoPath != null) ...[
                InkWell(
                  onTap: () => _openPhotoViewer(_current.photoPath!),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_current.photoPath!),
                      height: 280,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        height: 80,
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: Text('Photo file missing',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tap image to open zoom view',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'File: ${_current.photoPath != null ? _current.photoPath!.split('/').last.split('\\').last : ""}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
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
                      onTap: _editing ? _pickDate : null,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Date',
                          enabled: _editing,
                          suffixIcon: _editing
                              ? const Icon(Icons.calendar_today, size: 18)
                              : null,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            DateFormat('dd/MM/yyyy').format(_date),
                            maxLines: 1,
                            style: fieldStyle,
                          ),
                        ),
                      ),
                    );

                    final invoiceField = TextField(
                      controller: _invoiceNumber,
                      enabled: _editing,
                      style: fieldStyle,
                      textCapitalization: TextCapitalization.characters,
                      decoration:
                          const InputDecoration(labelText: 'Invoice no.'),
                    );

                    final supplierField = TextField(
                      controller: _supplier,
                      enabled: _editing,
                      style: fieldStyle,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                    );

                    final projectField = DropdownButtonFormField<int>(
                      key: ValueKey(
                        'receipt-project-${_projectId ?? 0}-${_projects.length}',
                      ),
                      initialValue: _projects.any((p) => p.id == _projectId)
                          ? _projectId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Operation'),
                      style: fieldStyle,
                      selectedItemBuilder: (context) => _projects
                          .where((p) => p.id != null)
                          .map(
                            (p) => Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: fieldStyle,
                              ),
                            ),
                          )
                          .toList(),
                      items: _projects
                          .where((p) => p.id != null)
                          .map(
                            (p) => DropdownMenuItem<int>(
                              value: p.id,
                              child: Text(
                                p.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _editing
                          ? (value) => setState(() => _projectId = value)
                          : null,
                    );

                    final netField = TextField(
                      controller: _net,
                      enabled: _editing,
                      style: fieldStyle,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Net',
                      ),
                    );

                    final vatField = TextField(
                      controller: _vat,
                      enabled: _editing,
                      style: fieldStyle,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'VAT',
                      ),
                    );

                    final grossField = TextField(
                      controller: _gross,
                      enabled: _editing,
                      style: fieldStyle,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Gross',
                      ),
                    );

                    final paidField = TextField(
                      controller: _paid,
                      enabled: _editing,
                      style: fieldStyle,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Paid',
                        hintText: 'Defaults to Gross',
                      ),
                    );

                    final notesField = TextField(
                      controller: _notes,
                      enabled: _editing,
                      style: fieldStyle,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Notes'),
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
                          projectField,
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
                        projectField,
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
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Saved: ${DateFormat('dd/MM/yyyy HH:mm').format(_current.createdAt)}'
                  '${_current.updatedAt.difference(_current.createdAt).inSeconds > 5 ? "\nLast edited: ${DateFormat('dd/MM/yyyy HH:mm').format(_current.updatedAt)}" : ""}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: !_editing
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save changes'),
                  ),
                ),
              ),
      ),
    );
  }
}
