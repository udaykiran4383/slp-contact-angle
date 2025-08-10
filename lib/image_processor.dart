import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';

// Note: Ensure you have a dependency on a vector math library or define Offset extensions for basic vector ops.
// For example: extension VectorOps on Offset { ... }

class ImageProcessor {
  static Future<ProcessedImageData> processDropletImage(ui.Image image) async {
    // This now calls the corrected auto-detection pipeline.
    return await _processDropletImageAuto(image);
  }

  static Future<ProcessedImageData> _processDropletImageAuto(ui.Image image) async {
    final imageData = await _convertImageToPixels(image);
    final width = image.width;
    final height = image.height;

    // Step 1: Detect droplet boundary using an improved edge detection and component analysis
    final boundary = await _detectDropletBoundary(imageData, width, height);
    if (boundary.length < 20) {
      throw Exception("Failed to detect a meaningful droplet boundary.");
    }

    // Step 2: Detect the best possible baseline with new strict validation
    final baseline = await _detectBestBaseline(imageData, width, height, boundary);
    if (baseline == null) {
      throw Exception("Failed to determine a valid baseline for the droplet.");
    }

    // Step 3: Find contact points where the final, validated baseline intersects the droplet
    final contactPoints = _findContactPoints(boundary, baseline);

    // Step 4: Calculate the contact angle from the reliable baseline and contact points
    final angle = _calculateContactAngle(boundary, contactPoints, baseline);

    return ProcessedImageData(
      boundary: boundary,
      baseline: baseline,
      leftContact: contactPoints.left,
      rightContact: contactPoints.right,
      contactAngle: angle,
    );
  }

  /// **[RE-ENGINEERED]** Detects the best baseline by scoring candidates from multiple methods.
  /// Now includes mandatory validation to ensure the baseline is geometrically sound.
  static Future<BaselineData?> _detectBestBaseline(
      Uint8List pixels, int width, int height, List<Offset> contour) async {
    if (contour.isEmpty) return null;

    final rect = _getBoundingBox(contour);
    final bottomPoints = contour.where((p) => p.dy > rect.bottom - 10).toList();
    if (bottomPoints.isEmpty) return null;

    final dropletMaxY = rect.bottom;

    // List of candidate baselines from various detectors.
    List<BaselineData> candidates = [];

    // **Primary Detector**: Tightly constrained search near the droplet bottom.
    // This is now the most reliable and prioritized method.
    final nearDropletBaseline =
        _detectBaselineNearDropletBandEnhanced(pixels, width, height, contour, dropletMaxY);
    if (nearDropletBaseline != null) {
      candidates.add(nearDropletBaseline);
    }

    // **Secondary Detectors** can be added here as fallbacks if needed.
    // For this advanced fix, we rely on the robustness of the near-droplet detector.

    if (candidates.isEmpty) {
        // Ultimate fallback: A horizontal line through the lowest point of the contour.
        final fallbackY = contour.map((p) => p.dy).reduce(max);
        candidates.add(BaselineData(startPoint: Offset(0, fallbackY), endPoint: Offset(width.toDouble(), fallbackY)));
    }


    // **Crucial Step**: Validate all candidates and score them.
    final List<(BaselineData, double)> scoredCandidates = [];
    for (var candidate in candidates) {
      bool isValid = await _validateAndRefineBaseline(candidate, contour, dropletMaxY);
      if (isValid) {
        // Score based on proximity to droplet bottom and horizontalness.
        final yError = (candidate.startPoint.dy - dropletMaxY).abs();
        final slopeError = (candidate.startPoint.dy - candidate.endPoint.dy).abs() / width;
        // Lower score is better. Proximity is heavily weighted.
        final score = yError * 10 + slopeError;
        scoredCandidates.add((candidate, score));
      }
    }

    if (scoredCandidates.isEmpty) return null;

    // Return the best valid candidate.
    scoredCandidates.sort((a, b) => a.$2.compareTo(b.$2));
    return scoredCandidates.first.$1;
  }

  /// **[NEW & CRITICAL]** Validates a baseline candidate.
  /// A baseline is only valid if it intersects the contour twice after optional nudging.
  /// This prevents the selection of baselines that are disconnected from the droplet.
  static Future<bool> _validateAndRefineBaseline(
      BaselineData candidate, List<Offset> contour, double dropletMaxY) async {
    const double maxAllowedYDeviation = 15.0; // Max pixels away from droplet bottom
    if ((candidate.startPoint.dy - dropletMaxY).abs() > maxAllowedYDeviation) {
      return false; // Reject if too far from the droplet
    }

    var intersections = _intersectLineWithContour(candidate, contour);
    if (intersections.length >= 2) {
      return true; // Already valid
    }

    // Attempt to nudge the baseline vertically to find a valid intersection
    for (int dy = 1; dy <= 3; dy++) {
      // Nudge down
      var nudgedLine = BaselineData(
        startPoint: candidate.startPoint.translate(0, dy.toDouble()),
        endPoint: candidate.endPoint.translate(0, dy.toDouble()),
      );
      if (_intersectLineWithContour(nudgedLine, contour).length >= 2) {
        candidate.startPoint = nudgedLine.startPoint;
        candidate.endPoint = nudgedLine.endPoint;
        return true;
      }
      // Nudge up
      nudgedLine = BaselineData(
        startPoint: candidate.startPoint.translate(0, -dy.toDouble()),
        endPoint: candidate.endPoint.translate(0, -dy.toDouble()),
      );
      if (_intersectLineWithContour(nudgedLine, contour).length >= 2) {
        candidate.startPoint = nudgedLine.startPoint;
        candidate.endPoint = nudgedLine.endPoint;
        return true;
      }
    }

    return false; // Could not find a valid intersection after nudging
  }

  /// **[RE-ENGINEERED & ENHANCED]** Stricter baseline detection in a tight, localized band.
  static BaselineData? _detectBaselineNearDropletBandEnhanced(
      Uint8List pixels, int width, int height, List<Offset> contour, double dropletMaxY) {
    final rect = _getBoundingBox(contour);
    
    // 1. Define a very tight, intelligent search window based on droplet geometry.
    final int searchXStart = (rect.left - rect.width * 0.1).round().clamp(0, width - 1);
    final int searchXEnd = (rect.right + rect.width * 0.1).round().clamp(0, width - 1);
    final int searchYStart = (dropletMaxY - 4).round().clamp(0, height - 1);
    final int searchYEnd = (dropletMaxY + 8).round().clamp(0, height - 1);

    double bestScore = -double.infinity;
    int bestY = -1;

    // Precompute grayscale for the tiny search region for efficiency
    final grayRegion = List.generate(searchYEnd - searchYStart,
        (_) => List<int>.filled(searchXEnd - searchXStart, 0));
    for (int y = searchYStart; y < searchYEnd; y++) {
      for (int x = searchXStart; x < searchXEnd; x++) {
        grayRegion[y - searchYStart][x - searchXStart] = _getGrayscale(pixels, x, y, width);
      }
    }

    // 2. Find the row with the strongest, most consistent vertical gradient (physical edge).
    for (int y = 1; y < grayRegion.length - 1; y++) {
      double rowScore = 0;
      int significantGrads = 0;
      for (int x = 0; x < grayRegion[0].length; x++) {
        // Vertical Sobel-like gradient calculation
        final gradY = grayRegion[y + 1][x] - grayRegion[y - 1][x]; 
        // We look for a strong, positive gradient (dark substrate below, bright background above)
        if (gradY > 15) { // Empirically tuned gradient threshold
          rowScore += gradY;
          significantGrads++;
        }
      }
      // 3. Enforce constraint: the edge must be supported across a significant portion of the droplet's width.
      if (significantGrads > (rect.width * 0.2)) {
        if (rowScore > bestScore) {
          bestScore = rowScore;
          bestY = y + searchYStart;
        }
      }
    }

    if (bestY != -1) {
      return BaselineData(
          startPoint: Offset(0, bestY.toDouble()), endPoint: Offset(width.toDouble(), bestY.toDouble()));
    }
    return null;
  }

  // --- Helper and Unchanged Functions (for completeness) ---

  static Rect _getBoundingBox(List<Offset> contour) {
    if (contour.isEmpty) return Rect.zero;
    double minX = contour[0].dx, maxX = contour[0].dx;
    double minY = contour[0].dy, maxY = contour[0].dy;
    for (var p in contour.skip(1)) {
      minX = min(minX, p.dx);
      maxX = max(maxX, p.dx);
      minY = min(minY, p.dy);
      maxY = max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<Offset> _intersectLineWithContour(BaselineData line, List<Offset> contour) {
    List<Offset> intersections = [];
    if (contour.isEmpty) return intersections;
    final p1 = line.startPoint;
    final p2 = line.endPoint;

    for (int i = 0; i < contour.length; i++) {
      final c1 = contour[i];
      final c2 = contour[(i + 1) % contour.length];

      // Standard line segment intersection algorithm
      final denominator = (p2.dx - p1.dx) * (c2.dy - c1.dy) - (p2.dy - p1.dy) * (c2.dx - c1.dx);
      if (denominator.abs() < 1e-6) continue;

      final t = ((c1.dx - p1.dx) * (c2.dy - c1.dy) - (c1.dy - p1.dy) * (c2.dx - c1.dx)) / denominator;
      final u = -((p2.dx - p1.dx) * (c1.dy - p1.dy) - (p2.dy - p1.dy) * (c1.dx - p1.dx)) / denominator;

      if (t >= 0 && t <= 1 && u >= 0 && u <= 1) {
        intersections.add(Offset(p1.dx + t * (p2.dx - p1.dx), p1.dy + t * (p2.dy - p1.dy)));
      }
    }
    return intersections;
  }

  static Future<Uint8List> _convertImageToPixels(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData!.buffer.asUint8List();
  }

  static Future<List<Offset>> _detectDropletBoundary(Uint8List pixels, int width, int height) async {
    final grayscale = List<int>.filled(width * height, 0);
    for (int i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      grayscale[i ~/ 4] = (0.299 * r + 0.587 * g + 0.114 * b).round();
    }
    final blurred = _gaussianBlur(grayscale, width, height);
    final edges = _cannyEdgeDetection(blurred, width, height);
    final dropletEdges = _findLargestConnectedComponent(edges, width, height);
    final boundary = <Offset>[];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (dropletEdges[y * width + x] > 0) {
          boundary.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    return _sortBoundaryPoints(boundary);
  }

  static List<int> _gaussianBlur(List<int> image, int width, int height) {
    const kernel = [1, 2, 1, 2, 4, 2, 1, 2, 1];
    const kernelSum = 16;
    final result = List<int>.from(image);
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        int sum = 0;
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            sum += image[(y + ky) * width + (x + kx)] * kernel[(ky + 1) * 3 + (kx + 1)];
          }
        }
        result[y * width + x] = sum ~/ kernelSum;
      }
    }
    return result;
  }

  static List<int> _cannyEdgeDetection(List<int> image, int width, int height) {
    final magnitude = List<int>.filled(width * height, 0);
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final gx = -image[(y - 1) * width + (x - 1)] + image[(y - 1) * width + (x + 1)] -
                   2 * image[y * width + (x - 1)] + 2 * image[y * width + (x + 1)] -
                   image[(y + 1) * width + (x - 1)] + image[(y + 1) * width + (x + 1)];
        final gy = -image[(y - 1) * width + (x - 1)] - 2 * image[(y - 1) * width + x] - image[(y - 1) * width + (x + 1)] +
                   image[(y + 1) * width + (x - 1)] + 2 * image[(y + 1) * width + x] + image[(y + 1) * width + (x + 1)];
        magnitude[y * width + x] = sqrt(gx * gx + gy * gy).round();
      }
    }
    final threshold = 50; 
    return magnitude.map((e) => e > threshold ? 255 : 0).toList();
  }

  static List<int> _findLargestConnectedComponent(List<int> edges, int width, int height) {
    final visited = List<bool>.filled(width * height, false);
    List<int> largestComponent = [];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final index = y * width + x;
        if (edges[index] > 0 && !visited[index]) {
          final component = _floodFill(edges, visited, x, y, width, height);
          if (component.length > largestComponent.length) {
            largestComponent = component;
          }
        }
      }
    }
    final result = List<int>.filled(width * height, 0);
    for (final index in largestComponent) {
      result[index] = 255;
    }
    return result;
  }

  static List<int> _floodFill(List<int> edges, List<bool> visited, int startX, int startY, int width, int height) {
    final component = <int>[];
    final stack = [Point(startX, startY)];
    visited[startY * width + startX] = true;
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      component.add(point.y * width + point.x);
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          final newX = point.x + dx;
          final newY = point.y + dy;
          final newIndex = newY * width + newX;
          if (newX >= 0 && newX < width && newY >= 0 && newY < height && !visited[newIndex] && edges[newIndex] > 0) {
            visited[newIndex] = true;
            stack.add(Point(newX, newY));
          }
        }
      }
    }
    return component;
  }

  static List<Offset> _sortBoundaryPoints(List<Offset> boundary) {
    if (boundary.isEmpty) return [];
    final center = boundary.fold(Offset.zero, (a, b) => a + b) / boundary.length.toDouble();
    boundary.sort((a, b) {
      return (atan2(a.dy - center.dy, a.dx - center.dx))
          .compareTo(atan2(b.dy - center.dy, b.dx - center.dx));
    });
    return boundary;
  }

  static int _getGrayscale(Uint8List pixels, int x, int y, int width) {
    final index = (y * width + x) * 4;
    return (0.299 * pixels[index] + 0.587 * pixels[index + 1] + 0.114 * pixels[index + 2]).round();
  }

  static ContactPointPair _findContactPoints(List<Offset> boundary, BaselineData baseline) {
    final intersections = _intersectLineWithContour(baseline, boundary);
    if (intersections.length >= 2) {
      intersections.sort((a, b) => a.dx.compareTo(b.dx));
      return ContactPointPair(left: intersections.first, right: intersections.last);
    }
    // Fallback if direct intersection fails (should be extremely rare with the new validation logic)
    final bottomPoints = boundary.where((p) => (p.dy - baseline.startPoint.dy).abs() < 5).toList();
    if(bottomPoints.length < 2) return ContactPointPair(left: boundary.first, right: boundary.last);
    bottomPoints.sort((a,b) => a.dx.compareTo(b.dx));
    return ContactPointPair(left: bottomPoints.first, right: bottomPoints.last);
  }

  static double _calculateContactAngle(List<Offset> boundary, ContactPointPair contactPoints, BaselineData baseline) {
    final leftTangent = _calculateTangentAtPoint(boundary, contactPoints.left);
    if (leftTangent == null) return 0.0;
    final baselineVector = baseline.endPoint - baseline.startPoint;
    final baselineAngle = atan2(baselineVector.dy, baselineVector.dx);
    final tangentAngle = atan2(leftTangent.dy, leftTangent.dx);
    double angleDiff = (tangentAngle - baselineAngle).abs();
    if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;
    return angleDiff * 180 / pi;
  }

  static Offset? _calculateTangentAtPoint(List<Offset> boundary, Offset point) {
    if (boundary.length < 5) return null;
    int nearestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < boundary.length; i++) {
      final d = (boundary[i] - point).distance;
      if (d < minDistance) {
        minDistance = d;
        nearestIndex = i;
      }
    }
    // Use a small, robust neighborhood for the tangent calculation
    final prev = boundary[(nearestIndex - 3 + boundary.length) % boundary.length];
    final next = boundary[(nearestIndex + 3) % boundary.length];
    final tangent = next - prev;
    if (tangent.distance == 0) return null;
    return tangent / tangent.distance;
  }
}

// --- Data Structures ---

class ProcessedImageData {
  final List<Offset> boundary;
  final BaselineData baseline;
  final Offset leftContact;
  final Offset rightContact;
  final double contactAngle;

  ProcessedImageData({
    required this.boundary,
    required this.baseline,
    required this.leftContact,
    required this.rightContact,
    required this.contactAngle,
  });
}

class BaselineData {
  Offset startPoint;
  Offset endPoint;

  BaselineData({
    required this.startPoint,
    required this.endPoint,
  });
}

class ContactPointPair {
  final Offset left;
  final Offset right;

  ContactPointPair({
    required this.left,
    required this.right,
  });
}
