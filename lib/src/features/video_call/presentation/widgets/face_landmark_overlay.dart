
import 'package:flutter/material.dart';

class FaceLandmarkOverlay extends StatelessWidget {
  final List<dynamic> landmarks;
  final double lipGap;

  const FaceLandmarkOverlay({
    super.key, 
    required this.landmarks,
    this.lipGap = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: FaceLandmarkPainter(landmarks, lipGap),
        child: Container(),
      ),
    );
  }
}

class FaceLandmarkPainter extends CustomPainter {
  final List<dynamic> landmarks;
  final double lipGap;

  FaceLandmarkPainter(this.landmarks, this.lipGap);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = Colors.orangeAccent.withOpacity(0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 1. Draw High-Frequency Mesh if LipGap is active (Audio-Driven)
    if (lipGap > 0) {
       _drawAudioDrivenMesh(canvas, size, lipGap);
    }

    // 2. Draw standard landmarks (Synced from AI results)
    if (landmarks.isNotEmpty) {
      final path = Path();
      for (int i = 0; i < landmarks.length; i++) {
        final point = landmarks[i];
        if (point is Map) {
          final x = (point['x'] as num).toDouble() * size.width;
          final y = (point['y'] as num).toDouble() * size.height;
          
          canvas.drawCircle(Offset(x, y), 2.5, paint);
          canvas.drawCircle(Offset(x, y), 1.0, dotPaint);

          if (i == 0) path.moveTo(x, y);
          else path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, linePaint);
    }
  }

  void _drawAudioDrivenMesh(Canvas canvas, Size size, double gap) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = 60.0 + (gap * 30);
    
    final meshPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.4)
      ..strokeWidth = 1.0;

    // Draw a "Dotted Star" mesh for the mouth area
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30) * (3.14159 / 180);
      final x = centerX + radius * 0.8 * (i % 2 == 0 ? 1 : 0.6) * (1 + gap * 0.5) * (i > 3 && i < 9 ? -1 : 1).abs(); // Simplified distortion
      
      // Use math to simulate mouth shape
      final dx = centerX + (radius * 1.2) * (i < 3 || i > 9 ? 1 : 0.5) * (i > 6 ? -1 : 1);
      final dy = centerY + (radius * 0.6) * (i % 6 < 3 ? 1 : -1) * (1 + gap);

      canvas.drawCircle(Offset(dx, dy), 3, meshPaint);
      canvas.drawCircle(Offset(dx, dy), 1.5, Paint()..color = Colors.white);
      
      // Connecting lines
      if (i > 0) {
        canvas.drawLine(Offset(centerX, centerY), Offset(dx, dy), Paint()..color = Colors.cyan.withOpacity(0.1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant FaceLandmarkPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks || oldDelegate.lipGap != lipGap;
  }
}
