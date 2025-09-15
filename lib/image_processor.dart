// ----------- IMPORTS (must be at the very top) -----------
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'processing/angle_utils.dart';
import 'utils/file_utils.dart';

// --------- Data classes for processing results ---------
class BoundaryCandidate {
  final List<Offset> boundary;
  final String method;
  final double score;
  final double confidence;
  BoundaryCandidate({
    required this.boundary,
    required this.method,
    required this.score,
    required this.confidence,
  });
}

class ProcessedImageData {
  final List<Offset> boundary;
  final BaselineData baseline;
  final Offset leftContact;
  final Offset rightContact;
  final double leftAngle;
  final double rightAngle;
  final double avgAngle;
  final double bestAngle;
  final double qualityScore;

  ProcessedImageData({
    required this.boundary,
    required this.baseline,
    required this.leftContact,
    required this.rightContact,
    required this.leftAngle,
    required this.rightAngle,
    required this.avgAngle,
    required this.bestAngle,
    required this.qualityScore,
  });
}

class BaselineData {
  final Offset startPoint;
  final Offset endPoint;
  final double score;
  final String method;

  BaselineData({
    required this.startPoint,
    required this.endPoint,
    required this.score,
    required this.method,
  });

  double get slope => (endPoint.dx - startPoint.dx).abs() < 1e-10
      ? 0.0
      : (endPoint.dy - startPoint.dy) / (endPoint.dx - startPoint.dx + 1e-12);
  double get intercept => startPoint.dy - slope * startPoint.dx;
}

class ContactPointPair {
  final Offset left;
  final Offset right;
  ContactPointPair({required this.left, required this.right});
}

// Helper function to create empty result when processing fails
ProcessedImageData _createEmptyResult() {
  return ProcessedImageData(
    boundary: [],
    baseline: BaselineData(
      startPoint: Offset.zero,
      endPoint: Offset.zero,
      score: 0.0,
      method: "none",
    ),
    leftContact: Offset.zero,
    rightContact: Offset.zero,
    leftAngle: 0.0,
    rightAngle: 0.0,
    avgAngle: 0.0,
    bestAngle: 0.0,
    qualityScore: 0.0,
  );
}

// --------- Helper functions ---------
Future<Uint8List> convertImageToPixels(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (byteData == null) {
    throw Exception('Failed to convert image to bytes');
  }
  return byteData.buffer.asUint8List();
}

Future<ProcessedImage> processImage(ui.Image image) async {
  try {
    // Convert image to bytes
    final imageData = await convertImageToPixels(image);
    
    // Create a temporary file to save the image
    final tempFile = await tempFileFromPixels(imageData);
    
    // Decode image from file to ensure proper loading
    final grayImage = cv.imread(tempFile.path, flags: cv.IMREAD_GRAYSCALE);
    if (grayImage == null) {
      print('Failed to load image from ${tempFile.path}');
      throw Exception('Failed to decode image to grayscale');
    }
    print('Loaded grayscale image size: ${grayImage.rows}x${grayImage.cols}');

    try {
      // Create CLAHE object with default parameters
      final clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
      if (clahe == null) {
        grayImage.release();
        throw Exception('Failed to create CLAHE');
      }

      // Apply CLAHE
      final enhanced = clahe.apply(grayImage);
      if (enhanced == null) {
        grayImage.release();
        throw Exception('CLAHE enhancement failed');
      }
      print('CLAHE output size: ${enhanced.rows}x${enhanced.cols}');

      try {
        // Apply median blur
        print('Applying median blur...');
        final blurred = cv.medianBlur(enhanced, 5);
        if (blurred == null) {
          enhanced.release();
          grayImage.release();
          throw Exception('Median blur failed');
        }
        print('Median blur complete. Output size: ${blurred.rows}x${blurred.cols}');

        try {
          // Process the blurred image for boundary detection
          final boundaries = await detectBoundaryThresholding(blurred);
          
          // Process the best boundary to find the contact angle
          if (boundaries.isEmpty) {
            return createEmptyResult();
          }

          // Sort boundaries by score
          boundaries.sort((a, b) => b.score.compareTo(a.score));
          final bestBoundary = boundaries.first;

          // Calculate baseline and contact points
          final baseline = await findBaselineFitted(bestBoundary.boundary);
          final contactPoints = findContactPoints(bestBoundary.boundary, baseline);
          
          // Calculate angles
          final leftAngle = calculateContactAngle(contactPoints.left, baseline);
          final rightAngle = calculateContactAngle(contactPoints.right, baseline);
          
          return ProcessedImage(
            boundary: bestBoundary.boundary,
            baseline: baseline,
            leftContact: contactPoints.left,
            rightContact: contactPoints.right,
            leftAngle: leftAngle,
            rightAngle: rightAngle,
            avgAngle: (leftAngle + rightAngle) / 2,
            bestAngle: leftAngle > rightAngle ? leftAngle : rightAngle,
            qualityScore: bestBoundary.score,
          );
        } finally {
          blurred.release();
        }
      } finally {
        enhanced.release();
      }
    } finally {
      grayImage.release();
    }
  } catch (e) {
    print('Error in image processing: $e');
    return createEmptyResult();
  }

Future<File> tempFileFromPixels(Uint8List pixels) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/temp_image.png');
  await tempFile.writeAsBytes(pixels);
  return tempFile;
}

Future<List<BoundaryCandidate>> contoursFromBinary(
    cv.Mat bin, int width, int height, String method) async {
  final findResult = cv.findContours(bin, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  if (findResult == null) {
    throw Exception('Failed to find contours in binary image');
  }
  
  final contours = findResult.$1;
  if (contours == null) {
    throw Exception('No contours found in binary image');
  }
  
  final out = <BoundaryCandidate>[];
  
  try {
    for (final contour in contours) {
      if (contour == null || contour.isEmpty) continue;
      
      final List<Offset> b = [
        for (int i = 0; i < contour.length; i++)
          Offset(contour[i].x.toDouble(), contour[i].y.toDouble())
      ];
      
      if (b.length > 12) {
        out.add(BoundaryCandidate(
          boundary: b,
          method: method,
          score: scoreBoundaryGeneric(b, width, height),
          confidence: 0.0,
        ));
      }
    }
    return out;
  } finally {
    // Clean up any resources from findContours if needed
    if (findResult.$2 != null) {
      findResult.$2.release();
    }
  }
}

double calculatePolygonArea(List<Offset> points) {
  if (points.length < 3) return 0.0;
  double area = 0.0;
  for (int i = 0; i < points.length; i++) {
    final j = (i + 1) % points.length;
    area += points[i].dx * points[j].dy - points[j].dx * points[i].dy;
  }
  return area.abs() / 2.0;
}

double scoreBoundaryGeneric(List<Offset> b, int width, int height) {
  double area = calculatePolygonArea(b);
  double perimeter = 0.0;
  for (int i = 0; i < b.length; i++) perimeter += (b[i] - b[(i + 1) % b.length]).distance;
  double circularity = perimeter == 0 ? 0 : (4 * pi * area) / (perimeter * perimeter);
  return (0.8 * circularity + 0.2).clamp(0.0, 1.0);
}

// --------- CORE PROCESSING ROUTINES (top-level!) ----------

Future<ProcessedImageData> processDropletImage(ui.Image image) async {
  try {
    final imageData = await convertImageToPixels(image);
    if (imageData == null || imageData.isEmpty) {
      throw Exception('Failed to convert image to pixels');
    }

    print('Image size: ${image.width}x${image.height}, bytes: ${imageData.length}');
    
    // Create a temporary file to save the image
    final tempFile = await tempFileFromPixels(imageData);
    
    // Decode image from file to ensure proper loading
    final grayImage = cv.imread(tempFile.path, flags: cv.IMREAD_GRAYSCALE);
    if (grayImage == null) {
      print('Failed to load image from ${tempFile.path}');
      throw Exception('Failed to decode image to grayscale');
    }
    print('Loaded grayscale image size: ${grayImage.rows}x${grayImage.cols}');

    // Advanced Pre-processing: CLAHE and denoising
    final clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
    if (clahe == null) {
      grayImage.release();
      throw Exception('Failed to create CLAHE');
    }
    
    try {
      final enhanced = clahe.apply(grayImage);
      print('CLAHE output size: ${enhanced?.rows ?? 0}x${enhanced?.cols ?? 0}');
      
      if (enhanced == null) {
        grayImage.release();
        throw Exception('CLAHE enhancement failed');
      }

      try {
        print('Applying median blur...');
        final blurred = cv.medianBlur(enhanced, 5);
        if (blurred == null) {
          enhanced.release();
          throw Exception('Median blur failed');
        }
        print('Median blur complete. Output size: ${blurred.rows}x${blurred.cols}');
        
        enhanced.release();
        
        // Process the blurred image for boundary detection
        final boundaries = await detectBoundaryThresholding(blurred);
        
        // Clean up resources
        blurred.release();
        
        return boundaries;
      } catch (e) {
        print('Median blur error: $e');
        enhanced.release();
        throw e;
      }
    } catch (e) {
      print('CLAHE error: $e');
      grayImage.release();
      throw e;
    }

    // Boundary Detection
    final boundaries = await detectBoundaryThresholding(blurred, image.width, image.height);
    
    // Clean up OpenCV resources
    grayImage.release();
    enhanced.release();
    blurred.release();

    if (boundaries.isEmpty) {
      return _createEmptyResult();
    }

    // Select the best candidate
    final bestBoundary = boundaries.reduce((a, b) => a.score > b.score ? a : b);

    // Baseline Detection (Advanced Fusion)
    final baseline = detectBaselineAdvanced(bestBoundary.boundary);

    // Subpixel contact point refinement
    final contacts = findContactPointsPrecise(bestBoundary.boundary, baseline);
    
    // Create normalized normal vectors for contact point refinement
    final leftVec = Offset(-baseline.slope, 1.0);
    final rightVec = Offset(baseline.slope, -1.0);
    final leftNormal = Offset(leftVec.dx / leftVec.distance, leftVec.dy / leftVec.distance);
    final rightNormal = Offset(rightVec.dx / rightVec.distance, rightVec.dy / rightVec.distance);

    final refinedLeftContact = subpixelRefineFromRGBA(
      rgba: imageData,
      width: image.width,
      height: image.height,
      approx: contacts.left,
      normal: leftNormal,
      samples: 25,
      spacing: 0.6,
    );

    final refinedRightContact = subpixelRefineFromRGBA(
      rgba: imageData,
      width: image.width,
      height: image.height,
      approx: contacts.right,
      normal: rightNormal,
      samples: 25,
      spacing: 0.6,
    );

    // Calculate angles
    final (leftAngle, rightAngle) = calculateContactAngleAdvanced(
      bestBoundary.boundary,
      ContactPointPair(left: refinedLeftContact, right: refinedRightContact),
      baseline
    );

    final avgAngle = (leftAngle + rightAngle) / 2.0;
    final bestAngle = (bestBoundary.boundary.first.dx < bestBoundary.boundary.last.dx) 
      ? leftAngle 
      : rightAngle;

    return ProcessedImageData(
      boundary: bestBoundary.boundary,
      baseline: baseline,
      leftContact: refinedLeftContact,
      rightContact: refinedRightContact,
      leftAngle: leftAngle,
      rightAngle: rightAngle,
      avgAngle: avgAngle,
      bestAngle: bestAngle,
      qualityScore: bestBoundary.score,
    );
  } catch (e) {
    print('Image processing error: $e');
    return _createEmptyResult();
  }
}

Future<List<BoundaryCandidate>> detectBoundaryThresholding(cv.Mat image) async {
  final candidates = <BoundaryCandidate>[];
  
  // Simple Otsu's thresholding
  final result = cv.threshold(image, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU);
  if (result == null) {
    throw Exception('Thresholding failed');
  }
  
  final otsu = result.$2;
  if (otsu == null) {
    throw Exception('No threshold result obtained');
  }
  
  candidates.addAll(await contoursFromBinary(otsu, image.rows, image.cols, "Otsu"));
  
  // Clean up
  otsu.release();
  
  return candidates;
}

BaselineData detectBaselineAdvanced(List<Offset> boundary) {
  if (boundary.isEmpty) {
    return BaselineData(startPoint: Offset.zero, endPoint: Offset.zero, score: 0.0, method: "none");
  }

  final sortedByY = List.of(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
  final maxY = sortedByY.first.dy;
  final contactThreshold = maxY - (maxY - sortedByY.last.dy) * 0.2;
  final contactPoints = boundary.where((p) => p.dy >= contactThreshold).toList();

  if (contactPoints.length < 3) {
    return detectBaseline(boundary);
  }
  
  // Fused approach - 1. RANSAC with slope prior
  final ransacLine = fitLineRANSACRefined(
    contactPoints,
    iterations: 600,
    inlierThresh: 2.0,
    slopePrior: 0.0,
    slopePriorWeight: 0.2,
  );

  final minX = boundary.map((p) => p.dx).reduce(min);
  final maxX = boundary.map((p) => p.dx).reduce(max);
  final ransacBaseline = BaselineData(
    startPoint: Offset(minX, ransacLine['m']! * minX + ransacLine['c']!),
    endPoint: Offset(maxX, ransacLine['m']! * maxX + ransacLine['c']!),
    score: ransacLine['inliers']!,
    method: "RANSAC",
  );

  return ransacBaseline;
}

BaselineData detectBaseline(List<Offset> boundary) {
  if (boundary.isEmpty) {
    return BaselineData(startPoint: Offset.zero, endPoint: Offset.zero, score: 0.0, method: "none");
  }

  final sorted = List.of(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
  final lowest = sorted.take(10).toList();
  
  double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
  for (final p in lowest) {
    sumX += p.dx;
    sumY += p.dy;
    sumXY += p.dx * p.dy;
    sumX2 += p.dx * p.dx;
  }
  final n = lowest.length;
  final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX + 1e-10);
  final intercept = (sumY - slope * sumX) / n;
  
  final minX = boundary.map((p) => p.dx).reduce(min);
  final maxX = boundary.map((p) => p.dx).reduce(max);
  
  return BaselineData(
    startPoint: Offset(minX, slope * minX + intercept),
    endPoint: Offset(maxX, slope * maxX + intercept),
    score: 1.0, // placeholder score
    method: "linear-fit",
  );
}

ContactPointPair findContactPointsPrecise(List<Offset> boundary, BaselineData baseline) {
  if (boundary.isEmpty) return ContactPointPair(left: Offset.zero, right: Offset.zero);
  final intersections = <Offset>[];
  for (int i = 0; i < boundary.length; i++) {
    final p1 = boundary[i], p2 = boundary[(i + 1) % boundary.length];
    final intersect = intersectSegmentWithBaseline(
        p1, p2, baseline.slope, baseline.intercept);
    if (intersect != null) intersections.add(intersect);
  }
  if (intersections.length >= 2) {
    intersections.sort((a, b) => a.dx.compareTo(b.dx));
    return ContactPointPair(left: intersections.first, right: intersections.last);
  }
  final fallback = List.of(boundary)..sort((a, b) => a.dx.compareTo(b.dx));
  return ContactPointPair(left: fallback.first, right: fallback.last);
}

(double, double) calculateContactAngleAdvanced(
    List<Offset> boundary, ContactPointPair contacts, BaselineData baseline) {
  final leftPt = contacts.left;
  final rightPt = contacts.right;

  // Fit a circle on the droplet's boundary above the baseline
  final topBoundary = boundary.where((p) => p.dy < baseline.startPoint.dy).toList();
  final circle = fitCircleKasa(topBoundary);

  double leftAngle = 0.0;
  double rightAngle = 0.0;

  if (circle != null) {
    // Use tangent from the circle fit for a scientific angle calculation
    final leftTanSlope = tangentSlopeFromCircleAtPoint(circle, leftPt);
    final rightTanSlope = tangentSlopeFromCircleAtPoint(circle, rightPt);
    leftAngle = contactAngleDegreesFromSlopes(leftTanSlope, baseline.slope);
    rightAngle = contactAngleDegreesFromSlopes(rightTanSlope, baseline.slope);
  } else {
    // Fallback to local linear fit if circle fit fails
    leftAngle = _fallbackAngle(boundary, leftPt, baseline);
    rightAngle = _fallbackAngle(boundary, rightPt, baseline);
  }

  return (leftAngle, rightAngle);
}

double _fallbackAngle(List<Offset> boundary, Offset contactPt, BaselineData baseline) {
  int idx = 0;
  double minDist = double.infinity;
  for (int i = 0; i < boundary.length; i++) {
    final d = (boundary[i] - contactPt).distance;
    if (d < minDist) {
      minDist = d;
      idx = i;
    }
  }

  final window = 7, half = window ~/ 2;
  final start = (idx - half).clamp(0, boundary.length - 1);
  final end = (idx + half).clamp(0, boundary.length - 1);
  final local = boundary.sublist(start, end + 1);

  if (local.length < 2) return 0.0;

  final localLine = fitLineRANSACRefined(local);
  final tanSlope = localLine['m']!;
  
  return contactAngleDegreesFromSlopes(tanSlope, baseline.slope);
}

Future<ProcessedImageData> processDropletImageAuto(ui.Image image, {bool debug = false, int maxDim = 1200}) async {
  return await processDropletImage(image);
}