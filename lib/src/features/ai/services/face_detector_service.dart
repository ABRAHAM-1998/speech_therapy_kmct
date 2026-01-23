import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorService {
  static final FaceDetectorService _instance = FaceDetectorService._internal();
  factory FaceDetectorService() => _instance;
  FaceDetectorService._internal();

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _isProcessing = false;

  void dispose() {
    _faceDetector.close();
  }

  Future<FaceAnalysisResult?> processFile(File imageFile) async {
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.first;
      
      final bytes = await imageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();
      final image = frameInfo.image;
      
      return _analyzeFace(
        face, 
        Size(image.width.toDouble(), image.height.toDouble()), 
        0 
      );
    } catch (e) {
      debugPrint("FaceDetectorService (File) Error: $e");
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  Future<FaceAnalysisResult?> processImage(CameraImage image, CameraDescription camera) async {
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      final inputImage = _inputImageFromCameraImage(image, camera);
      if (inputImage == null) return null;

      final faces = await _faceDetector.processImage(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.first;
      return _analyzeFace(
        face, 
        Size(image.width.toDouble(), image.height.toDouble()), 
        inputImage.metadata?.rotation.rawValue ?? 0
      );
    } catch (e) {
      debugPrint("FaceDetectorService Error: $e");
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  FaceAnalysisResult _analyzeFace(Face face, Size imageSize, int rotation) {
      // Calculate Lip Openness using Contours
      final upperLipBottom = face.contours[FaceContourType.upperLipBottom];
      final lowerLipTop = face.contours[FaceContourType.lowerLipTop];
      final upperLipTop = face.contours[FaceContourType.upperLipTop];
      final lowerLipBottom = face.contours[FaceContourType.lowerLipBottom];

      // Eyes for distance normalization
      final leftEye = face.landmarks[FaceLandmarkType.leftEye];
      final rightEye = face.landmarks[FaceLandmarkType.rightEye];

      double lipOpenness = 0.0;
      double verticalDistance = 0.0;
      double lipOpennessMM = 0.0;
      List<Map<String, double>> lipLandmarks = [];
      List<Map<String, double>> fullContour = [];

      // Calculate Inter-Pupillary Distance (IPD)
      double eyeDistance = 0.0;
      if (leftEye != null && rightEye != null) {
         // Euclidean distance
         eyeDistance = sqrt(pow(leftEye.position.x - rightEye.position.x, 2) + pow(leftEye.position.y - rightEye.position.y, 2));
      }

      if (upperLipBottom != null && lowerLipTop != null) {
         // Calculate average Y for upper lip bottom edge
         final double avgUpperY = upperLipBottom.points.map((p) => p.y.toDouble()).reduce((a,b)=>a+b) / upperLipBottom.points.length;
         // Calculate average Y for lower lip top edge
         final double avgLowerY = lowerLipTop.points.map((p) => p.y.toDouble()).reduce((a,b)=>a+b) / lowerLipTop.points.length;
         
         verticalDistance = (avgUpperY - avgLowerY).abs();

         // Normalize by face height (legacy relative metric)
         if (face.boundingBox.height > 0) {
            lipOpenness = (verticalDistance / face.boundingBox.height);
         }

         // Normalize by Eye Distance (Absolute MM approximation)
         // Avg IPD is ~63mm. 
         // Scale Factor = 63.0 / eyeDistanceInPixels
         if (eyeDistance > 10) { // Avoid div/0
            final double scaleToMM = 63.0 / eyeDistance;
            lipOpennessMM = verticalDistance * scaleToMM;
         }

         // Map landmarks for sync (minimal set)
         if (upperLipBottom.points.isNotEmpty) {
           final p = upperLipBottom.points[upperLipBottom.points.length ~/ 2];
           lipLandmarks.add({'x': p.x.toDouble(), 'y': p.y.toDouble()});
         }
         if (lowerLipTop.points.isNotEmpty) {
           final p = lowerLipTop.points[lowerLipTop.points.length ~/ 2];
           lipLandmarks.add({'x': p.x.toDouble(), 'y': p.y.toDouble()});
         }

         // Map full contours for local high-fidelity overlay
         // We keep raw coordinates here; scaling happens in UI Painter
         void addContour(FaceContour? contour) {
            if (contour == null) return;
            for (var p in contour.points) {
               fullContour.add({'x': p.x.toDouble(), 'y': p.y.toDouble()});
            }
         }
         
         addContour(upperLipTop);
         addContour(upperLipBottom);
         addContour(lowerLipTop);
         addContour(lowerLipBottom);
      }

      return FaceAnalysisResult(
        lipOpenness: lipOpenness,
        verticalDistance: verticalDistance,
        lipOpennessMM: lipOpennessMM,
        lipLandmarks: lipLandmarks,
        fullContour: fullContour,
        faceVisible: true,
        imageWidth: imageSize.width,
        imageHeight: imageSize.height,
        rotation: rotation,
      );
  }

  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    final sensorOrientation = camera.sensorOrientation;
    final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ?? InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ?? InputImageFormat.nv21;

    if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) {
      final allBytes = BytesBuilder();
      for (final plane in image.planes) {
        allBytes.add(plane.bytes);
      }
      final bytes = allBytes.takeBytes();

      final metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(bytes: bytes, metadata: metadata);
    }

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
}

class FaceAnalysisResult {
  final double lipOpenness;
  final double verticalDistance;
  final double lipOpennessMM; // Distance-invariant metric
  final List<Map<String, double>> lipLandmarks; // Raw Coords
  final List<Map<String, double>> fullContour; // Raw Coords
  final bool faceVisible;
  final double imageWidth;
  final double imageHeight;
  final int rotation;

  FaceAnalysisResult({
    required this.lipOpenness,
    required this.verticalDistance,
    this.lipOpennessMM = 0.0,
    required this.lipLandmarks,
    required this.fullContour,
    required this.faceVisible,
    this.imageWidth = 0.0,
    this.imageHeight = 0.0,
    this.rotation = 0,
  });
}


