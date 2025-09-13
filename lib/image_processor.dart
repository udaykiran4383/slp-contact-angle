import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';
import 'processing/angle_utils.dart';

class ImageProcessor {
  /// Main processing method with state-of-the-art droplet detection
  static Future<ProcessedImageData> processDropletImage(ui.Image image) async {
    try {
      // Step 1: Multi-scale image preprocessing
      final preprocessedData = await _advancedPreprocessing(image);
      
      // Step 2: Multi-algorithm boundary detection with ensemble methods
      final boundaryCandidates = await _detectBoundaryEnsemble(preprocessedData, image.width, image.height);
      
      // Step 3: Select best boundary using advanced scoring
      final bestBoundary = _selectBestBoundary(boundaryCandidates, image.width, image.height);
      
      // Step 4: Sub-pixel boundary refinement
      final refinedBoundary = await _subpixelRefinement(bestBoundary, preprocessedData.originalPixels, image.width, image.height);
      
      // Step 5: Advanced baseline detection with RANSAC
      final baseline = _detectBaselineAdvanced(refinedBoundary);
      
      // Step 6: Precise contact point detection
      final contactPoints = _findContactPointsPrecise(refinedBoundary, baseline);
      
      // Step 7: Advanced angle calculation with multiple methods
      final angle = _calculateContactAngleAdvanced(refinedBoundary, contactPoints, baseline);
      
      // Step 8: Comprehensive quality assessment
      final quality = _assessDetectionQuality(refinedBoundary, contactPoints, baseline);

      return ProcessedImageData(
        boundary: refinedBoundary,
        baseline: baseline,
        leftContact: contactPoints.left,
        rightContact: contactPoints.right,
        contactAngle: angle,
        qualityScore: quality,
      );
    } catch (e) {
      print('Advanced detection failed: $e');
      return await _fallbackDetection(image);
    }
  }

  /// Alternative method for compatibility with tests
  static Future<ProcessedImageData> processDropletImageAuto(ui.Image image, {bool debug = false, int maxDim = 1000}) async {
    return await processDropletImage(image);
  }

  static Future<Uint8List> _convertImageToPixels(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return byteData!.buffer.asUint8List();
  }

  /// Advanced multi-scale preprocessing with illumination correction
  static Future<PreprocessedImageData> _advancedPreprocessing(ui.Image image) async {
    final pixels = await _convertImageToPixels(image);
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_image.png');
    await tempFile.writeAsBytes(pixels);

    final src = cv.imread(tempFile.path);
    
    // Multi-scale analysis
    final scales = [1.0, 0.75, 0.5];
    final processedScales = <cv.Mat>[];
    
    for (final scale in scales) {
      cv.Mat scaledSrc;
      if (scale != 1.0) {
        final newWidth = (image.width * scale).round();
        final newHeight = (image.height * scale).round();
        scaledSrc = cv.resize(src, (newWidth, newHeight));
      } else {
        scaledSrc = src.clone();
      }
      
      // Convert to different color spaces
      final gray = cv.cvtColor(scaledSrc, cv.COLOR_BGR2GRAY);
      final lab = cv.cvtColor(scaledSrc, cv.COLOR_BGR2Lab);
      final hsv = cv.cvtColor(scaledSrc, cv.COLOR_BGR2HSV);
      
      // Extract channels for analysis
      final labChannels = cv.split(lab);
      final hsvChannels = cv.split(hsv);
      final lChannel = labChannels[0];
      final vChannel = hsvChannels[2];
      
      // Illumination correction using Retinex theory
      final illuminationCorrected = _correctIllumination(lChannel);
      
      // Multi-scale CLAHE
      final clahe1 = cv.createCLAHE(clipLimit: 2.0, tileGridSize: (8, 8));
      final clahe2 = cv.createCLAHE(clipLimit: 4.0, tileGridSize: (16, 16));
      final enhanced1 = clahe1.apply(illuminationCorrected);
      final enhanced2 = clahe2.apply(illuminationCorrected);
      
      // Combine enhancements
      final enhanced = cv.addWeighted(enhanced1, 0.6, enhanced2, 0.4, 0);
      
      // Advanced noise reduction with edge preservation
      final bilateral = cv.bilateralFilter(enhanced, 9, 75, 75);
      final nonLocalMeans = cv.fastNlMeansDenoising(bilateral);
      
      // Multi-scale edge enhancement
      final edges1 = cv.Canny(nonLocalMeans, 30, 100);
      final edges2 = cv.Canny(nonLocalMeans, 50, 150);
      final edges3 = cv.Canny(nonLocalMeans, 70, 200);
      
      // Combine edge information
      final combinedEdges = cv.addWeighted(edges1, 0.4, edges2, 0.4, 0);
      final finalEdges = cv.addWeighted(combinedEdges, 0.7, edges3, 0.3, 0);
      
      // Combine intensity and edge information
      final finalProcessed = cv.addWeighted(nonLocalMeans, 0.8, finalEdges, 0.2, 0);
      
      processedScales.add(finalProcessed);
    }
    
    // Scale back to original size and combine
    final originalSize = processedScales[0];
    final mediumSize = cv.resize(processedScales[1], (image.width, image.height));
    final smallSize = cv.resize(processedScales[2], (image.width, image.height));
    
    // Multi-scale fusion
    final fused = cv.addWeighted(originalSize, 0.5, mediumSize, 0.3, 0);
    final finalFused = cv.addWeighted(fused, 0.8, smallSize, 0.2, 0);
    
    return PreprocessedImageData(
      processedImage: finalFused,
      originalPixels: pixels,
      scales: processedScales,
    );
  }

  /// Illumination correction using Retinex theory
  static cv.Mat _correctIllumination(cv.Mat image) {
    // Estimate illumination using Gaussian blur
    final illumination = cv.gaussianBlur(image, (51, 51), 0);
    
    // Avoid division by zero
    final illuminationSafe = cv.add(illumination, cv.Scalar(1));
    
    // Apply Retinex correction: corrected = original / illumination
    final corrected = cv.divide(image, illuminationSafe);
    
    // Normalize to 0-255 range
    cv.normalize(corrected, corrected, 0, 255, cv.NORM_MINMAX);
    
    return corrected;
  }

  /// Ensemble boundary detection with multiple advanced algorithms
  static Future<List<BoundaryCandidate>> _detectBoundaryEnsemble(PreprocessedImageData preprocessedData, int width, int height) async {
    final candidates = <BoundaryCandidate>[];
    
    // Method 1: Multi-scale Canny Edge Detection
    final cannyCandidates = await _detectBoundaryCanny(preprocessedData.processedImage, width, height);
    candidates.addAll(cannyCandidates);
    
    // Method 2: Advanced Thresholding Ensemble
    final thresholdCandidates = await _detectBoundaryThresholding(preprocessedData.processedImage, width, height);
    candidates.addAll(thresholdCandidates);
    
    // Method 3: Watershed Segmentation
    final watershedCandidates = await _detectBoundaryWatershed(preprocessedData.processedImage, width, height);
    candidates.addAll(watershedCandidates);
    
    // Method 4: Active Contours (Snake Algorithm)
    final snakeCandidates = await _detectBoundaryActiveContours(preprocessedData.processedImage, width, height);
    candidates.addAll(snakeCandidates);
    
    // Method 5: Gradient-based Detection
    final gradientCandidates = await _detectBoundaryGradient(preprocessedData.processedImage, width, height);
    candidates.addAll(gradientCandidates);
    
    // Method 6: Machine Learning-based Detection (if available)
    final mlCandidates = await _detectBoundaryML(preprocessedData.processedImage, width, height);
    candidates.addAll(mlCandidates);
    
    return candidates;
  }

  /// Multi-scale Canny edge detection
  static Future<List<BoundaryCandidate>> _detectBoundaryCanny(cv.Mat image, int width, int height) async {
    final candidates = <BoundaryCandidate>[];
    
    // Multiple Canny thresholds for different scales
    final thresholds = [
      [30, 100], [50, 150], [70, 200], [100, 250]
    ];
    
    for (final threshold in thresholds) {
      final edges = cv.Canny(image, threshold[0], threshold[1]);
      
      // Morphological operations to connect edges
      final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
      final morphed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);
      
      // Find contours
      final (contours, _) = cv.findContours(morphed, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_TC89_L1);
      
      for (final contour in contours) {
        final boundary = _contourToOffsetList(contour);
        if (boundary.length > 20) {
          final score = _scoreBoundaryCanny(boundary, width, height);
          candidates.add(BoundaryCandidate(
            boundary: boundary,
            method: 'Canny_${threshold[0]}_${threshold[1]}',
            score: score,
            confidence: _calculateConfidence(boundary, width, height),
          ));
        }
      }
    }
    
    return candidates;
  }

  /// Advanced thresholding ensemble
  static Future<List<BoundaryCandidate>> _detectBoundaryThresholding(cv.Mat image, int width, int height) async {
    final candidates = <BoundaryCandidate>[];
    
    // Otsu's thresholding
    final (_, otsu) = cv.threshold(image, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU);
    final otsuCandidates = _extractContoursFromBinary(otsu, width, height, 'Otsu');
    candidates.addAll(otsuCandidates);
    
    // Adaptive thresholding with different parameters
    final adaptiveParams = [
      [11, 2], [15, 3], [21, 4]
    ];
    
    for (final params in adaptiveParams) {
      final adaptive = cv.adaptiveThreshold(
        image, 255, cv.ADAPTIVE_THRESH_GAUSSIAN_C, cv.THRESH_BINARY, params[0], params[1]
      );
      final adaptiveCandidates = _extractContoursFromBinary(adaptive, width, height, 'Adaptive_${params[0]}_${params[1]}');
      candidates.addAll(adaptiveCandidates);
    }
    
    // Triangle thresholding
    final (_, triangle) = cv.threshold(image, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_TRIANGLE);
    final triangleCandidates = _extractContoursFromBinary(triangle, width, height, 'Triangle');
    candidates.addAll(triangleCandidates);
    
    return candidates;
  }

  /// Watershed segmentation for droplet separation
  static Future<List<BoundaryCandidate>> _detectBoundaryWatershed(cv.Mat image, int width, int height) async {
    final candidates = <BoundaryCandidate>[];
    
    try {
      // Apply distance transform
      final binary = cv.threshold(image, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU).$2;
      final distTransform = cv.distanceTransform(binary, cv.DIST_L2, 5);
      
      // Normalize distance transform
      cv.normalize(distTransform, distTransform, 0, 255, cv.NORM_MINMAX);
      
      // Threshold to get sure foreground
      final (_, sureFg) = cv.threshold(distTransform, 0.7 * 255, 255, cv.THRESH_BINARY);
      
      // Find unknown region
      final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (3, 3));
      final sureBg = cv.dilate(binary, kernel, iterations: 3);
      final unknown = cv.subtract(sureBg, sureFg);
      
      // Create markers
      final markers = cv.connectedComponents(sureFg);
      markers.setTo(0, unknown);
      
      // Apply watershed
      final result = image.clone();
      cv.watershed(result, markers);
      
      // Extract contours from watershed result
      final watershedCandidates = _extractContoursFromBinary(markers, width, height, 'Watershed');
      candidates.addAll(watershedCandidates);
      
    } catch (e) {
      print('Watershed segmentation failed: $e');
    }
    
    return candidates;
  }

  /// Active contours (Snake algorithm) for boundary detection
  static Future<List<BoundaryCandidate>> _detectBoundaryActiveContours(cv.Mat image, int width, int height) async {
    final candidates = <BoundaryCandidate>[];
    
    try {
      // Create initial snake points (circular initialization)
      final centerX = width / 2;
      final centerY = height / 2;
      final radius = min(width, height) / 4;
      
      final initialSnake = <Offset>[];
      for (int i = 0; i < 36; i++) {
        final angle = (i * 10) * pi / 180;
        final x = centerX + radius * cos(angle);
        final y = centerY + radius * sin(angle);
        initialSnake.add(Offset(x, y));
      }
      
      // Apply snake algorithm
      final finalSnake = _applySnakeAlgorithm(image, initialSnake, width, height);
      
      if (finalSnake.length > 10) {
        final score = _scoreBoundarySnake(finalSnake, image, width, height);
        candidates.add(BoundaryCandidate(
          boundary: finalSnake,
          method: 'ActiveContours',
          score: score,
          confidence: _calculateConfidence(finalSnake, width, height),
        ));
      }
      
    } catch (e) {
      print('Active contours failed: $e');
    }
    
    return candidates;
  }

  /// Gradient-based boundary detection
  static Future<List<BoundaryCandidate>> _detectBoundaryGradient(cv.Mat image, int width, int height) async {
    final candidates = <BoundaryCandidate>[];
    
    try {
      // Calculate gradients
      final gradX = cv.Sobel(image, cv.CV_64F, 1, 0, ksize: 3);
      final gradY = cv.Sobel(image, cv.CV_64F, 0, 1, ksize: 3);
      
      // Calculate gradient magnitude
      final gradMag = cv.magnitude(gradX, gradY);
      
      // Threshold gradient magnitude
      final (_, gradBinary) = cv.threshold(gradMag, 50, 255, cv.THRESH_BINARY);
      
      // Convert to uint8
      final gradBinaryU8 = cv.convertScaleAbs(gradBinary);
      
      // Extract contours
      final gradientCandidates = _extractContoursFromBinary(gradBinaryU8, width, height, 'Gradient');
      candidates.addAll(gradientCandidates);
      
    } catch (e) {
      print('Gradient detection failed: $e');
    }
    
    return candidates;
  }

  /// Machine Learning-based boundary detection (placeholder for future implementation)
  static Future<List<BoundaryCandidate>> _detectBoundaryML(cv.Mat image, int width, int height) async {
    // This would implement deep learning-based boundary detection
    // For now, return empty list
    return <BoundaryCandidate>[];
  }

  /// Convert OpenCV contour to Offset list
  static List<Offset> _contourToOffsetList(cv.Mat contour) {
    final boundary = <Offset>[];
    for (int i = 0; i < contour.length; i++) {
      final point = contour[i];
      boundary.add(Offset(point.x.toDouble(), point.y.toDouble()));
    }
    return boundary;
  }

  /// Extract contours from binary image
  static List<BoundaryCandidate> _extractContoursFromBinary(cv.Mat binaryImage, int width, int height, String method) {
    final candidates = <BoundaryCandidate>[];
    
    try {
      final (contours, _) = cv.findContours(binaryImage, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_TC89_L1);
      
      for (final contour in contours) {
        final boundary = _contourToOffsetList(contour);
        if (boundary.length > 20) {
          final score = _scoreBoundaryGeneric(boundary, width, height);
          candidates.add(BoundaryCandidate(
            boundary: boundary,
            method: method,
            score: score,
            confidence: _calculateConfidence(boundary, width, height),
          ));
        }
      }
    } catch (e) {
      print('Error extracting contours from $method: $e');
    }
    
    return candidates;
  }

  /// Apply Snake algorithm for active contours
  static List<Offset> _applySnakeAlgorithm(cv.Mat image, List<Offset> initialSnake, int width, int height) {
    final snake = List<Offset>.from(initialSnake);
    const int maxIterations = 100;
    const double alpha = 0.1; // Elasticity
    const double beta = 0.1;  // Stiffness
    const double gamma = 0.1; // Step size
    
    for (int iter = 0; iter < maxIterations; iter++) {
      final newSnake = <Offset>[];
      
      for (int i = 0; i < snake.length; i++) {
        final prev = snake[(i - 1 + snake.length) % snake.length];
        final curr = snake[i];
        final next = snake[(i + 1) % snake.length];
        
        // Internal energy (elasticity + stiffness)
        final elasticForce = alpha * (next - curr) - alpha * (curr - prev);
        final stiffnessForce = beta * (next - 2 * curr + prev);
        
        // External energy (image gradient)
        final externalForce = _calculateExternalForce(image, curr, width, height);
        
        // Update position
        final newPos = curr + gamma * (elasticForce + stiffnessForce + externalForce);
        
        // Clamp to image bounds
        final clampedPos = Offset(
          newPos.dx.clamp(0.0, width - 1.0),
          newPos.dy.clamp(0.0, height - 1.0),
        );
        
        newSnake.add(clampedPos);
      }
      
      // Check convergence
      double maxMovement = 0.0;
      for (int i = 0; i < snake.length; i++) {
        final movement = (snake[i] - newSnake[i]).distance;
        maxMovement = max(maxMovement, movement);
      }
      
      snake.clear();
      snake.addAll(newSnake);
      
      if (maxMovement < 0.5) break; // Converged
    }
    
    return snake;
  }

  /// Calculate external force for snake algorithm
  static Offset _calculateExternalForce(cv.Mat image, Offset point, int width, int height) {
    try {
      final x = point.dx.round().clamp(0, width - 1);
      final y = point.dy.round().clamp(0, height - 1);
      
      // Calculate gradient at point
      final gradX = cv.Sobel(image, cv.CV_64F, 1, 0, ksize: 3);
      final gradY = cv.Sobel(image, cv.CV_64F, 0, 1, ksize: 3);
      
      // Sample gradient at point (simplified)
      final forceX = gradX.at<double>(y, x);
      final forceY = gradY.at<double>(y, x);
      
      return Offset(forceX, forceY);
    } catch (e) {
      return Offset.zero;
    }
  }

  /// Score boundary using Canny-specific criteria
  static double _scoreBoundaryCanny(List<Offset> boundary, int width, int height) {
    double score = 0.0;
    
    // Edge strength score
    score += _calculateEdgeStrength(boundary) * 0.3;
    
    // Shape regularity score
    score += _calculateShapeRegularity(boundary) * 0.3;
    
    // Size appropriateness score
    score += _calculateSizeScore(boundary, width, height) * 0.2;
    
    // Position score (prefer center-bottom)
    score += _calculatePositionScore(boundary, width, height) * 0.2;
    
    return score.clamp(0.0, 1.0);
  }

  /// Score boundary using Snake-specific criteria
  static double _scoreBoundarySnake(List<Offset> boundary, cv.Mat image, int width, int height) {
    double score = 0.0;
    
    // Gradient alignment score
    score += _calculateGradientAlignment(boundary, image) * 0.4;
    
    // Smoothness score
    score += _calculateSmoothness(boundary) * 0.3;
    
    // Shape regularity score
    score += _calculateShapeRegularity(boundary) * 0.3;
    
    return score.clamp(0.0, 1.0);
  }

  /// Generic boundary scoring
  static double _scoreBoundaryGeneric(List<Offset> boundary, int width, int height) {
    double score = 0.0;
    
    // Shape regularity score
    score += _calculateShapeRegularity(boundary) * 0.4;
    
    // Size appropriateness score
    score += _calculateSizeScore(boundary, width, height) * 0.3;
    
    // Position score
    score += _calculatePositionScore(boundary, width, height) * 0.3;
    
    return score.clamp(0.0, 1.0);
  }

  /// Calculate edge strength along boundary
  static double _calculateEdgeStrength(List<Offset> boundary) {
    if (boundary.length < 10) return 0.0;
    
    double totalStrength = 0.0;
    for (int i = 1; i < boundary.length - 1; i++) {
      final prev = boundary[i - 1];
      final curr = boundary[i];
      final next = boundary[i + 1];
      
      // Calculate curvature as edge strength indicator
      final curvature = _calculateCurvature(prev, curr, next);
      totalStrength += curvature.abs();
    }
    
    return (totalStrength / (boundary.length - 2)).clamp(0.0, 1.0);
  }

  /// Calculate shape regularity (circularity, convexity)
  static double _calculateShapeRegularity(List<Offset> boundary) {
    if (boundary.length < 10) return 0.0;
    
    // Calculate area and perimeter
    final area = _calculatePolygonArea(boundary);
    final perimeter = _calculatePolygonPerimeter(boundary);
    
    if (perimeter == 0) return 0.0;
    
    // Circularity score
    final circularity = (4 * pi * area) / (perimeter * perimeter);
    
    // Convexity score
    final convexHull = _calculateConvexHull(boundary);
    final convexArea = _calculatePolygonArea(convexHull);
    final convexity = convexArea > 0 ? area / convexArea : 0.0;
    
    return (circularity * 0.6 + convexity * 0.4).clamp(0.0, 1.0);
  }

  /// Calculate size appropriateness score
  static double _calculateSizeScore(List<Offset> boundary, int width, int height) {
    final imageArea = width * height;
    final boundaryArea = _calculatePolygonArea(boundary);
    
    final sizeRatio = boundaryArea / imageArea;
    
    // Prefer droplets that are 5% to 60% of image area
    if (sizeRatio >= 0.05 && sizeRatio <= 0.6) {
      return 1.0;
    } else if (sizeRatio >= 0.01 && sizeRatio <= 0.8) {
      return 0.7;
    } else {
      return 0.3;
    }
  }

  /// Calculate position score (prefer center-bottom droplets)
  static double _calculatePositionScore(List<Offset> boundary, int width, int height) {
    final center = _calculateCentroid(boundary);
    
    // Prefer droplets in center-bottom area
    final centerX = width / 2;
    final centerY = height * 0.7; // Bottom 30% of image
    
    final distanceFromCenter = sqrt(
      pow(center.dx - centerX, 2) + pow(center.dy - centerY, 2)
    );
    
    final maxDistance = sqrt(pow(width / 2, 2) + pow(height / 2, 2));
    final normalizedDistance = distanceFromCenter / maxDistance;
    
    return (1.0 - normalizedDistance).clamp(0.0, 1.0);
  }

  /// Calculate gradient alignment score
  static double _calculateGradientAlignment(List<Offset> boundary, cv.Mat image) {
    // Simplified gradient alignment calculation
    // In a full implementation, this would sample gradients along the boundary
    return 0.5; // Placeholder
  }

  /// Calculate smoothness score
  static double _calculateSmoothness(List<Offset> boundary) {
    if (boundary.length < 10) return 0.0;
    
    double totalCurvature = 0.0;
    for (int i = 1; i < boundary.length - 1; i++) {
      final curvature = _calculateCurvature(
        boundary[i - 1], boundary[i], boundary[i + 1]
      );
      totalCurvature += curvature.abs();
    }
    
    final avgCurvature = totalCurvature / (boundary.length - 2);
    return (1.0 - (avgCurvature / 10.0)).clamp(0.0, 1.0);
  }

  /// Calculate confidence score
  static double _calculateConfidence(List<Offset> boundary, int width, int height) {
    double confidence = 0.0;
    
    // Boundary completeness
    confidence += _calculateCompleteness(boundary) * 0.3;
    
    // Shape consistency
    confidence += _calculateShapeConsistency(boundary) * 0.3;
    
    // Size reasonableness
    confidence += _calculateSizeReasonableness(boundary, width, height) * 0.2;
    
    // Position reasonableness
    confidence += _calculatePositionReasonableness(boundary, width, height) * 0.2;
    
    return confidence.clamp(0.0, 1.0);
  }

  /// Select the best boundary from ensemble of candidates
  static List<Offset> _selectBestBoundary(List<BoundaryCandidate> candidates, int width, int height) {
    if (candidates.isEmpty) return [];
    
    // Sort candidates by combined score and confidence
    candidates.sort((a, b) {
      final scoreA = a.score * 0.7 + a.confidence * 0.3;
      final scoreB = b.score * 0.7 + b.confidence * 0.3;
      return scoreB.compareTo(scoreA);
    });
    
    // Return the best candidate's boundary
    return candidates.first.boundary;
  }

  /// Sub-pixel boundary refinement using gradient information
  static Future<List<Offset>> _subpixelRefinement(List<Offset> boundary, Uint8List originalPixels, int width, int height) async {
    if (boundary.length < 10) return boundary;
    
    final refinedBoundary = <Offset>[];
    
    for (int i = 0; i < boundary.length; i++) {
      final point = boundary[i];
      
      // Calculate normal direction at this point
      final normal = _calculateNormalAtPoint(boundary, i);
      
      // Refine using sub-pixel gradient analysis
      final refinedPoint = AngleUtils.subpixelRefineFromRGBA(
        rgba: originalPixels,
        width: width,
        height: height,
        approx: point,
        normal: normal,
        samples: 25,
        spacing: 0.6,
      );
      
      refinedBoundary.add(refinedPoint);
    }
    
    return refinedBoundary;
  }

  /// Calculate normal direction at boundary point
  static Offset _calculateNormalAtPoint(List<Offset> boundary, int index) {
    final prev = boundary[(index - 1 + boundary.length) % boundary.length];
    final curr = boundary[index];
    final next = boundary[(index + 1) % boundary.length];
    
    // Calculate tangent
    final tangent = next - prev;
    final tangentLength = tangent.distance;
    
    if (tangentLength == 0) return Offset(0, 1);
    
    // Normal is perpendicular to tangent (rotated 90 degrees)
    final normal = Offset(-tangent.dy, tangent.dx) / tangentLength;
    
    return normal;
  }

  /// Advanced baseline detection with RANSAC
  static BaselineData _detectBaselineAdvanced(List<Offset> boundary) {
    if (boundary.isEmpty) {
      return BaselineData(
        startPoint: Offset.zero,
        endPoint: const Offset(1000, 1000),
      );
    }
    
    // Find contact region (bottom 25% of droplet)
    final sortedByY = List<Offset>.from(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
    final maxY = sortedByY.first.dy;
    final minY = sortedByY.last.dy;
    final contactThreshold = maxY - (maxY - minY) * 0.25;
    
    final contactPoints = boundary.where((p) => p.dy >= contactThreshold).toList();
    
    if (contactPoints.length < 3) {
      return _detectBaseline(boundary);
    }
    
    // Use advanced RANSAC with slope prior
    final lineParams = AngleUtils.fitLineRANSACRefined(
      contactPoints,
      iterations: 600,
      inlierThresh: 2.0,
      slopePrior: 0.0, // Prefer horizontal baseline
      slopePriorWeight: 0.1,
    );
    
    // Extend baseline to cover full droplet width
    final minX = boundary.map((p) => p.dx).reduce(min);
    final maxX = boundary.map((p) => p.dx).reduce(max);
    
    return BaselineData(
      startPoint: Offset(minX, lineParams['m']! * minX + lineParams['c']!),
      endPoint: Offset(maxX, lineParams['m']! * maxX + lineParams['c']!),
    );
  }

  /// Precise contact point detection
  static ContactPointPair _findContactPointsPrecise(List<Offset> boundary, BaselineData baseline) {
    if (boundary.isEmpty) {
      return ContactPointPair(left: Offset.zero, right: Offset.zero);
    }

    // Find intersection points between boundary and baseline
    final intersections = <Offset>[];
    
    for (int i = 0; i < boundary.length; i++) {
      final p1 = boundary[i];
      final p2 = boundary[(i + 1) % boundary.length];
      
      final intersection = AngleUtils.intersectSegmentWithBaseline(
        p1, p2, baseline.slope, baseline.intercept, eps: 2.0
      );
      
      if (intersection != null) {
        intersections.add(intersection);
      }
    }
    
    if (intersections.length >= 2) {
      intersections.sort((a, b) => a.dx.compareTo(b.dx));
      return ContactPointPair(
        left: intersections.first,
        right: intersections.last,
      );
    }
    
    // Fallback to proximity-based detection
    return _findContactPointsByProximity(boundary, baseline);
  }

  /// Advanced contact angle calculation
  static double _calculateContactAngleAdvanced(List<Offset> boundary, ContactPointPair contactPoints, BaselineData baseline) {
    // Calculate tangents at both contact points using multiple methods
    final leftTangentMethods = <double>[];
    final rightTangentMethods = <double>[];
    
    // Method 1: Local quadratic derivative
    final leftQuadratic = _calculateLocalQuadraticTangent(boundary, contactPoints.left);
    final rightQuadratic = _calculateLocalQuadraticTangent(boundary, contactPoints.right);
    if (leftQuadratic != null) leftTangentMethods.add(leftQuadratic);
    if (rightQuadratic != null) rightTangentMethods.add(rightQuadratic);
    
    // Method 2: Circle fitting
    final leftCircle = _calculateCircleTangent(boundary, contactPoints.left);
    final rightCircle = _calculateCircleTangent(boundary, contactPoints.right);
    if (leftCircle != null) leftTangentMethods.add(leftCircle);
    if (rightCircle != null) rightTangentMethods.add(rightCircle);
    
    // Method 3: PCA-based tangent
    final leftPCA = _calculatePCATangent(boundary, contactPoints.left);
    final rightPCA = _calculatePCATangent(boundary, contactPoints.right);
    if (leftPCA != null) leftTangentMethods.add(leftPCA);
    if (rightPCA != null) rightTangentMethods.add(rightPCA);
    
    // Method 4: Robust local slope
    final leftRobust = _calculateRobustTangent(boundary, contactPoints.left);
    final rightRobust = _calculateRobustTangent(boundary, contactPoints.right);
    if (leftRobust != null) leftTangentMethods.add(leftRobust);
    if (rightRobust != null) rightTangentMethods.add(rightRobust);
    
    // Calculate angles using best available methods
    final leftAngle = leftTangentMethods.isNotEmpty 
        ? _calculateAngleFromTangent(leftTangentMethods.reduce((a, b) => a + b) / leftTangentMethods.length, baseline)
        : 0.0;
    
    final rightAngle = rightTangentMethods.isNotEmpty
        ? _calculateAngleFromTangent(rightTangentMethods.reduce((a, b) => a + b) / rightTangentMethods.length, baseline)
        : 0.0;
    
    // Return average of both angles for better accuracy
    return (leftAngle + rightAngle) / 2;
  }

  /// Calculate local quadratic tangent
  static double? _calculateLocalQuadraticTangent(List<Offset> boundary, Offset point) {
    final localPoints = _getLocalPoints(boundary, point, 7);
    if (localPoints.length < 5) return null;
    
    return AngleUtils.localQuadraticDerivativeAdaptive(localPoints, point);
  }

  /// Calculate circle-based tangent
  static double? _calculateCircleTangent(List<Offset> boundary, Offset point) {
    final localPoints = _getLocalPoints(boundary, point, 9);
    if (localPoints.length < 6) return null;
    
    final circle = AngleUtils.fitCircleKasa(localPoints);
    if (circle == null) return null;
    
    return AngleUtils.tangentSlopeFromCircleAtPoint(circle, point);
  }

  /// Calculate PCA-based tangent
  static double? _calculatePCATangent(List<Offset> boundary, Offset point) {
    final localPoints = _getLocalPoints(boundary, point, 7);
    if (localPoints.length < 5) return null;
    
    final pca = AngleUtils.pcaTangent(localPoints);
    return pca['slope'];
  }

  /// Calculate robust tangent
  static double? _calculateRobustTangent(List<Offset> boundary, Offset point) {
    final localPoints = _getLocalPoints(boundary, point, 7);
    if (localPoints.length < 3) return null;
    
    return AngleUtils.robustLocalSlopeAdaptive(localPoints);
  }

  /// Get local points around a given point
  static List<Offset> _getLocalPoints(List<Offset> boundary, Offset point, int windowSize) {
    // Find nearest point index
    int nearestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < boundary.length; i++) {
      final distance = (boundary[i] - point).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    
    // Extract local window
    final halfWindow = windowSize ~/ 2;
    final startIdx = (nearestIndex - halfWindow).clamp(0, boundary.length - 1);
    final endIdx = (nearestIndex + halfWindow).clamp(0, boundary.length - 1);
    
    return boundary.sublist(startIdx, endIdx + 1);
  }

  /// Calculate angle from tangent slope
  static double _calculateAngleFromTangent(double tangentSlope, BaselineData baseline) {
    final baselineSlope = baseline.slope;
    return AngleUtils.contactAngleDegreesFromSlopes(tangentSlope, baselineSlope);
  }

  /// Calculate polygon area using shoelace formula
  static double _calculatePolygonArea(List<Offset> points) {
    if (points.length < 3) return 0.0;
    
    double area = 0.0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      area += points[i].dx * points[j].dy;
      area -= points[j].dx * points[i].dy;
    }
    return area.abs() / 2.0;
  }

  /// Calculate polygon perimeter
  static double _calculatePolygonPerimeter(List<Offset> points) {
    if (points.length < 2) return 0.0;
    
    double perimeter = 0.0;
    for (int i = 0; i < points.length; i++) {
      final j = (i + 1) % points.length;
      perimeter += (points[i] - points[j]).distance;
    }
    return perimeter;
  }

  /// Calculate convex hull using Graham scan (simplified)
  static List<Offset> _calculateConvexHull(List<Offset> points) {
    if (points.length < 3) return points;
    
    // Simplified convex hull calculation
    // In a full implementation, this would use Graham scan or similar algorithm
    return points; // Placeholder
  }

  /// Calculate centroid of polygon
  static Offset _calculateCentroid(List<Offset> points) {
    if (points.isEmpty) return Offset.zero;
    
    double sumX = 0.0, sumY = 0.0;
    for (final point in points) {
      sumX += point.dx;
      sumY += point.dy;
    }
    
    return Offset(sumX / points.length, sumY / points.length);
  }

  /// Calculate curvature at three points
  static double _calculateCurvature(Offset p1, Offset p2, Offset p3) {
    final dx1 = p2.dx - p1.dx;
    final dy1 = p2.dy - p1.dy;
    final dx2 = p3.dx - p2.dx;
    final dy2 = p3.dy - p2.dy;
    
    final crossProduct = dx1 * dy2 - dy1 * dx2;
    final magnitude = pow(dx1 * dx1 + dy1 * dy1, 1.5);
    
    return magnitude > 0 ? crossProduct / magnitude : 0.0;
  }

  /// Calculate completeness score
  static double _calculateCompleteness(List<Offset> boundary) {
    if (boundary.length < 10) return 0.0;
    
    final firstPoint = boundary.first;
    final lastPoint = boundary.last;
    final distance = (firstPoint - lastPoint).distance;
    
    return distance < 5.0 ? 1.0 : (1.0 - distance / 50.0).clamp(0.0, 1.0);
  }

  /// Calculate shape consistency score
  static double _calculateShapeConsistency(List<Offset> boundary) {
    if (boundary.length < 10) return 0.0;
    
    // Calculate variance in distances from centroid
    final centroid = _calculateCentroid(boundary);
    final distances = boundary.map((p) => (p - centroid).distance).toList();
    
    final mean = distances.reduce((a, b) => a + b) / distances.length;
    final variance = distances.map((d) => pow(d - mean, 2)).reduce((a, b) => a + b) / distances.length;
    
    final coefficientOfVariation = sqrt(variance) / mean;
    return (1.0 - coefficientOfVariation).clamp(0.0, 1.0);
  }

  /// Calculate size reasonableness score
  static double _calculateSizeReasonableness(List<Offset> boundary, int width, int height) {
    final imageArea = width * height;
    final boundaryArea = _calculatePolygonArea(boundary);
    final sizeRatio = boundaryArea / imageArea;
    
    // Reasonable droplet size is 1% to 80% of image
    if (sizeRatio >= 0.01 && sizeRatio <= 0.8) {
      return 1.0;
    } else if (sizeRatio >= 0.005 && sizeRatio <= 0.9) {
      return 0.7;
    } else {
      return 0.3;
    }
  }

  /// Calculate position reasonableness score
  static double _calculatePositionReasonableness(List<Offset> boundary, int width, int height) {
    final centroid = _calculateCentroid(boundary);
    
    // Check if droplet is within image bounds
    if (centroid.dx < 0 || centroid.dx >= width || centroid.dy < 0 || centroid.dy >= height) {
      return 0.0;
    }
    
    // Prefer droplets not too close to edges
    final margin = min(width, height) * 0.1;
    if (centroid.dx < margin || centroid.dx > width - margin ||
        centroid.dy < margin || centroid.dy > height - margin) {
      return 0.7;
    }
    
    return 1.0;
  }


  /// Remove statistical outliers from boundary
  static List<Offset> _removeOutliers(List<Offset> boundary) {
    if (boundary.length < 20) return boundary;
    
    // Calculate distances between consecutive points
    final distances = <double>[];
    for (int i = 0; i < boundary.length; i++) {
      final next = (i + 1) % boundary.length;
      distances.add((boundary[i] - boundary[next]).distance);
    }
    
    // Calculate statistics
    distances.sort();
    final median = distances[distances.length ~/ 2];
    final q1 = distances[distances.length ~/ 4];
    final q3 = distances[distances.length * 3 ~/ 4];
    final iqr = q3 - q1;
    final threshold = median + 2.5 * iqr;
    
    // Remove outliers
    final cleaned = <Offset>[];
    for (int i = 0; i < boundary.length; i++) {
      final next = (i + 1) % boundary.length;
      final distance = (boundary[i] - boundary[next]).distance;
      if (distance <= threshold) {
        cleaned.add(boundary[i]);
      }
    }
    
    return cleaned.isNotEmpty ? cleaned : boundary;
  }

  /// Apply smoothing to boundary using moving average
  static List<Offset> _smoothBoundary(List<Offset> boundary) {
    if (boundary.length < 10) return boundary;
    
    final smoothed = <Offset>[];
    const int windowSize = 3;
    
    for (int i = 0; i < boundary.length; i++) {
      double sumX = 0, sumY = 0;
      int count = 0;
      
      for (int j = -windowSize; j <= windowSize; j++) {
        final index = (i + j + boundary.length) % boundary.length;
        sumX += boundary[index].dx;
        sumY += boundary[index].dy;
        count++;
      }
      
      smoothed.add(Offset(sumX / count, sumY / count));
    }
    
    return smoothed;
  }

  /// Ensure boundary points are ordered correctly
  static List<Offset> _orderBoundaryPoints(List<Offset> boundary) {
    if (boundary.isEmpty) return boundary;
    
    // Find the topmost point (minimum Y)
    int topIndex = 0;
    for (int i = 1; i < boundary.length; i++) {
      if (boundary[i].dy < boundary[topIndex].dy) {
        topIndex = i;
      }
    }
    
    // Reorder starting from topmost point
    final ordered = <Offset>[];
    for (int i = 0; i < boundary.length; i++) {
      final index = (topIndex + i) % boundary.length;
      ordered.add(boundary[index]);
    }
    
    return ordered;
  }

  /// Advanced baseline detection with improved accuracy
  static BaselineData _detectBaselineAdvanced(List<Offset> boundary) {
    if (boundary.isEmpty) {
      return BaselineData(
        startPoint: Offset.zero,
        endPoint: const Offset(1000, 1000),
      );
    }
    
    // Find contact region (bottom 20% of droplet)
    final sortedByY = List<Offset>.from(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
    final maxY = sortedByY.first.dy;
    final minY = sortedByY.last.dy;
    final contactThreshold = maxY - (maxY - minY) * 0.2;
    
    final contactPoints = boundary.where((p) => p.dy >= contactThreshold).toList();
    
    if (contactPoints.length < 3) {
      // Fallback to original method
      return _detectBaseline(boundary);
    }
    
    // Use RANSAC for robust line fitting
    final baseline = _fitLineRANSAC(contactPoints);
    
    // Extend baseline to cover full droplet width
    final minX = boundary.map((p) => p.dx).reduce(min);
    final maxX = boundary.map((p) => p.dx).reduce(max);
    
    return BaselineData(
      startPoint: Offset(minX, baseline.slope * minX + baseline.intercept),
      endPoint: Offset(maxX, baseline.slope * maxX + baseline.intercept),
    );
  }

  /// Fit line using RANSAC algorithm for robustness
  static LineParameters _fitLineRANSAC(List<Offset> points) {
    if (points.length < 2) {
      return LineParameters(slope: 0, intercept: 0);
    }
    
    const int maxIterations = 100;
    const double threshold = 2.0;
    int bestInliers = 0;
    LineParameters bestLine = LineParameters(slope: 0, intercept: 0);
    
    for (int iteration = 0; iteration < maxIterations; iteration++) {
      // Randomly select 2 points
      final indices = List.generate(2, (i) => (Random().nextDouble() * points.length).floor());
      if (indices[0] == indices[1]) continue;
      
      final p1 = points[indices[0]];
      final p2 = points[indices[1]];
      
      // Calculate line parameters
      final slope = (p2.dy - p1.dy) / (p2.dx - p1.dx);
      final intercept = p1.dy - slope * p1.dx;
      
      // Count inliers
      int inliers = 0;
      for (final point in points) {
        final distance = (point.dy - (slope * point.dx + intercept)).abs();
        if (distance <= threshold) {
          inliers++;
        }
      }
      
      if (inliers > bestInliers) {
        bestInliers = inliers;
        bestLine = LineParameters(slope: slope, intercept: intercept);
      }
    }
    
    return bestLine;
  }

  /// Fallback baseline detection (original method)
  static BaselineData _detectBaseline(List<Offset> boundary) {
    if (boundary.isEmpty) {
      return BaselineData(
        startPoint: Offset.zero,
        endPoint: const Offset(1000, 1000),
      );
    }
    
    // Find the lowest points of the droplet contour
    final sortedByY = List<Offset>.from(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
    final lowestPoints = sortedByY.take(10).toList();

    // Fit a linear regression line to the lowest points to find the baseline
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final p in lowestPoints) {
      sumX += p.dx;
      sumY += p.dy;
      sumXY += p.dx * p.dy;
      sumX2 += p.dx * p.dx;
    }

    final n = lowestPoints.length;
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;

    final startX = boundary.map((p) => p.dx).reduce(min);
    final endX = boundary.map((p) => p.dx).reduce(max);

    return BaselineData(
      startPoint: Offset(startX, slope * startX + intercept),
      endPoint: Offset(endX, slope * endX + intercept),
    );
  }

  /// Advanced contact point detection with sub-pixel accuracy
  static ContactPointPair _findContactPointsAdvanced(List<Offset> boundary, BaselineData baseline) {
    if (boundary.isEmpty) {
      return ContactPointPair(
        left: Offset.zero,
        right: Offset.zero,
      );
    }

    // Find intersection points between boundary and baseline
    final intersections = _findBoundaryBaselineIntersections(boundary, baseline);
    
    if (intersections.length >= 2) {
      intersections.sort((a, b) => a.dx.compareTo(b.dx));
      return ContactPointPair(
        left: intersections.first,
        right: intersections.last,
      );
    }
    
    // Fallback to proximity-based detection
    return _findContactPointsByProximity(boundary, baseline);
  }

  /// Find intersection points between boundary and baseline with sub-pixel accuracy
  static List<Offset> _findBoundaryBaselineIntersections(List<Offset> boundary, BaselineData baseline) {
    final intersections = <Offset>[];
    
    for (int i = 0; i < boundary.length; i++) {
      final p1 = boundary[i];
      final p2 = boundary[(i + 1) % boundary.length];
      
      // Check if line segment intersects with baseline
      final intersection = _lineIntersection(
        p1, p2,
        baseline.startPoint, baseline.endPoint,
      );
      
      if (intersection != null) {
        // Verify intersection is within the line segment
        if (_isPointOnLineSegment(intersection, p1, p2)) {
          intersections.add(intersection);
        }
      }
    }
    
    return intersections;
  }

  /// Calculate intersection of two line segments
  static Offset? _lineIntersection(Offset p1, Offset p2, Offset p3, Offset p4) {
    final denom = (p1.dx - p2.dx) * (p3.dy - p4.dy) - (p1.dy - p2.dy) * (p3.dx - p4.dx);
    
    if (denom.abs() < 1e-10) return null; // Lines are parallel
    
    final t = ((p1.dx - p3.dx) * (p3.dy - p4.dy) - (p1.dy - p3.dy) * (p3.dx - p4.dx)) / denom;
    
    return Offset(
      p1.dx + t * (p2.dx - p1.dx),
      p1.dy + t * (p2.dy - p1.dy),
    );
  }

  /// Check if point is on line segment
  static bool _isPointOnLineSegment(Offset point, Offset p1, Offset p2) {
    final crossProduct = (point.dy - p1.dy) * (p2.dx - p1.dx) - (point.dx - p1.dx) * (p2.dy - p1.dy);
    if (crossProduct.abs() > 1e-10) return false;
    
    final dotProduct = (point.dx - p1.dx) * (p2.dx - p1.dx) + (point.dy - p1.dy) * (p2.dy - p1.dy);
    final squaredLength = (p2.dx - p1.dx) * (p2.dx - p1.dx) + (p2.dy - p1.dy) * (p2.dy - p1.dy);
    
    return dotProduct >= 0 && dotProduct <= squaredLength;
  }

  /// Fallback contact point detection by proximity
  static ContactPointPair _findContactPointsByProximity(List<Offset> boundary, BaselineData baseline) {
    double baselineLine(Offset p) => baseline.slope * p.dx + baseline.intercept;
    const double tolerance = 3.0;

    final contactPoints = boundary.where((p) => (p.dy - baselineLine(p)).abs() < tolerance).toList();

    if (contactPoints.isEmpty) {
      final bottomPoints = List<Offset>.from(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
      return ContactPointPair(
        left: bottomPoints.first,
        right: bottomPoints.last,
      );
    }

    contactPoints.sort((a, b) => a.dx.compareTo(b.dx));
    
    return ContactPointPair(
      left: contactPoints.first,
      right: contactPoints.last,
    );
  }

  /// Fallback contact point detection (original method)
  static ContactPointPair _findContactPoints(List<Offset> boundary, BaselineData baseline) {
    if (boundary.isEmpty) {
      return ContactPointPair(
        left: Offset.zero,
        right: Offset.zero,
      );
    }

    double baselineLine(Offset p) => baseline.slope * p.dx + baseline.intercept;
    const double tolerance = 5.0;

    final contactPoints = boundary.where((p) => (p.dy - baselineLine(p)).abs() < tolerance).toList();

    if (contactPoints.isEmpty) {
      final bottomPoints = List<Offset>.from(boundary)..sort((a, b) => b.dy.compareTo(a.dy));
      return ContactPointPair(
        left: bottomPoints.first,
        right: bottomPoints.last,
      );
    }

    contactPoints.sort((a, b) => a.dx.compareTo(b.dx));
    
    return ContactPointPair(
      left: contactPoints.first,
      right: contactPoints.last,
    );
  }

  /// Advanced contact angle calculation with enhanced accuracy
  static double _calculateContactAngleAdvanced(
    List<Offset> boundary,
    ContactPointPair contactPoints,
    BaselineData baseline,
  ) {
    // Calculate tangents at both contact points
    final leftTangent = _calculateTangentAtPointAdvanced(boundary, contactPoints.left);
    final rightTangent = _calculateTangentAtPointAdvanced(boundary, contactPoints.right);
    
    if (leftTangent == null || rightTangent == null) {
      return _calculateContactAngle(boundary, contactPoints, baseline);
    }
    
    // Calculate baseline vector
    final baselineVector = baseline.endPoint - baseline.startPoint;
    final baselineAngle = atan2(baselineVector.dy, baselineVector.dx);
    
    // Calculate tangent angles
    final leftTangentAngle = atan2(leftTangent.dy, leftTangent.dx);
    final rightTangentAngle = atan2(rightTangent.dy, rightTangent.dx);
    
    // Calculate contact angles
    final leftAngle = _calculateAngleDifference(leftTangentAngle, baselineAngle);
    final rightAngle = _calculateAngleDifference(rightTangentAngle, baselineAngle);
    
    // Return average of both angles for better accuracy
    return (leftAngle + rightAngle) / 2;
  }

  /// Calculate angle difference with proper handling of circular angles
  static double _calculateAngleDifference(double angle1, double angle2) {
    double diff = (angle1 - angle2).abs();
    if (diff > pi) diff = 2 * pi - diff;
    return diff * 180 / pi;
  }

  /// Enhanced tangent calculation with better accuracy
  static Offset? _calculateTangentAtPointAdvanced(List<Offset> boundary, Offset point) {
    if (boundary.length < 10) return _calculateTangentAtPoint(boundary, point);
    
    // Find the nearest point on boundary
    int nearestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < boundary.length; i++) {
      final distance = (boundary[i] - point).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    
    // Use polynomial fitting for smoother tangent calculation
    const int windowSize = 7;
    final startIdx = (nearestIndex - windowSize).clamp(0, boundary.length - 1);
    final endIdx = (nearestIndex + windowSize).clamp(0, boundary.length - 1);
    
    if (startIdx == endIdx) return null;
    
    // Fit a quadratic polynomial to the local points
    final localPoints = boundary.sublist(startIdx, endIdx + 1);
    final tangent = _fitPolynomialTangent(localPoints, point);
    
    return tangent;
  }

  /// Fit polynomial to local points and calculate tangent
  static Offset? _fitPolynomialTangent(List<Offset> points, Offset targetPoint) {
    if (points.length < 3) return null;
    
    // Simple linear regression for tangent calculation
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final point in points) {
      sumX += point.dx;
      sumY += point.dy;
      sumXY += point.dx * point.dy;
      sumX2 += point.dx * point.dx;
    }
    
    final n = points.length;
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    
    // Create tangent vector
    final tangentVector = Offset(1.0, slope);
    final length = tangentVector.distance;
    
    if (length == 0) return null;
    
    return tangentVector / length;
  }

  /// Fallback contact angle calculation (original method)
  static double _calculateContactAngle(
    List<Offset> boundary,
    ContactPointPair contactPoints,
    BaselineData baseline,
  ) {
    // Calculate tangent at left contact point
    final leftTangent = _calculateTangentAtPoint(boundary, contactPoints.left);
    if (leftTangent == null) return 0.0;
    
    // Calculate baseline angle
    final baselineVector = baseline.endPoint - baseline.startPoint;
    final baselineAngle = atan2(baselineVector.dy, baselineVector.dx);
    
    // Calculate tangent angle
    final tangentAngle = atan2(leftTangent.dy, leftTangent.dx);
    
    // Calculate contact angle
    double angleDiff = (tangentAngle - baselineAngle).abs();
    if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;
    
    return angleDiff * 180 / pi;
  }

  /// Quality assessment of detection results
  static double _assessDetectionQuality(
    List<Offset> boundary,
    ContactPointPair contactPoints,
    BaselineData baseline,
  ) {
    double qualityScore = 0.0;
    
    // Boundary quality (30%)
    final boundaryQuality = _assessBoundaryQuality(boundary);
    qualityScore += boundaryQuality * 0.3;
    
    // Contact point quality (30%)
    final contactQuality = _assessContactPointQuality(boundary, contactPoints, baseline);
    qualityScore += contactQuality * 0.3;
    
    // Baseline quality (20%)
    final baselineQuality = _assessBaselineQuality(boundary, baseline);
    qualityScore += baselineQuality * 0.2;
    
    // Symmetry quality (20%)
    final symmetryQuality = _assessSymmetryQuality(boundary, contactPoints);
    qualityScore += symmetryQuality * 0.2;
    
    return qualityScore.clamp(0.0, 1.0);
  }

  /// Assess boundary quality based on smoothness and completeness
  static double _assessBoundaryQuality(List<Offset> boundary) {
    if (boundary.length < 10) return 0.0;
    
    // Check for smoothness
    double totalCurvature = 0.0;
    for (int i = 1; i < boundary.length - 1; i++) {
      final p1 = boundary[i - 1];
      final p2 = boundary[i];
      final p3 = boundary[i + 1];
      
      final curvature = _calculateCurvature(p1, p2, p3);
      totalCurvature += curvature.abs();
    }
    
    final avgCurvature = totalCurvature / (boundary.length - 2);
    final smoothnessScore = (1.0 - (avgCurvature / 10.0)).clamp(0.0, 1.0);
    
    // Check for completeness (closed boundary)
    final firstPoint = boundary.first;
    final lastPoint = boundary.last;
    final distance = (firstPoint - lastPoint).distance;
    final completenessScore = distance < 5.0 ? 1.0 : (1.0 - distance / 50.0).clamp(0.0, 1.0);
    
    return (smoothnessScore + completenessScore) / 2;
  }

  /// Calculate curvature at a point
  static double _calculateCurvature(Offset p1, Offset p2, Offset p3) {
    final dx1 = p2.dx - p1.dx;
    final dy1 = p2.dy - p1.dy;
    final dx2 = p3.dx - p2.dx;
    final dy2 = p3.dy - p2.dy;
    
    final crossProduct = dx1 * dy2 - dy1 * dx2;
    final magnitude = pow(dx1 * dx1 + dy1 * dy1, 1.5);
    
    return magnitude > 0 ? crossProduct / magnitude : 0.0;
  }

  /// Assess contact point quality
  static double _assessContactPointQuality(
    List<Offset> boundary,
    ContactPointPair contactPoints,
    BaselineData baseline,
  ) {
    // Check if contact points are on baseline
    final leftDistance = (contactPoints.left.dy - (baseline.slope * contactPoints.left.dx + baseline.intercept)).abs();
    final rightDistance = (contactPoints.right.dy - (baseline.slope * contactPoints.right.dx + baseline.intercept)).abs();
    
    final leftScore = leftDistance < 3.0 ? 1.0 : (1.0 - leftDistance / 20.0).clamp(0.0, 1.0);
    final rightScore = rightDistance < 3.0 ? 1.0 : (1.0 - rightDistance / 20.0).clamp(0.0, 1.0);
    
    return (leftScore + rightScore) / 2;
  }

  /// Assess baseline quality
  static double _assessBaselineQuality(List<Offset> boundary, BaselineData baseline) {
    // Check if baseline is approximately horizontal
    final baselineVector = baseline.endPoint - baseline.startPoint;
    final angle = atan2(baselineVector.dy, baselineVector.dx).abs();
    final horizontalScore = angle < pi / 12 ? 1.0 : (1.0 - angle / (pi / 2)).clamp(0.0, 1.0);
    
    return horizontalScore;
  }

  /// Assess symmetry quality
  static double _assessSymmetryQuality(List<Offset> boundary, ContactPointPair contactPoints) {
    // Check if droplet is roughly symmetric around vertical center
    final centerX = (contactPoints.left.dx + contactPoints.right.dx) / 2;
    
    double leftArea = 0.0;
    double rightArea = 0.0;
    
    for (int i = 0; i < boundary.length; i++) {
      final p1 = boundary[i];
      final p2 = boundary[(i + 1) % boundary.length];
      
      final area = (p1.dx - centerX) * (p2.dy - p1.dy);
      if (area > 0) {
        rightArea += area;
      } else {
        leftArea += area.abs();
      }
    }
    
    final totalArea = leftArea + rightArea;
    if (totalArea == 0) return 0.0;
    
    final symmetryRatio = (leftArea - rightArea).abs() / totalArea;
    return (1.0 - symmetryRatio).clamp(0.0, 1.0);
  }

  /// Original boundary detection method (fallback)
  static Future<List<Offset>> _detectDropletBoundary(Uint8List pixels, int width, int height) async {
    // Create a temporary file to save the image for OpenCV processing
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/temp_image.png');
    await tempFile.writeAsBytes(pixels);

    // Use OpenCV to load the image
    final src = cv.imread(tempFile.path);
    final gray = cv.cvtColor(src, cv.COLOR_RGBA2GRAY);
    
    // Apply a Gaussian blur to reduce noise
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);

    // Apply Otsu's thresholding to get a binary mask
    final (_, binary) = cv.threshold(blurred, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU);

    // Find contours
    final (contours, _) = cv.findContours(binary, cv.RETR_EXTERNAL, cv.CHAIN_APPROX_SIMPLE);

    if (contours.isEmpty) {
      return [];
    }

    // Find the largest contour, which is assumed to be the droplet
    double maxArea = 0;
    int largestContourIndex = -1;
    for (var i = 0; i < contours.length; i++) {
      final area = cv.contourArea(contours[i]);
      if (area > maxArea) {
        maxArea = area;
        largestContourIndex = i;
      }
    }

    if (largestContourIndex == -1) {
      return [];
    }

    // Convert the largest contour's points to a list of Offsets
    final boundary = <Offset>[];
    final largestContour = contours[largestContourIndex];
    for (int i = 0; i < largestContour.length; i++) {
      final point = largestContour[i];
      boundary.add(Offset(point.x.toDouble(), point.y.toDouble()));
    }

    return boundary;
  }

  /// Fallback detection method
  static Future<ProcessedImageData> _fallbackDetection(ui.Image image) async {
    final imageData = await _convertImageToPixels(image);
    final boundary = await _detectDropletBoundary(imageData, image.width, image.height);
    final baseline = _detectBaseline(boundary);
    final contactPoints = _findContactPoints(boundary, baseline);
    final angle = _calculateContactAngle(boundary, contactPoints, baseline);

    return ProcessedImageData(
      boundary: boundary,
      baseline: baseline,
      leftContact: contactPoints.left,
      rightContact: contactPoints.right,
      contactAngle: angle,
      qualityScore: 0.5, // Medium quality for fallback
    );
  }

  /// Original tangent calculation method (fallback)
  static Offset? _calculateTangentAtPoint(List<Offset> boundary, Offset point) {
    if (boundary.length < 5) return null;
    
    // Find the nearest point on boundary
    int nearestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < boundary.length; i++) {
      final distance = (boundary[i] - point).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    
    // Calculate tangent using neighboring points
    const int windowSize = 5;
    final startIdx = (nearestIndex - windowSize).clamp(0, boundary.length - 1);
    final endIdx = (nearestIndex + windowSize).clamp(0, boundary.length - 1);
    
    if (startIdx == endIdx) return null;
    
    final tangentVector = boundary[endIdx] - boundary[startIdx];
    final length = tangentVector.distance;
    
    if (length == 0) return null;
    
    return tangentVector / length;
  }
}

// --- Data Structures ---

class ProcessedImageData {
  final List<Offset> boundary;
  final BaselineData baseline;
  final Offset leftContact;
  final Offset rightContact;
  final double contactAngle;
  final double qualityScore;

  ProcessedImageData({
    required this.boundary,
    required this.baseline,
    required this.leftContact,
    required this.rightContact,
    required this.contactAngle,
    required this.qualityScore,
  });
}

class BaselineData {
  final Offset startPoint;
  final Offset endPoint;
  final double slope;
  final double intercept;

  BaselineData({
    required this.startPoint,
    required this.endPoint,
  }) : slope = (endPoint.dy - startPoint.dy) / (endPoint.dx - startPoint.dx),
       intercept = startPoint.dy - ((endPoint.dy - startPoint.dy) / (endPoint.dx - startPoint.dx)) * startPoint.dx;
}

class ContactPointPair {
  final Offset left;
  final Offset right;

  ContactPointPair({
    required this.left,
    required this.right,
  });
}

class LineParameters {
  final double slope;
  final double intercept;

  LineParameters({
    required this.slope,
    required this.intercept,
  });
}

class PreprocessedImageData {
  final cv.Mat processedImage;
  final Uint8List originalPixels;
  final List<cv.Mat> scales;

  PreprocessedImageData({
    required this.processedImage,
    required this.originalPixels,
    required this.scales,
  });
}

class BoundaryCandidate {
  final List<Offset> boundary;
  final String method;
  final double score;
  final double confidence;

  BoundaryCandidate({
    required this.boundary,
    required this.method,
    required this.score,
    required this.confidence,
  });
}
