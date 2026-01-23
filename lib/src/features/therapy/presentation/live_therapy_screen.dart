import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:speech_therapy/src/features/ai/services/face_detector_service.dart';
import 'package:speech_therapy/src/features/ai/services/gemini_service.dart';
import 'package:speech_therapy/src/features/ai/services/ml_service.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:speech_therapy/src/features/video_call/presentation/widgets/face_landmark_overlay.dart';

class LiveTherapyScreen extends StatefulWidget {
  final String exerciseTitle;
  
  const LiveTherapyScreen({super.key, required this.exerciseTitle});

  @override
  State<LiveTherapyScreen> createState() => _LiveTherapyScreenState();
}

class _LiveTherapyScreenState extends State<LiveTherapyScreen> {
  // Camera & ML Kit
  bool _isInit = false;
  CameraController? _cameraController;
  final FaceDetectorService _faceDetectorService = FaceDetectorService();
  bool _isProcessingImage = false;
  
  // AI State
  Timer? _analysisTimer;
  Map<String, dynamic> _aiStats = {
    'status': 'initializing',
    'feedback': 'Preparing AI...',
    'lipAccuracy': 0.0,
    'pronunciation': 0.0,
    'disorder': 'Analyzing...',
    'notes': 'Waiting for analysis...',
  };

  // Recording State
  final _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isRecording = false;
  double _lipGap = 0.0; // ML Kit driven openness
  List<Map<String, double>> _realLipLandmarks = []; // Full contour
  List<Map<String, double>> _syncLandmarks = []; // Measurement points
  
  IOSink? _fileSink;
  StreamSubscription<Uint8List>? _recordSubscription;
  final List<double> _audioBuffer = []; // Rolling buffer for AI
  static const int _maxBufferSize = 16000; // 1 second at 16kHz

  @override
  void initState() {
    super.initState();
    _initCameraAndAI();
  }

  Future<void> _initCameraAndAI() async {
    await MLService().loadModel(); // Load TFLite
    await _startCamera();
    _startAnalysisLoop();
    _startRecording();
  }

  Future<void> _startCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final frontCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false, // We use AudioRecorder for audio
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      
      // Start ML Kit Image Stream
      _cameraController!.startImageStream((image) async {
        if (_isProcessingImage || !mounted) return;
        _isProcessingImage = true;
        
        final result = await _faceDetectorService.processImage(image, frontCamera);
        if (result != null && mounted) {
           setState(() {
             _lipGap = result.lipOpenness * 5.0; 
             _verticalDistance = result.verticalDistance;
             _realLipLandmarks = result.fullContour;
             _syncLandmarks = result.lipLandmarks;
           });

        }


        _isProcessingImage = false;
      });

      if (mounted) setState(() => _isInit = true);
    } catch (e) {
      debugPrint("Error opening camera: $e");
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final path = '${tempDir.path}/session_${DateTime.now().millisecondsSinceEpoch}.pcm';
        
        final config = const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        );

        final stream = await _audioRecorder.startStream(config);
        
        final file = File(path);
        _fileSink = file.openWrite();
        _currentRecordingPath = path;

        _recordSubscription = stream.listen((data) {
           _fileSink?.add(data);

           final byteData = data.buffer.asByteData(data.offsetInBytes, data.length);
           for (var i = 0; i < data.length - 1; i += 2) {
             final sample = byteData.getInt16(i, Endian.little);
             final val = sample / 32768.0;
             _audioBuffer.add(val);
           }

           if (_audioBuffer.length > _maxBufferSize) {
             _audioBuffer.removeRange(0, _audioBuffer.length - _maxBufferSize);
           }
        });

        _isRecording = true;
      }
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  double _verticalDistance = 0.0;

  void _startAnalysisLoop() {
    _analysisTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;
      
      final result = await GeminiService().analyzeSession(
        isSpeaking: _isRecording, 
        isFaceVisible: true,
        avgLipOpenness: _lipGap * 25.0, 
      );
      
      if (mounted) {
         final offlineResult = MLService().classifyAudio(_audioBuffer);
         if (offlineResult.isNotEmpty && !offlineResult.containsKey('Error') && !offlineResult.containsKey('Model Not Loaded')) {
            String bestClass = offlineResult.entries.reduce((a, b) => a.value > b.value ? a : b).key;
            result['offline_label'] = bestClass;
            result['offline_score'] = offlineResult[bestClass];
         }
         
         // Inject exact measurement points and distance into stats for syncing
         result['lip_landmarks'] = _syncLandmarks;
         result['verticalDistance'] = _verticalDistance;
      
         setState(() => _aiStats = result);

      }
    });
  }




  @override
  void dispose() {
    _analysisTimer?.cancel();
    _audioRecorder.dispose();
    _cameraController?.dispose();
    super.dispose();
  }
  
  Future<void> _endSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if(mounted) context.pop();
      return;
    }

    // Show saving indicator
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Saving Session & Uploading Data..."),
        duration: Duration(seconds: 2),
      ));
    }

    String? uploadedAudioUrl;

    // 1. Stop Recording & Upload
    if (_isRecording) {
      try {
        await _recordSubscription?.cancel();
        await _fileSink?.close();
        final path = await _audioRecorder.stop();
        _isRecording = false;

        debugPrint("Recording stopped. Output path: $_currentRecordingPath");

        if (_currentRecordingPath != null) {
           final ref = FirebaseStorage.instance
                 .ref()
                 .child('session_recordings')
                 .child(user.uid)
                 .child('session_${DateTime.now().millisecondsSinceEpoch}.pcm');

          if (kIsWeb) {
             // On Web, stop() returns the blob path
             if (path != null) {
                final response = await http.get(Uri.parse(path));
                await ref.putData(response.bodyBytes, SettableMetadata(contentType: 'audio/pcm'));
                uploadedAudioUrl = await ref.getDownloadURL();
             }
          } else {
            // Mobile: Upload the manually written file
            final file = File(_currentRecordingPath!);
            if (await file.exists()) {
               await ref.putFile(file);
               uploadedAudioUrl = await ref.getDownloadURL();
            }
          }
           
           debugPrint("Audio uploaded success: $uploadedAudioUrl");
        }
      } catch (e) {
        debugPrint("Error uploading audio: $e");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload Failed: $e")));
      }
    }

    // 2. Save Results using GeminiService
    try {
      final finalData = Map<String, dynamic>.from(_aiStats);
      finalData['audio_recording_url'] = uploadedAudioUrl;
      finalData['exerciseTitle'] = widget.exerciseTitle;
      
      await GeminiService().saveAssessment(finalData);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Session Saved Successfully!")));
        context.pop();
      }
    } catch (e) {
      debugPrint("Error saving assessment: $e");
      if (mounted) context.pop();
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Layer
          if (_isInit && _cameraController != null)
            SizedBox.expand(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(_cameraController!),
                  FaceLandmarkOverlay(
                    contour: _realLipLandmarks,
                    measurementPoints: _syncLandmarks,
                    lipGap: _lipGap,
                    verticalDistance: _verticalDistance,
                  ),


                ],
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),

          // 2. Gradient Overlay for Text Readability
          const DecoratedBox(
             decoration: BoxDecoration(
               gradient: LinearGradient(
                 begin: Alignment.topCenter,
                 end: Alignment.bottomCenter,
                 colors: [Colors.black45, Colors.transparent, Colors.black54],
                 stops: [0.0, 0.4, 0.8],
               ),
             ),
          ),

          // 3. Header
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.circle, size: 10, color: Colors.white),
                        SizedBox(width: 8),
                        Text("LIVE", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ).animate(onPlay: (controller) => controller.repeat(reverse: true)).scale(begin: const Offset(1.0, 1.0), end: const Offset(1.1, 1.1), duration: 2.seconds),
                  IconButton(
                    icon: const Icon(Icons.stop_circle, color: Colors.red, size: 32),
                    onPressed: () => _endSession(),
                  ),
                ],
              ),
            ),
          ),

          // 4. AI HUD (Heads Up Display)
          Positioned(
            top: 100,
            right: 16,
            child: _buildAIStatsCard(),
          ),

          // 5. Bottom Controls & Feedback
          Positioned(
            bottom: 40,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLiveFeedback(),
                const SizedBox(height: 24),
                Text(
                  widget.exerciseTitle.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white54,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIStatsCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildGeminiCard(),
        const SizedBox(height: 12),
        _buildOfflineCard(),
      ],
    ).animate().slideX(begin: 1.0, end: 0.0, curve: Curves.easeOutBack);
  }

  Widget _buildGeminiCard() {
    final lipScore = ((_aiStats['lipAccuracy'] as num?) ?? 0.0).toDouble();
    final pronScore = ((_aiStats['pronunciation'] as num?) ?? 0.0).toDouble();
    final disorder = _aiStats['disorder'] as String? ?? 'Analyzing...';
    final note = _aiStats['notes'] as String? ?? 'Waiting for analysis...';

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(color: Colors.cyanAccent.withValues(alpha: 0.1), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
               const Icon(Icons.cloud_sync, color: Colors.cyanAccent, size: 16),
               const SizedBox(width: 8),
               Expanded(
                 child: Text(
                   disorder.toUpperCase(), 
                   style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 10),
                   overflow: TextOverflow.ellipsis,
                 ),
               ),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          _buildStatRow("Lip Move", lipScore),
          const SizedBox(height: 8),
          _buildStatRow("Speech", pronScore),
          const SizedBox(height: 8),
          _buildStatRow("Lip Opening", (_verticalDistance / 50).clamp(0.0, 1.0), rawValue: "${_verticalDistance.toStringAsFixed(1)} PX"),
          const SizedBox(height: 12),
          Text(note, style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }


  Widget _buildOfflineCard() {
    final label = _aiStats['offline_label'] as String? ?? 'Scanning Voice...';
    final score = (_aiStats['offline_score'] as num?)?.toDouble() ?? 0.0;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.orangeAccent.withValues(alpha: 0.1), blurRadius: 12),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
               Icon(Icons.offline_bolt, color: Colors.orangeAccent, size: 16),
               SizedBox(width: 8),
               Text("OFFLINE (TFLite)", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          _buildStatRow(label.split('(').first, score),
          const SizedBox(height: 8),
          const Text("Live TFLite Calculation", style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, double score, {String? rawValue}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(
              rawValue ?? "${(score * 100).toInt()}%", 
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: score,
          backgroundColor: Colors.white10,
          valueColor: AlwaysStoppedAnimation<Color>(score > 0.7 ? Colors.greenAccent : Colors.orangeAccent),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
      ],
    );
  }


  Widget _buildLiveFeedback() {
    final feedback = _aiStats['feedback'] as String? ?? '...';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.record_voice_over, color: Colors.white70),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              feedback,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
      ),
    ).animate(target: feedback.hashCode.toDouble()).shimmer();
  }
}
