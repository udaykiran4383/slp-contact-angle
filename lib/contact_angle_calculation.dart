import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:isolate';

/// Enhanced contact angle calculation with improved accuracy and robustness
/// Addresses edge cases, numerical stability, and multi-model fitting
class EnhancedContactAngleCalculator {
  
  // Cache for calculation results
  static final Map<String, Map<String, dynamic>> _calculationCache = {};
  
  /// Main entry point for enhanced contact angle calculation
  static Future<Map<String, dynamic>> calculateContactAnglesEnhanced(
      List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
    
    // Validate inputs
    if (contourPoints.length < 5) {
      throw Exception('Insufficient contour points (${contourPoints.length}). Need at least 5.');
    }
    if (baselinePoints.length < 2) {
      throw Exception('Insufficient baseline points (${baselinePoints.length}). Need at least 2.');
    }

    // Check cache first
    String cacheKey = _generateCacheKey(contourPoints, baselinePoints);
    if (_calculationCache.containsKey(cacheKey)) {
      return _calculationCache[cacheKey]!;
    }

    // Preprocess contour for better fitting
    final processedContour = await _preprocessContour(contourPoints);
    
    // Detect baseline using multiple methods
    final baseline = await _detectAdaptiveBaseline(processedContour, baselinePoints);
    
    // Fit multiple models for robust angle calculation
    final multiModelResults = await _fitMultiModels(processedContour, baseline);
    
    // Calculate contact angles using enhanced method
    final contactAngles = await _calculateEnhancedContactAngles(
        processedContour, baseline, multiModelResults);
    
    // Analyze uncertainty comprehensively
    final uncertainty = await _analyzeUncertainty(
        processedContour, baseline, multiModelResults, contactAngles);
    
    // Assess quality metrics
    final qualityMetrics = await _assessQuality(
        processedContour, baseline, contactAngles, uncertainty);
    
    final results = {
      ...contactAngles,
      'uncertainty': uncertainty,
      'qualityMetrics': qualityMetrics,
      'processingMethod': 'Enhanced Multi-Model',
      'baseline': baseline,
      'modelFits': multiModelResults,
    };
    
    // Cache the results
    _calculationCache[cacheKey] = results;
    
    return results;
  }

  /// Process image in isolate for heavy computations
  static Future<Map<String, dynamic>> processImageInIsolate(
      List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
    return await Isolate.run(() async {
      return await calculateContactAnglesEnhanced(contourPoints, baselinePoints);
    });
  }

  /// Downsample image for faster processing
  static List<cv.Point2f> downsampleContour(List<cv.Point2f> points, {double factor = 0.5}) {
    if (factor >= 1.0) return points;
    
    int step = (1.0 / factor).round();
    List<cv.Point2f> downsampled = [];
    
    for (int i = 0; i < points.length; i += step) {
      downsampled.add(points[i]);
    }
    
    // Ensure we have at least 5 points
    if (downsampled.length < 5 && points.length >= 5) {
      downsampled = points.sublist(0, min(5, points.length));
    }
    
    return downsampled;
  }

  /// Generate cache key for contour and baseline points
  static String _generateCacheKey(List<cv.Point2f> contourPoints, List<Offset> baselinePoints) {
    // Create a simple hash based on point coordinates
    String contourHash = '';
    for (var point in contourPoints) {
      contourHash += '${point.x.round()},${point.y.round()};';
    }
    
    String baselineHash = '';
    for (var point in baselinePoints) {
      baselineHash += '${point.dx.round()},${point.dy.round()};';
    }
    
    return '${contourHash.hashCode}_${baselineHash.hashCode}';
  }

  /// Clear calculation cache
  static void clearCache() {
    _calculationCache.clear();
  }

  /// Get cache statistics
  static Map<String, dynamic> getCacheStats() {
    return {
      'size': _calculationCache.length,
      'keys': _calculationCache.keys.toList(),
    };
  }

  /// Enhanced contact angle calculation with smooth edge case handling
  static double calculateEnhancedContactAngle(double tangentSlope, double baselineSlope) {
    // Handle vertical tangents with robust calculation
    if (tangentSlope.isInfinite || tangentSlope.abs() > 1e10) {
      double baselineAngle = _robustAtan2(baselineSlope, 1.0);
      return 90.0 - baselineAngle.abs();
    }
    
    // Handle horizontal baseline (most common case)
    if (baselineSlope.abs() < 1e-9) {
      return _calculateHorizontalBaselineAngle(tangentSlope);
    }
    
    // General case with enhanced numerical stability
    return _calculateGeneralCaseAngle(tangentSlope, baselineSlope);
  }

  /// Enhanced contact angle calculation with smooth edge case handling (private version)
  static double _calculateEnhancedContactAngle(double tangentSlope, double baselineSlope) {
    return calculateEnhancedContactAngle(tangentSlope, baselineSlope);
  }

  /// Smooth edge case handling for horizontal baseline
  static double _calculateHorizontalBaselineAngle(double tangentSlope) {
    const double threshold = 1e-3;
    const double transitionWidth = 1e-4;
    
    // Handle very small slopes with smooth interpolation
    if (tangentSlope.abs() < threshold) {
      double t = tangentSlope.abs() / transitionWidth;
      double smoothFactor = _smoothStep(t);
      
      if (tangentSlope > 0) {
        double standardAngle = _robustAtan2(tangentSlope, 1.0);
        return smoothFactor * 0.0 + (1 - smoothFactor) * standardAngle;
      } else {
        double standardAngle = 180 - _robustAtan2(tangentSlope.abs(), 1.0);
        return smoothFactor * 180.0 + (1 - smoothFactor) * standardAngle;
      }
    }
    
    // Standard calculation for normal slopes
    double tangentAngle = _robustAtan2(tangentSlope, 1.0);
    
    double contactAngle;
    if (tangentSlope > 0) {
      contactAngle = tangentAngle;
    } else {
      contactAngle = 180 - tangentAngle.abs();
    }
    
    // Ensure angle is in correct range
    return _normalizeAngle(contactAngle);
  }

  /// Enhanced general case angle calculation
  static double _calculateGeneralCaseAngle(double tangentSlope, double baselineSlope) {
    double tangentAngle = _robustAtan2(tangentSlope, 1.0);
    double baselineAngle = _robustAtan2(baselineSlope, 1.0);
    
    // Calculate angle difference with proper handling
    double angleDifference = (tangentAngle - baselineAngle).abs();
    
    // Ensure angle is in correct range (0-180 degrees)
    if (angleDifference > 180) {
      angleDifference = 360 - angleDifference;
    }
    
    // For droplet geometry, consider the direction
    double contactAngle = angleDifference;
    
    // Additional correction for droplet geometry
    if (tangentSlope < baselineSlope) {
      contactAngle = 180 - contactAngle;
    }
    
    return _normalizeAngle(contactAngle);
  }

  /// Robust atan2 calculation with numerical stability
  static double _robustAtan2(double y, double x) {
    if (x.abs() < 1e-10 && y.abs() < 1e-10) {
      return 0.0; // Default to 0 for very small values
    }
    return atan2(y, x) * 180 / pi;
  }

  /// Smooth step function for edge case transitions
  static double _smoothStep(double t) {
    t = t.clamp(0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
  }

  /// Normalize angle to 0-180 range
  static double _normalizeAngle(double angle) {
    angle = angle % 360;
    if (angle < 0) angle += 360;
    if (angle > 180) angle = 360 - angle;
    return angle;
  }

  /// Fit multiple models for robust angle calculation
  static Future<Map<String, Map<String, dynamic>>> _fitMultiModels(
      List<cv.Point2f> points, Map<String, dynamic> baseline) async {
    
    final results = <String, Map<String, dynamic>>{};
    
    // Try ellipse fitting
    try {
      results['ellipse'] = await _fitEllipseModel(points);
    } catch (e) {
      print('Ellipse fitting failed: $e');
    }
    
    // Try polynomial fitting
    try {
      results['polynomial'] = await _fitPolynomialModel(points);
    } catch (e) {
      print('Polynomial fitting failed: $e');
    }
    
    // Try circle fitting
    try {
      results['circle'] = await _fitCircleModel(points);
    } catch (e) {
      print('Circle fitting failed: $e');
    }
    
    // If no models succeeded, use fallback
    if (results.isEmpty) {
      results['fallback'] = await _fitFallbackModel(points);
    }
    
    return results;
  }

  /// Fit ellipse model to points
  static Future<Map<String, dynamic>> _fitEllipseModel(List<cv.Point2f> points) async {
    if (points.length < 5) {
      throw Exception('Insufficient points for ellipse fitting');
    }
    
    // Convert to integer points for OpenCV
    List<cv.Point> intPoints = points
        .map((p) => cv.Point(p.x.round(), p.y.round()))
        .toList();
    
    final ellipse = cv.fitEllipse(cv.VecPoint.fromList(intPoints));
    
    // Calculate fit quality
    double rmsError = _calculateFitError(points, 'ellipse', ellipse);
    double quality = _calculateModelQuality(points, rmsError, 'ellipse');
    
    return {
      'centerX': ellipse.center.x.toDouble(),
      'centerY': ellipse.center.y.toDouble(),
      'semiMajor': max(ellipse.size.width, ellipse.size.height) / 2,
      'semiMinor': min(ellipse.size.width, ellipse.size.height) / 2,
      'rotation': ellipse.angle.toDouble(),
      'error': rmsError,
      'quality': quality,
      'type': 'ellipse',
    };
  }

  /// Fit polynomial model to points
  static Future<Map<String, dynamic>> _fitPolynomialModel(List<cv.Point2f> points) async {
    if (points.length < 4) {
      throw Exception('Insufficient points for polynomial fitting');
    }
    
    // Simple polynomial fitting (quadratic)
    final coefficients = _fitQuadraticPolynomial(points);
    double rmsError = _calculatePolynomialError(points, coefficients);
    double quality = _calculateModelQuality(points, rmsError, 'polynomial');
    
    return {
      'a': coefficients[0],
      'b': coefficients[1],
      'c': coefficients[2],
      'error': rmsError,
      'quality': quality,
      'type': 'polynomial',
    };
  }

  /// Fit circle model to points
  static Future<Map<String, dynamic>> _fitCircleModel(List<cv.Point2f> points) async {
    if (points.length < 3) {
      throw Exception('Insufficient points for circle fitting');
    }
    
    // Simple circle fitting using least squares
    final circle = _fitCircleLeastSquares(points);
    double rmsError = _calculateCircleError(points, circle);
    double quality = _calculateModelQuality(points, rmsError, 'circle');
    
    return {
      'centerX': circle['centerX']!,
      'centerY': circle['centerY']!,
      'radius': circle['radius']!,
      'error': rmsError,
      'quality': quality,
      'type': 'circle',
    };
  }

  /// Fallback model for when other models fail
  static Future<Map<String, dynamic>> _fitFallbackModel(List<cv.Point2f> points) async {
    // Simple linear approximation
    final bounds = _calculateBounds(points);
    
    return {
      'minX': bounds['minX']!,
      'maxX': bounds['maxX']!,
      'minY': bounds['minY']!,
      'maxY': bounds['maxY']!,
      'error': 1.0, // High error for fallback
      'quality': 0.1, // Low quality for fallback
      'type': 'fallback',
    };
  }

  /// Fit quadratic polynomial to points
  static List<double> _fitQuadraticPolynomial(List<cv.Point2f> points) {
    // Simple quadratic fitting: y = ax² + bx + c
    double sumX = 0, sumX2 = 0, sumX3 = 0, sumX4 = 0;
    double sumY = 0, sumXY = 0, sumX2Y = 0;
    int n = points.length;
    
    for (var point in points) {
      double x = point.x;
      double y = point.y;
      double x2 = x * x;
      double x3 = x2 * x;
      double x4 = x2 * x2;
      
      sumX += x;
      sumX2 += x2;
      sumX3 += x3;
      sumX4 += x4;
      sumY += y;
      sumXY += x * y;
      sumX2Y += x2 * y;
    }
    
    // Solve system of equations using Cramer's rule
    double det = n * sumX2 * sumX4 + 2 * sumX * sumX2 * sumX3 - sumX2 * sumX2 * sumX2 - n * sumX3 * sumX3 - sumX * sumX * sumX4;
    
    if (det.abs() < 1e-10) {
      // Fallback to linear fit
      return [0.0, (sumXY - sumX * sumY / n) / (sumX2 - sumX * sumX / n), sumY / n];
    }
    
    double a = (n * sumX2Y * sumX2 + sumX * sumXY * sumX3 + sumY * sumX2 * sumX3 - sumX2Y * sumX * sumX2 - sumXY * sumX2 * sumX2 - sumY * n * sumX3) / det;
    double b = (n * sumXY * sumX4 + sumX * sumY * sumX3 + sumX2Y * sumX * sumX2 - sumXY * sumX * sumX4 - sumY * sumX2 * sumX2 - sumX2Y * n * sumX3) / det;
    double c = (sumY * sumX2 * sumX4 + sumX2Y * sumX * sumX3 + sumXY * sumX2 * sumX3 - sumX2Y * sumX2 * sumX2 - sumXY * sumY * sumX4 - sumX2Y * sumX * sumX3) / det;
    
    return [a, b, c];
  }

  /// Fit circle using least squares method
  static Map<String, double> _fitCircleLeastSquares(List<cv.Point2f> points) {
    double sumX = 0, sumY = 0, sumX2 = 0, sumY2 = 0, sumXY = 0, sumX3 = 0, sumY3 = 0, sumXY2 = 0, sumX2Y = 0;
    int n = points.length;
    
    for (var point in points) {
      double x = point.x;
      double y = point.y;
      double x2 = x * x;
      double y2 = y * y;
      
      sumX += x;
      sumY += y;
      sumX2 += x2;
      sumY2 += y2;
      sumXY += x * y;
      sumX3 += x2 * x;
      sumY3 += y2 * y;
      sumXY2 += x * y2;
      sumX2Y += x2 * y;
    }
    
    // Solve for circle parameters
    double a = (sumX2 + sumY2) / n;
    double b = (sumX3 + sumXY2) / n;
    double c = (sumX2Y + sumY3) / n;
    
    double centerX = (b * sumY - c * sumX) / (2 * (sumX2 * sumY2 - sumXY * sumXY));
    double centerY = (c * sumX - b * sumY) / (2 * (sumX2 * sumY2 - sumXY * sumXY));
    double radius = sqrt(centerX * centerX + centerY * centerY + a);
    
    return {
      'centerX': centerX,
      'centerY': centerY,
      'radius': radius,
    };
  }

  /// Calculate fit error for a model
  static double _calculateFitError(List<cv.Point2f> points, String modelType, dynamic model) {
    double totalError = 0.0;
    
    for (var point in points) {
      double predictedY = _predictY(point.x, modelType, model);
      double error = (point.y - predictedY).abs();
      totalError += error * error;
    }
    
    return sqrt(totalError / points.length);
  }

  /// Calculate polynomial error
  static double _calculatePolynomialError(List<cv.Point2f> points, List<double> coefficients) {
    double totalError = 0.0;
    
    for (var point in points) {
      double predictedY = coefficients[0] * point.x * point.x + coefficients[1] * point.x + coefficients[2];
      double error = (point.y - predictedY).abs();
      totalError += error * error;
    }
    
    return sqrt(totalError / points.length);
  }

  /// Calculate circle error
  static double _calculateCircleError(List<cv.Point2f> points, Map<String, double> circle) {
    double totalError = 0.0;
    double centerX = circle['centerX']!;
    double centerY = circle['centerY']!;
    double radius = circle['radius']!;
    
    for (var point in points) {
      double distance = sqrt((point.x - centerX) * (point.x - centerX) + (point.y - centerY) * (point.y - centerY));
      double error = (distance - radius).abs();
      totalError += error * error;
    }
    
    return sqrt(totalError / points.length);
  }

  /// Calculate model quality based on error and point count
  static double _calculateModelQuality(List<cv.Point2f> points, double error, String modelType) {
    // Base quality on error and number of points
    double errorQuality = max(0.0, 1.0 - error / 100.0); // Normalize error
    double pointQuality = min(1.0, points.length / 50.0); // More points = better quality
    
    // Model-specific quality adjustments
    double modelQuality = 1.0;
    switch (modelType) {
      case 'ellipse':
        modelQuality = 1.0; // High quality for ellipse
        break;
      case 'circle':
        modelQuality = 0.9; // Good quality for circle
        break;
      case 'polynomial':
        modelQuality = 0.8; // Moderate quality for polynomial
        break;
      case 'fallback':
        modelQuality = 0.3; // Low quality for fallback
        break;
    }
    
    return (errorQuality + pointQuality + modelQuality) / 3.0;
  }

  /// Predict Y value for a given X and model
  static double _predictY(double x, String modelType, dynamic model) {
    switch (modelType) {
      case 'ellipse':
        // Simplified ellipse prediction
        return model.center.y.toDouble();
      default:
        return 0.0;
    }
  }

  /// Calculate bounds of points
  static Map<String, double> _calculateBounds(List<cv.Point2f> points) {
    double minX = points.map((p) => p.x).reduce(min);
    double maxX = points.map((p) => p.x).reduce(max);
    double minY = points.map((p) => p.y).reduce(min);
    double maxY = points.map((p) => p.y).reduce(max);
    
    return {
      'minX': minX,
      'maxX': maxX,
      'minY': minY,
      'maxY': maxY,
    };
  }

  /// Adaptive baseline detection
  static Future<Map<String, dynamic>> _detectAdaptiveBaseline(
      List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
    
    // Multiple baseline detection methods
    final methods = [
      _detectHorizontalBaseline,
      _detectRANSACBaseline,
      _detectLeastSquaresBaseline,
    ];
    
    final results = <Map<String, dynamic>>[];
    
    for (var method in methods) {
      try {
        final result = await method(contourPoints, baselinePoints);
        results.add(result);
      } catch (e) {
        // Skip failed methods
      }
    }
    
    // Select best baseline based on quality metrics
    return _selectBestBaseline(results);
  }

  /// Detect horizontal baseline
  static Future<Map<String, dynamic>> _detectHorizontalBaseline(
      List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
    
    double y = baselinePoints[0].dy;
    double quality = _calculateBaselineQuality(contourPoints, 0.0, y);
    
    return {
      'slope': 0.0,
      'intercept': y,
      'quality': quality,
      'method': 'horizontal',
    };
  }

  /// Detect RANSAC baseline
  static Future<Map<String, dynamic>> _detectRANSACBaseline(
      List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
    
    // Simple RANSAC implementation for baseline detection
    final bottomPoints = _extractBottomPoints(contourPoints);
    
    if (bottomPoints.length < 2) {
      throw Exception('Insufficient bottom points for RANSAC');
    }
    
    double bestSlope = 0.0;
    double bestIntercept = 0.0;
    double bestQuality = 0.0;
    
    // RANSAC iterations
    for (int i = 0; i < 100; i++) {
      // Randomly select two points
      final randomPoints = _selectRandomPoints(bottomPoints, 2);
      
      if (randomPoints.length < 2) continue;
      
      // Calculate line through points
      double slope = (randomPoints[1].y - randomPoints[0].y) / 
                    (randomPoints[1].x - randomPoints[0].x);
      double intercept = randomPoints[0].y - slope * randomPoints[0].x;
      
      // Calculate quality
      double quality = _calculateBaselineQuality(contourPoints, slope, intercept);
      
      if (quality > bestQuality) {
        bestQuality = quality;
        bestSlope = slope;
        bestIntercept = intercept;
      }
    }
    
    return {
      'slope': bestSlope,
      'intercept': bestIntercept,
      'quality': bestQuality,
      'method': 'ransac',
    };
  }

  /// Detect least squares baseline
  static Future<Map<String, dynamic>> _detectLeastSquaresBaseline(
      List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
    
    final bottomPoints = _extractBottomPoints(contourPoints);
    
    if (bottomPoints.length < 2) {
      throw Exception('Insufficient bottom points for least squares');
    }
    
    // Simple least squares fitting
    double sumX = bottomPoints.map((p) => p.x).reduce((a, b) => a + b);
    double sumY = bottomPoints.map((p) => p.y).reduce((a, b) => a + b);
    double sumXY = bottomPoints.asMap().entries.map((e) => e.value.x * e.value.y).reduce((a, b) => a + b);
    double sumX2 = bottomPoints.map((p) => p.x * p.x).reduce((a, b) => a + b);
    
    int n = bottomPoints.length;
    
    double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    double intercept = (sumY - slope * sumX) / n;
    
    double quality = _calculateBaselineQuality(contourPoints, slope, intercept);
    
    return {
      'slope': slope,
      'intercept': intercept,
      'quality': quality,
      'method': 'least_squares',
    };
  }

  /// Extract bottom points for baseline detection
  static List<cv.Point2f> _extractBottomPoints(List<cv.Point2f> points) {
    // Find points near the bottom of the contour
    double maxY = points.map((p) => p.y).reduce(max);
    double threshold = maxY - (maxY - points.map((p) => p.y).reduce(min)) * 0.1;
    
    return points.where((p) => p.y >= threshold).toList();
  }

  /// Select random points
  static List<cv.Point2f> _selectRandomPoints(List<cv.Point2f> points, int count) {
    if (points.length <= count) return points;
    
    final random = Random();
    final selected = <cv.Point2f>[];
    final indices = <int>{};
    
    while (indices.length < count) {
      indices.add(random.nextInt(points.length));
    }
    
    for (int index in indices) {
      selected.add(points[index]);
    }
    
    return selected;
  }

  /// Calculate baseline quality
  static double _calculateBaselineQuality(List<cv.Point2f> points, double slope, double intercept) {
    double totalError = 0.0;
    int count = 0;
    
    for (var point in points) {
      double predictedY = slope * point.x + intercept;
      double error = (point.y - predictedY).abs();
      totalError += error;
      count++;
    }
    
    if (count == 0) return 0.0;
    
    double averageError = totalError / count;
    return max(0.0, 1.0 - averageError / 10.0);
  }

  /// Select best baseline
  static Map<String, dynamic> _selectBestBaseline(List<Map<String, dynamic>> results) {
    if (results.isEmpty) {
      return {'slope': 0.0, 'intercept': 0.0, 'quality': 0.0, 'method': 'default'};
    }
    
    // Sort by quality
    results.sort((a, b) => (b['quality'] as double).compareTo(a['quality'] as double));
    
    return results.first;
  }

  /// Preprocess contour
  static Future<List<cv.Point2f>> _preprocessContour(List<cv.Point2f> contour) async {
    // Remove outliers
    final filteredContour = await _removeOutliers(contour);
    
    // Smooth contour
    final smoothedContour = await _smoothContour(filteredContour);
    
    // Resample contour
    final resampledContour = await _resampleContour(smoothedContour);
    
    return resampledContour;
  }

  /// Remove outliers
  static Future<List<cv.Point2f>> _removeOutliers(List<cv.Point2f> contour) async {
    if (contour.length < 10) return contour;
    
    // Calculate distances between consecutive points
    List<double> distances = [];
    for (int i = 0; i < contour.length; i++) {
      cv.Point2f p1 = contour[i];
      cv.Point2f p2 = contour[(i + 1) % contour.length];
      double distance = sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
      distances.add(distance);
    }
    
    // Calculate statistics
    double mean = distances.reduce((a, b) => a + b) / distances.length;
    double variance = distances.map((d) => (d - mean) * (d - mean)).reduce((a, b) => a + b) / distances.length;
    double stdDev = sqrt(variance);
    
    // Filter outliers
    List<cv.Point2f> filtered = [];
    for (int i = 0; i < contour.length; i++) {
      if (distances[i] <= mean + 2 * stdDev) {
        filtered.add(contour[i]);
      }
    }
    
    return filtered.isEmpty ? contour : filtered;
  }

  /// Smooth contour
  static Future<List<cv.Point2f>> _smoothContour(List<cv.Point2f> contour) async {
    if (contour.length < 4) return contour;
    
    List<cv.Point2f> smoothed = [];
    int windowSize = min(7, contour.length ~/ 2);
    int halfWindow = windowSize ~/ 2;
    
    for (int i = 0; i < contour.length; i++) {
      double sumX = 0, sumY = 0;
      int count = 0;
      
      for (int j = -halfWindow; j <= halfWindow; j++) {
        int idx = (i + j + contour.length) % contour.length;
        sumX += contour[idx].x;
        sumY += contour[idx].y;
        count++;
      }
      
      smoothed.add(cv.Point2f(sumX / count, sumY / count));
    }
    
    return smoothed;
  }

  /// Resample contour
  static Future<List<cv.Point2f>> _resampleContour(List<cv.Point2f> contour) async {
    if (contour.length < 3) return contour;
    
    // Calculate total perimeter
    double totalPerimeter = 0;
    for (int i = 0; i < contour.length; i++) {
      cv.Point2f p1 = contour[i];
      cv.Point2f p2 = contour[(i + 1) % contour.length];
      totalPerimeter += sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
    }
    
    // Resample to 100 points
    int numPoints = 100;
    double stepSize = totalPerimeter / numPoints;
    
    List<cv.Point2f> resampled = [];
    double currentDistance = 0;
    int currentIndex = 0;
    
    for (int i = 0; i < numPoints; i++) {
      double targetDistance = i * stepSize;
      
      while (currentDistance < targetDistance && currentIndex < contour.length - 1) {
        cv.Point2f p1 = contour[currentIndex];
        cv.Point2f p2 = contour[currentIndex + 1];
        double segmentLength = sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
        
        if (currentDistance + segmentLength >= targetDistance) {
          double t = (targetDistance - currentDistance) / segmentLength;
          double x = p1.x + t * (p2.x - p1.x);
          double y = p1.y + t * (p2.y - p1.y);
          resampled.add(cv.Point2f(x, y));
          break;
        }
        
        currentDistance += segmentLength;
        currentIndex++;
      }
    }
    
    return resampled.isEmpty ? contour : resampled;
  }

  /// Calculate enhanced contact angles
  static Future<Map<String, dynamic>> _calculateEnhancedContactAngles(
      List<cv.Point2f> points, Map<String, dynamic> baseline, 
      Map<String, Map<String, dynamic>> modelResults) async {
    
    // Use the best fitting model for angle calculation
    String bestModel = _selectBestModel(modelResults);
    final model = modelResults[bestModel]!;
    
    // Calculate intersection points
    final intersections = await _calculateIntersections(points, baseline, model, bestModel);
    
    if (intersections.length < 2) {
      throw Exception('Failed to find intersection points');
    }
    
    // Calculate tangent angles
    final tangentAngles = await _calculateTangentAngles(intersections, model, bestModel);
    
    // Calculate contact angles
    double angleLeft = _calculateEnhancedContactAngle(tangentAngles['left']!, baseline['slope']!);
    double angleRight = _calculateEnhancedContactAngle(tangentAngles['right']!, baseline['slope']!);
    
    return {
      'left': angleLeft,
      'right': angleRight,
      'average': (angleLeft + angleRight) / 2,
      'difference': (angleLeft - angleRight).abs(),
      'model': bestModel,
    };
  }

  /// Select best model based on quality
  static String _selectBestModel(Map<String, Map<String, dynamic>> modelResults) {
    String bestModel = 'ellipse';
    double bestQuality = 0.0;
    
    for (var entry in modelResults.entries) {
      if (entry.value['quality']! > bestQuality) {
        bestQuality = entry.value['quality']!;
        bestModel = entry.key;
      }
    }
    
    return bestModel;
  }

  /// Calculate intersections
  static Future<List<Map<String, double>>> _calculateIntersections(
      List<cv.Point2f> points, Map<String, dynamic> baseline,
      Map<String, dynamic> model, String modelType) async {
    
    double slope = baseline['slope']!;
    double intercept = baseline['intercept']!;
    
    // Find points near the baseline
    List<Map<String, double>> intersections = [];
    
    // First, find the bottom points of the contour (closest to baseline)
    List<cv.Point2f> bottomPoints = [];
    double maxY = points.map((p) => p.y).reduce(max);
    double minY = points.map((p) => p.y).reduce(min);
    double threshold = maxY - (maxY - minY) * 0.1; // Bottom 10% of points
    
    for (var point in points) {
      if (point.y >= threshold) {
        bottomPoints.add(point);
      }
    }
    
    // Sort bottom points by x-coordinate
    bottomPoints.sort((a, b) => a.x.compareTo(b.x));
    
    // Find the leftmost and rightmost points that are close to the baseline
    if (bottomPoints.isNotEmpty) {
      // Left intersection (first point)
      var leftPoint = bottomPoints.first;
      double leftY = slope * leftPoint.x + intercept;
      intersections.add({'x': leftPoint.x, 'y': leftY});
      
      // Right intersection (last point)
      var rightPoint = bottomPoints.last;
      double rightY = slope * rightPoint.x + intercept;
      intersections.add({'x': rightPoint.x, 'y': rightY});
    }
    
    // If we don't have enough intersections, try a different approach
    if (intersections.length < 2) {
      // Use the original contour points and find crossings
      for (int i = 0; i < points.length - 1; i++) {
        cv.Point2f p1 = points[i];
        cv.Point2f p2 = points[i + 1];
        
        double y1 = slope * p1.x + intercept;
        double y2 = slope * p2.x + intercept;
        
        // Check if line segment crosses baseline
        if ((p1.y - y1) * (p2.y - y2) < 0) {
          // Line segment crosses baseline
          double t = (y1 - p1.y) / (p2.y - p1.y);
          if (t >= 0 && t <= 1) {
            double x = p1.x + t * (p2.x - p1.x);
            double y = y1;
            
            intersections.add({'x': x, 'y': y});
          }
        }
      }
    }
    
    // Sort by x-coordinate
    intersections.sort((a, b) => a['x']!.compareTo(b['x']!));
    
    // If still no intersections, create default ones
    if (intersections.length < 2) {
      double minX = points.map((p) => p.x).reduce(min);
      double maxX = points.map((p) => p.x).reduce(max);
      double centerY = points.map((p) => p.y).reduce((a, b) => a + b) / points.length;
      
      intersections.add({'x': minX, 'y': centerY});
      intersections.add({'x': maxX, 'y': centerY});
    }
    
    return intersections;
  }

  /// Calculate tangent angles
  static Future<Map<String, double>> _calculateTangentAngles(
      List<Map<String, double>> intersections, Map<String, dynamic> model, String modelType) async {
    
    // Simplified tangent calculation
    // In practice, you'd implement specific tangent calculations for each model type
    
    double leftSlope = 0.0;
    double rightSlope = 0.0;
    
    if (intersections.length >= 2) {
      // Calculate approximate tangents using nearby points
      leftSlope = _calculateApproximateTangent(intersections[0], model, modelType);
      rightSlope = _calculateApproximateTangent(intersections[1], model, modelType);
    }
    
    return {
      'left': leftSlope,
      'right': rightSlope,
    };
  }

  /// Calculate approximate tangent
  static double _calculateApproximateTangent(Map<String, double> point, Map<String, dynamic> model, String modelType) {
    // Simplified tangent calculation
    // This is a placeholder - you'd implement specific calculations for each model type
    
    switch (modelType) {
      case 'ellipse':
        return _calculateEllipseTangent(point['x']!, point['y']!, 
            model['centerX'] as double, model['centerY'] as double, model['semiMajor'] as double, model['semiMinor'] as double, model['rotation'] as double);
      case 'circle':
        return _calculateCircleTangent(point['x']!, point['y']!, 
            model['centerX'] as double, model['centerY'] as double, model['radius'] as double);
      case 'polynomial':
        return _calculatePolynomialTangent(point['x']!, model);
      default:
        return 0.0;
    }
  }

  /// Calculate ellipse tangent
  static double _calculateEllipseTangent(double x0, double y0, double h, double k, double a, double b, double phi) {
    double dx = x0 - h;
    double dy = y0 - k;
    double cosPhi = cos(phi * pi / 180);
    double sinPhi = sin(phi * pi / 180);
    
    double xRot = dx * cosPhi + dy * sinPhi;
    double yRot = -dx * sinPhi + dy * cosPhi;
    
    double dFdx = 2 * xRot / (a * a);
    double dFdy = 2 * yRot / (b * b);
    
    double dxOriginal = dFdx * cosPhi - dFdy * sinPhi;
    double dyOriginal = dFdx * sinPhi + dFdy * cosPhi;
    
    if (dyOriginal.abs() < 1e-10) {
      return double.infinity;
    }
    
    return -dxOriginal / dyOriginal;
  }

  /// Calculate circle tangent
  static double _calculateCircleTangent(double x0, double y0, double h, double k, double radius) {
    double dx = x0 - h;
    double dy = y0 - k;
    
    if (dy.abs() < 1e-10) {
      return double.infinity;
    }
    
    return -dx / dy;
  }

  /// Calculate polynomial tangent
  static double _calculatePolynomialTangent(double x, Map<String, dynamic> model) {
    // For quadratic polynomial: y = ax² + bx + c
    // Tangent slope = 2ax + b
    double a = model['a'] as double? ?? 0.0;
    double b = model['b'] as double? ?? 0.0;
    
    return 2 * a * x + b;
  }

  /// Analyze uncertainty comprehensively
  static Future<Map<String, double>> _analyzeUncertainty(
      List<cv.Point2f> points, Map<String, dynamic> baseline,
      Map<String, Map<String, dynamic>> modelResults, Map<String, dynamic> contactAngles) async {
    
    // Calculate various uncertainty components
    double systematic = _calculateSystematicUncertainty(points, modelResults);
    double random = _calculateRandomUncertainty(points);
    double geometric = _calculateGeometricUncertainty(modelResults);
    double numerical = _calculateNumericalUncertainty();
    
    // Combine uncertainties
    double total = sqrt(systematic * systematic + random * random + 
                       geometric * geometric + numerical * numerical);
    
    return {
      'systematic': systematic,
      'random': random,
      'geometric': geometric,
      'numerical': numerical,
      'total': total,
    };
  }

  /// Calculate systematic uncertainty
  static double _calculateSystematicUncertainty(List<cv.Point2f> points, Map<String, Map<String, dynamic>> modelResults) {
    // Simplified systematic uncertainty calculation
    double totalError = 0.0;
    int count = 0;
    
    for (var model in modelResults.values) {
      if (model.containsKey('error')) {
        totalError += model['error']!;
        count++;
      }
    }
    
    return count > 0 ? totalError / count : 0.5;
  }

  /// Calculate random uncertainty
  static double _calculateRandomUncertainty(List<cv.Point2f> points) {
    // Simplified random uncertainty calculation
    return 0.2; // Base random uncertainty
  }

  /// Calculate geometric uncertainty
  static double _calculateGeometricUncertainty(Map<String, Map<String, dynamic>> modelResults) {
    // Simplified geometric uncertainty calculation
    double maxError = 0.0;
    
    for (var model in modelResults.values) {
      if (model.containsKey('error')) {
        maxError = max(maxError, model['error']!);
      }
    }
    
    return maxError * 0.5;
  }

  /// Calculate numerical uncertainty
  static double _calculateNumericalUncertainty() {
    // Simplified numerical uncertainty calculation
    return 0.1; // Base numerical uncertainty
  }

  /// Assess quality metrics
  static Future<Map<String, dynamic>> _assessQuality(
      List<cv.Point2f> points, Map<String, dynamic> baseline,
      Map<String, dynamic> contactAngles, Map<String, double> uncertainty) async {
    
    // Calculate various quality metrics
    double smoothness = await _calculateContourSmoothness(points);
    double baselineQuality = baseline['quality']!;
    double symmetry = 1.0 - (contactAngles['difference'] as double) / 180.0;
    double uncertaintyReliability = _assessUncertaintyReliability(uncertainty);
    
    // Calculate overall confidence
    double overallConfidence = (smoothness + baselineQuality + symmetry + uncertaintyReliability) / 4;
    
    return {
      'smoothness': smoothness,
      'baselineQuality': baselineQuality,
      'symmetry': symmetry,
      'uncertaintyReliability': uncertaintyReliability,
      'overallConfidence': overallConfidence,
      'confidence': overallConfidence > 0.8 ? 'High' : overallConfidence > 0.6 ? 'Medium' : 'Low',
    };
  }

  /// Calculate contour smoothness
  static Future<double> _calculateContourSmoothness(List<cv.Point2f> contour) async {
    if (contour.length < 3) return 0.0;
    
    double totalCurvature = 0.0;
    int count = 0;
    
    for (int i = 1; i < contour.length - 1; i++) {
      cv.Point2f prev = contour[i - 1];
      cv.Point2f curr = contour[i];
      cv.Point2f next = contour[i + 1];
      
      double curvature = _calculateCurvature(prev, curr, next);
      totalCurvature += curvature.abs();
      count++;
    }
    
    double averageCurvature = count > 0 ? totalCurvature / count : 0.0;
    
    return max(0.0, 1.0 - averageCurvature / 100.0);
  }

  /// Calculate curvature at a point
  static double _calculateCurvature(cv.Point2f p1, cv.Point2f p2, cv.Point2f p3) {
    double dx1 = p2.x - p1.x;
    double dy1 = p2.y - p1.y;
    double dx2 = p3.x - p2.x;
    double dy2 = p3.y - p2.y;
    
    double cross = dx1 * dy2 - dy1 * dx2;
    double dot = dx1 * dx2 + dy1 * dy2;
    
    if (dot == 0) return 0.0;
    
    return cross / (dot * sqrt(dx1 * dx1 + dy1 * dy1));
  }

  /// Assess uncertainty reliability
  static double _assessUncertaintyReliability(Map<String, double> uncertainty) {
    double total = uncertainty['total']!;
    
    // Higher uncertainty means lower reliability
    return max(0.0, 1.0 - total / 5.0);
  }
}

/// Legacy function for backward compatibility
Future<Map<String, double>> calculateContactAngles(
    List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
  
  final enhancedResults = await EnhancedContactAngleCalculator.calculateContactAnglesEnhanced(
      contourPoints, baselinePoints);
  
  // Extract legacy format
  return {
    'left': enhancedResults['left']!,
    'right': enhancedResults['right']!,
    'average': enhancedResults['average']!,
    'uncertainty': enhancedResults['uncertainty']['total']!,
    'eccentricity': enhancedResults['modelFits']['ellipse']?['quality'] ?? 0.0,
    'bondNumber': 0.0, // Calculate if needed
  };
}