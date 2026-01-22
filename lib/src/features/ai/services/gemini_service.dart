

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
      // Simulate analysis with occasional "bad" scores to show the diagnosis working
      final random = DateTime.now().millisecond;
      final isStruggling = random % 4 == 0; // 25% chance of struggling

      double lipScore = 0.85 + (random % 15) / 100; 
      double pronScore = 0.70 + (DateTime.now().second % 30) / 100;
      String note = "Good articulation observed.";

      if (isStruggling) {
         lipScore = 0.40 + (random % 20) / 100;
         pronScore = 0.50 + (random % 20) / 100;
         note = "Patient is under-articulating /r/ and /s/ sounds.";
      }

      // Simulate Lip Landmarks (Simple hexagon shape around center)
      final List<Map<String, double>> landmarks = [];
      final centerX = 0.5;
      final centerY = 0.5;
      final radius = isStruggling ? 0.05 : 0.08 + (random % 5) / 100; // Expands when speaking well

      for (int i = 0; i < 6; i++) {
        final angle = (i * 60) * 3.14159 / 180;
        landmarks.add({
          'x': centerX + radius * 0.7 * (i % 2 == 0 ? 1 : 0.8) *  (i > 2 ? -1 : 1), // Rough approximation
          'y': centerY + radius * (i % 3 == 0 ? 1 : -1),
        });
      }

      return {
        'status': 'analyzing',
        'feedback': isStruggling ? 'Try to round your lips more.' : 'Good articulation!',
        'lipAccuracy': lipScore,
        'pronunciation': pronScore,
        'diagnosis_note': note,
        'lip_landmarks': [
           {'x': 0.45, 'y': 0.52}, // Top Lip Left
           {'x': 0.55, 'y': 0.52}, // Top Lip Right
           {'x': 0.50, 'y': 0.55}, // Top Lip Center
           {'x': 0.45, 'y': 0.58}, // Bottom Lip Left
           {'x': 0.55, 'y': 0.58}, // Bottom Lip Right
           {'x': 0.50, 'y': 0.60 + (isStruggling ? 0.0 : 0.05)}, // Bottom Lip Center (moves down)
        ],
      };
    } else {
      // Idle / Listening Mode
      return {
        'status': 'listening',
        'feedback': 'Listening...',
        'lipAccuracy': 0.05, // Very low score implies silence
        'pronunciation': 0.02,
        'diagnosis_note': 'Patient is silent / Listen mode.',
        'lip_landmarks': [],
      };
    }
  }
}
