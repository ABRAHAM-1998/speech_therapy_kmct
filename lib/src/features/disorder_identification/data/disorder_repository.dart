
import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:flutter/foundation.dart'; // for debugPrint

class DisorderRepository {
  String? _lastError;

  Future<Map<String, dynamic>> analyzeSession(String text, {double avgLipOpenness = 0.0}) async {
    _lastError = null;
    // 1. Try Gemini Analysis
    try {
      // ignore: deprecated_member_use
      final model = FirebaseVertexAI.instance.generativeModel(model: 'gemini-2.5-flash');
      
      final prompt = """
      Act as an expert Speech Pathologist. Analyze the following patient data from a session:
      1. Transcribed Speech: "$text"
      2. Average Lip Openness score: $avgLipOpenness (Pixels. 0=Closed, ~10-30=Normal opening)

      Diagnosis Criteria:
      - If text is empty but lip openness is normal/high (>15), suggest 'Silent/Mouthing'.
      - If text is present but lip openness is very low (<5), suggest 'Mumbling/Restricted ROM'.
      - Check for articulation errors in the text (e.g., 'wabbit' for 'rabbit').
      - If speech seems normal and clear, diagnose as 'Normal/Fluency WNL'.

      Return a raw JSON object ONLY (no markdown formatting) with:
      {
        "disorder": "Short Title",
        "confidence": 0.0 to 1.0,
        "notes": "Short, actionable clinical feedback (max 2 sentences)."
      }
      """;

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      if (response.text != null) {
         // Clean potential markdown code blocks
         String cleanJson = response.text!.replaceAll('```json', '').replaceAll('```', '').trim();
         final Map<String, dynamic> data = jsonDecode(cleanJson);
         return data;
      }
    } catch (e) {
      // Fallback if API fails (e.g. Quota, Offline)
      _lastError = e.toString();
      debugPrint("Gemini Error: $e"); 
            
      // If it's a permission/API error, let the user know for debugging
      if (e.toString().contains('403') || e.toString().contains('API key')) {
         return {
          'disorder': 'AI Configuration Error',
          'confidence': 0.0,
          'notes': 'Vertex AI API not enabled. Enable it in Firebase Console.',
        };
      }
      
      if (e.toString().contains('400') || e.toString().toLowerCase().contains('billing')) {
         return {
          'disorder': 'Billing Required',
          'confidence': 0.0,
          'notes': 'Vertex AI requires a Billing Account (even for free tier). Link a card in Firebase Console.',
        };
      }
    }

    // 2. Fallback Heuristics (Offline Mode)
    await Future.delayed(const Duration(seconds: 1)); // UX delay

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

    if (avgLipOpenness < 5 && text.length > 10) {
       return {
        'disorder': 'Potential Mumbling',
        'confidence': 0.85,
        'notes': 'Speech detected but lip movement is minimal ($avgLipOpenness px avg).',
      };
    }

    // Simple keyword checks
    final lowerText = text.toLowerCase();
    if (lowerText.contains('rabbit') || lowerText.contains('run')) {
      if (!lowerText.contains('wabbit')) {
         return {
          'disorder': 'Normal R-Articulation',
          'confidence': 0.95,
          'notes': 'Good pronounciation of "R".',
        };
      }
    }
    
    // Generic Fallback for valid speech detection
    if (text.length > 10) {
       String errorNote = _lastError != null ? " (Error: $_lastError)" : "";
       return {
        'disorder': 'Fluent Speech (Offline)',
        'confidence': 0.80,
        'notes': 'Speech detected: "$text". AI Analysis failed$errorNote. Check Internet/API.',
      };
    }

    return {
      'disorder': 'Analysis Pending',
      'confidence': 0.50,
      'notes': 'Could not determine specific disorder offline. Connect to internet for AI analysis.',
    };
  }
}
