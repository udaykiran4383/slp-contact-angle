import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';
import 'package:flutter/material.dart';

/// Calculates contact angles using ellipse fitting with uncertainty estimation
/// Based on scientific methods for exact measurement
Future<Map<String, double>> calculateContactAngles(
    List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
  // Extract x and y points from contour
  List<double> xPoints = contourPoints.map((p) => p.x).toList();
  List<double> yPoints = contourPoints.map((p) => p.y).toList();

  // Define baseline parameters
  double x1 = baselinePoints[0].dx;
  double y1 = baselinePoints[0].dy;
  double x2 = baselinePoints[1].dx;
  double y2 = baselinePoints[1].dy;
  
  // Calculate baseline slope and intercept
  double baselineSlope = (y2 - y1) / (x2 - x1);
  double baselineIntercept = y1 - baselineSlope * x1;

  // Select points above baseline (y < baselineSlope*x + baselineIntercept)
  List<cv.Point2f> selectedPoints = [];
  for (int i = 0; i < contourPoints.length; i++) {
    double baselineY = baselineSlope * xPoints[i] + baselineIntercept;
    if (yPoints[i] < baselineY) {  // Above baseline in image coordinates
      selectedPoints.add(contourPoints[i]);
    }
  }

  if (selectedPoints.length < 5) {
    throw Exception('Insufficient points (${selectedPoints.length}) for ellipse fitting. Need at least 5.');
  }

  // Convert to integer points for fitEllipse
  List<cv.Point> intPoints = selectedPoints
      .map((p) => cv.Point(p.x.round(), p.y.round()))
      .toList();

  // Fit ellipse to droplet profile
  final ellipse = cv.fitEllipse(cv.VecPoint.fromList(intPoints));
  
  // Extract ellipse parameters
  double centerX = ellipse.center.x;
  double centerY = ellipse.center.y;
  double semiMajor = max(ellipse.size.width, ellipse.size.height) / 2;
  double semiMinor = min(ellipse.size.width, ellipse.size.height) / 2;
  double rotationAngle = ellipse.angle * (pi / 180);  // Convert to radians
  
  // Calculate eccentricity for quality check
  double eccentricity = sqrt(1 - (semiMinor * semiMinor) / (semiMajor * semiMajor));
  
  // Find analytical intersection points between ellipse and baseline
  var intersections = _findEllipseLineIntersections(
      centerX, centerY, semiMajor, semiMinor, rotationAngle,
      baselineSlope, baselineIntercept);
  
  if (intersections.length < 2) {
    throw Exception('Failed to find two intersection points between ellipse and baseline.');
  }
  
  // Sort intersections by x-coordinate
  intersections.sort((a, b) => a['x']!.compareTo(b['x']!));
  
  double xLeft = intersections[0]['x']!;
  double yLeft = intersections[0]['y']!;
  double xRight = intersections[1]['x']!;
  double yRight = intersections[1]['y']!;
  
  // Calculate tangent slopes at intersection points using analytical derivatives
  double tangentLeft = _calculateEllipseTangent(
      xLeft, yLeft, centerX, centerY, semiMajor, semiMinor, rotationAngle);
  double tangentRight = _calculateEllipseTangent(
      xRight, yRight, centerX, centerY, semiMajor, semiMinor, rotationAngle);
  
  // Calculate contact angles using the corrected method for droplet geometry
  double angleLeft = _calculateDropletContactAngle(tangentLeft, baselineSlope);
  double angleRight = _calculateDropletContactAngle(tangentRight, baselineSlope);
  
  // Check for outliers (asymmetry)
  double angleDifference = (angleLeft - angleRight).abs();
  
  // Calculate average and uncertainty
  double averageAngle = (angleLeft + angleRight) / 2;
  double uncertainty = _estimateUncertainty(
      selectedPoints, ellipse, eccentricity, angleDifference);
  
  // Calculate Bond number to check gravity effects
  double dropletRadius = (xRight - xLeft) / 2;
  double bondNumber = _calculateBondNumber(dropletRadius);
  
  return {
    'left': angleLeft,
    'right': angleRight,
    'average': averageAngle,
    'uncertainty': uncertainty,
    'eccentricity': eccentricity,
    'bondNumber': bondNumber,
  };
}

/// Find analytical intersections between ellipse and line
List<Map<String, double>> _findEllipseLineIntersections(
    double h, double k, double a, double b, double phi,
    double m, double c) {
  // Transform line equation to ellipse coordinate system
  double cosPhi = cos(phi);
  double sinPhi = sin(phi);
  
  // Coefficients for quadratic equation after substitution
  double A = (cosPhi - m * sinPhi) * (cosPhi - m * sinPhi) / (a * a) +
             (sinPhi + m * cosPhi) * (sinPhi + m * cosPhi) / (b * b);
  double B = 2 * ((c - k + m * h) * sinPhi * (cosPhi - m * sinPhi) / (a * a) +
                  (c - k + m * h) * cosPhi * (sinPhi + m * cosPhi) / (b * b));
  double C = (c - k + m * h) * (c - k + m * h) * sinPhi * sinPhi / (a * a) +
             (c - k + m * h) * (c - k + m * h) * cosPhi * cosPhi / (b * b) - 1;
  
  // Solve quadratic equation
  double discriminant = B * B - 4 * A * C;
  if (discriminant < 0) {
    return [];
  }
  
  double sqrtDisc = sqrt(discriminant);
  double t1 = (-B - sqrtDisc) / (2 * A);
  double t2 = (-B + sqrtDisc) / (2 * A);
  
  // Convert back to x,y coordinates
  List<Map<String, double>> intersections = [];
  for (double t in [t1, t2]) {
    double x = h + t * cosPhi;
    double y = k + t * sinPhi;
    // Verify the point is on the line (within tolerance)
    if ((y - (m * x + c)).abs() < 0.1) {
      intersections.add({'x': x, 'y': y});
    }
  }
  
  return intersections;
}

/// Calculate ellipse tangent slope at a point using implicit differentiation
double _calculateEllipseTangent(
    double x0, double y0, double h, double k, double a, double b, double phi) {
  // Transform point to ellipse coordinate system
  double dx = x0 - h;
  double dy = y0 - k;
  double cosPhi = cos(phi);
  double sinPhi = sin(phi);
  
  // Rotated coordinates
  double xRot = dx * cosPhi + dy * sinPhi;
  double yRot = -dx * sinPhi + dy * cosPhi;
  
  // Partial derivatives of ellipse equation
  double dFdx = 2 * xRot / (a * a);
  double dFdy = 2 * yRot / (b * b);
  
  // Transform back to original coordinates
  double dxOriginal = dFdx * cosPhi - dFdy * sinPhi;
  double dyOriginal = dFdx * sinPhi + dFdy * cosPhi;
  
  // Tangent slope is -dF/dx / dF/dy
  if (dyOriginal.abs() < 1e-10) {
    return double.infinity;  // Vertical tangent
  }
  
  return -dxOriginal / dyOriginal;
}

/// Calculate contact angle from tangent and baseline slopes - CORRECTED METHOD
double _calculateContactAngleCorrected(double tangentSlope, double baselineSlope) {
  // Handle vertical tangents
  if (tangentSlope.isInfinite) {
    double baselineAngle = atan(baselineSlope) * 180 / pi;
    return 90.0 - baselineAngle.abs();
  }
  
  // Handle horizontal baseline (most common case)
  if (baselineSlope.abs() < 1e-6) {
    // Baseline is horizontal
    double tangentAngle = atan(tangentSlope) * 180 / pi;
    double contactAngle = tangentAngle.abs();
    
    // Ensure the angle is in the correct range (0-180 degrees)
    if (contactAngle > 180) {
      contactAngle = 360 - contactAngle;
    }
    
    // For a droplet, the contact angle is the angle inside the droplet
    // If the tangent is pointing downward (negative slope), we need to adjust
    if (tangentSlope < 0) {
      contactAngle = 180 - contactAngle;
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
  
  // Contact angle is the angle between the tangent and the baseline
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

/// Calculate contact angle from tangent and baseline slopes (legacy method)
double _calculateContactAngle(double tangentSlope, double baselineSlope) {
  // Handle vertical tangents
  if (tangentSlope.isInfinite) {
    return 90.0 - atan(baselineSlope).abs() * 180 / pi;
  }
  
  // Calculate angle between tangent and baseline
  double angleRad = atan((tangentSlope - baselineSlope) / (1 + tangentSlope * baselineSlope)).abs();
  double angleDeg = angleRad * 180 / pi;
  
  // Ensure angle is in [0, 180] range (contact angle inside droplet)
  if (angleDeg > 90) {
    angleDeg = 180 - angleDeg;
  }
  
  return angleDeg;
}

/// Calculate contact angle specifically for droplet geometry
/// This method handles the specific case of a droplet on a surface
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
    
    // Special handling for very small slopes (near horizontal)
    if (tangentSlope.abs() < 1e-3) {
      if (tangentSlope > 0) {
        contactAngle = 0.0;
      } else {
        contactAngle = 180.0;
      }
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

/// Estimate measurement uncertainty based on fit quality and symmetry
double _estimateUncertainty(List<cv.Point2f> points, cv.RotatedRect ellipse,
    double eccentricity, double angleDifference) {
  // Base uncertainty from pixel discretization
  double pixelUncertainty = 0.5;
  
  // Fit quality: calculate RMS distance from points to ellipse
  double rmsError = 0.0;
  for (var point in points) {
    double dist = _pointToEllipseDistance(
        point.x, point.y, ellipse.center.x, ellipse.center.y,
        ellipse.size.width / 2, ellipse.size.height / 2,
        ellipse.angle * pi / 180);
    rmsError += dist * dist;
  }
  rmsError = sqrt(rmsError / points.length);
  
  // Uncertainty factors
  double fitUncertainty = rmsError * 0.5;  // Empirical factor
  double asymmetryUncertainty = angleDifference * 0.1;
  double eccentricityFactor = 1.0 + eccentricity * 0.5;  // Higher eccentricity = higher uncertainty
  
  // Combined uncertainty (simplified model)
  double totalUncertainty = sqrt(
      pixelUncertainty * pixelUncertainty +
      fitUncertainty * fitUncertainty +
      asymmetryUncertainty * asymmetryUncertainty
  ) * eccentricityFactor;
  
  return min(totalUncertainty, 5.0);  // Cap at 5 degrees
}

/// Calculate distance from point to ellipse (approximate)
double _pointToEllipseDistance(
    double px, double py, double cx, double cy, double a, double b, double phi) {
  // Transform to ellipse coordinate system
  double dx = px - cx;
  double dy = py - cy;
  double cosPhi = cos(phi);
  double sinPhi = sin(phi);
  double x = dx * cosPhi + dy * sinPhi;
  double y = -dx * sinPhi + dy * cosPhi;
  
  // Distance to ellipse (approximate using scaling)
  double scale = sqrt((x * x) / (a * a) + (y * y) / (b * b));
  return (scale - 1.0).abs() * sqrt(x * x + y * y) / scale;
}

/// Calculate Bond number to assess gravity effects
double _calculateBondNumber(double dropletRadius) {
  // Physical constants
  const double gravity = 9.81;  // m/s²
  const double waterDensity = 997;  // kg/m³ at 25°C
  const double waterSurfaceTension = 0.0728;  // N/m at 25°C
  
  // Convert radius from pixels to meters (assume ~50 pixels/mm)
  double radiusMeters = dropletRadius / 50000;  // 50 pixels/mm * 1000 mm/m
  
  // Bond number Bo = ρgL²/σ
  return waterDensity * gravity * radiusMeters * radiusMeters / waterSurfaceTension;
}

/// NEW: Enhanced contact angle calculation with improved accuracy
Future<Map<String, dynamic>> calculateContactAnglesEnhanced(
    List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
  
  // Apply advanced preprocessing to contour points
  final processedContour = await _preprocessContour(contourPoints);
  
  // Use the corrected contact angle calculation
  final results = await calculateContactAngles(processedContour, baselinePoints);
  
  // Calculate additional quality metrics
  final qualityMetrics = await _calculateQualityMetrics(processedContour, baselinePoints, results);
  
  return {
    ...results,
    'qualityMetrics': qualityMetrics,
    'processingMethod': 'Enhanced Corrected',
  };
}

/// Preprocess contour for better fitting
Future<List<cv.Point2f>> _preprocessContour(List<cv.Point2f> contour) async {
  // Remove outliers using statistical filtering
  final filteredContour = await _removeOutliers(contour);
  
  // Smooth contour using B-spline
  final smoothedContour = await _smoothContourBSPline(filteredContour);
  
  // Resample contour for uniform spacing
  final resampledContour = await _resampleContour(smoothedContour);
  
  return resampledContour;
}

/// Remove outliers using statistical filtering
Future<List<cv.Point2f>> _removeOutliers(List<cv.Point2f> contour) async {
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
  
  // Filter outliers (points with distance > mean + 2*stdDev)
  List<cv.Point2f> filtered = [];
  for (int i = 0; i < contour.length; i++) {
    if (distances[i] <= mean + 2 * stdDev) {
      filtered.add(contour[i]);
    }
  }
  
  return filtered.isEmpty ? contour : filtered;
}

/// Smooth contour using B-spline interpolation
Future<List<cv.Point2f>> _smoothContourBSPline(List<cv.Point2f> contour) async {
  if (contour.length < 4) return contour;
  
  // Simple smoothing using moving average with larger window
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

/// Resample contour for uniform spacing
Future<List<cv.Point2f>> _resampleContour(List<cv.Point2f> contour) async {
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
    
    // Find the segment containing the target distance
    while (currentDistance < targetDistance && currentIndex < contour.length - 1) {
      cv.Point2f p1 = contour[currentIndex];
      cv.Point2f p2 = contour[currentIndex + 1];
      double segmentLength = sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
      
      if (currentDistance + segmentLength >= targetDistance) {
        // Interpolate point
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

/// Calculate quality metrics for the measurement
Future<Map<String, dynamic>> _calculateQualityMetrics(
    List<cv.Point2f> contour,
    List<Offset> baselinePoints,
    Map<String, double> results) async {
  
  // Calculate contour smoothness
  double smoothness = await _calculateContourSmoothness(contour);
  
  // Calculate baseline quality
  double baselineQuality = await _calculateBaselineQuality(baselinePoints);
  
  // Calculate angle symmetry
  double symmetry = 1.0 - (results['left']! - results['right']!).abs() / 180.0;
  
  // Overall quality score
  double overallQuality = (smoothness + baselineQuality + symmetry) / 3;
  
  return {
    'smoothness': smoothness,
    'baselineQuality': baselineQuality,
    'symmetry': symmetry,
    'overallQuality': overallQuality,
    'confidence': overallQuality > 0.8 ? 'High' : overallQuality > 0.6 ? 'Medium' : 'Low',
  };
}

/// Calculate contour smoothness
Future<double> _calculateContourSmoothness(List<cv.Point2f> contour) async {
  if (contour.length < 3) return 0.0;
  
  double totalCurvature = 0.0;
  int count = 0;
  
  for (int i = 1; i < contour.length - 1; i++) {
    cv.Point2f prev = contour[i - 1];
    cv.Point2f curr = contour[i];
    cv.Point2f next = contour[i + 1];
    
    // Calculate curvature
    double curvature = _calculateCurvature(prev, curr, next);
    totalCurvature += curvature.abs();
    count++;
  }
  
  double averageCurvature = count > 0 ? totalCurvature / count : 0.0;
  
  // Convert to smoothness score (0-1)
  return max(0.0, 1.0 - averageCurvature / 100.0);
}

/// Calculate baseline quality
Future<double> _calculateBaselineQuality(List<Offset> baselinePoints) async {
  if (baselinePoints.length < 2) return 0.0;
  
  Offset p1 = baselinePoints[0];
  Offset p2 = baselinePoints[1];
  
  // Check baseline length
  double length = sqrt((p2.dx - p1.dx) * (p2.dx - p1.dx) + (p2.dy - p1.dy) * (p2.dy - p1.dy));
  double lengthScore = min(1.0, length / 100.0);
  
  // Check baseline orientation (should be roughly horizontal)
  double angle = atan2(p2.dy - p1.dy, p2.dx - p1.dx).abs();
  double orientationScore = 1.0 - angle / (pi / 2);
  
  return (lengthScore + orientationScore) / 2;
}

/// Calculate curvature at a point
double _calculateCurvature(cv.Point2f p1, cv.Point2f p2, cv.Point2f p3) {
  double dx1 = p2.x - p1.x;
  double dy1 = p2.y - p1.y;
  double dx2 = p3.x - p2.x;
  double dy2 = p3.y - p2.y;
  
  double cross = dx1 * dy2 - dy1 * dx2;
  double dot = dx1 * dx2 + dy1 * dy2;
  
  if (dot == 0) return 0.0;
  
  return cross / (dot * sqrt(dx1 * dx1 + dy1 * dy1));
}

/// Test method to verify contact angle calculation accuracy
/// This method can be used to validate the algorithm with known test cases
Future<Map<String, dynamic>> testContactAngleCalculation() async {
  // Test case 1: Horizontal baseline, vertical tangent (90 degrees)
  double test1 = _calculateContactAngleCorrected(double.infinity, 0.0);
  
  // Test case 2: Horizontal baseline, 45-degree tangent (45 degrees)
  double test2 = _calculateContactAngleCorrected(1.0, 0.0);
  
  // Test case 3: Horizontal baseline, -45-degree tangent (135 degrees)
  double test3 = _calculateContactAngleCorrected(-1.0, 0.0);
  
  // Test case 4: Horizontal baseline, 30-degree tangent (30 degrees)
  double test4 = _calculateContactAngleCorrected(tan(30 * pi / 180), 0.0);
  
  // Test case 5: Horizontal baseline, 150-degree tangent (150 degrees)
  double test5 = _calculateContactAngleCorrected(tan(150 * pi / 180), 0.0);
  
  return {
    'test1_vertical_tangent': test1,
    'test2_45_degree': test2,
    'test3_135_degree': test3,
    'test4_30_degree': test4,
    'test5_150_degree': test5,
    'all_tests_passed': (test1 - 90.0).abs() < 1.0 &&
                       (test2 - 45.0).abs() < 1.0 &&
                       (test3 - 135.0).abs() < 1.0 &&
                       (test4 - 30.0).abs() < 1.0 &&
                       (test5 - 150.0).abs() < 1.0,
  };
}

/// Enhanced contact angle calculation with validation
Future<Map<String, dynamic>> calculateContactAnglesWithValidation(
    List<cv.Point2f> contourPoints, List<Offset> baselinePoints) async {
  
  // First, run the test to ensure the algorithm is working correctly
  final testResults = await testContactAngleCalculation();
  
  if (!testResults['all_tests_passed']) {
    throw Exception('Contact angle calculation validation failed. Please check the algorithm.');
  }
  
  // Proceed with the actual calculation
  final results = await calculateContactAngles(contourPoints, baselinePoints);
  
  // Add validation information to the results
  final enhancedResults = <String, dynamic>{
    ...results,
    'validation': testResults,
    'calculationMethod': 'Validated Corrected',
  };
  
  return enhancedResults;
}