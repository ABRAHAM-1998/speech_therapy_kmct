import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _isModelLoaded = false;

  Future<void> loadModel() async {
    try {
      // Load Model
      _interpreter = await Interpreter.fromAsset('assets/models/speech_classifier.tflite');
      
      // Load Labels
      final labelData = await rootBundle.loadString('assets/models/labels.txt');
      _labels = labelData.split('\n');
      
      _isModelLoaded = true;
      debugPrint("TFLite Model Loaded Successfully");
    } catch (e) {
      debugPrint("Offline ML Warning: $e");
      _labels = ['Normal', 'Stuttering', 'Lisp', 'Mumbling'];
    }
  }

  Map<String, double> classifyAudio(List<double> audioBuffer) {
    if (_isModelLoaded && _interpreter != null) {
       try {
         // Real Inference Logic would go here
       } catch(e) {
          debugPrint("Inference Error: $e");
       }
    }
    
    // Fallback/Demo Logic (matches original logic)
    double energy = audioBuffer.fold(0.0, (sum, val) => sum + (val * val));
    if (energy < 0.1) {
       return {'Silence': 0.9, 'Normal': 0.1};
    }
    
    final random = DateTime.now().second;
    if (random % 5 == 0) return {'Stuttering': 0.85, 'Normal': 0.15};
    if (random % 7 == 0) return {'Lisp': 0.70, 'Normal': 0.30};
    
    return {'Normal': 0.92, 'Disorder': 0.08};
  }
}
