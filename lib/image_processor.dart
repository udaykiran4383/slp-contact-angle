// ----------- IMPORTS (must be at the very top) -----------
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'processing/angle_utils.dart';

// Top-level utility functions for boundary scoring
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
  double get contactAngle => avgAngle;
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
  double get slope => (endPoint.dy - startPoint.dy) / (endPoint.dx - startPoint.dx + 1e-10);
  double get intercept => startPoint.dy - slope * startPoint.dx;
  BaselineData({required this.startPoint, required this.endPoint});
}

class ContactPointPair {
  final Offset left;
  final Offset right;
  ContactPointPair({required this.left, required this.right});
}

// Missing function stubs
Future<Uint8List> convertImageToPixels(ui.Image image) async {
  debugPrint('convertImageToPixels called');
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    debugPrint('convertImageToPixels: byteData is null');
    return Uint8List(0);
  }
  debugPrint('convertImageToPixels: got ${byteData.lengthInBytes} bytes');
  return byteData.buffer.asUint8List();
}

Future<File> tempFileFromPixels(Uint8List pixels) async {
  debugPrint('tempFileFromPixels called');
  final tempDir = Directory.systemTemp;
  final tempFile = File('${tempDir.path}/flutter_image_${DateTime.now().millisecondsSinceEpoch}.png');
  await tempFile.writeAsBytes(pixels);
  debugPrint('tempFileFromPixels: wrote ${pixels.length} bytes to ${tempFile.path}');
  return tempFile;
}

Future<List<BoundaryCandidate>> detectBoundaryThresholding(cv.Mat mat, int width, int height) async {
  debugPrint('detectBoundaryThresholding called');
  // Example: Use OpenCV threshold and contour detection
  final thresholdResult = cv.threshold(mat, 100, 255, cv.THRESH_BINARY);
  final bin = thresholdResult.$2; // $2 is the thresholded Mat
  final contours = <List<Offset>>[];
  // OpenCV Dart returns a tuple: (contours, hierarchy)
  final contoursResult = cv.findContours(bin, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  final contoursList = contoursResult.$1; // $1 is the contours list
  for (final c in contoursList) {
    final points = <Offset>[];
    for (final pt in c) {
      points.add(Offset(pt.x.toDouble(), pt.y.toDouble()));
    }
    if (points.length > 3) contours.add(points);
  }
  debugPrint('detectBoundaryThresholding: found ${contours.length} contours');
  if (contours.isEmpty) {
    debugPrint('detectBoundaryThresholding: no contours found');
    return [];
  }
  // Score and wrap
  return contours.map((b) => BoundaryCandidate(
    boundary: b,
    method: 'threshold',
    score: scoreBoundaryGeneric(b, width, height),
    confidence: 1.0,
  )).toList();
}

Future<List<Offset>> subpixelRefinement(
    List<Offset> boundary, Uint8List orig, int width, int height) async {
  final refined = <Offset>[];
  for (int i = 0; i < boundary.length; i++) {
    final point = boundary[i];
    final prev = boundary[(i - 1 + boundary.length) % boundary.length];
    final next = boundary[(i + 1) % boundary.length];
    final tangent = next - prev;
    final tangentLength = tangent.distance;
    final normal = tangentLength == 0
        ? Offset(0, 1)
        : Offset(-tangent.dy, tangent.dx) / tangentLength;
    final refinedPoint = subpixelRefineFromRGBA(
        rgba: orig, width: width, height: height,
        approx: point, normal: normal, samples: 25, spacing: 0.6);
    refined.add(refinedPoint);
  }
  return refined;
}

  BaselineData detectBaselineAdvanced(List<Offset> boundary) {
    if (boundary.isEmpty) return BaselineData(startPoint: Offset.zero, endPoint: Offset.zero);
    final sortedByY = List.of(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
    final maxY = sortedByY.first.dy, minY = sortedByY.last.dy;
    final contactThreshold = maxY - (maxY - minY) * 0.2;
    final contactPoints = boundary.where((p) => p.dy >= contactThreshold).toList();
    if (contactPoints.length < 3) return detectBaseline(boundary);
    final line = fitLineRANSACRefined(
        contactPoints, iterations: 600, inlierThresh: 2.0, slopePrior: 0.0, slopePriorWeight: 0.1);
    final minX = boundary.map((p) => p.dx).reduce(min),
        maxX = boundary.map((p) => p.dx).reduce(max);
    return BaselineData(
      startPoint: Offset(minX, line['m']! * minX + line['c']!),
      endPoint: Offset(maxX, line['m']! * maxX + line['c']!),
    );
  }

  BaselineData detectBaseline(List<Offset> boundary) {
    if (boundary.isEmpty) return BaselineData(startPoint: Offset.zero, endPoint: Offset.zero);
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
    final minX = boundary.map((p) => p.dx).reduce(min),
        maxX = boundary.map((p) => p.dx).reduce(max);
    return BaselineData(
      startPoint: Offset(minX, slope * minX + intercept),
      endPoint: Offset(maxX, slope * maxX + intercept),
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
    final fallback = boundary;
    fallback.sort((a, b) => a.dx.compareTo(b.dx));
    return ContactPointPair(left: fallback.first, right: fallback.last);
  }

  double calculateContactAngle(
      List<Offset> boundary, ContactPointPair contacts, BaselineData baseline) {
    final contactPoints = [contacts.left, contacts.right];
    double sum = 0;
    for (final pt in contactPoints) {
      int idx = 0;
      double minDist = double.infinity;
      for (int i = 0; i < boundary.length; i++) {
        final d = (boundary[i] - pt).distance;
        if (d < minDist) {
          minDist = d;
          idx = i;
        }
      }
      final window = 7, half = window ~/ 2;
      final start = (idx - half).clamp(0, boundary.length - 1),
          end = (idx + half).clamp(0, boundary.length - 1);
      final local = boundary.sublist(start, end + 1);
      if (local.length >= 6) {
        final circle = fitCircleKasa(local);
        if (circle != null) {
          final tanSlope = tangentSlopeFromCircleAtPoint(circle, pt);
          final angle =
              contactAngleDegreesFromSlopes(tanSlope, baseline.slope);
          sum += angle;
          continue;
        }
      }
      if (boundary.length >= 6) {
        final prev = boundary[(idx - 3 + boundary.length) % boundary.length],
            next = boundary[(idx + 3) % boundary.length];
        final tan = (next - prev);
        final tanSlope = tan.dy / (tan.dx == 0 ? 1e-8 : tan.dx);
        sum += contactAngleDegreesFromSlopes(tanSlope, baseline.slope);
      }
    }
    return sum / 2;
  }

  void maskReflectionRegion(cv.Mat img, int width, int height) {
    int ystart = (height * 0.92).toInt();
    for (int y = ystart; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (img.at(y, x) > 210) img.set(y, x, 0);
      }
    }
  }


// Main scientific droplet processing function
Future<ProcessedImageData?> processDropletImage(ui.Image image) async {
  print('Starting processDropletImage');
  final imageData = await convertImageToPixels(image);
  if (imageData == null || imageData.isEmpty) {
    print('convertImageToPixels returned null or empty');
    return null;
  }
  final temp = await tempFileFromPixels(imageData);
  if (temp == null || !await temp.exists()) {
    print('tempFileFromPixels returned null or file does not exist');
    return null;
  }
  print('Temp file path: \'${temp.path}\' size: ${await temp.length()}');
  if (await temp.length() == 0) {
    print('Temp file is empty');
    return null;
  }
  final mat = cv.imread(temp.path);
  if (mat == null || mat.rows == 0 || mat.cols == 0) {
    print('cv.imread returned null or empty');
    return null;
  }
  // Step 1: Preprocess image
  final gray = cv.cvtColor(mat, cv.COLOR_BGRA2GRAY);
  cv.CLAHE clahe = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
  final enhanced = clahe.apply(gray);
  final blurred = cv.medianBlur(enhanced, 5);

  // Step 2: Robust boundary detection (adaptive thresholding + contour filtering)
  final boundaries = await detectBoundaryThresholding(blurred, image.width, image.height);
  if (boundaries == null || boundaries.isEmpty) {
    print('detectBoundaryThresholding returned null or empty');
    return null;
  }
  // Filter boundaries by area and circularity
  final filtered = boundaries.where((b) => calculatePolygonArea(b.boundary) > 1000 && scoreBoundaryGeneric(b.boundary, image.width, image.height) > 0.5).toList();
  if (filtered.isEmpty) {
    print('No robust boundary found');
    return null;
  }
  final bestBoundary = filtered.reduce((a, b) => a.score > b.score ? a : b);

  // Step 3: RANSAC baseline detection
  final baseline = detectBaselineAdvanced(bestBoundary.boundary);
  debugPrint('Baseline: start=${baseline.startPoint}, end=${baseline.endPoint}, slope=${baseline.slope}');

  // Step 4: Subpixel contact point detection
  final contacts = findContactPointsPrecise(bestBoundary.boundary, baseline);
  debugPrint('Contacts: left=${contacts.left}, right=${contacts.right}');
  final refinedLeftContact = subpixelRefineFromRGBA(
    rgba: imageData,
    width: image.width,
    height: image.height,
    approx: contacts.left,
    normal: Offset(-baseline.slope, 1.0),
    samples: 35,
    spacing: 0.5,
  );
  final refinedRightContact = subpixelRefineFromRGBA(
    rgba: imageData,
    width: image.width,
    height: image.height,
    approx: contacts.right,
    normal: Offset(baseline.slope, -1.0),
    samples: 35,
    spacing: 0.5,
  );
  debugPrint('Refined contacts: left=$refinedLeftContact, right=$refinedRightContact');

  // Step 5: Angle calculation (average both sides)
  final leftAngle = _contactAngleAt(bestBoundary.boundary, refinedLeftContact, baseline);
  final rightAngle = _contactAngleAt(bestBoundary.boundary, refinedRightContact, baseline);
  debugPrint('Angles: left=$leftAngle, right=$rightAngle');
  final avgAngle = (leftAngle + rightAngle) / 2.0;
  final bestAngle = avgAngle;
  debugPrint('--- processDropletImage END --- Returning result ---');
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
}

double _contactAngleAt(List<Offset> boundary, Offset contactPt, BaselineData baseline) {
  int idx = 0;
  double minDist = double.infinity;
  for (int i = 0; i < boundary.length; i++) {
    final d = (boundary[i] - contactPt).distance;
    if (d < minDist) {
      minDist = d;
      idx = i;
    }
  }
  final window = 9, half = window ~/ 2;
  final start = (idx - half).clamp(0, boundary.length - 1);
  final end = (idx + half).clamp(0, boundary.length - 1);
  // Guard against RangeError: ensure end+1 <= boundary.length
  List<Offset> local = [];
  if (end + 1 <= boundary.length && start < boundary.length && start <= end) {
    local = boundary.sublist(start, end + 1);
  }
  if (local.length >= 6) {
    final circle = fitCircleKasa(local);
    if (circle != null) {
      final tanSlope = tangentSlopeFromCircleAtPoint(circle, contactPt);
      return contactAngleDegreesFromSlopes(tanSlope, baseline.slope);
    }
  }
  if (boundary.length >= 6) {
    final prev = boundary[(idx - 3 + boundary.length) % boundary.length],
        next = boundary[(idx + 3) % boundary.length];
    final tan = (next - prev);
    final tanSlope = tan.dy / (tan.dx == 0 ? 1e-8 : tan.dx);
    return contactAngleDegreesFromSlopes(tanSlope, baseline.slope);
  }
  return 0.0;
}
// Removed unreachable code fragment
