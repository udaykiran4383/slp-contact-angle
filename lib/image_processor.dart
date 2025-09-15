
// ----------- IMPORTS (must be at the very top) -----------
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'processing/angle_utils.dart';

// --------- Helper functions (must be before usage) ---------
Future<Uint8List> convertImageToPixels(ui.Image image) async {
// (Removed duplicate helper functions)

// --------- BoundaryCandidate data class ---------
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

// --------- contoursFromBinary helper ---------
Future<List<BoundaryCandidate>> contoursFromBinary(
    cv.Mat bin, int width, int height, String method) async {
  final findResult = cv.findContours(bin, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
  final contours = findResult.$1;
  final out = <BoundaryCandidate>[];
  for (final contour in contours) {
    final List<Offset> b = [
      for (int i = 0; i < contour.length; i++)
        Offset(contour[i].x.toDouble(), contour[i].y.toDouble())
    ];
    if (b.length > 12) {
      out.add(BoundaryCandidate(
        boundary: b,
        method: method,
        score: 0.0,
        confidence: 0.0,
      ));
    }
  }
  return out;
}

// Restore missing top-level function definitions (helpers BEFORE usage)
Future<Uint8List> convertImageToPixels(ui.Image image) async {
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return byteData!.buffer.asUint8List();
}

Future<File> tempFileFromPixels(Uint8List pixels) async {
  final tempDir = await getTemporaryDirectory();
  final tempFile = File('${tempDir.path}/temp_image.png');
  await tempFile.writeAsBytes(pixels);
  return tempFile;
}

Future<List<BoundaryCandidate>> detectBoundaryThresholding(
    cv.Mat image, int width, int height) async {
  final candidates = <BoundaryCandidate>[];
  final result = cv.threshold(image, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU);
  final otsu = result.$2;
  candidates.addAll(await contoursFromBinary(otsu, width, height, "Otsu"));
  return candidates;
}

class ProcessedImageData {
  final List<Offset> boundary;
  final BaselineData baseline;
  final Offset leftContact;
  final Offset rightContact;
  final double contactAngle;
  final double qualityScore;

  ProcessedImageData({
    required this.boundary,
    required this.baseline,
    required this.leftContact,
    required this.rightContact,
    required this.contactAngle,
    required this.qualityScore,
  });
}

class BaselineData {
  final Offset startPoint;
  final Offset endPoint;
  BaselineData({required this.startPoint, required this.endPoint});

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

class PreprocessedImageData {

  final cv.Mat processedImage;
  final Uint8List originalPixels;
  PreprocessedImageData({required this.processedImage, required this.originalPixels});
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

  // ---------- CORE PROCESSING ROUTINES (top-level!) ----------

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
          Future<File> tempFileFromPixels(Uint8List pixels) async {
            final tempDir = await getTemporaryDirectory();
            final tempFile = File('${tempDir.path}/temp_image.png');
            await tempFile.writeAsBytes(pixels);
            return tempFile;
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


// Fallback detection as a top-level function
Future<ProcessedImageData> fallbackDetection(ui.Image image) async {
  final imageData = await convertImageToPixels(image);
  final temp = await tempFileFromPixels(imageData);
  final mat = cv.imread(temp.path);
  final boundaries = await detectBoundaryThresholding(mat, image.width, image.height);

  // Ensure 'best' is always a List<Offset>
  List<Offset> best = boundaries.isNotEmpty ? boundaries.first.boundary : <Offset>[];
  final baseline = detectBaseline(best);
  final contacts = findContactPointsPrecise(best, baseline);
  final angle = calculateContactAngle(best, contacts, baseline);
  return ProcessedImageData(
    boundary: best,
    baseline: baseline,
    leftContact: contacts.left,
    rightContact: contacts.right,
    contactAngle: angle,
    qualityScore: scoreBoundaryGeneric(best, image.width, image.height),
  );
}
  final best = boundaries.isEmpty ? [] : boundaries.first.boundary;
  final baseline = detectBaseline(best);
  final contacts = findContactPointsPrecise(best, baseline);
  final angle = calculateContactAngle(best, contacts, baseline);
  return ProcessedImageData(
    boundary: best,
    baseline: baseline,
    leftContact: contacts.left,
    rightContact: contacts.right,
    contactAngle: angle,
    qualityScore: scoreBoundaryGeneric(best, image.width, image.height),
  );
}
