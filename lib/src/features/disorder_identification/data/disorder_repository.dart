

class DisorderRepository {
  Future<Map<String, dynamic>> analyzeSession(String text, {double avgLipOpenness = 0.0}) async {
    // Mock processing delay to simulate backend analysis
    await Future.delayed(const Duration(seconds: 2));

    if (text.trim().isEmpty) {
      if (avgLipOpenness > 20) {
         return {
          'disorder': 'Silent Movement',
          'confidence': 0.70,
          'notes': 'Lip movement detected but no voice. Check microphone.',
        };
      }
      return {
        'disorder': 'No Speech Detected',
        'confidence': 0.0,
        'notes': 'Could not hear any words. Please try speaking closer to the microphone.',
      };
    }

    // Heuristics with Lip Data
    // Assumption: Normal lip openness variance is around 10-30 pixels depending on distance.
    // Low openness (< 5) with speech suggests mumbling.
    if (avgLipOpenness < 5 && text.length > 10) {
       return {
        'disorder': 'Potential Mumbling',
        'confidence': 0.85,
        'notes': 'Speech detected but lip movement is minimal ($avgLipOpenness px avg). Articulation exercises recommended.',
      };
    }

    final lowerText = text.toLowerCase();
    
    // Simple Heuristics for Demo purposes
    if (lowerText.contains('rabbit') || lowerText.contains('run')) {
      if (!lowerText.contains('wabbit')) {
         return {
          'disorder': 'Normal R-Articulation',
          'confidence': 0.95,
          'notes': 'Great job pronouncing the "R" sound correctly!',
        };
      }
    }

    if (lowerText.length < 5) {
       return {
        'disorder': 'Limited Output',
        'confidence': 0.60,
        'notes': 'Utterance was very short. Try speaking a full sentence.',
      };
    }

    // Default "SafetyNet" mock response if no specific pattern matched, 
    // but vary it based on length to seem dynamic.
    if (text.length > 50) {
       return {
        'disorder': 'Fluent Speech',
        'confidence': 0.90,
        'notes': 'Good speech flow detected. No obvious disfluencies.',
      };
    }

    return {
      'disorder': 'Analyzing...',
      'confidence': 0.50,
      'notes': 'Speech detected: "$text". Further clinical analysis recommended.',
    };
  }
}
