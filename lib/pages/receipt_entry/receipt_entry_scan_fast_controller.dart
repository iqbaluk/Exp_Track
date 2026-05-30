part of '../../main.dart';

extension _ReceiptEntryFastScanController on _ReceiptEntryPageState {
  Future<void> _scanWithGeminiFast() async {
    await _scanWithGeminiMode(GeminiService.scanModeFast);
  }
}
