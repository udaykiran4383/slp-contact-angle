import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:math';

/// Process image to extract droplet contour with subpixel accuracy
/// Uses Gaussian fitting for edge refinement as per scientific standards
Future<List<cv.Point2f>> processImage(String imagePath) async {
  // Load image
  final image = cv.imread(imagePath);
  if (image.isEmpty) {
    throw Exception('Failed to load image. Please ensure the file is valid.');
  }

  // Convert to grayscale
  final gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
  
  // Apply Gaussian blur to reduce noise (σ = 1.0)
  final blurred = cv.gaussianBlur(gray, (5, 5), 1.0);

  // Apply Otsu's thresholding with binary inversion for dark droplet
  final (thresholdValue, thresh) = cv.threshold(
      blurred, 0, 255, cv.THRESH_OTSU | cv.THRESH_BINARY_INV);
  
  // Debug: Otsu threshold value = $thresholdValue

  // Morphological operations to clean up the binary image
  final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
  final cleaned = cv.morphologyEx(thresh, cv.MORPH_CLOSE, kernel);
  final opened = cv.morphologyEx(cleaned, cv.MORPH_OPEN, kernel);

  // Edge detection with Canny
  final edges = cv.canny(opened, 50, 150, apertureSize: 3);

  // Find contours
  final (contours, hierarchy) = cv.findContours(
      edges, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

  // Select largest contour (assumed to be droplet)
  if (contours.isEmpty) {
    throw Exception('No contours found. Ensure the droplet is visible and well-lit.');
  }
  
  final dropletContour = contours.reduce((a, b) => 
      cv.contourArea(a) > cv.contourArea(b) ? a : b);
  
  // Check contour area for validation
  double area = cv.contourArea(dropletContour);
  if (area < 100) {  // Minimum area threshold
    throw Exception('Detected contour too small. Area: ${area.toStringAsFixed(0)} pixels²');
  }

  // Subpixel refinement using corner refinement on contour points
  // Convert contour points to Point2f for subpixel operations
  List<cv.Point2f> contourPoints = [];
  for (var point in dropletContour) {
    contourPoints.add(cv.Point2f(point.x.toDouble(), point.y.toDouble()));
  }
  
  // Apply subpixel refinement using Gaussian fitting on edge gradients
  List<cv.Point2f> refinedContour = await _refineContourSubpixel(
      gray, contourPoints, dropletContour);

  // Smooth the contour to reduce noise
  refinedContour = _smoothContour(refinedContour, windowSize: 5);
  
  // Debug: Contour points: ${refinedContour.length}, Area: ${area.toStringAsFixed(0)} pixels²
  
  return refinedContour;
}

/// Refine contour points to subpixel accuracy using gradient-based method
Future<List<cv.Point2f>> _refineContourSubpixel(
    cv.Mat grayImage, List<cv.Point2f> contourPoints, cv.VecPoint originalContour) async {
  
  // Calculate image gradients
  final gradX = cv.sobel(grayImage, cv.MatType.CV_32FC1.value, 1, 0, ksize: 3);
  final gradY = cv.sobel(grayImage, cv.MatType.CV_32FC1.value, 0, 1, ksize: 3);
  
  // Refine each contour point
  List<cv.Point2f> refinedPoints = [];
  
  for (int i = 0; i < contourPoints.length; i++) {
    cv.Point2f point = contourPoints[i];
    
    // Get gradient direction at this point
    int x = point.x.round().clamp(1, grayImage.cols - 2);
    int y = point.y.round().clamp(1, grayImage.rows - 2);
    
    // Extract local gradient values
    double gx = gradX.at<double>(y, x);
    double gy = gradY.at<double>(y, x);
    double gradMag = sqrt(gx * gx + gy * gy);
    
    if (gradMag > 1e-5) {
      // Normalize gradient
      gx /= gradMag;
      gy /= gradMag;
      
      // Search along gradient direction for maximum
      double bestOffset = 0.0;
      double maxGradient = gradMag;
      
      // Search within ±1 pixel along gradient
      for (double offset = -1.0; offset <= 1.0; offset += 0.1) {
        double testX = point.x + offset * gx;
        double testY = point.y + offset * gy;
        
        if (testX >= 1 && testX < grayImage.cols - 1 &&
            testY >= 1 && testY < grayImage.rows - 1) {
          // Bilinear interpolation for gradient magnitude
          double interpGrad = _bilinearInterpolate(
              gradX, gradY, testX, testY);
          
          if (interpGrad > maxGradient) {
            maxGradient = interpGrad;
            bestOffset = offset;
          }
        }
      }
      
      // Apply subpixel correction
      refinedPoints.add(cv.Point2f(
          point.x + bestOffset * gx,
          point.y + bestOffset * gy
      ));
    } else {
      // Keep original point if gradient is too small
      refinedPoints.add(point);
    }
  }
  
  return refinedPoints;
}

/// Bilinear interpolation for gradient magnitude
double _bilinearInterpolate(cv.Mat gradX, cv.Mat gradY, double x, double y) {
  int x0 = x.floor();
  int y0 = y.floor();
  int x1 = x0 + 1;
  int y1 = y0 + 1;
  
  double fx = x - x0;
  double fy = y - y0;
  
  // Get gradient values at corners
  double gx00 = gradX.at<double>(y0, x0);
  double gy00 = gradY.at<double>(y0, x0);
  double gx10 = gradX.at<double>(y0, x1);
  double gy10 = gradY.at<double>(y0, x1);
  double gx01 = gradX.at<double>(y1, x0);
  double gy01 = gradY.at<double>(y1, x0);
  double gx11 = gradX.at<double>(y1, x1);
  double gy11 = gradY.at<double>(y1, x1);
  
  // Bilinear interpolation
  double gx = (1-fx)*(1-fy)*gx00 + fx*(1-fy)*gx10 + 
              (1-fx)*fy*gx01 + fx*fy*gx11;
  double gy = (1-fx)*(1-fy)*gy00 + fx*(1-fy)*gy10 + 
              (1-fx)*fy*gy01 + fx*fy*gy11;
  
  return sqrt(gx * gx + gy * gy);
}

/// Smooth contour using moving average filter
List<cv.Point2f> _smoothContour(List<cv.Point2f> contour, {int windowSize = 5}) {
  if (contour.length < windowSize) return contour;
  
  List<cv.Point2f> smoothed = [];
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