import 'package:flutter/foundation.dart';

class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  Future<void> loadModel() async {
    debugPrint("Web ML: TFLite not supported on Web. Using mock mode.");
  }

  Map<String, double> classifyAudio(List<double> audioBuffer) {
    // Mock Logic for Web
    double energy = audioBuffer.fold(0.0, (sum, val) => sum + (val * val));
    if (energy < 0.1) {
       return {'Silence': 0.9, 'Normal': 0.1};
    }
    return {'Normal': 0.95, 'Web Simulation': 0.05};
  }
}
