import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';
import 'package:flutter/material.dart';
import 'lib/contact_angle_calculation.dart';

void main() {
  group('Contact Angle Calculation Tests', () {
    test('Test droplet contact angle calculation with horizontal baseline', () {
      // Test cases with known expected results
      final testCases = [
        {'tangentSlope': 1.0, 'expected': 45.0}, // 45 degrees
        {'tangentSlope': -1.0, 'expected': 135.0}, // 135 degrees
        {'tangentSlope': 0.577, 'expected': 30.0}, // 30 degrees (tan(30°))
        {'tangentSlope': -0.577, 'expected': 150.0}, // 150 degrees (tan(150°))
        {'tangentSlope': 1.732, 'expected': 60.0}, // 60 degrees (tan(60°))
        {'tangentSlope': -1.732, 'expected': 120.0}, // 120 degrees (tan(120°))
      ];

      for (var testCase in testCases) {
        double result = _calculateDropletContactAngle(testCase['tangentSlope']!, 0.0);
        double expected = testCase['expected']!;
        double tolerance = 1.0; // 1 degree tolerance
        
        expect((result - expected).abs(), lessThan(tolerance),
            reason: 'Expected ${expected}°, got ${result}° for tangent slope ${testCase['tangentSlope']}');
      }
    });

    test('Test contact angle calculation with vertical tangent', () {
      double result = _calculateDropletContactAngle(double.infinity, 0.0);
      expect(result, closeTo(90.0, 1.0));
    });

    test('Test contact angle calculation with non-horizontal baseline', () {
      // Test with a slight slope baseline
      double result = _calculateDropletContactAngle(1.0, 0.1);
      expect(result, greaterThan(0.0));
      expect(result, lessThan(180.0));
    });

    test('Test full contact angle calculation with sample data', () async {
      // Create sample contour points (semi-circle)
      List<cv.Point2f> contourPoints = [];
      double radius = 50.0;
      double centerX = 100.0;
      double centerY = 100.0;
      
      // Generate semi-circle points
      for (int i = 0; i <= 180; i += 5) {
        double angle = i * pi / 180;
        double x = centerX + radius * cos(angle);
        double y = centerY - radius * sin(angle); // Negative for image coordinates
        contourPoints.add(cv.Point2f(x, y));
      }

      // Create baseline points (horizontal line)
      List<Offset> baselinePoints = [
        Offset(centerX - radius, centerY),
        Offset(centerX + radius, centerY),
      ];

      // Calculate contact angles
      final results = await calculateContactAngles(contourPoints, baselinePoints);
      
      // Verify results are reasonable
      expect(results['left'], greaterThan(0.0));
      expect(results['right'], greaterThan(0.0));
      expect(results['average'], greaterThan(0.0));
      expect(results['average'], lessThan(180.0));
      expect(results['uncertainty'], greaterThan(0.0));
      expect(results['uncertainty'], lessThan(10.0));
      
      print('Test Results:');
      print('Left Angle: ${results['left']?.toStringAsFixed(2)}°');
      print('Right Angle: ${results['right']?.toStringAsFixed(2)}°');
      print('Average Angle: ${results['average']?.toStringAsFixed(2)}°');
      print('Uncertainty: ${results['uncertainty']?.toStringAsFixed(2)}°');
    });

    test('Test contact angle calculation validation', () async {
      final validationResults = await testContactAngleCalculation();
      
      expect(validationResults['all_tests_passed'], isTrue);
      expect(validationResults['test1_vertical_tangent'], closeTo(90.0, 1.0));
      expect(validationResults['test2_45_degree'], closeTo(45.0, 1.0));
      expect(validationResults['test3_135_degree'], closeTo(135.0, 1.0));
      expect(validationResults['test4_30_degree'], closeTo(30.0, 1.0));
      expect(validationResults['test5_150_degree'], closeTo(150.0, 1.0));
      
      print('Validation Results:');
      print('Vertical Tangent: ${validationResults['test1_vertical_tangent']?.toStringAsFixed(2)}°');
      print('45° Test: ${validationResults['test2_45_degree']?.toStringAsFixed(2)}°');
      print('135° Test: ${validationResults['test3_135_degree']?.toStringAsFixed(2)}°');
      print('30° Test: ${validationResults['test4_30_degree']?.toStringAsFixed(2)}°');
      print('150° Test: ${validationResults['test5_150_degree']?.toStringAsFixed(2)}°');
    });
  });
}

/// Helper function to test the droplet contact angle calculation
double _calculateDropletContactAngle(double tangentSlope, double baselineSlope) {
  // Handle vertical tangents
  if (tangentSlope.isInfinite) {
    double baselineAngle = atan(baselineSlope) * 180 / pi;
    return 90.0 - baselineAngle.abs();
  }
  
  // Handle horizontal baseline (most common case for droplets)
  if (baselineSlope.abs() < 1e-6) {
    // Baseline is horizontal
    double tangentAngle = atan(tangentSlope) * 180 / pi;
    
    // For a droplet, the contact angle is the angle inside the droplet
    // This means we need to consider the direction of the tangent
    double contactAngle;
    
    if (tangentSlope > 0) {
      // Tangent is pointing upward (positive slope)
      contactAngle = tangentAngle;
    } else {
      // Tangent is pointing downward (negative slope)
      contactAngle = 180 - tangentAngle.abs();
    }
    
    // Ensure the angle is in the correct range (0-180 degrees)
    if (contactAngle < 0) {
      contactAngle = 180 + contactAngle;
    } else if (contactAngle > 180) {
      contactAngle = 360 - contactAngle;
    }
    
    return contactAngle;
  }
  
  // General case: both tangent and baseline have slopes
  double tangentAngle = atan(tangentSlope) * 180 / pi;
  double baselineAngle = atan(baselineSlope) * 180 / pi;
  
  // Calculate the angle between tangent and baseline
  double angleDifference = (tangentAngle - baselineAngle).abs();
  
  // Ensure the angle is in the correct range (0-180 degrees)
  if (angleDifference > 180) {
    angleDifference = 360 - angleDifference;
  }
  
  // For a droplet, the contact angle is the angle inside the droplet
  double contactAngle = angleDifference;
  
  // Ensure the angle is in the correct range for contact angles (0-180 degrees)
  if (contactAngle > 180) {
    contactAngle = 360 - contactAngle;
  }
  
  // Additional correction: if the tangent is pointing downward relative to baseline, we need to adjust
  if (tangentSlope < baselineSlope) {
    contactAngle = 180 - contactAngle;
  }
  
  return contactAngle;
} 