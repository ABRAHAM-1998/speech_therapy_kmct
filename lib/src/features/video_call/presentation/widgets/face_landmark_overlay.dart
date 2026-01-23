
import 'package:flutter/material.dart';

class FaceLandmarkOverlay extends StatelessWidget {
  final List<dynamic> contour;
  final List<dynamic> measurementPoints;
  final double lipGap;
  final double verticalDistance;
  final double lipOpennessMM;
  final double imageWidth;
  final double imageHeight;
  final int rotation;
  final bool isFrontCamera;

  const FaceLandmarkOverlay({
    super.key, 
    required this.contour,
    this.measurementPoints = const [],
    this.lipGap = 0.0,
    this.verticalDistance = 0.0,
    this.lipOpennessMM = 0.0,
    this.imageWidth = 0.0,
    this.imageHeight = 0.0,
    this.rotation = 0,
    this.isFrontCamera = false,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: FaceLandmarkPainter(
          contour: contour, 
          measurePoints: measurementPoints,
          lipGap: lipGap, 
          verticalDistance: verticalDistance,
          lipOpennessMM: lipOpennessMM,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          rotation: rotation,
          isFrontCamera: isFrontCamera,
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
  final double lipOpennessMM;
  final double imageWidth;
  final double imageHeight;
  final int rotation;
  final bool isFrontCamera;

  FaceLandmarkPainter({
    required this.contour, 
    required this.measurePoints,
    required this.lipGap, 
    required this.verticalDistance,
    required this.lipOpennessMM,
    required this.imageWidth,
    required this.imageHeight,
    required this.rotation,
    required this.isFrontCamera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (imageWidth == 0 || imageHeight == 0) return;

    final linePaint = Paint()
      ..color = Colors.orangeAccent.withValues(alpha: 0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // 1. Calculate Scale & Offset (BoxFit.cover logic)
    // Rotate dimensions if needed
    final bool isRotated = rotation == 90 || rotation == 270;
    final double wIn = isRotated ? imageHeight : imageWidth;
    final double hIn = isRotated ? imageWidth : imageHeight;

    final double scaleX = size.width / wIn;
    final double scaleY = size.height / hIn;
    final double scale = (scaleX > scaleY) ? scaleX : scaleY;

    final double offsetX = (size.width - wIn * scale) / 2;
    final double offsetY = (size.height - hIn * scale) / 2;

    Offset transform(Map point) {
      final double x = (point['x'] as num).toDouble();
      final double y = (point['y'] as num).toDouble();

      // Apply Scale & Content Offset
      double tx = x * scale + offsetX;
      double ty = y * scale + offsetY;

      // Apply Mirroring
      if (isFrontCamera) {
         tx = size.width - tx;
      }
      
      return Offset(tx, ty);
    }

    // 2. Draw Lip Contour
    if (contour.isNotEmpty) {
      final path = Path();
      for (int i = 0; i < contour.length; i++) {
        final point = contour[i];
        if (point is Map) {
          final p = transform(point);
          
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
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
       
       final p1 = transform(p1m);
       final p2 = transform(p2m);

       final measurePaint = Paint()
          ..color = Colors.cyanAccent
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke;

       canvas.drawLine(p1, p2, measurePaint);
       canvas.drawLine(p1.translate(-10, 0), p1.translate(10, 0), measurePaint);
       canvas.drawLine(p2.translate(-10, 0), p2.translate(10, 0), measurePaint);

       // Pixel Text Background
       final textString = lipOpennessMM > 0 
           ? "${lipOpennessMM.toStringAsFixed(1)} mm" 
           : "${verticalDistance.toStringAsFixed(1)} px";

       final textSpan = TextSpan(
          text: textString,
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
       
       // Ensure label stays on screen
       final safeDx = labelOffset.dx.clamp(0.0, size.width - textPainter.width);
       final safeDy = labelOffset.dy.clamp(0.0, size.height - textPainter.height);

       canvas.drawRect(
          Rect.fromLTWH(safeDx - 4, safeDy - 2, textPainter.width + 8, textPainter.height + 4),
          Paint()..color = Colors.black45
       );
       textPainter.paint(canvas, Offset(safeDx, safeDy));
    }
  }

  @override
  bool shouldRepaint(covariant FaceLandmarkPainter oldDelegate) {
    return oldDelegate.contour != contour || 
           oldDelegate.measurePoints != measurePoints || 
           oldDelegate.lipGap != lipGap ||
           oldDelegate.verticalDistance != verticalDistance ||
           oldDelegate.lipOpennessMM != lipOpennessMM ||
           oldDelegate.imageWidth != imageWidth ||
           oldDelegate.imageHeight != imageHeight ||
           oldDelegate.rotation != rotation;
  }
}
