part of '../main.dart';

String formatAppDate(DateTime value) => DateFormat('dd/MM/yyyy').format(value);

String formatAppMoney(
  num value, {
  int decimals = 2,
}) {
  final pattern = decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}';
  final formatted = NumberFormat(pattern).format(value);
  return formatted;
}

bool _isExactInvoiceDuplicate(
  Receipt receipt, {
  required String invoiceNumber,
  required String supplier,
}) {
  final invoice = normalizeInvoiceNumber(invoiceNumber);
  if (invoice.isEmpty) return false;
  return normalizeInvoiceNumber(receipt.invoiceNumber) == invoice &&
      normalizeSupplier(receipt.supplier) == normalizeSupplier(supplier);
}

bool _isAmountsBalanced({
  required double net,
  required double vat,
  required double gross,
}) {
  return ((net + vat) - gross).abs() < 0.01;
}

bool _isDuplicateSignatureError(Object error) {
  final text = error.toString().toUpperCase();
  return text.contains('DUPLICATE_INVOICE_SIGNATURE');
}

bool _isSupplierDateGrossDuplicateError(Object error) {
  final text = error.toString().toUpperCase();
  return text.contains('DUPLICATE_SUPPLIER_DATE_GROSS');
}

const String _paymentMismatchPrefix = '*** PAYMENT MISMATCH:';

String? _buildNotesWithPaymentMismatch({
  required String? existingNotes,
  required double gross,
  required double paid,
}) {
  final lines = (existingNotes ?? '')
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.trim().isNotEmpty)
      .where((line) => !line.trimLeft().startsWith(_paymentMismatchPrefix))
      .toList();

  final diff = paid - gross;
  if (diff.abs() >= 0.01) {
    lines.add(
      '$_paymentMismatchPrefix '
      'Invoice ${gross.toStringAsFixed(2)}, '
      'Paid ${paid.toStringAsFixed(2)}, '
      'Diff ${diff.toStringAsFixed(2)}',
    );
  }

  if (lines.isEmpty) return null;
  return lines.join('\n');
}

Future<void> _showHardDuplicateBlockedDialog(
  BuildContext context, {
  Receipt? existing,
}) async {
  await _showDuplicateBlockedDialog(
    context,
    existing: existing,
    messageWithRef:
        'A receipt with the same invoice no and supplier already exists as {ref}.',
    messageWithoutRef:
        'A receipt with the same invoice no and supplier already exists.',
  );
}

Future<void> _showSupplierDateGrossDuplicateBlockedDialog(
  BuildContext context, {
  Receipt? existing,
}) async {
  await _showDuplicateBlockedDialog(
    context,
    existing: existing,
    messageWithRef:
        'A receipt with the same supplier, date, and gross already exists as {ref}.',
    messageWithoutRef:
        'A receipt with the same supplier, date, and gross already exists.',
  );
}

Future<void> _showDuplicateBlockedDialog(
  BuildContext context, {
  required String messageWithRef,
  required String messageWithoutRef,
  Receipt? existing,
}) async {
  if (!context.mounted) return;
  final existingRef = existing == null
      ? null
      : '#${(existing.scanNo ?? existing.id ?? 0).toString().padLeft(5, '0')}';
  final details = existing == null
      ? null
      : '${existing.supplier}\n'
          'Date: ${formatAppDate(existing.date)}\n'
          'Gross: ${formatAppMoney(existing.gross)}';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 32),
      title: const Text('Duplicate receipt found'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            existingRef == null
                ? messageWithoutRef
                : messageWithRef.replaceAll('{ref}', existingRef),
          ),
          if (details != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border.all(color: Colors.orange.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(details),
            ),
          ],
          const SizedBox(height: 10),
          const Text('This duplicate cannot be saved.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

Future<ExportRange?> _pickExportRange(
  BuildContext context, {
  required String title,
  bool includeTodayWeek = false,
}) async {
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(title),
      children: [
        if (includeTodayWeek)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'today'),
            child: const Text('Today'),
          ),
        if (includeTodayWeek)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'week'),
            child: const Text('This week'),
          ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'month'),
          child: const Text('This month'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'last_month'),
          child: const Text('Last month'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'year'),
          child: const Text('This year'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'custom'),
          child: const Text('Custom range...'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, 'all'),
          child: const Text('All receipts'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );

  if (choice == null) return null;
  if (!context.mounted) return null;

  switch (choice) {
    case 'today':
      return ExportRange.today();
    case 'week':
      return ExportRange.thisWeek();
    case 'month':
      return ExportRange.thisMonth();
    case 'last_month':
      return ExportRange.lastMonth();
    case 'year':
      return ExportRange.thisYear();
    case 'all':
      return ExportRange.allTime();
    case 'custom':
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
      );
      if (!context.mounted) return null;
      if (picked == null) return null;
      return ExportRange.custom(picked.start, picked.end);
    default:
      return null;
  }
}
