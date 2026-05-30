part of '../../main.dart';

extension _ReceiptEntryQualityScanController on _ReceiptEntryPageState {
  Future<void> _scanWithGeminiQuality() async {
    await _scanWithGeminiMode(GeminiService.scanModeAccurate);
  }
}
