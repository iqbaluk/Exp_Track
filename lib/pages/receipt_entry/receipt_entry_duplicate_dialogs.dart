part of '../../main.dart';

extension _ReceiptEntryDuplicateDialogs on _ReceiptEntryPageState {
  /// Show duplicate warning. Returns one of:
  ///   'cancel' => abort save
  ///   'view'   => open the existing receipt
  Future<String?> _showDuplicateDialog(
    List<Receipt> dupes, {
    required String invoiceNumber,
    required String supplier,
    required DateTime date,
    required double gross,
  }) async {
    final existing = dupes.first;
    final hardDuplicate = dupes.any(
      (receipt) => _isExactInvoiceDuplicate(
        receipt,
        invoiceNumber: invoiceNumber,
        supplier: supplier,
      ),
    );

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.warning_amber,
          color: Theme.of(ctx).colorScheme.secondary,
          size: 32,
        ),
        title: Text(
          hardDuplicate ? 'Duplicate receipt found' : 'Possible duplicate',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hardDuplicate
                  ? 'A receipt with the same invoice no and supplier already exists. This receipt has not been added again.'
                  : 'A receipt with the same supplier, date, and gross amount already exists.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.secondaryContainer,
                border: Border.all(
                  color: Theme.of(ctx)
                      .colorScheme
                      .secondary
                      .withValues(alpha: 0.32),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${existing.scanNo?.toString().padLeft(5, '0') ?? existing.id}'
                    ' · ${existing.category}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${existing.supplier}\n'
                    '${_invoiceText(existing)}'
                    'Date: ${DateFormat('dd/MM/yyyy').format(existing.date)}\n'
                    'Gross: ${formatAppMoney(existing.gross)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Open the existing receipt to review it, or cancel.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'view'),
            child: const Text('View existing'),
          ),
        ],
      ),
    );
  }

  String _invoiceText(Receipt receipt) {
    final invoiceNumber = receipt.invoiceNumber?.trim();
    if (invoiceNumber == null || invoiceNumber.isEmpty) return '';
    return 'Invoice no: $invoiceNumber\n';
  }
}
