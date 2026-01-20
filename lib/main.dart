import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:speech_therapy/src/app.dart';

import 'package:speech_therapy/firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
  } catch (e) {
    debugPrint("Firebase initialization info: $e");
  }

  runApp(const SpeechTherapyApp());
}
