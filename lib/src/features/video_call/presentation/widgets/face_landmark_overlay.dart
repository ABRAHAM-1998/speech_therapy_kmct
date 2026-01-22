
import 'package:flutter/material.dart';

class FaceLandmarkOverlay extends StatelessWidget {
  final List<dynamic> landmarks;

  const FaceLandmarkOverlay({super.key, required this.landmarks});

  @override
  Widget build(BuildContext context) {
    if (landmarks.isEmpty) return const SizedBox();

    return IgnorePointer(
      child: CustomPaint(
        painter: FaceLandmarkPainter(landmarks),
        child: Container(),
      ),
    );
  }
}

class FaceLandmarkPainter extends CustomPainter {
  final List<dynamic> landmarks;

  FaceLandmarkPainter(this.landmarks);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final connectionPaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    
    for (int i = 0; i < landmarks.length; i++) {
      final point = landmarks[i];
      if (point is Map) {
         final x = (point['x'] as num).toDouble() * size.width;
         final y = (point['y'] as num).toDouble() * size.height;
         
         // Draw point
         canvas.drawCircle(Offset(x, y), 3.0, paint);
         
         // Build path for connection
         if (i == 0) {
           path.moveTo(x, y);
         } else {
           path.lineTo(x, y);
         }
      }
    }
    
    if (landmarks.isNotEmpty) {
       path.close();
       canvas.drawPath(path, connectionPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceLandmarkPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks;
  }
}
