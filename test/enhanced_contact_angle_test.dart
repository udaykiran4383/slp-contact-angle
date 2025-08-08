import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:contact_angle_app/contact_angle_calculation.dart';

void main() {
  group('Enhanced Contact Angle Calculation Tests', () {
    
    test('should handle near-horizontal tangents gracefully', () {
      // Test very small slopes that should use smooth interpolation
      final testCases = [
        {'tangentSlope': 1e-4, 'expectedRange': [0.0, 5.0]},
        {'tangentSlope': -1e-4, 'expectedRange': [175.0, 180.0]},
        {'tangentSlope': 1e-5, 'expectedRange': [0.0, 2.0]},
        {'tangentSlope': -1e-5, 'expectedRange': [178.0, 180.0]},
      ];

      for (var testCase in testCases) {
        double result = EnhancedContactAngleCalculator.calculateEnhancedContactAngle(
            testCase['tangentSlope'] as double, 0.0);
        List<double> expectedRange = testCase['expectedRange'] as List<double>;
        double minExpected = expectedRange[0];
        double maxExpected = expectedRange[1];
        
        expect(result, greaterThanOrEqualTo(minExpected));
        expect(result, lessThanOrEqualTo(maxExpected));
        
        print('✅ Edge case test passed: ${testCase['tangentSlope']}° → ${result.toStringAsFixed(2)}° (expected: ${minExpected}-${maxExpected}°)');
      }
    });

    test('should handle vertical tangents correctly', () {
      // Test vertical tangents
      final testCases = [
        {'tangentSlope': double.infinity, 'baselineSlope': 0.0, 'expected': 90.0},
        {'tangentSlope': double.infinity, 'baselineSlope': 1.0, 'expected': 45.0},
        {'tangentSlope': double.infinity, 'baselineSlope': -1.0, 'expected': 45.0},
      ];

      for (var testCase in testCases) {
        double result = EnhancedContactAngleCalculator.calculateEnhancedContactAngle(
            testCase['tangentSlope'] as double, testCase['baselineSlope'] as double);
        double expected = testCase['expected'] as double;
        double tolerance = 1.0;
        
        expect((result - expected).abs(), lessThan(tolerance),
            reason: 'Expected ${expected}°, got ${result}° for vertical tangent');
        
        print('✅ Vertical tangent test passed: ${testCase['tangentSlope']}° → ${result.toStringAsFixed(2)}° (expected: ${expected}°)');
      }
    });

    test('should handle horizontal baseline correctly', () {
      // Test horizontal baseline cases
      final testCases = [
        {'tangentSlope': 1.0, 'expected': 45.0}, // 45 degrees
        {'tangentSlope': -1.0, 'expected': 135.0}, // 135 degrees
        {'tangentSlope': 0.577, 'expected': 30.0}, // 30 degrees (tan(30°))
        {'tangentSlope': -0.577, 'expected': 150.0}, // 150 degrees (tan(150°))
        {'tangentSlope': 1.732, 'expected': 60.0}, // 60 degrees (tan(60°))
        {'tangentSlope': -1.732, 'expected': 120.0}, // 120 degrees (tan(120°))
      ];

      for (var testCase in testCases) {
        double result = EnhancedContactAngleCalculator.calculateEnhancedContactAngle(
            testCase['tangentSlope'] as double, 0.0);
        double expected = testCase['expected'] as double;
        double tolerance = 0.5;
        
        expect((result - expected).abs(), lessThan(tolerance),
            reason: 'Expected ${expected}°, got ${result}° for tangent slope ${testCase['tangentSlope']}');
        
        print('✅ Horizontal baseline test passed: ${testCase['tangentSlope']}° → ${result.toStringAsFixed(2)}° (expected: ${expected}°)');
      }
    });

    test('should handle numerical stability issues', () {
      // Test cases that should demonstrate improved numerical stability
      final stabilityTests = [
        {'tangentSlope': 1e-10, 'expectedRange': [0.0, 1.0]}, // Very small positive
        {'tangentSlope': -1e-10, 'expectedRange': [179.0, 180.0]}, // Very small negative
        {'tangentSlope': 1e-8, 'expectedRange': [0.0, 1.0]}, // Small positive
        {'tangentSlope': -1e-8, 'expectedRange': [179.0, 180.0]}, // Small negative
      ];

      for (var testCase in stabilityTests) {
        double result = EnhancedContactAngleCalculator.calculateEnhancedContactAngle(
            testCase['tangentSlope'] as double, 0.0);
        List<double> expectedRange = testCase['expectedRange'] as List<double>;
        double minExpected = expectedRange[0];
        double maxExpected = expectedRange[1];
        
        expect(result, greaterThanOrEqualTo(minExpected));
        expect(result, lessThanOrEqualTo(maxExpected));
        
        print('✅ Stability test passed: ${testCase['tangentSlope']}° → ${result.toStringAsFixed(2)}° (expected: ${minExpected}-${maxExpected}°)');
      }
    });

    test('should handle caching correctly', () {
      // Test caching functionality
      List<cv.Point2f> contourPoints = [
        cv.Point2f(100.0, 100.0),
        cv.Point2f(101.0, 101.0),
        cv.Point2f(102.0, 102.0),
        cv.Point2f(103.0, 103.0),
        cv.Point2f(104.0, 104.0),
      ];

      List<Offset> baselinePoints = [
        Offset(100.0, 100.0),
        Offset(104.0, 100.0),
      ];

      // Clear cache first
      EnhancedContactAngleCalculator.clearCache();
      
      // Check initial cache stats
      var initialStats = EnhancedContactAngleCalculator.getCacheStats();
      expect(initialStats['size'], equals(0));
      
      print('✅ Caching test passed: Cache cleared successfully');
    });

    test('should handle downsampling correctly', () {
      // Test downsampling functionality
      List<cv.Point2f> originalPoints = [];
      for (int i = 0; i < 100; i++) {
        originalPoints.add(cv.Point2f(i.toDouble(), i.toDouble()));
      }

      // Test different downsampling factors
      final testFactors = [0.5, 0.25, 0.1];
      
      for (var factor in testFactors) {
        List<cv.Point2f> downsampled = EnhancedContactAngleCalculator.downsampleContour(originalPoints, factor: factor);
        
        // Verify downsampling
        expect(downsampled.length, lessThanOrEqualTo(originalPoints.length));
        expect(downsampled.length, greaterThanOrEqualTo(5)); // Minimum required points
        
        print('✅ Downsampling test passed: ${originalPoints.length} → ${downsampled.length} points (factor: $factor)');
      }
    });

    test('should handle error cases gracefully', () {
      // Test insufficient points
      List<cv.Point2f> insufficientPoints = [
        cv.Point2f(100.0, 100.0),
        cv.Point2f(101.0, 101.0),
        cv.Point2f(102.0, 102.0),
      ];

      List<Offset> baselinePoints = [
        Offset(100.0, 100.0),
        Offset(102.0, 100.0),
      ];

      // Should throw exception for insufficient points
      expect(
        () => EnhancedContactAngleCalculator.calculateContactAnglesEnhanced(
            insufficientPoints, baselinePoints),
        throwsException,
      );
      
      print('✅ Error handling test passed: Insufficient points exception thrown correctly');
    });

    test('should provide consistent results for same inputs', () async {
      // Test consistency of results
      List<cv.Point2f> contourPoints = [];
      double radius = 50.0;
      double centerX = 100.0;
      double centerY = 100.0;
      
      // Generate semi-circle points
      for (int i = 0; i <= 180; i += 5) {
        double angle = i * pi / 180;
        double x = centerX + radius * cos(angle);
        double y = centerY - radius * sin(angle);
        contourPoints.add(cv.Point2f(x, y));
      }

      List<Offset> baselinePoints = [
        Offset(centerX - radius, centerY),
        Offset(centerX + radius, centerY),
      ];

      // Run calculation multiple times
      final result1 = await EnhancedContactAngleCalculator.calculateContactAnglesEnhanced(
          contourPoints, baselinePoints);
      final result2 = await EnhancedContactAngleCalculator.calculateContactAnglesEnhanced(
          contourPoints, baselinePoints);
      
      // Results should be identical (or very close due to floating point)
      double avg1 = result1['average'] as double;
      double avg2 = result2['average'] as double;
      expect((avg1 - avg2).abs(), lessThan(1e-6));
      
      double left1 = result1['left'] as double;
      double left2 = result2['left'] as double;
      expect((left1 - left2).abs(), lessThan(1e-6));
      
      double right1 = result1['right'] as double;
      double right2 = result2['right'] as double;
      expect((right1 - right2).abs(), lessThan(1e-6));
      
      print('✅ Consistency test passed: Results are consistent across multiple runs');
    });
  });
}
