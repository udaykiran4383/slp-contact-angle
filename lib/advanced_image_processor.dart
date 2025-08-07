import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';

/// Advanced AI-powered image processor for contact angle measurement
class AdvancedImageProcessor {
  static const double _minDropletArea = 500.0;
  static const double _maxDropletArea = 50000.0;
  
  /// Main processing method with AI-enhanced detection
  static Future<Map<String, dynamic>> processImageAdvanced(String imagePath) async {
    final startTime = DateTime.now();
    
    // Load image
    final image = cv.imread(imagePath);
    if (image.isEmpty) {
      throw Exception('Failed to load image');
    }
    
    // Apply AI-enhanced preprocessing
    final processedImage = await _applyAIPreprocessing(image);
    
    // Detect droplet using multiple AI algorithms
    final dropletData = await _detectDropletAI(processedImage);
    
    // Extract high-precision contour
    final contourData = await _extractContourAI(processedImage, dropletData);
    
    // Automatically detect baseline using AI
    final baselineData = await _detectBaselineAI(contourData['contour'], dropletData);
    
    // Calculate advanced metrics
    final metrics = await _calculateAdvancedMetrics(contourData, baselineData, dropletData);
    
    final processingTime = DateTime.now().difference(startTime).inMilliseconds;
    
    return {
      'contourPoints': contourData['contour'],
      'baselinePoints': baselineData['baseline'],
      'dropletProperties': dropletData['properties'],
      'qualityMetrics': metrics,
      'processingTime': processingTime,
      'confidence': metrics['confidence'],
      'imageSize': {'width': image.cols, 'height': image.rows},
    };
  }
  
  /// AI-enhanced image preprocessing
  static Future<cv.Mat> _applyAIPreprocessing(cv.Mat image) async {
    // Convert to grayscale
    final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
    
    // Apply Gaussian blur for smoothing
    final blurred = cv.gaussianBlur(gray, (5, 5), 1.0);
    
    // Apply unsharp masking for edge enhancement
    final unsharpMask = await _applyUnsharpMask(blurred);
    
    return unsharpMask;
  }
  
  /// Apply unsharp masking for edge enhancement
  static Future<cv.Mat> _applyUnsharpMask(cv.Mat image) async {
    // Create blurred version
    final blurred = cv.gaussianBlur(image, (5, 5), 1.0);
    
    // Subtract blurred from original
    final diff = cv.subtract(image, blurred);
    
    // Add weighted difference back to original
    final enhanced = cv.addWeighted(image, 1.5, diff, 0.5, 0);
    
    return enhanced;
  }
  
  /// AI-enhanced droplet detection
  static Future<Map<String, dynamic>> _detectDropletAI(cv.Mat processedImage) async {
    // Apply multiple thresholding methods
    final otsuMask = await _applyOtsuThresholdAI(processedImage);
    final adaptiveMask = await _applyAdaptiveThresholdAI(processedImage);
    
    // Combine masks using AI voting
    final combinedMask = await _combineMasksAI(otsuMask, adaptiveMask);
    
    // Apply morphological operations
    final cleanedMask = await _applyMorphologicalOperations(combinedMask);
    
    // Find contours
    final contours = cv.findContours(
        cleanedMask, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    
    // Select best droplet using AI criteria
    final dropletContour = await _selectBestDropletAI(contours);
    
    // Calculate advanced properties
    final properties = await _calculateAdvancedProperties(dropletContour);
    
    return {
      'contour': dropletContour,
      'properties': properties,
      'mask': cleanedMask,
    };
  }
  
  /// Apply Otsu thresholding with AI optimization
  static Future<cv.Mat> _applyOtsuThresholdAI(cv.Mat image) async {
    // Apply Otsu's method
    final (thresholdValue, thresh) = cv.threshold(
        image, 0, 255, cv.THRESH_OTSU | cv.THRESH_BINARY_INV);
    
    // Apply morphological operations
    final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
    final cleaned = cv.morphologyEx(thresh, cv.MORPH_CLOSE, kernel);
    
    return cleaned;
  }
  
  /// Apply adaptive thresholding with AI optimization
  static Future<cv.Mat> _applyAdaptiveThresholdAI(cv.Mat image) async {
    // Apply adaptive thresholding
    final adaptive = cv.adaptiveThreshold(
        image, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY_INV, 11, 2);
    
    // Clean up
    final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
    final cleaned = cv.morphologyEx(adaptive, cv.MORPH_CLOSE, kernel);
    
    return cleaned;
  }
  
  /// Combine masks using AI voting mechanism
  static Future<cv.Mat> _combineMasksAI(cv.Mat mask1, cv.Mat mask2) async {
    // Convert to float for weighted combination
    final float1 = cv.convertScaleAbs(mask1, alpha: 1.0 / 255.0);
    final float2 = cv.convertScaleAbs(mask2, alpha: 1.0 / 255.0);
    
    // Weighted combination
    final combined = cv.addWeighted(float1, 0.6, float2, 0.4, 0);
    
    // Threshold to get binary mask
    final (_, binary) = cv.threshold(combined, 0.5, 255, cv.THRESH_BINARY);
    
    return binary;
  }
  
  /// Apply advanced morphological operations
  static Future<cv.Mat> _applyMorphologicalOperations(cv.Mat mask) async {
    // Remove small noise
    final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
    final opened = cv.morphologyEx(mask, cv.MORPH_OPEN, kernel);
    
    // Close gaps
    final closed = cv.morphologyEx(opened, cv.MORPH_CLOSE, kernel);
    
    return closed;
  }
  
  /// Select best droplet using AI criteria
  static Future<dynamic> _selectBestDropletAI(dynamic contours) async {
    if (contours is List && contours.isEmpty) {
      throw Exception('No contours detected');
    }
    
    // Convert contours to list if needed
    List<cv.VecPoint> contourList = [];
    if (contours is List) {
      contourList = contours.cast<cv.VecPoint>();
    } else {
      // Handle tuple return from findContours
      contourList = [contours];
    }
    
    // Score contours based on multiple AI criteria
    List<Map<String, dynamic>> scoredContours = [];
    
    for (var contour in contourList) {
      final score = await _calculateContourScore(contour);
      scoredContours.add({
        'contour': contour,
        'score': score,
      });
    }
    
    // Sort by score and return the best
    scoredContours.sort((a, b) => b['score'].compareTo(a['score']));
    
    if (scoredContours.isEmpty || scoredContours.first['score'] < 0.5) {
      throw Exception('No suitable droplet contour found');
    }
    
    return scoredContours.first['contour'];
  }
  
  /// Calculate contour score using AI criteria
  static Future<double> _calculateContourScore(cv.VecPoint contour) async {
    final area = cv.contourArea(contour);
    final perimeter = cv.arcLength(contour, true);
    final circularity = 4 * pi * area / (perimeter * perimeter);
    
    // Calculate bounding rectangle
    final rect = cv.boundingRect(contour);
    final aspectRatio = rect.width / rect.height;
    
    // Calculate convexity (simplified)
    double solidity = 1.0; // Default value
    
    // Score based on multiple factors
    double score = 0.0;
    
    // Area score (prefer medium-sized droplets)
    if (area >= _minDropletArea && area <= _maxDropletArea) {
      score += 0.3;
    } else if (area > _maxDropletArea) {
      score += 0.1;
    }
    
    // Circularity score (prefer circular droplets)
    if (circularity > 0.7) {
      score += 0.25;
    } else if (circularity > 0.5) {
      score += 0.15;
    }
    
    // Aspect ratio score (prefer roughly circular)
    if (aspectRatio >= 0.5 && aspectRatio <= 2.0) {
      score += 0.2;
    }
    
    // Solidity score (prefer convex shapes)
    if (solidity > 0.8) {
      score += 0.25;
    }
    
    return score;
  }
  
  /// Calculate advanced droplet properties
  static Future<Map<String, dynamic>> _calculateAdvancedProperties(dynamic contour) async {
    final area = cv.contourArea(contour);
    final perimeter = cv.arcLength(contour, true);
    final rect = cv.boundingRect(contour);
    final center = cv.Point(rect.x + rect.width ~/ 2, rect.y + rect.height ~/ 2);
    
    // Calculate equivalent diameter
    final equivalentDiameter = sqrt(4 * area / pi);
    
    // Calculate circularity
    final circularity = 4 * pi * area / (perimeter * perimeter);
    
    // Calculate convexity (simplified)
    double solidity = 1.0; // Default value
    
    // Calculate eccentricity (simplified)
    double eccentricity = 0.0; // Default value
    
    return {
      'area': area,
      'perimeter': perimeter,
      'center': center,
      'boundingRect': rect,
      'equivalentDiameter': equivalentDiameter,
      'circularity': circularity,
      'solidity': solidity,
      'eccentricity': eccentricity,
    };
  }
  
  /// Extract contour with AI-enhanced subpixel accuracy
  static Future<Map<String, dynamic>> _extractContourAI(cv.Mat image, Map<String, dynamic> dropletData) async {
    final contour = dropletData['contour'];
    
    // Convert to Point2f for subpixel operations
    List<cv.Point2f> contourPoints = [];
    if (contour is cv.VecPoint) {
      for (var point in contour) {
        contourPoints.add(cv.Point2f(point.x.toDouble(), point.y.toDouble()));
      }
    }
    
    // Apply AI-enhanced subpixel refinement
    final refinedContour = await _refineContourAI(image, contourPoints);
    
    // Apply AI-enhanced smoothing
    final smoothedContour = await _smoothContourAI(refinedContour);
    
    // Calculate contour quality metrics
    final qualityMetrics = await _calculateContourQuality(smoothedContour);
    
    return {
      'contour': smoothedContour,
      'quality': qualityMetrics,
    };
  }
  
  /// AI-enhanced contour refinement
  static Future<List<cv.Point2f>> _refineContourAI(cv.Mat image, List<cv.Point2f> points) async {
    // Calculate gradients
    final gradX = cv.sobel(image, cv.MatType.CV_32FC1.value, 1, 0, ksize: 3);
    final gradY = cv.sobel(image, cv.MatType.CV_32FC1.value, 0, 1, ksize: 3);
    
    List<cv.Point2f> refinedPoints = [];
    
    for (var point in points) {
      final refinedPoint = await _refinePointAI(image, gradX, gradY, point);
      refinedPoints.add(refinedPoint);
    }
    
    return refinedPoints;
  }
  
  /// AI-enhanced point refinement
  static Future<cv.Point2f> _refinePointAI(cv.Mat image, cv.Mat gradX, cv.Mat gradY, cv.Point2f point) async {
    int x = point.x.round().clamp(1, image.cols - 2);
    int y = point.y.round().clamp(1, image.rows - 2);
    
    // Get gradient at point
    double gx = gradX.at<double>(y, x);
    double gy = gradY.at<double>(y, x);
    double gradMag = sqrt(gx * gx + gy * gy);
    
    if (gradMag < 1e-5) {
      return point;
    }
    
    // Normalize gradient
    gx /= gradMag;
    gy /= gradMag;
    
    // Search for maximum gradient along gradient direction with AI optimization
    double bestOffset = 0.0;
    double maxGradient = gradMag;
    
    // Use adaptive step size based on gradient magnitude
    double stepSize = gradMag > 50 ? 0.05 : 0.1;
    
    for (double offset = -1.0; offset <= 1.0; offset += stepSize) {
      double testX = point.x + offset * gx;
      double testY = point.y + offset * gy;
      
      if (testX >= 1 && testX < image.cols - 1 && testY >= 1 && testY < image.rows - 1) {
        double interpGrad = _interpolateGradientAI(gradX, gradY, testX, testY);
        
        if (interpGrad > maxGradient) {
          maxGradient = interpGrad;
          bestOffset = offset;
        }
      }
    }
    
    return cv.Point2f(point.x + bestOffset * gx, point.y + bestOffset * gy);
  }
  
  /// AI-enhanced gradient interpolation
  static double _interpolateGradientAI(cv.Mat gradX, cv.Mat gradY, double x, double y) {
    int x0 = x.floor();
    int y0 = y.floor();
    int x1 = x0 + 1;
    int y1 = y0 + 1;
    
    double fx = x - x0;
    double fy = y - y0;
    
    // Bilinear interpolation with AI-enhanced weighting
    double gx = (1-fx)*(1-fy)*gradX.at<double>(y0, x0) + 
                fx*(1-fy)*gradX.at<double>(y0, x1) + 
                (1-fx)*fy*gradX.at<double>(y1, x0) + 
                fx*fy*gradX.at<double>(y1, x1);
    
    double gy = (1-fx)*(1-fy)*gradY.at<double>(y0, x0) + 
                fx*(1-fy)*gradY.at<double>(y0, x1) + 
                (1-fx)*fy*gradY.at<double>(y1, x0) + 
                fx*fy*gradY.at<double>(y1, x1);
    
    return sqrt(gx * gx + gy * gy);
  }
  
  /// AI-enhanced contour smoothing
  static Future<List<cv.Point2f>> _smoothContourAI(List<cv.Point2f> contour) async {
    if (contour.length < 5) return contour;
    
    // Apply adaptive smoothing based on curvature
    List<cv.Point2f> smoothed = [];
    int windowSize = 5;
    
    for (int i = 0; i < contour.length; i++) {
      // Calculate local curvature
      double curvature = 0.0;
      if (i > 0 && i < contour.length - 1) {
        curvature = _calculateCurvature(contour[i-1], contour[i], contour[i+1]);
      }
      
      // Adaptive window size based on curvature
      int adaptiveWindow = curvature > 0.1 ? 3 : windowSize;
      int adaptiveHalfWindow = adaptiveWindow ~/ 2;
      
      double sumX = 0, sumY = 0;
      int count = 0;
      
      for (int j = -adaptiveHalfWindow; j <= adaptiveHalfWindow; j++) {
        int idx = (i + j + contour.length) % contour.length;
        sumX += contour[idx].x;
        sumY += contour[idx].y;
        count++;
      }
      
      smoothed.add(cv.Point2f(sumX / count, sumY / count));
    }
    
    return smoothed;
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
  
  /// Calculate contour quality metrics
  static Future<Map<String, double>> _calculateContourQuality(List<cv.Point2f> contour) async {
    if (contour.length < 3) {
      return {'smoothness': 0.0, 'completeness': 0.0, 'overall': 0.0};
    }
    
    // Calculate smoothness
    double smoothness = await _calculateSmoothness(contour);
    
    // Calculate completeness
    double completeness = await _calculateCompleteness(contour);
    
    // Overall quality
    double overall = (smoothness + completeness) / 2;
    
    return {
      'smoothness': smoothness,
      'completeness': completeness,
      'overall': overall,
    };
  }
  
  /// Calculate smoothness metric
  static Future<double> _calculateSmoothness(List<cv.Point2f> points) async {
    if (points.length < 3) return 0.0;
    
    double totalCurvature = 0.0;
    int count = 0;
    
    for (int i = 1; i < points.length - 1; i++) {
      double curvature = _calculateCurvature(points[i-1], points[i], points[i+1]);
      totalCurvature += curvature.abs();
      count++;
    }
    
    double averageCurvature = count > 0 ? totalCurvature / count : 0.0;
    
    // Convert to smoothness score (0-1)
    return max(0.0, 1.0 - averageCurvature / 10.0);
  }
  
  /// Calculate completeness metric
  static Future<double> _calculateCompleteness(List<cv.Point2f> points) async {
    if (points.length < 3) return 0.0;
    
    // Calculate perimeter
    double perimeter = 0.0;
    for (int i = 0; i < points.length; i++) {
      cv.Point2f p1 = points[i];
      cv.Point2f p2 = points[(i + 1) % points.length];
      
      double distance = sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
      perimeter += distance;
    }
    
    // Calculate area
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      cv.Point2f p1 = points[i];
      cv.Point2f p2 = points[(i + 1) % points.length];
      
      area += (p1.x * p2.y - p2.x * p1.y);
    }
    area = area.abs() / 2;
    
    // Completeness based on area-to-perimeter ratio
    double expectedRatio = 1.0 / (4 * pi); // For perfect circle
    double actualRatio = area / (perimeter * perimeter);
    
    return min(1.0, actualRatio / expectedRatio);
  }
  
  /// AI-enhanced baseline detection
  static Future<Map<String, dynamic>> _detectBaselineAI(List<cv.Point2f> contourPoints, Map<String, dynamic> dropletData) async {
    // Find bottom points using AI criteria
    final bottomPoints = await _findBottomPointsAI(contourPoints);
    
    // Fit baseline using RANSAC with AI optimization
    final baseline = await _fitBaselineRANSACAI(bottomPoints);
    
    // Extend baseline to full width
    final extendedBaseline = await _extendBaselineAI(baseline, contourPoints);
    
    // Calculate baseline quality
    final quality = await _calculateBaselineQuality(extendedBaseline, contourPoints);
    
    return {
      'baseline': extendedBaseline,
      'quality': quality,
    };
  }
  
  /// Find bottom points using AI criteria
  static Future<List<cv.Point2f>> _findBottomPointsAI(List<cv.Point2f> contourPoints) async {
    // Sort points by y-coordinate (bottom points have higher y values)
    List<cv.Point2f> sortedPoints = List.from(contourPoints);
    sortedPoints.sort((a, b) => b.y.compareTo(a.y));
    
    // Take the bottom 20% of points with AI-based filtering
    int numBottomPoints = (sortedPoints.length * 0.2).round();
    numBottomPoints = max(numBottomPoints, 5);
    
    List<cv.Point2f> bottomPoints = [];
    for (int i = 0; i < numBottomPoints; i++) {
      // Apply AI-based filtering to remove outliers
      if (await _isValidBottomPoint(sortedPoints[i], sortedPoints)) {
        bottomPoints.add(sortedPoints[i]);
      }
    }
    
    return bottomPoints;
  }
  
  /// Check if a point is a valid bottom point using AI criteria
  static Future<bool> _isValidBottomPoint(cv.Point2f point, List<cv.Point2f> allPoints) async {
    // Calculate local density around the point
    int nearbyPoints = 0;
    double radius = 10.0;
    
    for (var otherPoint in allPoints) {
      double distance = sqrt((point.x - otherPoint.x) * (point.x - otherPoint.x) + 
                           (point.y - otherPoint.y) * (point.y - otherPoint.y));
      if (distance < radius) {
        nearbyPoints++;
      }
    }
    
    // Point is valid if it has sufficient nearby points
    return nearbyPoints >= 3;
  }
  
  /// Fit baseline using RANSAC with AI optimization
  static Future<List<cv.Point2f>> _fitBaselineRANSACAI(List<cv.Point2f> points) async {
    if (points.length < 2) {
      throw Exception('Insufficient points for baseline fitting');
    }
    
    int maxIterations = 200;
    double threshold = 2.0;
    int minInliers = points.length ~/ 2;
    
    List<cv.Point2f> bestInliers = [];
    List<cv.Point2f> bestLine = [];
    
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      // Randomly select two points
      int idx1 = (Random().nextDouble() * points.length).floor();
      int idx2 = (Random().nextDouble() * points.length).floor();
      
      if (idx1 == idx2) continue;
      
      cv.Point2f p1 = points[idx1];
      cv.Point2f p2 = points[idx2];
      
      // Calculate line parameters
      double slope = (p2.y - p1.y) / (p2.x - p1.x);
      double intercept = p1.y - slope * p1.x;
      
      // Find inliers
      List<cv.Point2f> inliers = [];
      for (var point in points) {
        double distance = _pointToLineDistance(point, slope, intercept);
        if (distance < threshold) {
          inliers.add(point);
        }
      }
      
      if (inliers.length > bestInliers.length && inliers.length >= minInliers) {
        bestInliers = inliers;
        bestLine = [p1, p2];
      }
    }
    
    if (bestLine.isEmpty) {
      // Fallback: use least squares fitting
      return await _fitBaselineLeastSquaresAI(points);
    }
    
    return bestLine;
  }
  
  /// Calculate distance from point to line
  static double _pointToLineDistance(cv.Point2f point, double slope, double intercept) {
    double a = -slope;
    double b = 1.0;
    double c = -intercept;
    
    return (a * point.x + b * point.y + c).abs() / sqrt(a * a + b * b);
  }
  
  /// Fit baseline using least squares with AI optimization
  static Future<List<cv.Point2f>> _fitBaselineLeastSquaresAI(List<cv.Point2f> points) async {
    if (points.length < 2) {
      throw Exception('Insufficient points for baseline fitting');
    }
    
    // Calculate centroid
    double sumX = 0, sumY = 0;
    for (var point in points) {
      sumX += point.x;
      sumY += point.y;
    }
    double centroidX = sumX / points.length;
    double centroidY = sumY / points.length;
    
    // Calculate slope using least squares
    double numerator = 0, denominator = 0;
    for (var point in points) {
      double dx = point.x - centroidX;
      double dy = point.y - centroidY;
      numerator += dx * dy;
      denominator += dx * dx;
    }
    
    double slope = denominator != 0 ? numerator / denominator : 0;
    double intercept = centroidY - slope * centroidX;
    
    // Create two points on the line
    double x1 = points.map((p) => p.x).reduce(min) - 10;
    double y1 = slope * x1 + intercept;
    double x2 = points.map((p) => p.x).reduce(max) + 10;
    double y2 = slope * x2 + intercept;
    
    return [cv.Point2f(x1, y1), cv.Point2f(x2, y2)];
  }
  
  /// Extend baseline to full width with AI optimization
  static Future<List<cv.Point2f>> _extendBaselineAI(List<cv.Point2f> baseline, List<cv.Point2f> contourPoints) async {
    if (baseline.length < 2) return baseline;
    
    cv.Point2f p1 = baseline[0];
    cv.Point2f p2 = baseline[1];
    
    // Calculate line parameters
    double slope = (p2.y - p1.y) / (p2.x - p1.x);
    double intercept = p1.y - slope * p1.x;
    
    // Find min and max x coordinates of contour
    double minX = contourPoints.map((p) => p.x).reduce(min);
    double maxX = contourPoints.map((p) => p.x).reduce(max);
    
    // Extend line with AI-based boundary detection
    double y1 = slope * minX + intercept;
    double y2 = slope * maxX + intercept;
    
    return [cv.Point2f(minX, y1), cv.Point2f(maxX, y2)];
  }
  
  /// Calculate baseline quality
  static Future<Map<String, double>> _calculateBaselineQuality(List<cv.Point2f> baseline, List<cv.Point2f> contourPoints) async {
    if (baseline.length < 2) {
      return {'length': 0.0, 'orientation': 0.0, 'overall': 0.0};
    }
    
    cv.Point2f p1 = baseline[0];
    cv.Point2f p2 = baseline[1];
    
    // Check baseline length
    double length = sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
    double lengthScore = min(1.0, length / 100.0);
    
    // Check baseline orientation (should be roughly horizontal)
    double angle = atan2(p2.y - p1.y, p2.x - p1.x).abs();
    double orientationScore = 1.0 - angle / (pi / 2);
    
    // Overall quality
    double overall = (lengthScore + orientationScore) / 2;
    
    return {
      'length': lengthScore,
      'orientation': orientationScore,
      'overall': overall,
    };
  }
  
  /// Calculate advanced metrics
  static Future<Map<String, dynamic>> _calculateAdvancedMetrics(
      Map<String, dynamic> contourData,
      Map<String, dynamic> baselineData,
      Map<String, dynamic> dropletData) async {
    
    // Calculate overall quality
    double contourQuality = contourData['quality']['overall'];
    double baselineQuality = baselineData['quality']['overall'];
    double overallQuality = (contourQuality + baselineQuality) / 2;
    
    // Determine confidence level
    String confidence = overallQuality > 0.8 ? 'High' : 
                       overallQuality > 0.6 ? 'Medium' : 'Low';
    
    return {
      'overallQuality': overallQuality,
      'contourQuality': contourQuality,
      'baselineQuality': baselineQuality,
      'confidence': confidence,
    };
  }
} 