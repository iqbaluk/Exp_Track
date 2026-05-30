part of '../../main.dart';

extension _ReceiptEntrySaveController on _ReceiptEntryPageState {
  List<String> _missingRequiredFields() {
    final missing = <String>[];
    if (_selectedDate == null) missing.add('Invoice date');
    if (_supplierController.text.trim().isEmpty) missing.add('Supplier');
    final grossText = _grossController.text.trim();
    if (grossText.isEmpty) {
      missing.add('Gross amount');
    } else if (double.tryParse(grossText) == null) {
      missing.add('Gross amount (valid number)');
    }
    return missing;
  }

  Future<void> _saveRecord() async {
    final canWrite = await ActivationLicenseService.canWriteData();
    if (!canWrite) {
      _showStatus(
        'Activation required. Save to database is disabled.',
        isError: true,
      );
      return;
    }

    final missing = _missingRequiredFields();
    if (missing.isNotEmpty) {
      _formKey.currentState!.validate();
      _showStatus(
        'Please add manually: ${missing.join(', ')}.',
        isError: true,
        duration: const Duration(seconds: 6),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) {
      _showStatus('Please fix the errors above', isError: true);
      return;
    }
    final canProceed = await _confirmLowCategoryConfidenceBeforeSave();
    if (!canProceed) return;
    final saveCategory = _selectedCategory ?? _resolveDefaultCategory();
    if (saveCategory == null) {
      _showStatus(
        'Category seed is missing. Please contact support to re-seed defaults.',
        isError: true,
      );
      return;
    }

    final supplier = _supplierController.text.trim();
    final invoiceNumber = _invoiceNumberController.text.trim();
    final gross = double.tryParse(_grossController.text) ?? 0;
    final paid = (double.tryParse(_paidController.text) ?? 0) > 0
        ? (double.tryParse(_paidController.text) ?? gross)
        : gross;
    final notesWithFlag = _buildNotesWithPaymentMismatch(
      existingNotes: _notesController.text.trim(),
      gross: gross,
      paid: paid,
    );
    final invoiceDate = _selectedDate!;

    if (invoiceNumber.isNotEmpty) {
      final existingBySupplier = await DatabaseService.findByInvoiceSupplier(
        invoiceNumber: invoiceNumber,
        supplier: supplier,
        projectId: widget.project.id,
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
        invoiceNumber: invoiceNumber,
        date: invoiceDate,
        projectId: widget.project.id,
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

    _setSavingState(true);
    try {
      final dupes = await DatabaseService.findPossibleDuplicates(
        invoiceNumber: invoiceNumber,
        supplier: supplier,
        date: invoiceDate,
        gross: gross,
        projectId: widget.project.id,
      );

      if (dupes.isNotEmpty) {
        if (!mounted) return;
        _setSavingState(false);
        final action = await _showDuplicateDialog(
          dupes,
          invoiceNumber: invoiceNumber,
          supplier: supplier,
          date: invoiceDate,
          gross: gross,
        );
        if (action == 'cancel' || action == null) return;
        if (action == 'view') {
          await _openDetail(dupes.first);
          return;
        }
        _setSavingState(true);
      }
    } catch (e) {
      debugPrint('Duplicate check failed: $e');
    }

    try {
      final draft = Receipt(
        projectId: widget.project.id,
        date: invoiceDate,
        invoiceNumber: invoiceNumber.isEmpty ? null : invoiceNumber,
        category: saveCategory,
        supplier: supplier,
        vat: double.tryParse(_vatController.text) ?? 0,
        gross: gross,
        paidAmount: paid,
        net: double.tryParse(_netController.text) ?? 0,
        notes: notesWithFlag,
      );

      final saved = await DatabaseService.saveReceipt(
        draft: draft,
        photoBytes: _imageBytes,
      );
      if (!mounted) return;
      _showStatus(
        'Saved as scan #${saved.scanNo!.toString().padLeft(5, '0')}',
      );
      _clearForm(silent: true, keepCategory: true);
      await _loadRecent();
    } catch (e) {
      if (_isDuplicateSignatureError(e)) {
        Receipt? existingInvoice;
        if (invoiceNumber.isNotEmpty) {
          existingInvoice = await DatabaseService.findByInvoiceSupplier(
            invoiceNumber: invoiceNumber,
            supplier: supplier,
            projectId: widget.project.id,
          );
          existingInvoice ??= await DatabaseService.findByInvoiceSignature(
            invoiceNumber: invoiceNumber,
            date: invoiceDate,
            projectId: widget.project.id,
          );
        }
        if (!mounted) return;
        await _showHardDuplicateBlockedDialog(
          context,
          existing: existingInvoice,
        );
      } else if (_isSupplierDateGrossDuplicateError(e)) {
        final dupes = await DatabaseService.findPossibleDuplicates(
          invoiceNumber: invoiceNumber,
          supplier: supplier,
          date: invoiceDate,
          gross: gross,
          projectId: widget.project.id,
        );
        if (!mounted) return;
        await _showSupplierDateGrossDuplicateBlockedDialog(
          context,
          existing: dupes.isEmpty ? null : dupes.first,
        );
      } else {
        _showStatus('Save failed: $e', isError: true);
      }
    } finally {
      _setSavingState(false);
    }
  }
}
