part of '../gemini_service.dart';

String _buildFastPrompt({
  String? userHint,
}) {
  final hint = (userHint?.trim().isNotEmpty ?? false)
      ? 'User hint: ${userHint!.trim()}\n'
      : '';
  const schemaBlock =
      '{"date":"YYYY-MM-DD or null","invoice_number":"string or null","supplier":"string or null","vat":"number or null","gross":"number or null","paid_amount":"number or null","payment_context":"string or null","net":"number or null","notes":"string or null","extraction_warnings":"array"}';
  const rulesBlock = '''
- Return JSON only in the requested schema.
- Find details quickly and accurately from a standard invoice/receipt layout.
- Use visible labeled fields directly; do not over-reason.
- Term aliases: supplier=vendor/seller/merchant, vat=tax/gst/sales tax, gross=total to pay/grand total/amount due, net=subtotal ex VAT, invoice_number=invoice no/bill no/receipt no/doc ref.
- Date: UK-first normalize to YYYY-MM-DD.
- Invoice number: use invoice/document/bill/ref label area; if missing return null.
- Supplier: use seller/store/company name; avoid buyer/customer line.
- Gross: final payable amount after discounts/savings (TOTAL TO PAY / AMOUNT DUE), not pre-discount subtotal.
- VAT, net, paid_amount: extract visible values; if not shown, return null.
- Handwriting: if a clear handwritten paid mark/amount appears (e.g., Paid/Pd 38), use it for paid_amount.
- Money fields must be plain numbers only.
- Notes: short purchased-items summary only (comma-separated, max ~8 words).
- If a field is unclear, return null.
''';
  GeminiService._logPromptComposition(
    mode: 'fast',
    schemaBlock: schemaBlock,
    rulesBlock: rulesBlock,
    hintBlock: hint,
  );
  return '''
You extract structured data from a UK receipt/invoice image. Return ONLY valid JSON.
$hint
Schema:
$schemaBlock
Rules:
$rulesBlock
''';
}
