import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_therapy/src/features/ai/services/gemini_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    await _localRenderer.initialize();
    await _startCamera();
    _startAnalysisLoop();
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
      setState(() {
        _localStream = stream;
        _localRenderer.srcObject = _localStream;
        _isInit = true;
      });
    } catch (e) {
      debugPrint("Error opening camera: $e");
    }
  }

  void _startAnalysisLoop() {
    // Poll the "AI" every 2 seconds
    _analysisTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) return;
      
      // Simulate "talking" based on audio track status (very rough proxy)
      final isAudioEnabled = _localStream?.getAudioTracks().firstOrNull?.enabled ?? false;
      
      final result = await GeminiService().analyzeSession(
        isSpeaking: isAudioEnabled, // In real app, check volume level
        isFaceVisible: true, // In real app, check face detection
      );

      if (mounted) {
        setState(() => _aiStats = result);
      }
    });
  }


  @override
  void dispose() {
    _analysisTimer?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _localRenderer.dispose();
    super.dispose();
  }
  
  Future<void> _endSession() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Save results
      await FirebaseFirestore.instance.collection('assessments').add({
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'disorder': 'General Therapy', // Could be dynamic based on widget.exerciseTitle
        'severity': _calculateSeverity(),
        'avg_lip_openness': (_aiStats['lipAccuracy'] as num?)?.toDouble() ?? 0.0,
        'pronunciation_score': (_aiStats['pronunciation'] as num?)?.toDouble() ?? 0.0,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Session Saved!")));
        context.pop();
      }
    } else {
       if(mounted) context.pop();
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
    final lipScore = ((_aiStats['lipAccuracy'] as num?) ?? 0.0).toDouble();
    final pronScore = ((_aiStats['pronunciation'] as num?) ?? 0.0).toDouble();
    
    return Container(
      width: 140,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
               Icon(Icons.auto_awesome, color: Colors.cyanAccent, size: 16),
               SizedBox(width: 8),
               Text("Gemini AI", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(color: Colors.white24),
          const SizedBox(height: 8),
          _buildStatRow("Lip Move", lipScore),
          const SizedBox(height: 8),
          _buildStatRow("Speech", pronScore),
        ],
      ),
    ).animate().slideX(begin: 1.0, end: 0.0, curve: Curves.easeOutBack);
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
