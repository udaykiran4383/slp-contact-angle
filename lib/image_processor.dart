import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';

class ImageProcessor {
  static Future<ProcessedImageData> processDropletImage(ui.Image image) async {
    // Convert image to grayscale and analyze
    final imageData = await _convertImageToPixels(image);
    
    // Step 1: Detect droplet boundary using edge detection
    final boundary = await _detectDropletBoundary(imageData, image.width, image.height);
    
    // Step 2: Detect baseline (surface) automatically
    final baseline = await _detectBaseline(imageData, image.width, image.height, boundary);
    
    // Step 3: Find contact points where droplet meets surface
    final contactPoints = await _findContactPoints(boundary, baseline);
    
    // Step 4: Calculate contact angle automatically
    final angle = await _calculateContactAngle(boundary, contactPoints, baseline);
    
    return ProcessedImageData(
      boundary: boundary,
      baseline: baseline,
      leftContact: contactPoints.left,
      rightContact: contactPoints.right,
      contactAngle: angle,
    );
  }

  static Future<Uint8List> _convertImageToPixels(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData!.buffer.asUint8List();
  }

  static Future<List<Offset>> _detectDropletBoundary(Uint8List pixels, int width, int height) async {
    // Convert to grayscale for edge detection
    final grayscale = List<int>.filled(width * height, 0);
    
    for (int i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];
      final gray = (0.299 * r + 0.587 * g + 0.114 * b).round();
      grayscale[i ~/ 4] = gray;
    }

    // Apply Gaussian blur to reduce noise
    final blurred = _gaussianBlur(grayscale, width, height);
    
    // Apply Canny edge detection
    final edges = _cannyEdgeDetection(blurred, width, height);
    
    // Find the largest connected component (droplet)
    final dropletEdges = _findLargestConnectedComponent(edges, width, height);
    
    // Convert edge pixels to boundary points
    final boundary = <Offset>[];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        if (dropletEdges[y * width + x] > 0) {
          boundary.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }

    // Sort boundary points to form a continuous contour
    return _sortBoundaryPoints(boundary);
  }

  static List<int> _gaussianBlur(List<int> image, int width, int height) {
    // Simple 3x3 Gaussian kernel
    final kernel = [1, 2, 1, 2, 4, 2, 1, 2, 1];
    final kernelSum = 16;
    final result = List<int>.filled(width * height, 0);
    
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        int sum = 0;
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            final pixel = image[(y + ky) * width + (x + kx)];
            final weight = kernel[(ky + 1) * 3 + (kx + 1)];
            sum += pixel * weight;
          }
        }
        result[y * width + x] = sum ~/ kernelSum;
      }
    }
    return result;
  }

  static List<int> _cannyEdgeDetection(List<int> image, int width, int height) {
    // Simplified Canny edge detection
    final gradientX = List<int>.filled(width * height, 0);
    final gradientY = List<int>.filled(width * height, 0);
    final magnitude = List<int>.filled(width * height, 0);
    
    // Calculate gradients using Sobel operator
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        // Sobel X kernel: [-1, 0, 1, -2, 0, 2, -1, 0, 1]
        final gx = -image[(y - 1) * width + (x - 1)] + image[(y - 1) * width + (x + 1)] +
                   -2 * image[y * width + (x - 1)] + 2 * image[y * width + (x + 1)] +
                   -image[(y + 1) * width + (x - 1)] + image[(y + 1) * width + (x + 1)];
        
        // Sobel Y kernel: [-1, -2, -1, 0, 0, 0, 1, 2, 1]
        final gy = -image[(y - 1) * width + (x - 1)] - 2 * image[(y - 1) * width + x] - image[(y - 1) * width + (x + 1)] +
                   image[(y + 1) * width + (x - 1)] + 2 * image[(y + 1) * width + x] + image[(y + 1) * width + (x + 1)];
        
        gradientX[y * width + x] = gx;
        gradientY[y * width + x] = gy;
        magnitude[y * width + x] = sqrt(gx * gx + gy * gy).round();
      }
    }
    
    // Apply threshold to create binary edge map
    final threshold = 50; // Adjust based on image characteristics
    final edges = List<int>.filled(width * height, 0);
    for (int i = 0; i < magnitude.length; i++) {
      edges[i] = magnitude[i] > threshold ? 255 : 0;
    }
    
    return edges;
  }

  static List<int> _findLargestConnectedComponent(List<int> edges, int width, int height) {
    final visited = List<bool>.filled(width * height, false);
    final result = List<int>.filled(width * height, 0);
    int largestSize = 0;
    List<int> largestComponent = [];
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final index = y * width + x;
        if (edges[index] > 0 && !visited[index]) {
          final component = _floodFill(edges, visited, x, y, width, height);
          if (component.length > largestSize) {
            largestSize = component.length;
            largestComponent = component;
          }
        }
      }
    }
    
    // Mark the largest component in result
    for (final index in largestComponent) {
      result[index] = 255;
    }
    
    return result;
  }

  static List<int> _floodFill(List<int> edges, List<bool> visited, int startX, int startY, int width, int height) {
    final component = <int>[];
    final stack = <Point<int>>[];
    stack.add(Point(startX, startY));
    
    while (stack.isNotEmpty) {
      final point = stack.removeLast();
      final x = point.x;
      final y = point.y;
      final index = y * width + x;
      
      if (x < 0 || x >= width || y < 0 || y >= height || visited[index] || edges[index] == 0) {
        continue;
      }
      
      visited[index] = true;
      component.add(index);
      
      // Add 8-connected neighbors
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          if (dx != 0 || dy != 0) {
            stack.add(Point(x + dx, y + dy));
          }
        }
      }
    }
    
    return component;
  }

  static List<Offset> _sortBoundaryPoints(List<Offset> boundary) {
    if (boundary.isEmpty) return boundary;
    
    // Find the topmost point as starting point
    Offset startPoint = boundary.reduce((a, b) => a.dy < b.dy ? a : b);
    
    // Sort points by angle from center
    final center = boundary.fold(Offset.zero, (sum, point) => sum + point) / boundary.length.toDouble();
    
    boundary.sort((a, b) {
      final angleA = atan2(a.dy - center.dy, a.dx - center.dx);
      final angleB = atan2(b.dy - center.dy, b.dx - center.dx);
      return angleA.compareTo(angleB);
    });
    
    return boundary;
  }

  static Future<BaselineData> _detectBaseline(Uint8List pixels, int width, int height, List<Offset> boundary) async {
    // Find the bottom of the image where the surface likely is
    final bottomRegionHeight = (height * 0.3).round(); // Bottom 30% of image
    final startY = height - bottomRegionHeight;
    
    // Look for horizontal lines in the bottom region using Hough transform
    final lines = _detectHorizontalLines(pixels, width, height, startY);
    
    if (lines.isNotEmpty) {
      // Use the most prominent horizontal line as baseline
      final mainLine = lines.first;
      return BaselineData(
        startPoint: Offset(0, mainLine.toDouble()),
        endPoint: Offset(width.toDouble(), mainLine.toDouble()),
      );
    }
    
    // Fallback: use the lowest points of the droplet boundary
    final bottomPoints = boundary.where((p) => p.dy > height * 0.7).toList();
    if (bottomPoints.isNotEmpty) {
      bottomPoints.sort((a, b) => b.dy.compareTo(a.dy));
      final baselineY = bottomPoints.first.dy + 20; // Slightly below the droplet
      return BaselineData(
        startPoint: Offset(0, baselineY),
        endPoint: Offset(width.toDouble(), baselineY),
      );
    }
    
    // Final fallback: bottom 10% of image
    final defaultY = height * 0.9;
    return BaselineData(
      startPoint: Offset(0, defaultY),
      endPoint: Offset(width.toDouble(), defaultY),
    );
  }

  static List<int> _detectHorizontalLines(Uint8List pixels, int width, int height, int startY) {
    final lines = <int>[];
    final threshold = width * 0.6; // At least 60% of width should be edge
    
    for (int y = startY; y < height - 1; y++) {
      int edgeCount = 0;
      for (int x = 1; x < width - 1; x++) {
        final current = _getGrayscale(pixels, x, y, width);
        final next = _getGrayscale(pixels, x + 1, y, width);
        if ((current - next).abs() > 30) { // Edge detected
          edgeCount++;
        }
      }
      if (edgeCount > threshold) {
        lines.add(y);
      }
    }
    
    return lines;
  }

  static int _getGrayscale(Uint8List pixels, int x, int y, int width) {
    final index = (y * width + x) * 4;
    if (index >= pixels.length - 2) return 0;
    final r = pixels[index];
    final g = pixels[index + 1];
    final b = pixels[index + 2];
    return (0.299 * r + 0.587 * g + 0.114 * b).round();
  }

  static Future<ContactPointPair> _findContactPoints(List<Offset> boundary, BaselineData baseline) async {
    if (boundary.isEmpty) {
      return ContactPointPair(
        left: Offset.zero,
        right: Offset.zero,
      );
    }
    
    // Find points on boundary that are closest to the baseline
    final baselineY = baseline.startPoint.dy;
    final tolerance = 20.0; // Pixels
    
    final nearBaselinePoints = boundary
        .where((point) => (point.dy - baselineY).abs() < tolerance)
        .toList();
    
    if (nearBaselinePoints.isEmpty) {
      // Fallback: use the bottommost points
      boundary.sort((a, b) => b.dy.compareTo(a.dy));
      final bottom = boundary.take(10).toList();
      bottom.sort((a, b) => a.dx.compareTo(b.dx));
      
      return ContactPointPair(
        left: bottom.first,
        right: bottom.last,
      );
    }
    
    // Sort by x-coordinate to find leftmost and rightmost
    nearBaselinePoints.sort((a, b) => a.dx.compareTo(b.dx));
    
    return ContactPointPair(
      left: nearBaselinePoints.first,
      right: nearBaselinePoints.last,
    );
  }

  static Future<double> _calculateContactAngle(
    List<Offset> boundary,
    ContactPointPair contactPoints,
    BaselineData baseline,
  ) async {
    // Calculate tangent at left contact point
    final leftTangent = _calculateTangentAtPoint(boundary, contactPoints.left);
    if (leftTangent == null) return 0.0;
    
    // Calculate baseline angle
    final baselineVector = baseline.endPoint - baseline.startPoint;
    final baselineAngle = atan2(baselineVector.dy, baselineVector.dx);
    
    // Calculate tangent angle
    final tangentAngle = atan2(leftTangent.dy, leftTangent.dx);
    
    // Calculate contact angle
    double angleDiff = (tangentAngle - baselineAngle).abs();
    if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;
    
    return angleDiff * 180 / pi;
  }

  static Offset? _calculateTangentAtPoint(List<Offset> boundary, Offset point) {
    if (boundary.length < 5) return null;
    
    // Find the nearest point on boundary
    int nearestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < boundary.length; i++) {
      final distance = (boundary[i] - point).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    
    // Calculate tangent using neighboring points
    final windowSize = 5;
    final startIdx = (nearestIndex - windowSize).clamp(0, boundary.length - 1);
    final endIdx = (nearestIndex + windowSize).clamp(0, boundary.length - 1);
    
    if (startIdx == endIdx) return null;
    
    final tangentVector = boundary[endIdx] - boundary[startIdx];
    final length = tangentVector.distance;
    
    if (length == 0) return null;
    
    return tangentVector / length;
  }
}

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
  final Offset startPoint;
  final Offset endPoint;

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
