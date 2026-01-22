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
      _labels = labelData.split('\n').where((l) => l.trim().isNotEmpty).toList();
      
      _isModelLoaded = true;
      debugPrint("TFLite Model Loaded Successfully. Labels: ${_labels.length}");
      
      // Verify input shape
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      debugPrint("Model Input: $inputShape, Output: $outputShape");
      
    } catch (e) {
      debugPrint("Offline ML Load Error: $e");
      // Keep empty to signal failure
      _isModelLoaded = false;
    }
  }

  Map<String, double> classifyAudio(List<double> audioBuffer) {
    if (!_isModelLoaded || _interpreter == null) {
      return {'Model Not Loaded': 0.0};
    }

    try {
      // 1. Preprocess: Pad or Truncate to 16000 samples
      const int sampleLength = 16000;
      List<double> processedAudio;
      
      if (audioBuffer.length >= sampleLength) {
        processedAudio = audioBuffer.sublist(0, sampleLength);
      } else {
        processedAudio = List<double>.from(audioBuffer);
        processedAudio.addAll(List.filled(sampleLength - audioBuffer.length, 0.0));
      }

      // 2. Extract Features (Simulated MFCC for now to match Shape [1, 44, 13])
      // Real MFCC requires complex FFT/DCT. For now, we bin the audio to match shape.
      var input = List.generate(1, (b) {
        return List.generate(44, (t) {
            // grab a window of audio
            int start = t * (16000 ~/ 44);
            int end = start + (16000 ~/ 44);
            if (end > processedAudio.length) end = processedAudio.length;
            
            // Generate 13 "features" (mocking MFCCs with simple stats for now)
            double mean = 0.0;
            if (start < end) {
               mean = processedAudio.sublist(start, end).fold(0.0, (p, c) => p + c.abs()) / (end-start);
            }
            return List.generate(13, (f) => mean * (f + 1)); // Mock features
        });
      });
      
      // Ensure specific type for TFLite
      // Shape: [1, 44, 13]

      // 3. Prepare Output: [1, 22] (or number of labels)
      var output = List.generate(1, (index) => List<double>.filled(_labels.length, 0.0));

      // 4. Run Inference
      _interpreter!.run(input, output);

      // 5. Map Outputs to Labels
      Map<String, double> results = {};
      final probs = output[0];
      
      for (int i = 0; i < probs.length; i++) {
        if (i < _labels.length) {
          results[_labels[i]] = probs[i];
        }
      }

      // Sort and Return Top Results (optional, but UI handles Map)
      return results;

    } catch (e) {
      debugPrint("Inference Error: $e");
      return {'Error': 0.0};
    }
  }
}
