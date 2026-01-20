
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      Act as a Senior Clinical Speech-Language Pathologist (SLP). 
      Analyze the following patient session data.
      
      Patient Data:
      1. Transcribed Speech: "$text"
      2. Lip Openness Metric: $avgLipOpenness (Pixels. <5=Low, 10-25=Normal).

      Guidelines:
      - **Normal Speech**: If the text is fluent, makes sense, and has no obvious phonetic errors, diagnose as "Normal Speech / Within Normal Limits". 
      - **Restricted ROM**: If text exists but lip openness is extremely low (<3), consider *Mumbling*, but ONLY if text is also short/simple.
      - **Articulation**: Analyze phonemes (e.g. 'Wabbit' = Gliding).
      - **Fluency**: Repetitions/blocks in text = *Stuttering*.

      Return a raw JSON object:
      {
        "disorder": "Clinical Diagnosis (OR 'Normal Speech')",
        "confidence": 0.0 to 1.0,
        "notes": "Specific feedback. If normal, praise the clarity.",
        "medical_analysis": "Hypothesis (or 'None' if normal).",
        "severity": "None / Low / Moderate / Severe"
      }
      """;

      final content = [Content.text(prompt)];
      final response = await model.generateContent(content);
      
      if (response.text != null) {
         String cleanJson = response.text!.replaceFirst('```json', '').replaceAll('```', '').trim();
         final Map<String, dynamic> data = jsonDecode(cleanJson);
         // Inject metrics
         data['avg_lip_openness'] = avgLipOpenness;
         return data;
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint("Gemini Error: $e"); 
            
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

    // 2. Fallback Heuristics (Offline Mode) -> Adjusted for False Positives
    await Future.delayed(const Duration(seconds: 1)); 

    if (text.trim().isEmpty) {
      if (avgLipOpenness > 20) {
         return {
          'disorder': 'Silent Movement',
          'confidence': 0.70,
          'notes': 'Lip movement detected but no voice. Check microphone.',
          'severity': 'Moderate',
          'avg_lip_openness': avgLipOpenness,
        };
      }
      return {
        'disorder': 'No Speech Detected',
        'confidence': 0.0,
        'notes': 'Could not hear any words. Please try speaking closer to the microphone.',
        'severity': 'None',
        'avg_lip_openness': avgLipOpenness,
      };
    }

    // Relaxed Mumbling Threshold: Only if < 4 (was 5) and text is SHORT.
    // Long text implies intelligibility, so it's likely NOT mumbling even if lips move less.
    if (avgLipOpenness < 4 && text.length > 20) {
       // Do nothing, let it pass to Normal. 
       // Only flag if really restricted on short phrases.
    } else if (avgLipOpenness < 3 && text.length > 5) {
       return {
        'disorder': 'Potential Mumbling',
        'confidence': 0.75, // Lower confidence
        'notes': 'Speech detected but lip movement is minimal ($avgLipOpenness px avg).',
        'severity': 'Mild'
      };
    }

    // Simple keyword checks for Articulation
    final lowerText = text.toLowerCase();
    if (lowerText.contains('wabbit')) {
       return {
        'disorder': 'Articulation (Gliding)',
        'confidence': 0.85,
        'notes': 'Substituted "W" for "R" in Rabbit.',
        'severity': 'Mild'
      };
    }
    
    // Default to Normal if text is sufficient length
    if (text.length > 5) {
       return {
        'disorder': 'Normal Speech',
        'confidence': 0.90,
        'notes': 'Speech is fluent and clear. No obvious disorders detected offline.',
        'severity': 'None',
        'medical_analysis': 'None',
        'avg_lip_openness': avgLipOpenness,
      };
    }

    return {
      'disorder': 'Analysis Pending',
      'confidence': 0.50,
      'notes': 'Could not determine specific disorder offline. Connect to internet for AI analysis.',
      'avg_lip_openness': avgLipOpenness,
    };
  }



  Future<void> saveAssessment(Map<String, dynamic> analysisData) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not logged in");

    await FirebaseFirestore.instance.collection('assessments').add({
      'userId': user.uid,
      'timestamp': FieldValue.serverTimestamp(),
      'disorder': analysisData['disorder'],
      'confidence': analysisData['confidence'],
      'severity': analysisData['severity'],
      'notes': analysisData['notes'],
      'medical_analysis': analysisData['medical_analysis'],
      'avg_lip_openness': analysisData['avg_lip_openness'], // Top-level metric
      'raw_data': analysisData,
    });
  }
}
