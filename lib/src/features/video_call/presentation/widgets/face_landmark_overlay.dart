
import 'package:flutter/material.dart';

class FaceLandmarkOverlay extends StatelessWidget {
  final List<dynamic> contour;
  final List<dynamic> measurementPoints;
  final double lipGap;
  final double verticalDistance;

  const FaceLandmarkOverlay({
    super.key, 
    required this.contour,
    this.measurementPoints = const [],
    this.lipGap = 0.0,
    this.verticalDistance = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: FaceLandmarkPainter(
          contour: contour, 
          measurePoints: measurementPoints,
          lipGap: lipGap, 
          verticalDistance: verticalDistance
        ),
        child: Container(),
      ),
    );
  }
}

class FaceLandmarkPainter extends CustomPainter {
  final List<dynamic> contour;
  final List<dynamic> measurePoints;
  final double lipGap;
  final double verticalDistance;

  FaceLandmarkPainter({
    required this.contour, 
    required this.measurePoints,
    required this.lipGap, 
    required this.verticalDistance
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 1. Draw High-Frequency Mesh (Audio Fallback)
    if (lipGap > 0 && contour.isEmpty) {
       _drawAudioDrivenMesh(canvas, size, lipGap);
    }

    // 2. Draw Lip Contour
    if (contour.isNotEmpty) {
      final path = Path();
      for (int i = 0; i < contour.length; i++) {
        final point = contour[i];
        if (point is Map) {
          final x = (point['x'] as num).toDouble() * size.width;
          final y = (point['y'] as num).toDouble() * size.height;
          
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
      }
      path.close();
      canvas.drawPath(path, linePaint);
    }

    // 3. Draw Measurement Line
    if (measurePoints.length >= 2) {
       final p1m = measurePoints[0];
       final p2m = measurePoints[1];
       
       final p1 = Offset((p1m['x'] as num).toDouble() * size.width, (p1m['y'] as num).toDouble() * size.height);
       final p2 = Offset((p2m['x'] as num).toDouble() * size.width, (p2m['y'] as num).toDouble() * size.height);

       final measurePaint = Paint()
          ..color = Colors.cyanAccent
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

       canvas.drawLine(p1, p2, measurePaint);
       canvas.drawLine(p1.translate(-10, 0), p1.translate(10, 0), measurePaint);
       canvas.drawLine(p2.translate(-10, 0), p2.translate(10, 0), measurePaint);

       // Pixel Text Background
       final textSpan = TextSpan(
          text: "${verticalDistance.toStringAsFixed(1)} PX",
          style: TextStyle(
            color: Colors.cyanAccent, 
            fontSize: 14, 
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black.withValues(alpha: 0.6),
          ),
       );
       final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
       );
       textPainter.layout();
       
       final labelOffset = Offset((p1.dx + p2.dx)/2 + 20, (p1.dy + p2.dy)/2 - (textPainter.height / 2));
       canvas.drawRect(
          Rect.fromLTWH(labelOffset.dx - 4, labelOffset.dy - 2, textPainter.width + 8, textPainter.height + 4),
          Paint()..color = Colors.black45
       );
       textPainter.paint(canvas, labelOffset);
    }
  }



  void _drawAudioDrivenMesh(Canvas canvas, Size size, double gap) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final radius = 60.0 + (gap * 30);
    
    final meshPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.2)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // Draw a "Scanning HUD" instead of dots
    canvas.drawRect(
      Rect.fromCenter(center: Offset(centerX, centerY), width: radius * 2.5, height: radius * 1.5),
      meshPaint
    );
    
    // Horizontal scanning bars
    for (int i = 0; i < 3; i++) {
       double y = centerY - (radius * 0.5) + (i * radius * 0.5);
       canvas.drawLine(
         Offset(centerX - (radius * 1.2), y),
         Offset(centerX + (radius * 1.2), y),
         meshPaint..color = Colors.cyanAccent.withValues(alpha: 0.1)
       );
    }
  }


  @override
  bool shouldRepaint(covariant FaceLandmarkPainter oldDelegate) {
    return oldDelegate.contour != contour || 
           oldDelegate.measurePoints != measurePoints || 
           oldDelegate.lipGap != lipGap ||
           oldDelegate.verticalDistance != verticalDistance;
  }

}
