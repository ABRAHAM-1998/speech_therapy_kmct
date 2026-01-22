import 'dart:math';
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

    final stopwatch = Stopwatch()..start();

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

      // 2. Extract Features (Statistical features matching Python logic)
      var input = List.generate(1, (b) {
        return List.generate(44, (t) {
            int frameSize = (16000 ~/ 44);
            int start = t * frameSize;
            int end = start + frameSize;
            if (end > processedAudio.length) end = processedAudio.length;
            
            final frame = processedAudio.sublist(start, end);
            
            if (frame.isEmpty) return List.filled(13, 0.0);

            // 1. RMS
            double sumSq = frame.fold(0.0, (p, c) => p + (c * c));
            double rms = sqrt(sumSq / frame.length + 1e-8);

            // 2. ZCR (Zero Crossing Rate)
            int crossings = 0;
            for (int i = 1; i < frame.length; i++) {
              if (frame[i].sign != frame[i-1].sign) crossings++;
            }
            double zcr = crossings / frame.length;

            // 3. Mean Absolute
            double meanAbs = frame.fold(0.0, (p, c) => p + c.abs()) / frame.length;

            // 4. Variance
            double mean = frame.fold(0.0, (p, c) => p + c) / frame.length;
            double variance = frame.fold(0.0, (p, c) => p + pow(c - mean, 2)) / frame.length;

            // Match Python list: [rms, zcr, meanAbs, variance, ...scales]
            return [
                rms, zcr, meanAbs, variance,
                rms * 2, zcr * 2, meanAbs * 2, variance * 2,
                rms * 4, zcr * 4, meanAbs * 4, variance * 4,
                rms * 0.5
            ];
        });
      });
      
      // LOGS FOR DIAGNOSTICS
      double totalEnergy = audioBuffer.fold(0.0, (p, c) => p + c.abs()) / (audioBuffer.length + 1);
      debugPrint("Offline AI Input Energy: ${totalEnergy.toStringAsFixed(6)} (Buffer: ${audioBuffer.length})");
      
      // Ensure specific type for TFLite
      // Shape: [1, 44, 13]

      // 3. Prepare Output: [1, 22] (or number of labels)
      var output = List.generate(1, (index) => List<double>.filled(_labels.length, 0.0));

      // 4. Run Inference
      _interpreter!.run(input, output);
      debugPrint("Offline AI Raw Output: ${output[0].sublist(0, 5)}..."); // Log first 5 classes

      // 5. Map Outputs to Labels
      Map<String, double> results = {};
      final probs = output[0];
      
      for (int i = 0; i < probs.length; i++) {
        if (i < _labels.length) {
          results[_labels[i]] = probs[i];
        }
      }

      stopwatch.stop();
      debugPrint("Offline AI Inference Time: ${stopwatch.elapsedMilliseconds}ms");
      
      return results;

    } catch (e) {
      debugPrint("Inference Error: $e");
      return {'Error': 0.0};
    }
  }
}
