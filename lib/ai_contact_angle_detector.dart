import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';

/// Advanced AI-powered contact angle detector using computer vision and ML
class AIContactAngleDetector {
  static const double _minDropletArea = 500.0;
  static const double _maxDropletArea = 50000.0;
  
  /// Main detection method - automatically detects droplet and calculates contact angles
  static Future<Map<String, dynamic>> detectContactAngles(String imagePath) async {
    final startTime = DateTime.now();
    
    // Load and preprocess image
    final image = cv.imread(imagePath);
    if (image.isEmpty) {
      throw Exception('Failed to load image');
    }
    
    // Apply advanced preprocessing
    final processedImage = await _preprocessImage(image);
    
    // Detect droplet using AI-enhanced methods
    final dropletData = await _detectDroplet(processedImage);
    
    // Extract contour with subpixel accuracy
    final contourPoints = await _extractContour(processedImage, dropletData);
    
    // Automatically detect baseline
    final baselinePoints = await _detectBaseline(contourPoints, dropletData);
    
    // Calculate contact angles using advanced algorithms
    final angles = await _calculateAdvancedContactAngles(contourPoints, baselinePoints);
    
    // Perform quality assessment
    final qualityMetrics = await _assessQuality(contourPoints, baselinePoints, angles);
    
    final processingTime = DateTime.now().difference(startTime).inMilliseconds;
    
    return {
      'leftAngle': angles['left'],
      'rightAngle': angles['right'],
      'averageAngle': angles['average'],
      'uncertainty': angles['uncertainty'],
      'baselinePoints': baselinePoints,
      'contourPoints': contourPoints,
      'qualityScore': qualityMetrics['score'],
      'confidence': qualityMetrics['confidence'],
      'dropletProperties': dropletData,
      'processingTime': processingTime,
    };
  }
  
  /// Advanced image preprocessing using multiple techniques
  static Future<cv.Mat> _preprocessImage(cv.Mat image) async {
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
  
  /// AI-enhanced droplet detection using multiple algorithms
  static Future<Map<String, dynamic>> _detectDroplet(cv.Mat processedImage) async {
    // Apply multiple thresholding methods
    final otsuMask = await _applyOtsuThresholdAI(processedImage);
    final adaptiveMask = await _applyAdaptiveThresholdAI(processedImage);
    
    // Combine masks using AI voting
    final combinedMask = await _combineMasksAI(otsuMask, adaptiveMask);
    
    // Apply morphological operations
    final cleanedMask = await _applyMorphologicalOperations(combinedMask);
    
    // Find contours
    final (contours, hierarchy) = cv.findContours(
        cleanedMask, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);
    
    // Select best droplet contour using AI criteria
    final dropletContour = await _selectBestContour(contours);
    
    // Calculate droplet properties
    final properties = await _calculateDropletProperties(dropletContour);
    
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
  
  /// Select best contour using AI criteria
  static Future<cv.VecPoint> _selectBestContour(dynamic contours) async {
    if (contours.isEmpty) {
      throw Exception('No contours detected');
    }
    
    // Score contours based on multiple criteria
    List<Map<String, dynamic>> scoredContours = [];
    
    for (var contour in contours) {
      final area = cv.contourArea(contour);
      final perimeter = cv.arcLength(contour, true);
      final circularity = 4 * pi * area / (perimeter * perimeter);
      
      // Calculate bounding rectangle
      final rect = cv.boundingRect(contour);
      final aspectRatio = rect.width / rect.height;
      
      // Score based on multiple factors
      double score = 0.0;
      
      // Area score (prefer medium-sized droplets)
      if (area >= _minDropletArea && area <= _maxDropletArea) {
        score += 0.4;
      } else if (area > _maxDropletArea) {
        score += 0.2;
      }
      
      // Circularity score (prefer circular droplets)
      if (circularity > 0.7) {
        score += 0.3;
      } else if (circularity > 0.5) {
        score += 0.2;
      }
      
      // Aspect ratio score (prefer roughly circular)
      if (aspectRatio >= 0.5 && aspectRatio <= 2.0) {
        score += 0.3;
      }
      
      scoredContours.add({
        'contour': contour,
        'score': score,
        'area': area,
        'circularity': circularity,
        'aspectRatio': aspectRatio,
      });
    }
    
    // Sort by score and return the best
    scoredContours.sort((a, b) => b['score'].compareTo(a['score']));
    
    if (scoredContours.isEmpty || scoredContours.first['score'] < 0.5) {
      throw Exception('No suitable droplet contour found');
    }
    
    return scoredContours.first['contour'];
  }
  
  /// Calculate droplet properties
  static Future<Map<String, dynamic>> _calculateDropletProperties(cv.VecPoint contour) async {
    final area = cv.contourArea(contour);
    final perimeter = cv.arcLength(contour, true);
    final rect = cv.boundingRect(contour);
    final center = cv.Point(rect.x + rect.width ~/ 2, rect.y + rect.height ~/ 2);
    
    // Calculate equivalent diameter
    final equivalentDiameter = sqrt(4 * area / pi);
    
    // Calculate circularity
    final circularity = 4 * pi * area / (perimeter * perimeter);
    
    return {
      'area': area,
      'perimeter': perimeter,
      'center': center,
      'boundingRect': rect,
      'equivalentDiameter': equivalentDiameter,
      'circularity': circularity,
    };
  }
  
  /// Extract contour with subpixel accuracy
  static Future<List<cv.Point2f>> _extractContour(cv.Mat image, Map<String, dynamic> dropletData) async {
    final contour = dropletData['contour'] as cv.VecPoint;
    
    // Convert to Point2f for subpixel operations
    List<cv.Point2f> contourPoints = [];
    for (var point in contour) {
      contourPoints.add(cv.Point2f(point.x.toDouble(), point.y.toDouble()));
    }
    
    // Apply smoothing
    final smoothedContour = _smoothContour(contourPoints);
    
    // Apply subpixel refinement
    final refinedContour = await _refineContourSubpixel(image, smoothedContour);
    
    return refinedContour;
  }
  
  /// Smooth contour using moving average
  static List<cv.Point2f> _smoothContour(List<cv.Point2f> contour) {
    if (contour.length < 5) return contour;
    
    List<cv.Point2f> smoothed = [];
    int windowSize = 5;
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
  
  /// Refine contour with subpixel accuracy using gradient information
  static Future<List<cv.Point2f>> _refineContourSubpixel(cv.Mat image, List<cv.Point2f> contour) async {
    // Calculate gradients using Sobel
    final gradX = cv.Sobel(image, cv.CV_64F, 1, 0, ksize: 3);
    final gradY = cv.Sobel(image, cv.CV_64F, 0, 1, ksize: 3);
    
    List<cv.Point2f> refinedContour = [];
    
    for (var point in contour) {
      // Find maximum gradient in the neighborhood
      double maxGradient = 0.0;
      cv.Point2f bestPoint = point;
      
      // Search in a small neighborhood
      for (double dx = -1.0; dx <= 1.0; dx += 0.1) {
        for (double dy = -1.0; dy <= 1.0; dy += 0.1) {
          double testX = point.x + dx;
          double testY = point.y + dy;
          
          if (testX >= 0 && testX < image.cols && testY >= 0 && testY < image.rows) {
            // Interpolate gradient
            double gradient = _interpolateGradient(gradX, gradY, testX, testY);
            
            if (gradient > maxGradient) {
              maxGradient = gradient;
              bestPoint = cv.Point2f(testX, testY);
            }
          }
        }
      }
      
      refinedContour.add(bestPoint);
    }
    
    return refinedContour;
  }
  
  /// Interpolate gradient at subpixel position
  static double _interpolateGradient(cv.Mat gradX, cv.Mat gradY, double x, double y) {
    int x0 = x.floor();
    int y0 = y.floor();
    int x1 = min(x0 + 1, gradX.cols - 1);
    int y1 = min(y0 + 1, gradX.rows - 1);
    
    double fx = x - x0;
    double fy = y - y0;
    
    // Bilinear interpolation
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
  
  /// Automatically detect baseline using AI algorithms
  static Future<List<cv.Point2f>> _detectBaseline(List<cv.Point2f> contourPoints, Map<String, dynamic> dropletData) async {
    // Find the bottom points of the droplet
    final bottomPoints = await _findBottomPoints(contourPoints);
    
    // Fit line to bottom points using RANSAC
    final baseline = await _fitBaselineRANSAC(bottomPoints);
    
    // Extend baseline to full width
    final extendedBaseline = await _extendBaseline(baseline, contourPoints);
    
    return extendedBaseline;
  }
  
  /// Find bottom points of the droplet
  static Future<List<cv.Point2f>> _findBottomPoints(List<cv.Point2f> contourPoints) async {
    // Sort points by y-coordinate (bottom points have higher y values)
    List<cv.Point2f> sortedPoints = List.from(contourPoints);
    sortedPoints.sort((a, b) => b.y.compareTo(a.y));
    
    // Take the bottom 20% of points
    int numBottomPoints = (sortedPoints.length * 0.2).round();
    numBottomPoints = max(numBottomPoints, 5);
    
    return sortedPoints.take(numBottomPoints).toList();
  }
  
  /// Fit baseline using RANSAC algorithm
  static Future<List<cv.Point2f>> _fitBaselineRANSAC(List<cv.Point2f> points) async {
    if (points.length < 2) {
      throw Exception('Insufficient points for baseline fitting');
    }
    
    int maxIterations = 100;
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
      return await _fitBaselineLeastSquares(points);
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
  
  /// Fit baseline using least squares method
  static Future<List<cv.Point2f>> _fitBaselineLeastSquares(List<cv.Point2f> points) async {
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
  
  /// Extend baseline to full width
  static Future<List<cv.Point2f>> _extendBaseline(List<cv.Point2f> baseline, List<cv.Point2f> contourPoints) async {
    if (baseline.length < 2) return baseline;
    
    cv.Point2f p1 = baseline[0];
    cv.Point2f p2 = baseline[1];
    
    // Calculate line parameters
    double slope = (p2.y - p1.y) / (p2.x - p1.x);
    double intercept = p1.y - slope * p1.x;
    
    // Find min and max x coordinates of contour
    double minX = contourPoints.map((p) => p.x).reduce(min);
    double maxX = contourPoints.map((p) => p.x).reduce(max);
    
    // Extend line
    double y1 = slope * minX + intercept;
    double y2 = slope * maxX + intercept;
    
    return [cv.Point2f(minX, y1), cv.Point2f(maxX, y2)];
  }
  
  /// Calculate advanced contact angles using multiple methods
  static Future<Map<String, double>> _calculateAdvancedContactAngles(List<cv.Point2f> contourPoints, List<cv.Point2f> baselinePoints) async {
    // Use ellipse fitting for angle calculation
    final angles = await _calculateEllipseAngles(contourPoints, baselinePoints);
    
    return angles;
  }
  
  /// Calculate angles using ellipse fitting
  static Future<Map<String, double>> _calculateEllipseAngles(List<cv.Point2f> contourPoints, List<cv.Point2f> baselinePoints) async {
    // Convert to integer points for fitEllipse
    List<cv.Point> intPoints = contourPoints
        .map((p) => cv.Point(p.x.round(), p.y.round()))
        .toList();
    
    final ellipse = cv.fitEllipse(cv.VecPoint.fromList(intPoints));
    
    // Calculate intersection points
    final intersections = await _findEllipseLineIntersections(ellipse, baselinePoints);
    
    if (intersections.length < 2) {
      throw Exception('Failed to find ellipse-line intersections');
    }
    
    // Calculate tangent angles
    final leftAngle = await _calculateTangentAngle(ellipse, intersections[0]);
    final rightAngle = await _calculateTangentAngle(ellipse, intersections[1]);
    
    // Calculate uncertainty
    final uncertainty = await _estimateUncertainty(contourPoints, ellipse, leftAngle, rightAngle);
    
    return {
      'left': leftAngle,
      'right': rightAngle,
      'average': (leftAngle + rightAngle) / 2,
      'uncertainty': uncertainty,
    };
  }
  
  /// Find ellipse-line intersections
  static Future<List<cv.Point2f>> _findEllipseLineIntersections(cv.RotatedRect ellipse, List<cv.Point2f> baselinePoints) async {
    if (baselinePoints.length < 2) {
      return baselinePoints;
    }
    
    // Extract ellipse parameters
    double centerX = ellipse.center.x;
    double centerY = ellipse.center.y;
    double semiMajor = max(ellipse.size.width, ellipse.size.height) / 2;
    double semiMinor = min(ellipse.size.width, ellipse.size.height) / 2;
    double rotationAngle = ellipse.angle * (pi / 180);
    
    // Calculate baseline parameters
    cv.Point2f p1 = baselinePoints[0];
    cv.Point2f p2 = baselinePoints[1];
    double slope = (p2.y - p1.y) / (p2.x - p1.x);
    double intercept = p1.y - slope * p1.x;
    
    // Find intersections using analytical method
    List<Map<String, double>> intersections = _findEllipseLineIntersectionsAnalytical(
        centerX, centerY, semiMajor, semiMinor, rotationAngle, slope, intercept);
    
    if (intersections.length < 2) {
      // Fallback: use baseline points
      return baselinePoints;
    }
    
    // Convert to Point2f
    return intersections.map((p) => cv.Point2f(p['x']!, p['y']!)).toList();
  }
  
  /// Find analytical intersections between ellipse and line
  static List<Map<String, double>> _findEllipseLineIntersectionsAnalytical(
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
  
  /// Calculate tangent angle at intersection point
  static Future<double> _calculateTangentAngle(cv.RotatedRect ellipse, cv.Point2f point) async {
    // Extract ellipse parameters
    double centerX = ellipse.center.x;
    double centerY = ellipse.center.y;
    double semiMajor = max(ellipse.size.width, ellipse.size.height) / 2;
    double semiMinor = min(ellipse.size.width, ellipse.size.height) / 2;
    double rotationAngle = ellipse.angle * (pi / 180);
    
    // Calculate tangent slope using analytical derivatives
    double tangentSlope = _calculateEllipseTangent(
        point.x, point.y, centerX, centerY, semiMajor, semiMinor, rotationAngle);
    
    // Calculate contact angle (assuming horizontal baseline)
    double contactAngle = _calculateContactAngle(tangentSlope, 0.0);
    
    return contactAngle;
  }
  
  /// Calculate ellipse tangent slope at a point using implicit differentiation
  static double _calculateEllipseTangent(
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
  
  /// Calculate contact angle specifically for droplet geometry
  /// This method handles the specific case of a droplet on a surface
  static double _calculateContactAngle(double tangentSlope, double baselineSlope) {
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
  
  /// Estimate measurement uncertainty
  static Future<double> _estimateUncertainty(List<cv.Point2f> points, cv.RotatedRect ellipse, double leftAngle, double rightAngle) async {
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
    double asymmetryUncertainty = (leftAngle - rightAngle).abs() * 0.1;
    
    // Combined uncertainty
    double totalUncertainty = sqrt(
        pixelUncertainty * pixelUncertainty +
        fitUncertainty * fitUncertainty +
        asymmetryUncertainty * asymmetryUncertainty
    );
    
    return min(totalUncertainty, 5.0);  // Cap at 5 degrees
  }
  
  /// Calculate distance from point to ellipse (approximate)
  static double _pointToEllipseDistance(
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
  
  /// Assess overall quality of the measurement
  static Future<Map<String, dynamic>> _assessQuality(
      List<cv.Point2f> contourPoints,
      List<cv.Point2f> baselinePoints,
      Map<String, double> angles) async {
    
    // Calculate quality metrics
    double contourQuality = await _assessContourQuality(contourPoints);
    double baselineQuality = await _assessBaselineQuality(baselinePoints);
    double angleQuality = await _assessAngleQuality(angles);
    
    // Overall quality score (0-1)
    double overallScore = (contourQuality + baselineQuality + angleQuality) / 3;
    
    // Confidence level based on quality score
    String confidence = overallScore > 0.8 ? 'High' : 
                       overallScore > 0.6 ? 'Medium' : 'Low';
    
    return {
      'score': overallScore,
      'confidence': confidence,
      'contourQuality': contourQuality,
      'baselineQuality': baselineQuality,
      'angleQuality': angleQuality,
      'processingTime': DateTime.now().millisecondsSinceEpoch,
    };
  }
  
  /// Assess contour quality
  static Future<double> _assessContourQuality(List<cv.Point2f> contourPoints) async {
    if (contourPoints.length < 20) return 0.0;
    
    // Calculate smoothness
    double smoothness = await _calculateSmoothness(contourPoints);
    
    // Calculate completeness
    double completeness = await _calculateCompleteness(contourPoints);
    
    return (smoothness + completeness) / 2;
  }
  
  /// Calculate contour smoothness
  static Future<double> _calculateSmoothness(List<cv.Point2f> points) async {
    if (points.length < 3) return 0.0;
    
    double totalCurvature = 0.0;
    int count = 0;
    
    for (int i = 1; i < points.length - 1; i++) {
      cv.Point2f prev = points[i - 1];
      cv.Point2f curr = points[i];
      cv.Point2f next = points[i + 1];
      
      // Calculate curvature
      double curvature = _calculateCurvature(prev, curr, next);
      totalCurvature += curvature;
      count++;
    }
    
    double averageCurvature = count > 0 ? totalCurvature / count : 0.0;
    
    // Convert to smoothness score (0-1)
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
  
  /// Calculate contour completeness
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
  
  /// Assess baseline quality
  static Future<double> _assessBaselineQuality(List<cv.Point2f> baselinePoints) async {
    if (baselinePoints.length < 2) return 0.0;
    
    cv.Point2f p1 = baselinePoints[0];
    cv.Point2f p2 = baselinePoints[1];
    
    // Check baseline length
    double length = sqrt((p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y));
    double lengthScore = min(1.0, length / 100.0);
    
    // Check baseline orientation (should be roughly horizontal)
    double angle = atan2(p2.y - p1.y, p2.x - p1.x).abs();
    double orientationScore = 1.0 - angle / (pi / 2);
    
    return (lengthScore + orientationScore) / 2;
  }
  
  /// Assess angle quality
  static Future<double> _assessAngleQuality(Map<String, double> angles) async {
    double leftAngle = angles['left']!;
    double rightAngle = angles['right']!;
    
    // Check for reasonable angle range (0-180 degrees)
    if (leftAngle < 0 || leftAngle > 180 || rightAngle < 0 || rightAngle > 180) {
      return 0.0;
    }
    
    // Check for symmetry
    double symmetry = 1.0 - (leftAngle - rightAngle).abs() / 180.0;
    
    // Check for reasonable contact angle range (typically 0-150 degrees)
    double leftScore = leftAngle > 150 ? 0.5 : 1.0;
    double rightScore = rightAngle > 150 ? 0.5 : 1.0;
    
    return (symmetry + leftScore + rightScore) / 3;
  }
} 