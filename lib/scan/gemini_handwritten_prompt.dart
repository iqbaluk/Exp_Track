part of '../gemini_service.dart';

String _buildHandwrittenPrompt({
  String? userHint,
}) {
  final hint = (userHint?.trim().isNotEmpty ?? false)
      ? 'User hint: ${userHint!.trim()}\n'
      : '';
  const schemaBlock =
      '{"date":"YYYY-MM-DD or null","invoice_number":"string or null","supplier":"string or null","vat":"number or null","gross":"number or null","paid_amount":"number or null","payment_context":"string or null","net":"number or null","notes":"string or null","extraction_warnings":"array"}';
  const rulesBlock = '''
- Handwritten invoice mode. Return JSON only in schema.
- Supplier priority: stamped seller name anywhere on page > top seller name.
- Never output buyer/customer name as supplier, including typo/variant forms.
- Supplier targeting: prefer the first handwritten name in the top NAME row as supplier.
- Do not use lower memo/signature lines as supplier (e.g., bank transfer note, paid note, signature area).
- If top NAME row text is legible but uncertain spelling, still return best top-row supplier candidate and add "Low supplier confidence" in extraction_warnings.
- Invoice number: top-right serial digits; ignore form/style numbers.
- Date: UK-first -> YYYY-MM-DD.
- Gross: final TOTAL payable; if corrected/overwritten, use final corrected value.
- paid_amount only from explicit paid evidence (Paid/Bank transfer note). Else null.
- VAT/net: use written values; if VAT absent set vat=null and keep net consistent with visible totals.
- Money fields numeric only. Notes short line-items summary only. If unclear, return null.
''';
  GeminiService._logPromptComposition(
    mode: GeminiService.scanModeHandwritten,
    schemaBlock: schemaBlock,
    rulesBlock: rulesBlock,
    hintBlock: hint,
  );
  return '''
You extract structured fields from a handwritten UK invoice/voucher image. Return ONLY valid JSON.
$hint
Schema:
$schemaBlock
Rules:
$rulesBlock
''';
}
