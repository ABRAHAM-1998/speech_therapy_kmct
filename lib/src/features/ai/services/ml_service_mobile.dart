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

      // 2. Reshape Input: [1, 16000, 1]
      // We must match the model's expected shape exactly.
      // Shape: [Batch=1, TimeSteps=16000, Features=1]
      var input = [
        List.generate(sampleLength, (i) => [processedAudio[i]])
      ];

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
