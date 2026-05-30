String normalizeInvoiceNumber(String? value) {
  if (value == null) return '';
  return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
}

String normalizeSupplier(String? value) {
  if (value == null) return '';
  return value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
