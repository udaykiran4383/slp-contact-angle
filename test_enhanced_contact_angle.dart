import 'package:flutter_test/flutter_test.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';
import 'package:flutter/material.dart';
import 'lib/contact_angle_calculation.dart';

void main() {
  group('Enhanced Contact Angle Calculation Tests', () {
    test('Test enhanced contact angle calculation with sample data', () async {
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

      // Calculate contact angles using enhanced algorithm
      final results = await EnhancedContactAngleCalculator.calculateContactAnglesEnhanced(
          contourPoints, baselinePoints);
      
      // Verify results are reasonable
      expect(results['left'], greaterThan(0.0));
      expect(results['right'], greaterThan(0.0));
      expect(results['average'], greaterThan(0.0));
      expect(results['average'], lessThan(180.0));
      expect(results['uncertainty']['total'], greaterThan(0.0));
      expect(results['uncertainty']['total'], lessThan(5.0));
      
      // Verify quality metrics
      expect(results['qualityMetrics']['overallConfidence'], greaterThan(0.0));
      expect(results['qualityMetrics']['overallConfidence'], lessThanOrEqualTo(1.0));
      
      print('Enhanced Test Results:');
      print('Left Angle: ${results['left']?.toStringAsFixed(2)}°');
      print('Right Angle: ${results['right']?.toStringAsFixed(2)}°');
      print('Average Angle: ${results['average']?.toStringAsFixed(2)}°');
      print('Total Uncertainty: ${results['uncertainty']['total']?.toStringAsFixed(2)}°');
      print('Overall Confidence: ${results['qualityMetrics']['overallConfidence']?.toStringAsFixed(3)}');
      print('Processing Method: ${results['processingMethod']}');
    });

    test('Test backward compatibility with legacy function', () async {
      // Create sample data
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

      // Create baseline points
      List<Offset> baselinePoints = [
        Offset(centerX - radius, centerY),
        Offset(centerX + radius, centerY),
      ];

      // Test backward compatibility
      final legacyResults = await calculateContactAngles(contourPoints, baselinePoints);
      
      // Verify legacy format
      expect(legacyResults.containsKey('left'), isTrue);
      expect(legacyResults.containsKey('right'), isTrue);
      expect(legacyResults.containsKey('average'), isTrue);
      expect(legacyResults.containsKey('uncertainty'), isTrue);
      expect(legacyResults.containsKey('eccentricity'), isTrue);
      expect(legacyResults.containsKey('bondNumber'), isTrue);
      
      print('Backward Compatibility Test Results:');
      print('Left Angle: ${legacyResults['left']?.toStringAsFixed(2)}°');
      print('Right Angle: ${legacyResults['right']?.toStringAsFixed(2)}°');
      print('Average Angle: ${legacyResults['average']?.toStringAsFixed(2)}°');
      print('Uncertainty: ${legacyResults['uncertainty']?.toStringAsFixed(2)}°');
      print('Eccentricity: ${legacyResults['eccentricity']?.toStringAsFixed(3)}');
    });

    test('Test enhanced algorithm with different droplet shapes', () async {
      // Test with different droplet shapes
      final testCases = [
        {
          'name': 'Semi-circle',
          'radius': 50.0,
          'centerX': 100.0,
          'centerY': 100.0,
          'startAngle': 0,
          'endAngle': 180,
        },
        {
          'name': 'Elliptical',
          'radius': 50.0,
          'centerX': 100.0,
          'centerY': 100.0,
          'startAngle': 0,
          'endAngle': 180,
          'elliptical': true,
        },
      ];

      for (var testCase in testCases) {
        List<cv.Point2f> contourPoints = [];
        double radius = testCase['radius'] as double;
        double centerX = testCase['centerX'] as double;
        double centerY = testCase['centerY'] as double;
        int startAngle = testCase['startAngle'] as int;
        int endAngle = testCase['endAngle'] as int;
        bool elliptical = testCase['elliptical'] as bool? ?? false;
        
        // Generate contour points
        for (int i = startAngle; i <= endAngle; i += 5) {
          double angle = i * pi / 180;
          double x = centerX + radius * cos(angle);
          double y = centerY - radius * sin(angle);
          
          if (elliptical) {
            // Make it elliptical by scaling y
            y = centerY - (radius * 0.7) * sin(angle);
          }
          
          contourPoints.add(cv.Point2f(x, y));
        }

        // Create baseline points
        List<Offset> baselinePoints = [
          Offset(centerX - radius, centerY),
          Offset(centerX + radius, centerY),
        ];

        // Calculate contact angles
        final results = await EnhancedContactAngleCalculator.calculateContactAnglesEnhanced(
            contourPoints, baselinePoints);
        
        // Verify results
        expect(results['left'], greaterThan(0.0));
        expect(results['right'], greaterThan(0.0));
        expect(results['average'], greaterThan(0.0));
        expect(results['average'], lessThan(180.0));
        
        print('${testCase['name']} Test Results:');
        print('  Left Angle: ${results['left']?.toStringAsFixed(2)}°');
        print('  Right Angle: ${results['right']?.toStringAsFixed(2)}°');
        print('  Average Angle: ${results['average']?.toStringAsFixed(2)}°');
        print('  Confidence: ${results['qualityMetrics']['confidence']}');
      }
    });

    test('Test enhanced algorithm error handling', () async {
      // Test with insufficient points
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
    });

    test('Test enhanced algorithm quality metrics', () async {
      // Create sample data
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

      // Create baseline points
      List<Offset> baselinePoints = [
        Offset(centerX - radius, centerY),
        Offset(centerX + radius, centerY),
      ];

      // Calculate contact angles
      final results = await EnhancedContactAngleCalculator.calculateContactAnglesEnhanced(
          contourPoints, baselinePoints);
      
      // Verify quality metrics
      final qualityMetrics = results['qualityMetrics'] as Map<String, dynamic>;
      
      expect(qualityMetrics.containsKey('smoothness'), isTrue);
      expect(qualityMetrics.containsKey('baselineQuality'), isTrue);
      expect(qualityMetrics.containsKey('symmetry'), isTrue);
      expect(qualityMetrics.containsKey('uncertaintyReliability'), isTrue);
      expect(qualityMetrics.containsKey('overallConfidence'), isTrue);
      expect(qualityMetrics.containsKey('confidence'), isTrue);
      
      // Verify quality values are reasonable
      for (var metric in qualityMetrics.entries) {
        if (metric.key != 'confidence') {
          expect(metric.value, greaterThanOrEqualTo(0.0));
          expect(metric.value, lessThanOrEqualTo(1.0));
        }
      }
      
      print('Quality Metrics Test Results:');
      for (var entry in qualityMetrics.entries) {
        if (entry.key != 'confidence') {
          print('  ${entry.key}: ${entry.value.toStringAsFixed(3)}');
        } else {
          print('  ${entry.key}: ${entry.value}');
        }
      }
    });
  });
} 