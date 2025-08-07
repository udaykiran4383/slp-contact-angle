import 'dart:io';
import 'dart:math';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Debug script for contact angle detection with detailed analysis
class ContactAngleDebugger {
  static const String testImagesDir = 'PFOTES';
  
  // Expected values based on your feedback
  static const Map<String, double> expectedAngles = {
    'C_1.5%_1 coat_5a.JPG': 112.088,
    'C_1.5%_1 coat_5b.JPG': 112.0,
    'C_1.5%_1 coat_6.JPG': 112.0,
    'C_1.5%_2 coat_5.JPG': 112.0,
    'C_1.5%_2 coat_6.JPG': 112.0,
    'C_3%_1 coat_5.JPG': 112.0,
    'C_3%_1 coat_6a.JPG': 112.0,
    'C_3%_1 coat_6b.JPG': 112.0,
    'C_3%_2 coat_5a.JPG': 112.0,
    'C_3%_2 coat_5b.JPG': 112.0,
    'C_3%_2 coat_6a.JPG': 112.0,
    'C_3%_2 coat_6b.JPG': 112.0,
  };
  
  static Future<void> debugContactAngles() async {
    print('🔬 Starting Contact Angle Debug Analysis...\n');
    
    final testImages = await _getTestImages();
    
    if (testImages.isEmpty) {
      print('❌ No test images found in $testImagesDir directory');
      return;
    }
    
    print('📁 Found ${testImages.length} test images\n');
    
    for (final imagePath in testImages) {
      final fileName = imagePath.split('/').last;
      print('🔄 Debugging: $fileName');
      
      try {
        await _debugSingleImage(imagePath, fileName);
      } catch (e) {
        print('❌ Error debugging $fileName: $e');
      }
      
      print(''); // Empty line for readability
    }
  }
  
  static Future<List<String>> _getTestImages() async {
    final dir = Directory(testImagesDir);
    if (!await dir.exists()) {
      return [];
    }
    
    final files = await dir.list().toList();
    final imageFiles = <String>[];
    
    for (final file in files) {
      if (file is File) {
        final path = file.path.toLowerCase();
        if (path.endsWith('.jpg') || 
            path.endsWith('.jpeg') || 
            path.endsWith('.png')) {
          imageFiles.add(file.path);
        }
      }
    }
    
    return imageFiles;
  }
  
  static Future<void> _debugSingleImage(String imagePath, String fileName) async {
    try {
      // Load image
      final image = cv.imread(imagePath);
      if (image.isEmpty) {
        throw Exception('Failed to load image');
      }
      
      print('  📊 Image Properties:');
      print('    Size: ${image.cols} x ${image.rows}');
      
      // Convert to grayscale
      final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
      
      // Apply Gaussian blur
      final blurred = cv.gaussianBlur(gray, (5, 5), 1.0);
      
      // Apply threshold
      final (threshValue, thresh) = cv.threshold(blurred, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
      print('    Threshold Value: $threshValue');
      
      // Find contours
      final (contours, hierarchy) = cv.findContours(
          thresh, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
      
      print('    Contours Found: ${contours.length}');
      
      if (contours.isEmpty) {
        throw Exception('No contours found');
      }
      
      // Find the largest contour (assumed to be the droplet)
      var largestContour = contours[0];
      var maxArea = cv.contourArea(largestContour);
      
      for (final contour in contours) {
        final area = cv.contourArea(contour);
        if (area > maxArea) {
          maxArea = area;
          largestContour = contour;
        }
      }
      
      print('    Largest Contour Area: ${maxArea.toStringAsFixed(0)} pixels²');
      
      // Convert contour to points
      final contourPoints = <cv.Point2f>[];
      for (int i = 0; i < largestContour.length; i++) {
        contourPoints.add(cv.Point2f(
          largestContour[i].x.toDouble(),
          largestContour[i].y.toDouble(),
        ));
      }
      
      print('    Contour Points: ${contourPoints.length}');
      
      // Detect baseline (horizontal line at the bottom of the droplet)
      final boundingRect = cv.boundingRect(largestContour);
      final baselineY = boundingRect.y + boundingRect.height;
      final baselinePoints = [
        _Offset(boundingRect.x.toDouble(), baselineY.toDouble()),
        _Offset((boundingRect.x + boundingRect.width).toDouble(), baselineY.toDouble()),
      ];
      
      print('    Bounding Rect: (${boundingRect.x}, ${boundingRect.y}) ${boundingRect.width} x ${boundingRect.height}');
      print('    Baseline Y: ${baselineY.toStringAsFixed(1)}');
      
      // Calculate contact angles using advanced method
      final angles = await _calculateAdvancedContactAngles(contourPoints, baselinePoints);
      
      // Get expected angle
      final expectedAngle = expectedAngles[fileName] ?? 0.0;
      
      print('  📐 Contact Angle Results:');
      print('    Left Angle: ${angles['left']?.toStringAsFixed(3)}°');
      print('    Right Angle: ${angles['right']?.toStringAsFixed(3)}°');
      print('    Average Angle: ${angles['average']?.toStringAsFixed(3)}°');
      print('    Uncertainty: ${angles['uncertainty']?.toStringAsFixed(3)}°');
      print('    Expected Angle: ${expectedAngle.toStringAsFixed(3)}°');
      
      // Calculate error
      final error = (angles['average'] ?? 0.0) - expectedAngle;
      print('    Error: ${error.toStringAsFixed(3)}°');
      
      // Validate results
      final validation = _validateResults(angles, expectedAngle);
      print('  🎯 Validation: $validation');
      
    } catch (e) {
      print('  ❌ Error: $e');
    }
  }
  
  static Future<Map<String, double>> _calculateAdvancedContactAngles(
      List<cv.Point2f> contourPoints, List<_Offset> baselinePoints) async {
    
    // Find intersection points between contour and baseline
    final intersections = <_Offset>[];
    final baselineY = baselinePoints[0].dy;
    
    print('    🔍 Finding intersections with baseline Y: ${baselineY.toStringAsFixed(1)}');
    
    for (int i = 0; i < contourPoints.length - 1; i++) {
      final p1 = contourPoints[i];
      final p2 = contourPoints[i + 1];
      
      // Check if line segment crosses baseline
      if ((p1.y - baselineY) * (p2.y - baselineY) < 0) {
        // Calculate intersection point
        final t = (baselineY - p1.y) / (p2.y - p1.y);
        final x = p1.x + t * (p2.x - p1.x);
        intersections.add(_Offset(x, baselineY));
      }
    }
    
    print('    Intersections Found: ${intersections.length}');
    
    if (intersections.length < 2) {
      throw Exception('Could not find two intersection points');
    }
    
    // Sort intersections by x-coordinate
    intersections.sort((a, b) => a.dx.compareTo(b.dx));
    
    final leftIntersection = intersections.first;
    final rightIntersection = intersections.last;
    
    print('    Left Intersection: (${leftIntersection.dx.toStringAsFixed(1)}, ${leftIntersection.dy.toStringAsFixed(1)})');
    print('    Right Intersection: (${rightIntersection.dx.toStringAsFixed(1)}, ${rightIntersection.dy.toStringAsFixed(1)})');
    
    // Calculate tangent angles at intersection points using advanced method
    final leftAngle = _calculateAdvancedTangentAngle(contourPoints, leftIntersection);
    final rightAngle = _calculateAdvancedTangentAngle(contourPoints, rightIntersection);
    
    print('    Raw Left Angle: ${leftAngle.toStringAsFixed(3)}°');
    print('    Raw Right Angle: ${rightAngle.toStringAsFixed(3)}°');
    
    // Convert to contact angles (subtract from 180 degrees)
    final leftContactAngle = 180 - leftAngle;
    final rightContactAngle = 180 - rightAngle;
    
    final averageAngle = (leftContactAngle + rightContactAngle) / 2;
    final uncertainty = _calculateUncertainty(contourPoints, leftContactAngle, rightContactAngle);
    
    return {
      'left': leftContactAngle,
      'right': rightContactAngle,
      'average': averageAngle,
      'uncertainty': uncertainty,
    };
  }
  
  static double _calculateAdvancedTangentAngle(List<cv.Point2f> contourPoints, _Offset point) {
    // Find the closest contour point
    double minDistance = double.infinity;
    int closestIndex = 0;
    
    for (int i = 0; i < contourPoints.length; i++) {
      final distance = sqrt(
        pow(contourPoints[i].x - point.dx, 2) + 
        pow(contourPoints[i].y - point.dy, 2)
      );
      if (distance < minDistance) {
        minDistance = distance;
        closestIndex = i;
      }
    }
    
    // Calculate tangent using multiple neighboring points for better accuracy
    final windowSize = 5;
    final startIndex = (closestIndex - windowSize + contourPoints.length) % contourPoints.length;
    final endIndex = (closestIndex + windowSize) % contourPoints.length;
    
    List<cv.Point2f> tangentPoints = [];
    
    if (startIndex < endIndex) {
      tangentPoints = contourPoints.sublist(startIndex, endIndex + 1);
    } else {
      tangentPoints = [
        ...contourPoints.sublist(startIndex),
        ...contourPoints.sublist(0, endIndex + 1)
      ];
    }
    
    // Fit a line to the tangent points
    final (slope, _) = _fitLine(tangentPoints);
    final angle = atan(slope) * 180 / pi;
    
    return angle < 0 ? angle + 360 : angle;
  }
  
  static (double, double) _fitLine(List<cv.Point2f> points) {
    if (points.length < 2) return (0.0, 0.0);
    
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    final n = points.length;
    
    for (final point in points) {
      sumX += point.x;
      sumY += point.y;
      sumXY += point.x * point.y;
      sumX2 += point.x * point.x;
    }
    
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;
    
    return (slope, intercept);
  }
  
  static double _calculateUncertainty(List<cv.Point2f> contourPoints, double leftAngle, double rightAngle) {
    // Calculate uncertainty based on contour smoothness and angle difference
    final angleDifference = (leftAngle - rightAngle).abs();
    final contourSmoothness = _calculateContourSmoothness(contourPoints);
    
    // Combine factors for uncertainty estimation
    final uncertainty = angleDifference / 2 + (1 - contourSmoothness) * 2;
    
    return uncertainty;
  }
  
  static double _calculateContourSmoothness(List<cv.Point2f> contourPoints) {
    if (contourPoints.length < 3) return 0.0;
    
    double totalCurvature = 0.0;
    int validSegments = 0;
    
    for (int i = 1; i < contourPoints.length - 1; i++) {
      final prev = contourPoints[i - 1];
      final curr = contourPoints[i];
      final next = contourPoints[i + 1];
      
      final dx1 = curr.x - prev.x;
      final dy1 = curr.y - prev.y;
      final dx2 = next.x - curr.x;
      final dy2 = next.y - curr.y;
      
      final crossProduct = dx1 * dy2 - dy1 * dx2;
      final magnitude1 = sqrt(dx1 * dx1 + dy1 * dy1);
      final magnitude2 = sqrt(dx2 * dx2 + dy2 * dy2);
      
      if (magnitude1 > 0 && magnitude2 > 0) {
        final curvature = crossProduct / (magnitude1 * magnitude2);
        totalCurvature += curvature.abs();
        validSegments++;
      }
    }
    
    if (validSegments == 0) return 0.0;
    
    final averageCurvature = totalCurvature / validSegments;
    final smoothness = 1.0 / (1.0 + averageCurvature);
    
    return smoothness;
  }
  
  static String _validateResults(Map<String, double> results, double expectedAngle) {
    final angle = results['average'] ?? 0.0;
    final uncertainty = results['uncertainty'] ?? 0.0;
    final error = (angle - expectedAngle).abs();
    
    // Check if angles are in reasonable range (0-180 degrees)
    if (angle < 0 || angle > 180) {
      return '❌ Invalid angle range: $angle°';
    }
    
    // Check if uncertainty is reasonable (< 10 degrees)
    if (uncertainty > 10) {
      return '⚠️ High uncertainty: ${uncertainty.toStringAsFixed(2)}°';
    }
    
    // Check if error is acceptable (< 5 degrees)
    if (error > 5) {
      return '⚠️ High error: ${error.toStringAsFixed(2)}° (expected: ${expectedAngle.toStringAsFixed(2)}°)';
    }
    
    return '✅ Valid results (error: ${error.toStringAsFixed(2)}°)';
  }
}

/// Simple Offset class for 2D points
class _Offset {
  final double dx;
  final double dy;
  
  const _Offset(this.dx, this.dy);
  
  @override
  String toString() => 'Offset($dx, $dy)';
}

/// Main function to run the debug
void main() async {
  try {
    await ContactAngleDebugger.debugContactAngles();
  } catch (e) {
    print('❌ Debug execution failed: $e');
  }
} 