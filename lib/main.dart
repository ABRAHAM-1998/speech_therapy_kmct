import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:speech_therapy/src/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  // We wrap in try-catch because the firebase_options.dart might not be generated yet
  // This allows the UI to still render for testing purposes
  try {
      await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase initialization info: $e");
  }

  runApp(const SpeechTherapyApp());
}
