import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoicePracticeScreen extends StatefulWidget {
  const VoicePracticeScreen({super.key});

  @override
  State<VoicePracticeScreen> createState() => _VoicePracticeScreenState();
}

class _VoicePracticeScreenState extends State<VoicePracticeScreen> {
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  double _soundLevel = 0.0;
  double _ballPosition = 0.0; // -1.0 (bottom) to 1.0 (top)
  
  // Game Logic
  int _score = 0;
  bool _isInZone = false;
  Timer? _gameLoop;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  void _initSpeech() async {
    await _speechToText.initialize();
    setState(() {});
  }

  void _startPractice() async {
    if (_isListening) {
      await _speechToText.stop();
      _gameLoop?.cancel();
      setState(() {
         _isListening = false;
         _soundLevel = 0.0;
         _ballPosition = -1.0;
      });
    } else {
      await _speechToText.listen(
        onSoundLevelChange: (level) {
          // Level is approx 0 to 10.
          if (mounted) {
             setState(() => _soundLevel = level);
          }
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 5), // Keep listening even if silence briefly
        cancelOnError: true,
        partialResults: true,
        onResult: (result) {}, // We only care about sound level
      );
      
      setState(() => _isListening = true);
      _startGameLoop();
    }
  }

  void _startGameLoop() {
    _gameLoop = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) return;
      
      setState(() {
        // Physics: Ball is pushed up by sound, pulled down by gravity
        // Target: Keep ball in range [0.2, 0.6]
        
        // Normalize sound force (0 to 1.5 roughly)
        double force = (_soundLevel / 5.0).clamp(0.0, 2.0);
        double gravity = 0.1;
        
        // Simple smoothing
        double targetPos = -1.0 + force; 
        _ballPosition += (targetPos - _ballPosition) * 0.1;
        
        // Clamp
        if (_ballPosition > 1.0) _ballPosition = 1.0;
        if (_ballPosition < -1.0) _ballPosition = -1.0;

        // Scoring
        // Target Zone: 0.0 to 0.5 (Middle-Upper)
        if (_ballPosition >= 0.0 && _ballPosition <= 0.5) {
          _isInZone = true;
          _score += 1; // 20 points per second
        } else {
          _isInZone = false;
        }
      });
    });
  }

  @override
  void dispose() {
    _speechToText.cancel();
    _gameLoop?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Breath & Control')),
      body: Column(
        children: [
          // Info Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.teal.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Target Zone", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text("Keep the ball in the green box", style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
                Text("Score: ${(_score / 20).toStringAsFixed(1)}s", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
          ),
          
          Expanded(
            child: Row(
              children: [
                // Game Area
                Expanded(
                  child: Stack(
                    
                    children: [
                      // Background
                      Container(color: Colors.grey[100]),
                      
                      // Target Zone
                      Positioned(
                        top: MediaQuery.of(context).size.height * 0.25, // Approx middle top
                        bottom: MediaQuery.of(context).size.height * 0.45,
                        left: 0, 
                        right: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            border: Border.symmetric(horizontal: BorderSide(color: Colors.green.withValues(alpha: 0.5), width: 2)),
                          ),
                          child: Center(
                            child: Text(
                              _isInZone ? "PERFECT!" : "HOLD HERE",
                              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, letterSpacing: 2),
                            ),
                          ),
                        ),
                      ),
                      
                      // The Ball
                      Align(
                        alignment: Alignment(0, -_ballPosition), // Inverted Y for Align widget logic
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: _isInZone ? Colors.green : Colors.redAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: (_isInZone ? Colors.green : Colors.redAccent).withValues(alpha: 0.4), blurRadius: 20, spreadRadius: 5)
                            ]
                          ),
                          child: const Icon(Icons.mic, color: Colors.white),
                        ).animate(target: _isInZone ? 1 : 0).scale(begin: const Offset(1,1), end: const Offset(1.2,1.2)),
                      ),
                    ],
                  ),
                ),
                
                 // Level Indicator Bar
                Container(
                  width: 30,
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                     color: Colors.grey[300],
                     borderRadius: BorderRadius.circular(15)
                  ),
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: (_soundLevel / 10).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                         borderRadius: BorderRadius.circular(15)
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          
          // Controls
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _startPractice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isListening ? Colors.red : Colors.teal,
                ),
                icon: Icon(_isListening ? Icons.stop : Icons.play_arrow),
                label: Text(_isListening ? "STOP PRACTICE" : "START PRACTICE"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
