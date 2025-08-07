import 'package:flutter_test/flutter_test.dart';
import 'dart:math';

void main() {
  group('Contact Angle Calculation Algorithm Tests', () {
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
        
        print('✅ Test passed: ${testCase['tangentSlope']}° → ${result.toStringAsFixed(2)}° (expected: ${expected}°)');
      }
    });

    test('Test contact angle calculation with vertical tangent', () {
      double result = _calculateDropletContactAngle(double.infinity, 0.0);
      expect(result, closeTo(90.0, 1.0));
      print('✅ Vertical tangent test passed: ${result.toStringAsFixed(2)}°');
    });

    test('Test contact angle calculation with non-horizontal baseline', () {
      // Test with a slight slope baseline
      double result = _calculateDropletContactAngle(1.0, 0.1);
      expect(result, greaterThan(0.0));
      expect(result, lessThan(180.0));
      print('✅ Non-horizontal baseline test passed: ${result.toStringAsFixed(2)}°');
    });

    test('Test specific angle ranges for your use case', () {
      // Test angles in the range you mentioned (110-140 degrees)
      final testCases = [
        {'tangentSlope': -0.839, 'expected': 130.0}, // tan(130°)
        {'tangentSlope': -0.700, 'expected': 125.0}, // tan(125°)
        {'tangentSlope': -0.577, 'expected': 120.0}, // tan(120°)
        {'tangentSlope': -0.466, 'expected': 115.0}, // tan(115°)
        {'tangentSlope': -0.364, 'expected': 110.0}, // tan(110°)
      ];

      for (var testCase in testCases) {
        double result = _calculateDropletContactAngle(testCase['tangentSlope']!, 0.0);
        double expected = testCase['expected']!;
        double tolerance = 1.0;
        
        expect((result - expected).abs(), lessThan(tolerance),
            reason: 'Expected ${expected}°, got ${result}° for tangent slope ${testCase['tangentSlope']}');
        
        print('✅ Range test passed: ${testCase['tangentSlope']}° → ${result.toStringAsFixed(2)}° (expected: ${expected}°)');
      }
    });

    test('Test edge cases and boundary conditions', () {
      // Test edge cases
      expect(_calculateDropletContactAngle(0.0, 0.0), closeTo(0.0, 1.0)); // Horizontal tangent
      expect(_calculateDropletContactAngle(double.infinity, 0.0), closeTo(90.0, 1.0)); // Vertical tangent
      expect(_calculateDropletContactAngle(-0.001, 0.0), greaterThan(179.0)); // Near horizontal downward
      
      print('✅ Edge cases test passed');
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