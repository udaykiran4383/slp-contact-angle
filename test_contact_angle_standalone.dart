import 'dart:io';
import 'dart:math';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Simple Offset class for 2D points
class Offset {
  final double dx;
  final double dy;
  
  const Offset(this.dx, this.dy);
  
  @override
  String toString() => 'Offset($dx, $dy)';
}

/// Standalone test script for contact angle detection
class ContactAngleTester {
  static const String testImagesDir = 'PFOTES';
  
  static Future<void> runTests() async {
    print('🔬 Starting Contact Angle Detection Tests...\n');
    
    final testResults = <String, Map<String, dynamic>>{};
    final testImages = await _getTestImages();
    
    if (testImages.isEmpty) {
      print('❌ No test images found in $testImagesDir directory');
      return;
    }
    
    print('📁 Found ${testImages.length} test images\n');
    
    for (final imagePath in testImages) {
      print('🔄 Testing: ${imagePath.split('/').last}');
      
      try {
        final results = await _testSingleImage(imagePath);
        testResults[imagePath] = results;
        
        // Print immediate results
        _printTestResults(imagePath.split('/').last, results);
        
      } catch (e) {
        print('❌ Error testing $imagePath: $e');
        testResults[imagePath] = {
          'error': e.toString(),
          'success': false,
        };
      }
      
      print(''); // Empty line for readability
    }
    
    // Generate comprehensive report
    await _generateTestReport(testResults);
  }
  
  static Future<List<String>> _getTestImages() async {
    final dir = Directory(testImagesDir);
    if (!await dir.exists()) {
      return [];
    }
    
    final files = await dir.list().toList();
    final imageFiles = <String>[];
    
    for (final file in files) {
      if (file is File && 
          (file.path.endsWith('.jpg') || 
           file.path.endsWith('.jpeg') || 
           file.path.endsWith('.png'))) {
        imageFiles.add(file.path);
      }
    }
    
    return imageFiles;
  }
  
  static Future<Map<String, dynamic>> _testSingleImage(String imagePath) async {
    final startTime = DateTime.now();
    
    // Load image
    final image = cv.imread(imagePath);
    if (image.isEmpty) {
      throw Exception('Failed to load image');
    }
    
    // Convert to grayscale
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    
    // Apply Gaussian blur
    final blurred = cv.gaussianBlur(gray, (5, 5), 1.0);
    
    // Apply threshold
    final (thresh, _) = cv.threshold(blurred, 0, 255, cv.THRESH_BINARY + cv.THRESH_OTSU);
    
    // Find contours
    final (contours, hierarchy) = cv.findContours(
        thresh, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    
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
    
    // Convert contour to points
    final contourPoints = <cv.Point2f>[];
    for (int i = 0; i < largestContour.length; i++) {
      contourPoints.add(cv.Point2f(
        largestContour[i].x.toDouble(),
        largestContour[i].y.toDouble(),
      ));
    }
    
    // Detect baseline (horizontal line at the bottom of the droplet)
    final boundingRect = cv.boundingRect(largestContour);
    final baselineY = boundingRect.y + boundingRect.height;
    final baselinePoints = [
      Offset(boundingRect.x.toDouble(), baselineY.toDouble()),
      Offset((boundingRect.x + boundingRect.width).toDouble(), baselineY.toDouble()),
    ];
    
    // Calculate contact angles using simplified method
    final angles = await _calculateContactAngles(contourPoints, baselinePoints);
    
    final processingTime = DateTime.now().difference(startTime).inMilliseconds;
    
    return {
      'leftAngle': angles['left'],
      'rightAngle': angles['right'],
      'averageAngle': angles['average'],
      'uncertainty': angles['uncertainty'],
      'baselinePoints': baselinePoints,
      'contourPoints': contourPoints,
      'processingTime': processingTime,
      'success': true,
    };
  }
  
  static Future<Map<String, double>> _calculateContactAngles(
      List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
    
    // Find intersection points between contour and baseline
    final intersections = <Offset>[];
    final baselineY = baselinePoints[0].dy;
    
    for (int i = 0; i < contourPoints.length - 1; i++) {
      final p1 = contourPoints[i];
      final p2 = contourPoints[i + 1];
      
      // Check if line segment crosses baseline
      if ((p1.y - baselineY) * (p2.y - baselineY) < 0) {
        // Calculate intersection point
        final t = (baselineY - p1.y) / (p2.y - p1.y);
        final x = p1.x + t * (p2.x - p1.x);
        intersections.add(Offset(x, baselineY));
      }
    }
    
    if (intersections.length < 2) {
      throw Exception('Could not find two intersection points');
    }
    
    // Sort intersections by x-coordinate
    intersections.sort((a, b) => a.dx.compareTo(b.dx));
    
    final leftIntersection = intersections.first;
    final rightIntersection = intersections.last;
    
    // Calculate tangent angles at intersection points
    final leftAngle = _calculateTangentAngle(contourPoints, leftIntersection);
    final rightAngle = _calculateTangentAngle(contourPoints, rightIntersection);
    
    // Convert to contact angles (subtract from 180 degrees)
    final leftContactAngle = 180 - leftAngle;
    final rightContactAngle = 180 - rightAngle;
    
    final averageAngle = (leftContactAngle + rightContactAngle) / 2;
    final uncertainty = (leftContactAngle - rightContactAngle).abs() / 2;
    
    return {
      'left': leftContactAngle,
      'right': rightContactAngle,
      'average': averageAngle,
      'uncertainty': uncertainty,
    };
  }
  
  static double _calculateTangentAngle(List<cv.Point2f> contourPoints, Offset point) {
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
    
    // Calculate tangent using neighboring points
    final prevIndex = (closestIndex - 1 + contourPoints.length) % contourPoints.length;
    final nextIndex = (closestIndex + 1) % contourPoints.length;
    
    final prevPoint = contourPoints[prevIndex];
    final nextPoint = contourPoints[nextIndex];
    
    final dx = nextPoint.x - prevPoint.x;
    final dy = nextPoint.y - prevPoint.y;
    
    final angle = atan2(dy, dx) * 180 / pi;
    return angle < 0 ? angle + 360 : angle;
  }
  
  static void _printTestResults(String imageName, Map<String, dynamic> results) {
    if (results['success'] == false) {
      print('  ❌ Failed: ${results['error']}');
      return;
    }
    
    print('  ✅ Detection Results:');
    print('    Left Angle: ${results['leftAngle']?.toStringAsFixed(2)}°');
    print('    Right Angle: ${results['rightAngle']?.toStringAsFixed(2)}°');
    print('    Average Angle: ${results['averageAngle']?.toStringAsFixed(2)}°');
    print('    Uncertainty: ${results['uncertainty']?.toStringAsFixed(2)}°');
    print('    Processing Time: ${results['processingTime']}ms');
    
    // Validate results
    final validation = _validateResults(results);
    print('  🎯 Validation: $validation');
  }
  
  static String _validateResults(Map<String, dynamic> results) {
    final angle = results['averageAngle'] ?? 0.0;
    final uncertainty = results['uncertainty'] ?? 0.0;
    
    // Check if angles are in reasonable range (0-180 degrees)
    if (angle < 0 || angle > 180) {
      return '❌ Invalid angle range: $angle°';
    }
    
    // Check if uncertainty is reasonable (< 10 degrees)
    if (uncertainty > 10) {
      return '⚠️ High uncertainty: ${uncertainty.toStringAsFixed(2)}°';
    }
    
    // Check if angle is in expected range for water droplets (typically 0-120 degrees)
    if (angle > 120) {
      return '⚠️ Unusually high angle: ${angle.toStringAsFixed(2)}°';
    }
    
    return '✅ Valid results';
  }
  
  static Future<void> _generateTestReport(Map<String, Map<String, dynamic>> testResults) async {
    print('\n📊 GENERATING COMPREHENSIVE TEST REPORT\n');
    print('=' * 60);
    
    int totalTests = testResults.length;
    int successfulTests = 0;
    int failedTests = 0;
    double totalProcessingTime = 0;
    List<double> allAngles = [];
    List<double> allUncertainties = [];
    
    for (final entry in testResults.entries) {
      final results = entry.value;
      
      if (results['success'] == true) {
        successfulTests++;
        final processingTime = results['processingTime'] ?? 0;
        
        totalProcessingTime += processingTime;
        allAngles.add(results['averageAngle'] ?? 0.0);
        allUncertainties.add(results['uncertainty'] ?? 0.0);
        
      } else {
        failedTests++;
      }
    }
    
    // Calculate statistics
    final successRate = (successfulTests / totalTests) * 100;
    final avgProcessingTime = totalProcessingTime / successfulTests;
    final avgAngle = allAngles.isNotEmpty ? allAngles.reduce((a, b) => a + b) / allAngles.length : 0.0;
    final avgUncertainty = allUncertainties.isNotEmpty ? allUncertainties.reduce((a, b) => a + b) / allUncertainties.length : 0.0;
    
    print('📈 TEST SUMMARY');
    print('Total Tests: $totalTests');
    print('Successful: $successfulTests');
    print('Failed: $failedTests');
    print('Success Rate: ${successRate.toStringAsFixed(1)}%');
    print('');
    
    print('⏱️ PERFORMANCE METRICS');
    print('Average Processing Time: ${avgProcessingTime.toStringAsFixed(0)}ms');
    print('');
    
    print('📐 ANGLE STATISTICS');
    print('Average Contact Angle: ${avgAngle.toStringAsFixed(2)}°');
    print('Average Uncertainty: ${avgUncertainty.toStringAsFixed(2)}°');
    print('');
    
    print('🎯 QUALITY ASSESSMENT');
    if (avgUncertainty < 1.0) {
      print('Precision: 🟢 HIGH');
    } else if (avgUncertainty < 2.0) {
      print('Precision: 🟡 MEDIUM');
    } else {
      print('Precision: 🔴 LOW');
    }
    
    if (avgAngle >= 0 && avgAngle <= 120) {
      print('Angle Range: 🟢 VALID');
    } else {
      print('Angle Range: 🔴 OUT OF RANGE');
    }
    
    print('\n' + '=' * 60);
    print('✅ Contact Angle Detection Test Complete!');
  }
}

/// Main function to run the tests
void main() async {
  try {
    await ContactAngleTester.runTests();
  } catch (e) {
    print('❌ Test execution failed: $e');
  }
} 