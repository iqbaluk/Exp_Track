part of '../../main.dart';

extension _ReceiptEntryHandwrittenScanController on _ReceiptEntryPageState {
  Future<void> _scanWithGeminiHandwritten() async {
    await _scanWithGeminiMode(GeminiService.scanModeHandwritten);
  }
}

