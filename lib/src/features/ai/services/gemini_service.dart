

class GeminiService {
  // Singleton instance
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  /// Simulates analyzing a video frame or audio buffer to get therapy statistics.
  /// In a real implementation, this would send data to the Gemini API.
  Future<Map<String, dynamic>> analyzeSession({
    required bool isSpeaking,
    required bool isFaceVisible,
  }) async {
    // Latency simulation (network call)
    await Future.delayed(const Duration(milliseconds: 800));

    if (!isFaceVisible) {
      return {
        'status': 'no_face',
        'feedback': 'Please align your face',
        'lipAccuracy': 0.0,
        'pronunciation': 0.0,
      };
    }

    if (isSpeaking) {
      return {
        'status': 'analyzing',
        'feedback': 'Good articulation!',
        'lipAccuracy': 0.85 + (DateTime.now().millisecond % 15) / 100, // Randomish 0.85-0.99
        'pronunciation': 0.70 + (DateTime.now().second % 30) / 100, // Randomish 0.70-0.99
      };
    } else {
      return {
        'status': 'listening',
        'feedback': 'Speak clearly...',
        'lipAccuracy': 0.0,
        'pronunciation': 0.0,
      };
    }
  }
}
