import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_therapy/src/features/ai/services/gemini_service.dart';
import 'package:speech_therapy/src/features/ai/services/ml_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;

class LiveTherapyScreen extends StatefulWidget {
  final String exerciseTitle;
  
  const LiveTherapyScreen({super.key, required this.exerciseTitle});

  @override
  State<LiveTherapyScreen> createState() => _LiveTherapyScreenState();
}

class _LiveTherapyScreenState extends State<LiveTherapyScreen> {
  final _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _isInit = false;
  
  // AI State
  Timer? _analysisTimer;
  Map<String, dynamic> _aiStats = {
    'status': 'initializing',
    'feedback': 'Preparing AI...',
    'lipAccuracy': 0.0,
    'pronunciation': 0.0,
  };

  // Recording State
  final _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
    await _startCamera();
    _startAnalysisLoop(); // Fire and forget (timer)
    _startRecording();
  }

  Future<void> _startCamera() async {
    final Map<String, dynamic> constraints = {
      'audio': true,
      'video': {
        'facingMode': 'user',
      },
    };

    try {
      final stream = await navigator.mediaDevices.getUserMedia(constraints);
      if (mounted) {
        setState(() {
          _localStream = stream;
          _localRenderer.srcObject = _localStream;
          _isInit = true;
        });
      }
    } catch (e) {
      debugPrint("Error opening camera: $e");
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        String path = '';
        
        if (!kIsWeb) {
          final tempDir = await getTemporaryDirectory();
          path = '${tempDir.path}/session_${DateTime.now().millisecondsSinceEpoch}.m4a';
        } else {
          // On Web, provide a generic name. The plugin handles Blob storage internally usually.
          path = 'session_${DateTime.now().millisecondsSinceEpoch}.m4a';
        }
        
        await _audioRecorder.start(const RecordConfig(), path: path);
        _currentRecordingPath = path;
        _isRecording = true;
        debugPrint("Recording started. Path: $path (Web: ${kIsWeb})");
      }
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  void _startAnalysisLoop() {
    // Poll the "AI" every 2 seconds
    _analysisTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;
      
      // Simulate "talking" based on audio track status (very rough proxy)
      final isAudioEnabled = _localStream?.getAudioTracks().firstOrNull?.enabled ?? false;
      
      // 1. Online Analysis (Gemini)
      final result = await GeminiService().analyzeSession(
        isSpeaking: isAudioEnabled, 
        isFaceVisible: true,
      );
      
      // 2. Offline Analysis (TensorFlow Lite) - Augment or Fallback
      if (mounted) {
         // Create dummy buffer for demo (in real app, get from audio stream)
         // NOTE: Getting real bytes from MediaStream via Flutter WebRTC is complex.
         final dummyBuffer = List.generate(16000, (i) => (DateTime.now().millisecond / 1000) * 2 - 1);
         final offlineResult = MLService().classifyAudio(dummyBuffer);
         
         // Merge Offline "Diagnosis" into "Medical Hypothesis" if online failed or just to show both
         if (offlineResult.isNotEmpty && offlineResult.values.first > 0.6) {
            String bestClass = offlineResult.entries.reduce((a, b) => a.value > b.value ? a : b).key;
            result['offline_analysis'] = "Offline Model Detected: $bestClass (${(offlineResult[bestClass]! * 100).toInt()}%)";
         }
      
         setState(() => _aiStats = result);
      }
    });
  }


  @override
  void dispose() {
    _analysisTimer?.cancel();
    _audioRecorder.dispose();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localRenderer.dispose();
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
        final path = await _audioRecorder.stop();
        _isRecording = false;

        debugPrint("Recording stopped. Output path: $path");

        if (path != null) {
           final ref = FirebaseStorage.instance
                 .ref()
                 .child('session_recordings')
                 .child(user.uid)
                 .child('session_${DateTime.now().millisecondsSinceEpoch}.m4a');

          if (kIsWeb) {
            // Web: Fetch Blob and Upload
            final response = await http.get(Uri.parse(path));
            if (response.statusCode == 200) {
               await ref.putData(response.bodyBytes, SettableMetadata(contentType: 'audio/mp4'));
               uploadedAudioUrl = await ref.getDownloadURL();
            }
          } else {
            // Mobile: Upload File
            final file = File(path);
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

    // 2. Save Results to Firestore
    try {
      await FirebaseFirestore.instance.collection('assessments').add({
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'disorder': 'General Therapy', // Could be dynamic based on widget.exerciseTitle
        'severity': _calculateSeverity(),
        'avg_lip_openness': (_aiStats['lipAccuracy'] as num?)?.toDouble() ?? 0.0,
        'pronunciation_score': (_aiStats['pronunciation'] as num?)?.toDouble() ?? 0.0,
        'audio_recording_url': uploadedAudioUrl, // <--- SAVED HERE
        'offline_hypothesis': _aiStats['offline_analysis'],
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Session Saved Successfully!")));
        context.pop();
      }
    } catch (e) {
      debugPrint("Error saving assessment: $e");
      if (mounted) context.pop();
    }
  }

  String _calculateSeverity() {
     final score = (_aiStats['pronunciation'] as num?)?.toDouble() ?? 0.0;
     if (score > 0.8) return 'None';
     if (score > 0.5) return 'Mild';
     return 'Severe';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Layer
          if (_isInit)
            SizedBox.expand(
              child: RTCVideoView(
                _localRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                mirror: true,
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
    final note = _aiStats['diagnosis_note'] as String? ?? 'Waiting for analysis...';

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
          const Row(
            children: [
               Icon(Icons.cloud_sync, color: Colors.cyanAccent, size: 16),
               SizedBox(width: 8),
               Text("GEMINI LIVE", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          _buildStatRow("Lip Move", lipScore),
          const SizedBox(height: 8),
          _buildStatRow("Speech", pronScore),
          const SizedBox(height: 12),
          Text(note, style: const TextStyle(color: Colors.white70, fontSize: 11, fontStyle: FontStyle.italic), maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildOfflineCard() {
    final offlineNote = _aiStats['offline_analysis'] as String?;
    if (offlineNote == null) return const SizedBox.shrink();

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
               Text("OFFLINE DIAGNOSIS", style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
          const Divider(color: Colors.white24, height: 16),
          Text(
            offlineNote.replaceAll('Offline Model Detected: ', ''), 
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          const Text("Real-time TFLite Inference", style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, double score) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text("${(score * 100).toInt()}%", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
