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
  String? _result;
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

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initSpeech();
  }

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



  void _initSpeech() async {
    _isSpeechEnabled = await _speechToText.initialize();
    if(mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      // Stop Recording & Analyzing
      await _speechToText.stop();
      // await _cameraController?.stopImageStream(); // Keep stream for preview
      
      // Validate Data Presence
      bool hasAudio = _lastWords.trim().isNotEmpty;
      bool hasFaceData = _lipOpennessHistory.isNotEmpty;

      if (!hasAudio || !hasFaceData) {
         if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text(
                 !hasAudio && !hasFaceData ? "No Audio or Face detected! Speak clearly and look at camera." :
                 !hasAudio ? "No Speech detected. Please speak louder." : "No Face detected. Keep your face in frame."
               ),
               backgroundColor: Colors.red,
             )
           );
           
           setState(() {
            _isRecording = false;
            _isAnalyzing = false;
            _lastWords = '';
            _lipOpennessHistory.clear();
           });
         }
         return;
      }

      setState(() {
        _isRecording = false;
        _isAnalyzing = true;
      });
      
      // Calculate Average Openness
      double avg = _lipOpennessHistory.reduce((a, b) => a + b) / _lipOpennessHistory.length;
      _lipOpennessHistory.clear();

      // Analyze the transcribed text + Lip Data
      final result = await DisorderRepository().analyzeSession(_lastWords, avgLipOpenness: avg);
      
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _result = "${result['disorder']}\n${result['notes']}";
        });
        _showResultDialog();
      }
    } else {
      // Start Recording
      _lastWords = ''; 
      _lipOpennessHistory.clear();
      
      if (_isSpeechEnabled) {
          await _speechToText.listen(onResult: (result) {
            setState(() {
              _lastWords = result.recognizedWords;
            });
          });
      }
      setState(() => _isRecording = true);
    }
  }

  void _showResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analysis Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Heard: "$_lastWords"', style: const TextStyle(fontStyle: FontStyle.italic)),
            const Divider(),
            Text(_result ?? 'No result'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() => _lastWords = ''); 
            },
             child: const Text('Try Again'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/dashboard');
            },
            child: const Text('Save & Exit'),
          ),
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

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('New Assessment')),
      body: Stack(
        children: [
          // Camera Preview
          // Camera Preview
          Positioned.fill(child: CameraPreview(_cameraController!)),
          
          if (_customPaint != null)
             Positioned.fill(child: _customPaint!),

          // Live Text Overlay (CC)
          if (_isRecording && _lastWords.isNotEmpty)
             Positioned(
              bottom: 150,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                color: Colors.black45,
                child: Text(
                  _lastWords,
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ).animate().fadeIn(),
             ),
             // Debug Lip Openness
             Positioned(
               top: 50,
               left: 16,
               child: Container(
                  padding: const EdgeInsets.all(4),
                  color: Colors.black54,
                  child: Text(
                    "Lip Openness: ${_currentLipOpenness.toStringAsFixed(1)}",
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
               ),
             ),

          // Overlay for Analyzing State
          if (_isAnalyzing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Analyzing Speech...', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ),

          // Controls
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.large(
                onPressed: (_isAnalyzing || !_isSpeechEnabled) ? null : _toggleRecording,
                backgroundColor: _isRecording ? Colors.red : Colors.white,
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: _isRecording ? Colors.white : (_isSpeechEnabled ? Colors.red : Colors.grey),
                  size: 40,
                ),
                ).animate(target: _isRecording ? 1 : 0).shimmer(duration: 1.seconds, color: Colors.white54),
            ),
          ),
          
          if (_isRecording)
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(8)),
              child: const Text("Listening...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
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
