class VoiceCommandWebSpeechController {
  String get lastRecognizedWords => '';

  Future<bool> initialize() async => false;

  Future<bool> listen({
    required String localeId,
    required void Function(String status) onStatus,
    required void Function(String errorCode) onError,
    required void Function(String words, bool finalResult) onResult,
  }) async {
    return false;
  }

  Future<void> stop() async {}
}
