

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:flutter/foundation.dart';

class GeminiService {
  // Singleton instance
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  String? _lastError;

  /// Analyzes the session using real Gemini AI or fallback heuristics
  Future<Map<String, dynamic>> analyzeSession({
    required bool isSpeaking,
    required bool isFaceVisible,
    String? transcribedText,
    double avgLipOpenness = 0.0, // Pixels. <5=Low, 10-25=Normal
  }) async {
    _lastError = null;

    // 1. Basic Checks (Local) - Immediate feedback for UI
    if (!isFaceVisible) {
      return {
        'status': 'no_face',
        'disorder': 'Face Not Visible',
        'confidence': 0.0,
        'notes': 'Please align your face for accurate analysis.',
        'severity': 'None',
        'lipAccuracy': 0.0,
        'pronunciation': 0.0,
        'lip_landmarks': [],
      };
    }

    // 2. Try Gemini AI Analysis
    try {
      // ignore: deprecated_member_use
      final model = FirebaseVertexAI.instance.generativeModel(
        model: 'gemini-2.5-flash',
        generationConfig: GenerationConfig(responseMimeType: 'application/json'),
      );

      final prompt = """
      Act as a Senior Clinical Speech-Language Pathologist (SLP). 
      Analyze the following patient session data in real-time.
      
      Patient Data:
      1. Transcribed Speech: "${transcribedText ?? (isSpeaking ? 'Audio input detected...' : 'Silent')}"
      2. Lip Openness Metric: $avgLipOpenness (Pixels avg over last few seconds).

      Clinical Guidelines:
      - **Normal Speech**: If text is fluent AND lip openness is 10-25, diagnose as "Normal Speech". 
      - **Restricted ROM**: If text exists but lip openness is <5, flag as *Potential Mumbling* or *Low Range of Motion*.
      - **Articulation**: Look for phonetic substitutions (e.g., 'W' for 'R' = Gliding).
      - **Fluency**: Look for repetitions or blocks in transcribed text = *Stuttering*.
      - **Silent Movement**: If lip openness > 15 but text is empty, flag as *Silent Articulation*.

      Return a precise JSON clinical analysis:
      {
        "disorder": "Clinical Diagnosis (OR 'Normal Speech')",
        "confidence": 0.0 to 1.0,
        "notes": "Specific clinical feedback (max 10 words).",
        "medical_analysis": "Brief SLP hypothesis.",
        "severity": "None / Low / Moderate / Severe",
        "lipAccuracy": 0.0 to 1.0,
        "pronunciation": 0.0 to 1.0
      }
      """;

      final response = await model.generateContent([Content.text(prompt)]);
      
      if (response.text != null) {
        String cleanJson = response.text!.replaceFirst('```json', '').replaceAll('```', '').trim();
        final Map<String, dynamic> data = jsonDecode(cleanJson);
        
        data['status'] = 'analyzing';
        // Add landmarks mock for visualizer
        data['lip_landmarks'] = _generateMockLandmarks(data['lipAccuracy'] ?? 0.5); 
        
        return data;
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint("Gemini Live Error: $e");
      
      if (e.toString().contains('403') || e.toString().contains('API key')) {
         return {
          'disorder': 'AI Config Error',
          'confidence': 0.0,
          'notes': 'Vertex AI API not enabled.',
          'status': 'error',
        };
      }
    }

    // 3. Fallback Heuristics (Offline Mode / Error State)
    if (!isSpeaking) {
      if (avgLipOpenness > 15) {
         return {
          'disorder': 'Silent Movement',
          'confidence': 0.70,
          'notes': 'Lip movement detected but no voice. Check microphone.',
          'severity': 'Moderate',
          'status': 'offline_fallback',
          'lip_landmarks': _generateMockLandmarks(0.6),
        };
      }
      return {
        'disorder': 'No Speech Detected',
        'confidence': 0.0,
        'notes': 'Please speak closer to the microphone.',
        'severity': 'None',
        'status': 'listening',
        'lip_landmarks': [],
      };
    }

    // Heuristic for Mumbling
    if (avgLipOpenness < 4) {
       return {
        'disorder': 'Potential Mumbling',
        'confidence': 0.75,
        'notes': 'Restricted lip movement detected ($avgLipOpenness px).',
        'severity': 'Mild',
        'status': 'offline_fallback',
        'lipAccuracy': 0.3,
        'pronunciation': 0.6,
        'lip_landmarks': _generateMockLandmarks(0.3),
      };
    }

    // Keyword Check (Lisp/Gliding)
    final lowerText = (transcribedText ?? "").toLowerCase();
    if (lowerText.contains('wabbit')) {
       return {
        'disorder': 'Articulation (Gliding)',
        'confidence': 0.85,
        'notes': 'Substituted "W" for "R" in Rabbit.',
        'severity': 'Mild',
        'status': 'offline_fallback',
        'lip_landmarks': _generateMockLandmarks(0.7),
      };
    }

    // Default Normal Fallback
    return {
      'status': 'offline_fallback',
      'disorder': 'Normal Speech',
      'confidence': 0.90,
      'notes': 'Speech is fluent and clear.',
      'severity': 'None',
      'medical_analysis': 'None',
      'lipAccuracy': 0.85,
      'pronunciation': 0.9,
      'lip_landmarks': _generateMockLandmarks(0.85),
    };
  }

  Future<void> saveAssessment(Map<String, dynamic> analysisData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not logged in");

    await FirebaseFirestore.instance.collection('assessments').add({
      'userId': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'disorder': analysisData['disorder'] ?? 'Unknown',
      'confidence': analysisData['confidence'] ?? 0.0,
      'severity': analysisData['severity'] ?? 'None',
      'notes': analysisData['notes'] ?? '',
      'medical_analysis': analysisData['medical_analysis'] ?? 'None',
      'lipAccuracy': analysisData['lipAccuracy'] ?? 0.0,
      'pronunciation': analysisData['pronunciation'] ?? 0.0,
      'raw_data': analysisData,
    });
  }

  List<Map<String, double>> _generateMockLandmarks(double accuracy) {
      final List<Map<String, double>> landmarks = [];
      final centerX = 0.5;
      final centerY = 0.5;
      final radius = 0.08 + (accuracy * 0.05); 

      for (int i = 0; i < 6; i++) {
        landmarks.add({
          'x': centerX + radius * 0.7 * (i % 2 == 0 ? 1 : 0.8) *  (i > 2 ? -1 : 1),
          'y': centerY + radius * (i % 3 == 0 ? 1 : -1),
        });
      }
      return landmarks;
  }
}

