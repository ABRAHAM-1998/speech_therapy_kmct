import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

class PitchPracticeScreen extends StatefulWidget {
  const PitchPracticeScreen({super.key});

  @override
  State<PitchPracticeScreen> createState() => _PitchPracticeScreenState();
}

class _PitchPracticeScreenState extends State<PitchPracticeScreen> with TickerProviderStateMixin {
  bool _isListening = false;
  double _currentPitch = 0.5; // 0.0 to 1.0 (Low to High)
  double _targetPitch = 0.5;
  int _score = 0;
  Timer? _timer;

  late final AnimationController _birdController;

  @override
  void initState() {
    super.initState();
    _birdController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _generateTarget();
  }
  
  void _generateTarget() {
     setState(() {
       _targetPitch = (0.2 + (DateTime.now().millisecond % 60) / 100).clamp(0.2, 0.8);
     });
  }

  void _toggleGame() {
    if (_isListening) {
      _stopGame();
    } else {
      _startGame();
    }
  }

  void _startGame() {
    setState(() => _isListening = true);
    // Simulate Microphone Input
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
       // In a real app, use `flutter_audio_capture` and FFT to get pitch.
       // Here we simulate pitch changes based on "touch" or Random for demo.
       // actually, let's make it interactive with a slider for now, or just random simulation
       // simulating "Voice" fluctuation
       
       double jitter = (DateTime.now().millisecond % 10 - 5) / 500.0;
       setState(() {
          _currentPitch = (_currentPitch + jitter).clamp(0.0, 1.0);
          
          if ((_currentPitch - _targetPitch).abs() < 0.1) {
             _score += 1;
             if (_score % 50 == 0) _generateTarget();
          }
       });
    });
  }

  void _stopGame() {
    _timer?.cancel();
    setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _birdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.lightBlue.shade100,
      appBar: AppBar(title: const Text("Pitch Control Game"), backgroundColor: Colors.transparent),
      body: Stack(
        children: [
          // Clouds
          Positioned(top: 50, left: 50, child: const Icon(Icons.cloud, color: Colors.white, size: 60).animate().slideX(duration: 10.seconds)),
          Positioned(top: 100, right: 50, child: const Icon(Icons.cloud, color: Colors.white, size: 80).animate().slideX(duration: 15.seconds, begin: 1, end: -1)),

          Column(
            children: [
               const SizedBox(height: 20),
               Text("Score: $_score", style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
               Expanded(
                 child: Row(
                   children: [
                      // Pitch Indicator
                      Container(
                        width: 50,
                        margin: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(25)
                        ),
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: _currentPitch,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(25)
                            ),
                          ),
                        ),
                      ),
                      
                      // Game Area
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return Stack(
                              children: [
                                // Target Line
                                Positioned(
                                  top: constraints.maxHeight * (1 - _targetPitch) - 20,
                                  left: 0,
                                  right: 0,
                                  child: Container(height: 5, color: Colors.amberAccent, child: const Center(child: Text("TARGET PITCH", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
                                ),
                                
                                // Player (Bird)
                                AnimatedPositioned(
                                  duration: const Duration(milliseconds: 100),
                                  top: constraints.maxHeight * (1 - _currentPitch) - 30, // Invert Y
                                  left: constraints.maxWidth / 2 - 30,
                                  child: const Icon(Icons.flutter_dash, size: 60, color: Colors.blueAccent),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                   ],
                 ),
               ),
               
               // Controls
               Container(
                 padding: const EdgeInsets.all(32),
                 color: Colors.white,
                 child: Column(
                   children: [
                      const Text("Make high sounds to fly up, low sounds to fly down!", style: TextStyle(fontSize: 16)),
                      const SizedBox(height: 20),
                      // Slider to "Simulate" Voice if mic not available in demo
                      Slider(
                        value: _currentPitch, 
                        onChanged: _isListening ? (val) => setState(() => _currentPitch = val) : null,
                        label: "Voice Pitch Simulator",
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _toggleGame,
                        icon: Icon(_isListening ? Icons.pause : Icons.mic),
                        label: Text(_isListening ? "Pause" : "Start Pitch Game"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
                          backgroundColor: _isListening ? Colors.orange : Colors.blue,
                          foregroundColor: Colors.white
                        ),
                      )
                   ],
                 ),
               ),
            ],
          ),
        ],
      ),
    );
  }
}
