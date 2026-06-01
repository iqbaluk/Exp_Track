part of '../gemini_service.dart';

String _buildQualityPromptCompact({
  String? userHint,
}) {
  final hint = (userHint?.trim().isNotEmpty ?? false)
      ? 'User hint: ${userHint!.trim()}\n'
      : '';
  const schemaBlock =
      '{"date":"YYYY-MM-DD or null","invoice_number":"string or null","supplier":"string or null","vat":"number or null","gross":"number or null","paid_amount":"number or null","payment_context":"string or null","net":"number or null","notes":"string or null","extraction_warnings":"array"}';
  const rulesBlock = '''
- Invoice number is critical. Scan full page (header/body/footer/boxes/margins).
- Invoice labels: Invoice No/Number/Inv No/Inv #/Document No/Bill No/Ref No/Doc Ref (incl OCR typos: Invoce/Invoice Ne).
- Exclude non-invoice IDs: VAT No, Company No, Tel/Phone, Account No, Customer Ref, Route, POD, AID, Auth Code, PAN, Merchant, ICC.
- Date normalize to YYYY-MM-DD. Parse UK-first: DD/MM/YYYY, DD/MM/YY, DD MMM YY/YYYY.
- Money fields must be plain numbers.
- Gross = final payable amount. If discounts/savings exist, use TOTAL TO PAY/AMOUNT DUE (post-discount).
- If both full total and outstanding balance are shown, gross is the full invoice total (not outstanding remainder).
- paid_amount only from explicit payment evidence (payment/tender lines).
- CRITICAL HANDWRITING EXCEPTION: Look carefully for pen annotations, circled values, ink stamps, or scribbled numbers; if a handwritten payment amount is present (for example "Pd 38"), extract that exact number as paid_amount even if it differs from printed gross.
- Handwritten supplier rule: for voucher/carbon-copy formats, prioritize seller stamp anywhere on page, otherwise first handwritten name in top NAME row.
- Do not use lower memo/signature lines as supplier (bank transfer note, paid note, signature area).
- If top supplier text is legible but spelling is uncertain, return best top-row supplier candidate and add "Low supplier confidence" in extraction_warnings.
- net is net-before-VAT where visible; do not derive from paid_amount.
- Notes must summarize purchased items only.
- Do not output personal names, addresses, email, phone.
- If a field is unclear, return null (no guessing).
- If invoice number missing/unclear, set null and include "Invoice number not detected" in extraction_warnings.
''';
  GeminiService._logPromptComposition(
    mode: 'accurate',
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
