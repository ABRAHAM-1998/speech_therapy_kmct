import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_therapy/src/features/disorder_identification/data/disorder_repository.dart';
import 'package:speech_to_text/speech_to_text.dart';

class DisorderIdentificationScreen extends StatefulWidget {
  const DisorderIdentificationScreen({super.key});

  @override
  State<DisorderIdentificationScreen> createState() =>
      _DisorderIdentificationScreenState();
}
class _DisorderIdentificationScreenState
    extends State<DisorderIdentificationScreen> {
  CameraController? _cameraController;
  final SpeechToText _speechToText = SpeechToText();
  bool _isSpeechEnabled = false;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  String _lastWords = '';
  CustomPaint? _customPaint;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  bool _isProcessingImage = false;
  double _currentLipOpenness = 0.0;
  final List<double> _lipOpennessHistory = [];



  Future<void> _initializeCamera() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final frontCamera = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.front,
            orElse: () => cameras.first);
            
        _cameraController = CameraController(
            frontCamera, ResolutionPreset.medium,
            enableAudio: false,
            imageFormatGroup: Platform.isAndroid 
                ? ImageFormatGroup.nv21 
                : ImageFormatGroup.bgra8888);
            
        await _cameraController?.initialize();
        
        // Start Image Stream for ML Kit
        _cameraController?.startImageStream(_processCameraImage);
        
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingImage || !_isRecording) return;
    _isProcessingImage = true;

    try {
      final inputImage = _inputImageFromCameraImage(image);
      if (inputImage == null) return;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isNotEmpty) {
        final face = faces.first;
        
        // 1. Calculate Lip Openness using Contours (More Accurate)
        final upperLipBottom = face.contours[FaceContourType.upperLipBottom];
        final lowerLipTop = face.contours[FaceContourType.lowerLipTop];
        
        if (upperLipBottom != null && lowerLipTop != null) {
           // Calculate average Y for upper lip bottom edge
           final double avgUpperY = upperLipBottom.points.map((p) => p.y.toDouble()).reduce((a,b)=>a+b) / upperLipBottom.points.length;
           // Calculate average Y for lower lip top edge
           final double avgLowerY = lowerLipTop.points.map((p) => p.y.toDouble()).reduce((a,b)=>a+b) / lowerLipTop.points.length;
           
           double distance = (avgUpperY - avgLowerY).abs();

           // Normalize by face height (approximate)
           if (face.boundingBox.height > 0) {
              // Normalized: (Openness / Face Height) * 1000
              // Example: 20px open / 400px face = 0.05 * 1000 = 50 score
              distance = (distance / face.boundingBox.height) * 1000; 
           }

          if (mounted) {
             setState(() {
              _currentLipOpenness = distance;
              _lipOpennessHistory.add(distance);
              
              // 2. Update Visual Overlay
              final painter = FacePainter(
                   imageSize: Size(image.width.toDouble(), image.height.toDouble()),
                   face: face,
                   sourceRotation: InputImageRotation.rotation270deg, // Fixed for portrait
                   isFrontCamera: true
              );
              _customPaint = CustomPaint(painter: painter);
            });
          }
        }
      } else {
        if(mounted && _customPaint != null) {
           setState(() => _customPaint = null);
        }
      }
    } catch (e) {
      debugPrint("Error processing face: $e");
    } finally {
      _isProcessingImage = false;
    }
  }

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    // 1. Get Camera Rotation
    final camera = _cameraController!.description;
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) ?? InputImageRotation.rotation0deg;

    // 2. Format
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

    // 3. Plane Data
    // For Android (NV21), we concatenate planes.
    // Note: This is simplified for the most common Android case (YUV_420_888 / NV21).
    if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) { 
       final allBytes = WriteBuffer();
       for (final plane in image.planes) {
         allBytes.putUint8List(plane.bytes);
       }
       final bytes = allBytes.done().buffer.asUint8List();

       final metadata = InputImageMetadata(
         size: Size(image.width.toDouble(), image.height.toDouble()),
         rotation: rotation,
         format: format,
         bytesPerRow: image.planes[0].bytesPerRow,
       );

       return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    } 
    
    // For iOS (BGRA8888)
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
       final plane = image.planes[0];
       final metadata = InputImageMetadata(
         size: Size(image.width.toDouble(), image.height.toDouble()),
         rotation: rotation,
         format: InputImageFormat.bgra8888,
         bytesPerRow: plane.bytesPerRow,
       );
       
       return InputImage.fromBytes(bytes: plane.bytes, metadata: metadata);
    }

    return null;
  }



  double _soundLevel = 0.0;
  final List<String> _sentences = [
    "The rainbow is a division of white light into many beautiful colors.",
    "Please take this dirty table cloth to the store for me.",
    "The north wind and the sun were disputing which was the stronger.",
    "You wish to know all about my grandfather. Well, he is nearly ninety-three years old.",
    "When the sunlight strikes raindrops in the air, they act as a prism and form a rainbow.",
    "Do you think you can find the way to the station by yourself?",
    "We saw several wild animals in the forest during our trip.",
    "She sells sea shells by the sea shore."
  ];

  String _targetText = "";

  @override
  void initState() {
    super.initState();
    _randomizeText();
    _initializeCamera();
    _initSpeech();
  }

  void _randomizeText() {
    setState(() {
      _targetText = _sentences[Random().nextInt(_sentences.length)];
    });
  }

  void _initSpeech() async {
    _isSpeechEnabled = await _speechToText.initialize();
    if(mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop
      await _speechToText.stop();
      setState(() {
        _isRecording = false;
        _isAnalyzing = true;
        _soundLevel = 0.0; // Reset wave
      });
      
      // Validation (Logic unchanged...)
      bool hasAudio = _lastWords.trim().isNotEmpty;
      bool hasFaceData = _lipOpennessHistory.isNotEmpty;
      
      // Logic for "Abnormal Sound"
      // If we had high sound levels but no text, it might be mumbling/noise.
      // We can't easily pass this to the Repo since it's transient, but the Repo checks "Text Empty + Lip Move".
      
      if (!hasAudio || !hasFaceData) {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text(
                 !hasAudio && !hasFaceData ? "No Audio or Face detected!" :
                 !hasAudio ? "Sound detected but no words. Possible Mumbling/Noise." : "No Face detected."
               ),
               backgroundColor: Colors.red,
             )
           );
           setState(() {
            _isAnalyzing = false;
            _lipOpennessHistory.clear();
           });
         }
         return;
      }

      double avg = _lipOpennessHistory.reduce((a, b) => a + b) / _lipOpennessHistory.length;
      _sessionHistory = List.from(_lipOpennessHistory); // Save for Graph
      _lipOpennessHistory.clear();

      final result = await DisorderRepository().analyzeSession(_lastWords, avgLipOpenness: avg);
      
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _resultMap = result;
        });
        _showResultDialog();
      }
    } else {
      // Start
      _lastWords = ''; 
      _lipOpennessHistory.clear();
      
      if (_isSpeechEnabled) {
          await _speechToText.listen(
            onResult: (result) {
              setState(() {
                _lastWords = result.recognizedWords;
              });
            },
            onSoundLevelChange: (level) {
               // Level is usually 0-10 or -10 to 10 depending on platform. 
               // We normalize visual only.
               if(mounted) setState(() => _soundLevel = level);
            }
          );
      }
      setState(() => _isRecording = true);
    }
  }

  // Helper State field
  Map<String, dynamic>? _resultMap;

  void _showResultDialog() {
    if (_resultMap == null) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.monitor_heart, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Clinical Assessment'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow("Diagnosis:", _resultMap!['disorder'], isBold: true),
              _buildInfoRow("Severity:", _resultMap!['severity'] ?? 'N/A'),
              _buildInfoRow("Confidence:", "${((_resultMap!['confidence'] ?? 0) * 100).toInt()}%"),
              
              const SizedBox(height: 12),
              const Text("Analysis Graph (Lip Openness):", style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 4),
              SizedBox(
                height: 80,
                width: double.infinity,
                child: CustomPaint(painter: LipChartPainter(_sessionHistory)),
              ),
              const SizedBox(height: 12),

              const Divider(),
              const Text("Clinical Notes:", style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_resultMap!['notes'] ?? 'No notes'),
              const SizedBox(height: 8),
              if (_resultMap!['medical_analysis'] != null) ...[
                 const Text("Medical Hypothesis:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                 Text(_resultMap!['medical_analysis'], style: const TextStyle(fontStyle: FontStyle.italic)),
              ]
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                 _lastWords = ''; 
                 _isRecording = false;
                 _isAnalyzing = false;
                 _lipOpennessHistory.clear();
                 _soundLevel = 0.0;
                 _resultMap = null;
                 _randomizeText(); 
              });
            },
             child: const Text('New Session'),
          ),
          FilledButton(
            onPressed: () async {
              // Show loading or just close? User requested "Save to Firestore".
              // Let's optimize for UX: Save in background, close dialog, show snackbar.
              Navigator.pop(context);
              
              if (_resultMap != null) {
                try {
                   await DisorderRepository().saveAssessment(_resultMap!);
                   if (!context.mounted) return;
                   
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text("Assessment Saved to Profile!"), backgroundColor: Colors.green)
                   );
                   context.go('/dashboard');
                } catch (e) {
                   if (!context.mounted) return;
                   
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Failed to save: $e"), backgroundColor: Colors.red)
                   );
                }
              }
            },
            child: const Text('Save to Profile'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label ", style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: isBold ? 16 : 14))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _speechToText.cancel();
    super.dispose();
  }

  // Store history for analysis chart
  List<double> _sessionHistory = [];

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.cyan)),
      );
    }

    // Camera aspect ratio handling
    // Ensure we don't stretch. Center the 4:3 preview on the screen.
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _cameraController!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AI Assessment'),
        backgroundColor: Colors.black54,
        elevation: 0,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Camera Preview (Centered & Scaled correctly or Fitted)
          // To get a strict 4:3 "Box" look as requested, we can wrap in AspectRatio.
          // Or full screen "cover". User asked "4:3". Let's center it.
          Center(
            child: CameraPreview(_cameraController!),
          ),

          if (_customPaint != null)
             Positioned.fill(child: _customPaint!),

          // 2. Modern Reading Prompt (Top Card)
          Positioned(
            top: 20, 
            left: 20, 
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.black.withOpacity(0.8), Colors.black.withOpacity(0.4)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12, width: 1),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)]
              ),
              child: Column(
                children: [
                   Row(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.record_voice_over, color: Colors.cyanAccent.withOpacity(0.8), size: 16),
                       const SizedBox(width: 8),
                       const Text("READ ALOUD", style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                     ],
                   ),
                   const SizedBox(height: 8),
                   Text(
                     "\"$_targetText\"",
                     style: const TextStyle(color: Colors.white, fontSize: 18, fontStyle: FontStyle.italic, fontWeight: FontWeight.w400, height: 1.3),
                     textAlign: TextAlign.center,
                   ),
                ],
              ),
            ).animate().slideY(begin: -0.5, end: 0, duration: 600.ms, curve: Curves.easeOutBack),
          ),

          // 3. Live Metrics Overlay (Left)
          if (_currentLipOpenness > 0)
          Positioned(
             top: 150,
             left: 20,
             child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.5))
                ),
                child: Row(
                  children: [
                    const Icon(Icons.height, color: Colors.greenAccent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      "${_currentLipOpenness.toStringAsFixed(1)} px",
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
             ),
          ),

          // 4. Transcription & Visualizer (bottom)
          Positioned(
             bottom: 0,
             left: 0,
             right: 0,
             child: Container(
               height: 250,
               decoration: BoxDecoration(
                 gradient: LinearGradient(
                   colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
                   begin: Alignment.topCenter,
                   end: Alignment.bottomCenter,
                 )
               ),
               child: Column(
                 mainAxisAlignment: MainAxisAlignment.end,
                 children: [
                    // CC Text
                    if (_lastWords.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                      child: Text(
                        _lastWords,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Wave Visualizer
                    if (_isRecording)
                    SizedBox(
                      height: 50,
                      width: 200,
                      child: CustomPaint(
                        painter: AudioWavePainter(soundLevel: _soundLevel),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Controls
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40.0),
                      child: FloatingActionButton.large(
                        onPressed: (_isAnalyzing || !_isSpeechEnabled) ? null : _toggleRecording,
                        backgroundColor: _isRecording ? Colors.redAccent : Colors.cyan,
                        elevation: 10,
                        child: Icon(
                          _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ).animate(target: _isRecording ? 1 : 0).scale(begin: const Offset(1,1), end: const Offset(1.1, 1.1), duration: 1.seconds, curve: Curves.easeInOut),
                    ),
                 ],
               ),
             ),
          ),
          
          // Analysis Loading Overlay
          if (_isAnalyzing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.cyanAccent),
                    const SizedBox(height: 24),
                    const Text('Analyzing Biometrics...', style: TextStyle(color: Colors.cyanAccent, fontSize: 18, letterSpacing: 1.2)),
                    const SizedBox(height: 8),
                    Text('Processing ${_lipOpennessHistory.length} frames...', style: const TextStyle(color: Colors.white38)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Chart Painter
class LipChartPainter extends CustomPainter {
  final List<double> data;
  LipChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final paint = Paint()
      ..color = Colors.cyanAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
      
    final bgPaint = Paint()
      ..color = Colors.white10
      ..style = PaintingStyle.fill;
      
    canvas.drawRect(Offset.zero & size, bgPaint);

    final path = Path();
    double stepName = size.width / (data.length - 1);
    double maxVal = data.reduce(max);
    if(maxVal == 0) maxVal = 1;

    for (int i = 0; i < data.length; i++) {
       double x = i * stepName;
       // Invert Y (0 at bottom)
       double y = size.height - ((data[i] / maxVal) * size.height); 
       if (i == 0) path.moveTo(x, y);
       else path.lineTo(x, y);
    }
    
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FacePainter extends CustomPainter {
  final Size imageSize;
  final Face face;
  final InputImageRotation sourceRotation;
  final bool isFrontCamera;

  FacePainter({
    required this.imageSize,
    required this.face,
    required this.sourceRotation,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final Paint dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.blueAccent;

    // Helper to translate points
    Offset translate(Point<int> p) {
      return Offset(
        translateX(p.x.toDouble(), size, imageSize, sourceRotation, isFrontCamera),
        translateY(p.y.toDouble(), size, imageSize, sourceRotation, isFrontCamera),
      );
    }

    final upperLip = face.contours[FaceContourType.upperLipBottom];
    final lowerLip = face.contours[FaceContourType.lowerLipTop];

    if (upperLip != null && lowerLip != null) {
       // 1. Draw Contours
       final Paint contourPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white.withOpacity(0.5);
        
       for (var point in upperLip.points) {
         canvas.drawCircle(translate(point), 1, contourPaint);
       }
       for (var point in lowerLip.points) {
         canvas.drawCircle(translate(point), 1, contourPaint);
       }

       // 2. Find Center Points
       // Simple average of X and Y
       double upX = upperLip.points.map((p)=>p.x).reduce((a,b)=>a+b) / upperLip.points.length;
       double upY = upperLip.points.map((p)=>p.y).reduce((a,b)=>a+b) / upperLip.points.length;
       
       double lowX = lowerLip.points.map((p)=>p.x).reduce((a,b)=>a+b) / lowerLip.points.length;
       double lowY = lowerLip.points.map((p)=>p.y).reduce((a,b)=>a+b) / lowerLip.points.length;
       
       Offset topPoint = translate(Point(upX.toInt(), upY.toInt()));
       Offset bottomPoint = translate(Point(lowX.toInt(), lowY.toInt()));

       // 3. Calculate Distance for Visual Color
       double rawDistance = (topPoint.dy - bottomPoint.dy).abs();
       
       // Color Logic: Red (Closed) -> Green (Open)
       // Thresholds depend on screen scale, but relative change is visible.
       Color statusColor = rawDistance > 10 ? Colors.greenAccent : Colors.redAccent;
       linePaint.color = statusColor;

       // 4. Draw Measurement Line
       canvas.drawLine(topPoint, bottomPoint, linePaint);
       canvas.drawCircle(topPoint, 4, dotPaint);
       canvas.drawCircle(bottomPoint, 4, dotPaint);
       
       // 5. Draw Text Label
       final textSpan = TextSpan(
        text: '${rawDistance.toStringAsFixed(1)} px',
        style: TextStyle(color: statusColor, fontSize: 16, fontWeight: FontWeight.bold, backgroundColor: Colors.black45),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, bottomPoint.translate(-textPainter.width / 2, 10)); // Draw below lip
    }
  }

  // Simplified Coordinate Translator
  double translateX(double x, Size canvasSize, Size imageSize, InputImageRotation rotation, bool isFrontCamera) {
     return x * canvasSize.width / imageSize.height; // Swapped width/height for portrait
  }
  
  double translateY(double y, Size canvasSize, Size imageSize, InputImageRotation rotation, bool isFrontCamera) {
     return y * canvasSize.height / imageSize.width; // Swapped
  }

  @override
  bool shouldRepaint(FacePainter oldDelegate) {
    return oldDelegate.imageSize != imageSize || oldDelegate.face != face;
  }
}

class AudioWavePainter extends CustomPainter {
  final double soundLevel;
  AudioWavePainter({required this.soundLevel});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.8)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final double centerY = size.height / 2;
    // Normalize level (-10 to 10 range typ, we want 0-1 factor)
    // SpeechToText level is often dB-like. Let's assume range 0-10 roughly for visual.
    double normalized = (soundLevel.abs() / 10).clamp(0.0, 1.0);
    double maxHeight = size.height;
    
    // Draw 5 bars
    for (int i = 0; i < 5; i++) {
       double barHeight = 10 + (normalized * maxHeight * (i % 2 == 0 ? 0.8 : 1.0));
       // Add some random/sine variation if we had time, but simple scaling is enough for feedback
       
       double x = size.width / 5 * i + (size.width/10);
       Rect rect = Rect.fromCenter(center: Offset(x, centerY), width: 10, height: barHeight);
       canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5)), paint);
    }
  }

  @override
  bool shouldRepaint(AudioWavePainter oldDelegate) => oldDelegate.soundLevel != soundLevel;
}
