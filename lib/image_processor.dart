// lib/image_processor.dart
// Fully-automatic droplet detection + baseline + contact-angle pipeline.
// Uses AngleUtils for geometry & refinement.

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'processing/angle_utils.dart';

class ImageProcessor {
  /// Entry: process image fully automatically.
  /// Returns ProcessedImageData including left/right/avg angles and overlay info.
  static Future<ProcessedImageData> processDropletImageAuto(ui.Image image,
      {bool debug = false, int maxDim = 1200}) async {
    // optionally downscale for speed while preserving precision via subpixel fits
    final scale = _computeDownscale(image.width, image.height, maxDim);
    final working = await _imageToRGBA(image);
    final width = (image.width / scale).round();
    final height = (image.height / scale).round();
    // downscale bytes -> simple bilinear shrink
    final rgba = _resizeRGBA(working, image.width, image.height, width, height);

    // grayscale + CLAHE-like local contrast
    final gray = _rgbaToGray(rgba, width, height);
    final equal = _claheApprox(gray, width, height, tileSize: 64);

    // denoise: median -> gaussian
    final med = _medianBlur(equal, width, height, radius: 1);
    final gauss = _gaussianBlur(med, width, height);

    // edge detection: sobel magnitude + adaptive threshold
    final mag = _sobelMagnitude(gauss, width, height);
    final edges = _autoThreshold(mag, width, height);

    // morphological: close then open
    final morph = _morphology(edges, width, height, closeR: 2, openR: 1);

    // largest connected component -> droplet mask
    final mask = _largestComponent(morph, width, height);

    // contour extraction + smoothing
    final contour = _maskToContour(mask, width, height);
    final smooth = _smoothContour(contour, window: 4);

    // Smart fused baseline detection: evaluate several detectors and pick the best-scoring baseline
    final baselineResult = _detectBestBaseline(
      contour: smooth,
      mask: mask,
      width: width,
      height: height,
      gray: gauss, // use denoised downscaled grayscale for gradient-based detectors
    );
    
    double m = baselineResult['m']!;
    double c = baselineResult['c']!;
    final baselineCandidates = (baselineResult['pts'] as List<Offset>);
    final Offset? contactLeftHint = baselineResult['left'] as Offset?;
    final Offset? contactRightHint = baselineResult['right'] as Offset?;

    // Prepare placeholders for approximate contact points. We'll finalize them after we lock the baseline.
    Offset leftApprox, rightApprox;
    // Start with detector hints if available (some detectors provide rough left/right positions)
    if (contactLeftHint != null && contactRightHint != null) {
      leftApprox = contactLeftHint;
      rightApprox = contactRightHint;
    } else {
      // Robust fallback: choose the lowest contour point in each half of the droplet
      double bboxMinX = double.infinity, bboxMaxX = -double.infinity;
      for (final p in smooth) { if (p.dx < bboxMinX) bboxMinX = p.dx; if (p.dx > bboxMaxX) bboxMaxX = p.dx; }
      final midX0 = (bboxMinX + bboxMaxX) * 0.5;
      Offset? bestL; double bestLy = -1e9;
      Offset? bestR; double bestRy = -1e9;
      for (final p in smooth) {
        if (p.dx <= midX0) { if (p.dy > bestLy) { bestLy = p.dy; bestL = p; } }
        else { if (p.dy > bestRy) { bestRy = p.dy; bestR = p; } }
      }
      leftApprox = bestL ?? smooth.first;
      rightApprox = bestR ?? smooth.last;
    }

    // compute normal at approximate contact: use local derivative to get tangent, then normal
    final leftLocal = _collectLocalNeighbors(smooth, leftApprox, k: 9);
    final rightLocal = _collectLocalNeighbors(smooth, rightApprox, k: 9);
    final leftSlope = AngleUtils.localQuadraticDerivative(leftLocal, leftApprox.dx);
    final rightSlope = AngleUtils.localQuadraticDerivative(rightLocal, rightApprox.dx);

    // tangent vector (math y-up => flip sign). normal is perpendicular
    final leftTangent = Offset(1.0, -leftSlope);
    final leftNormal = Offset(-leftTangent.dy, leftTangent.dx);
    final leftNormalU = _normalizeSafe(leftNormal);
    final rightTangent = Offset(1.0, -rightSlope);
    final rightNormal = Offset(-rightTangent.dy, rightTangent.dx);
    final rightNormalU = _normalizeSafe(rightNormal);

    // subpixel refine in original image coordinates:
    // we downscaled earlier - map approx points back to original
    final sx = scale;
    final leftApproxOrig = Offset(leftApprox.dx * sx, leftApprox.dy * sx);
    final rightApproxOrig = Offset(rightApprox.dx * sx, rightApprox.dy * sx);
    // original rgba bytes
    final origRgba = working;
    final origW = image.width;
    final origH = image.height;
    // normals in orig pixel scale (same direction)
    final leftNormalOrig = leftNormalU;
    final rightNormalOrig = rightNormalU;

    final leftRefined = AngleUtils.subpixelRefineFromRGBA(
      rgba: origRgba,
      width: origW,
      height: origH,
      approx: leftApproxOrig,
      normal: leftNormalOrig,
      samples: 25,
      spacing: 0.6,
    );
    final rightRefined = AngleUtils.subpixelRefineFromRGBA(
      rgba: origRgba,
      width: origW,
      height: origH,
      approx: rightApproxOrig,
      normal: rightNormalOrig,
      samples: 25,
      spacing: 0.6,
    );

    // recompute local derivative on original-scale contour: we'll lift nearby contour points to orig scale
    // build orig-scale contour by scaling smooth
    final origContour = smooth.map((p) => Offset(p.dx * sx, p.dy * sx)).toList();
    final leftLocalOrig = _collectLocalNeighbors(origContour, leftRefined, k: 12);
    final rightLocalOrig = _collectLocalNeighbors(origContour, rightRefined, k: 12);
    final leftSlopeOrig = AngleUtils.localQuadraticDerivative(leftLocalOrig, leftRefined.dx);
    final rightSlopeOrig = AngleUtils.localQuadraticDerivative(rightLocalOrig, rightRefined.dx);

    final leftAngle = AngleUtils.contactAngleDegreesFromSlopes(leftSlopeOrig, m);
    final rightAngle = AngleUtils.contactAngleDegreesFromSlopes(rightSlopeOrig, m);
    final avgAngle = (leftAngle + rightAngle) / 2.0;
    // Best-angle: choose side with stronger local edge magnitude (SNR proxy)
    final leftSnr = _localEdgeStrength(origRgba, origW, origH, leftRefined, radius: 9);
    final rightSnr = _localEdgeStrength(origRgba, origW, origH, rightRefined, radius: 9);
    final bool leftBest = leftSnr >= rightSnr;
    final bestAngle = leftBest ? leftAngle : rightAngle;
    final bestSide = leftBest ? 'left' : 'right';

    // Compute contour bbox for later use
    double minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final p in smooth) { if (p.dx < minX) minX = p.dx; if (p.dx > maxX) maxX = p.dx; if (p.dy < minY) minY = p.dy; if (p.dy > maxY) maxY = p.dy; }

    // Find intersections of final baseline with contour
    final intersections = <Offset>[];
    for (int i = 0; i < smooth.length; i++) {
      final p1 = smooth[i];
      final p2 = smooth[(i + 1) % smooth.length];
      final ip = AngleUtils.intersectSegmentWithBaseline(p1, p2, m, c);
      if (ip != null) intersections.add(ip);
    }
    if (intersections.isNotEmpty) {
      intersections.sort((a, b) => a.dx.compareTo(b.dx));
      leftApprox = intersections.first;
      rightApprox = intersections.length > 1 ? intersections.last : intersections.first;
    } else {
      // No strict intersection: choose the left-most and right-most contour points
      // that lie near the baseline band. This better approximates true contact points.
      final bandMin2 = maxY - 10.0; // focus near droplet base
      final bandMax2 = maxY + 6.0;
      Offset? leftmost; Offset? rightmost;
      for (final p in smooth) {
        if (p.dy < bandMin2 || p.dy > bandMax2) continue;
        if (leftmost == null || p.dx < leftmost!.dx) leftmost = p;
        if (rightmost == null || p.dx > rightmost!.dx) rightmost = p;
      }
      if (leftmost != null && rightmost != null) {
        leftApprox = leftmost!;
        rightApprox = rightmost!;
      }
    }

    // Build baseline endpoints in original coordinates (use width of orig image)
    final cOrig = c * sx; // scale intercept to original pixel space
    final baselineStart = Offset(0, (m * 0 + cOrig));
    final baselineEnd = Offset(origW.toDouble(), (m * origW + cOrig));
    
    // Create enhanced boundary with dashed option
    final enhancedBoundary = _createEnhancedBoundary(origContour, baselineResult, sx.toDouble());

    // Fit a robust spherical (circular) arc to the droplet above baseline and attach to enhancedBoundary
    final spherical = _fitSphericalArcRobust(
      origContour,
      baselineStart, baselineEnd,
      leftRefined, rightRefined,
    );
    if (spherical.isNotEmpty) {
      enhancedBoundary['sphericalArc'] = spherical['arc'];
      enhancedBoundary['circle'] = spherical['circle'];
    }
    
    // Build polyline for baseline visualization
    List<Offset> baselinePolyline = [];
    final candidatePts = baselineCandidates;
    if ((baselineResult['method'] ?? '') == 'mask_floor' && candidatePts.isNotEmpty) {
      baselinePolyline = List<Offset>.from(candidatePts);
    } else {
      final step = max(3, (width * 0.01).round());
      for (int x = 0; x < width; x += step) {
        final y = (m * x + c).clamp(0.0, height - 1.0);
        baselinePolyline.add(Offset(x.toDouble(), y));
      }
    }
    final baselinePolylineOrig = baselinePolyline.map((p) => Offset(p.dx * sx, p.dy * sx)).toList();

    return ProcessedImageData(
      boundary: origContour,
      enhancedBoundary: enhancedBoundary,
      baseline: BaselineData(startPoint: baselineStart, endPoint: baselineEnd, m: m, c: c),
      leftContact: leftRefined,
      rightContact: rightRefined,
      leftAngle: leftAngle,
      rightAngle: rightAngle,
      avgAngle: avgAngle,
      bestAngle: bestAngle,
      bestSide: bestSide,
      debug: debug ? {
        'downscale': scale,
        'width': width,
        'height': height,
        'baseline_m': m,
         'baseline_c_downscaled': c,
         'baseline_c_orig': cOrig,
        // Debug overlays
         'baseline_points': baselineCandidates
            .map((p) => Offset(p.dx * scale.toDouble(), p.dy * scale.toDouble()))
            .toList(),
        'baseline_polyline': baselinePolylineOrig,
        'left_neighborhood': leftLocalOrig,
        'right_neighborhood': rightLocalOrig,
        'approx_contacts': [leftApproxOrig, rightApproxOrig],
        // Additional debug info
        'baseline_method': baselineResult.containsKey('method') ? baselineResult['method'] : 'unknown',
        'baseline_point_count': baselineCandidates.length,
        'mask_dimensions': {'w': width, 'h': height},
        'contour_length': smooth.length,
        'processing_scale': scale,
      } : null,
    );
  }

  // Intelligent automatic enhanced boundary creation with adaptive parameters
  static Map<String, dynamic> _createEnhancedBoundary(List<Offset> contour, Map<String, dynamic> baselineResult, double scale) {
    if (contour.isEmpty) return {'contour': contour, 'background': <Offset>[]};
    
    // Automatically analyze contour characteristics
    final contourAnalysis = _analyzeContour(contour);
    
    // Find intelligent bounding box with automatic padding
    double minX = double.infinity, maxX = -double.infinity, minY = double.infinity, maxY = -double.infinity;
    for (final p in contour) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    
    // Automatically calculate optimal background dimensions based on contour analysis
    final contourWidth = maxX - minX;
    final contourHeight = maxY - minY;
    final aspectRatio = contourWidth / contourHeight;
    
    // Adaptive background sizing based on contour characteristics
    final horizontalPadding = _calculateOptimalPadding(contourWidth, scale);
    final verticalPadding = _calculateOptimalPadding(contourHeight, scale);
    final backgroundHeightRatio = _calculateOptimalBackgroundHeight(aspectRatio, contourHeight);
    
    // Create intelligent background rectangle with automatic positioning
    final backgroundRect = [
      Offset(minX - horizontalPadding, maxY + (contourHeight * backgroundHeightRatio)), // top-left
      Offset(maxX + horizontalPadding, maxY + (contourHeight * backgroundHeightRatio)), // top-right
      Offset(maxX + horizontalPadding, maxY + verticalPadding),                        // bottom-right
      Offset(minX - horizontalPadding, maxY + verticalPadding),                        // bottom-left
    ];
    
    // Automatically determine optimal drawing parameters
    final drawingParams = _calculateOptimalDrawingParams(contourAnalysis, scale);
    
    return {
      'contour': contour,
      'background': backgroundRect,
      'boundingBox': {'minX': minX, 'maxX': maxX, 'minY': minY, 'maxY': maxY},
      'drawingParams': drawingParams,
      'contourAnalysis': contourAnalysis,
    };
  }

  // Robust spherical fit: trimmed Pratt/Kåsa with RANSAC to avoid outliers.
  // Fits only contour points above the baseline and between left/right contacts.
  static Map<String, dynamic> _fitSphericalArcRobust(
    List<Offset> contour,
    Offset baselineStart, Offset baselineEnd,
    Offset leftContact, Offset rightContact,
  ) {
    if (contour.length < 30) return {};

    final dxBL = (baselineEnd.dx - baselineStart.dx);
    final m = dxBL.abs() < 1e-12 ? 0.0 : (baselineEnd.dy - baselineStart.dy) / dxBL;
    final c = baselineStart.dy - m * baselineStart.dx;

    // Keep points inside horizontal span of contacts, and above baseline by a margin
    final minX = min(leftContact.dx, rightContact.dx);
    final maxX = max(leftContact.dx, rightContact.dx);
    final candidates = <Offset>[
      for (final p in contour)
        if (p.dx >= minX && p.dx <= maxX && p.dy <= (m * p.dx + c) - 1.5) p
    ];
    if (candidates.length < 12) return {};

    // RANSAC over minimal subsets to get a robust circle proposal
    final rnd = Random(1337);
    Map<String, double>? bestCircle;
    double bestInlier = -1;
    for (int it = 0; it < 200; it++) {
      final subset = <Offset>[];
      for (int k = 0; k < 12; k++) subset.add(candidates[rnd.nextInt(candidates.length)]);
      final circle = AngleUtils.fitCirclePratt(subset) ?? AngleUtils.fitCircleKasa(subset);
      if (circle == null) continue;
      final xc = circle['xc']!, yc = circle['yc']!, r = circle['r']!;
      int inliers = 0;
      for (final p in candidates) {
        final d = sqrt((p.dx - xc) * (p.dx - xc) + (p.dy - yc) * (p.dy - yc));
        if ((d - r).abs() <= 2.0) inliers++;
      }
      if (inliers > bestInlier) { bestInlier = inliers.toDouble(); bestCircle = circle; }
    }
    if (bestCircle == null) return {};

    // Refit on top 70% closest to circle
    final xc = bestCircle['xc']!, yc = bestCircle['yc']!, r = bestCircle['r']!;
    final distances = <MapEntry<double, Offset>>[];
    for (final p in candidates) {
      final d = (sqrt((p.dx - xc) * (p.dx - xc) + (p.dy - yc) * (p.dy - yc)) - r).abs();
      distances.add(MapEntry(d, p));
    }
    distances.sort((a, b) => a.key.compareTo(b.key));
    final keep = max(12, (distances.length * 0.7).floor());
    final refinedSet = distances.take(keep).map((e) => e.value).toList();
    final circleRef = AngleUtils.fitCirclePratt(refinedSet) ?? AngleUtils.fitCircleKasa(refinedSet);
    if (circleRef == null) return {};

    final xc2 = circleRef['xc']!, yc2 = circleRef['yc']!, r2 = circleRef['r']!;
    // Sample arc between contacts across upper side
    double theta(Offset p) => atan2(p.dy - yc2, p.dx - xc2);
    double tL = theta(leftContact), tR = theta(rightContact);
    // Normalize
    double norm(double a) { while (a <= -pi) a += 2 * pi; while (a > pi) a -= 2 * pi; return a; }
    tL = norm(tL); tR = norm(tR);
    double d = tR - tL; if (d < -pi) d += 2 * pi; if (d > pi) d -= 2 * pi;
    List<Offset> sample(double a0, double a1) {
      final pts = <Offset>[]; const steps = 140;
      for (int i = 0; i <= steps; i++) {
        final t = a0 + (a1 - a0) * (i / steps);
        pts.add(Offset(xc2 + r2 * cos(t), yc2 + r2 * sin(t)));
      }
      return pts;
    }
    final arc1 = sample(tL, tL + d);
    final arc2 = sample(tL, tL + d + (d >= 0 ? -2 * pi : 2 * pi));
    double baselineYAt(double x) => m * x + c;
    double meanAbove(List<Offset> pts) { double s = 0; for (final p in pts) s += (baselineYAt(p.dx) - p.dy); return s / max(1, pts.length); }
    final chosen = meanAbove(arc1) >= meanAbove(arc2) ? arc1 : arc2;
    return {'arc': chosen, 'circle': {'xc': xc2, 'yc': yc2, 'r': r2}};
  }

  // Fused baseline selector: evaluate multiple detectors and pick the most plausible baseline
  static Map<String, dynamic> _detectBestBaseline({
    required List<Offset> contour,
    required List<int> mask,
    required int width,
    required int height,
    required List<int> gray,
  }) {
    final candidates = <Map<String, dynamic>>[];
    void add(Map<String, dynamic> m, String method) { if ((m['pts'] as List).isNotEmpty) { m['method'] = method; candidates.add(m); } }
    add(_detectBaselineFromContactPoints(contour, mask, width, height), 'contact_points');
    add(_detectBaselineFromMaskFloorEnhanced(mask, width, height), 'mask_floor');
    add(_detectBaselineFromContourEnhanced(contour, width, height), 'contour_bottom');
    final gb = _detectBaselineNearDropletBandEnhanced(gray: gray, w: width, h: height, mask: mask, contour: contour);
    if (gb != null) { gb['method'] = 'gradient_band'; candidates.add(gb); }
    final st = _detectBaselineStableEnhanced(gray: gray, w: width, h: height, mask: mask);
    if ((st['pts'] as List).isNotEmpty) { st['method'] = 'global_stable'; candidates.add(st); }

    // Score each candidate: (a) horizontalness, (b) proximity to droplet bottom, (c) support points count
    double maxY = -1e9; double minX = 1e9, maxX = -1e9;
    for (final p in contour) { if (p.dy > maxY) maxY = p.dy; if (p.dx < minX) minX = p.dx; if (p.dx > maxX) maxX = p.dx; }
    double score(Map<String, dynamic> b) {
      final m = (b['m'] as double); final c = (b['c'] as double); final pts = (b['pts'] as List).length.toDouble();
      final midX = (minX + maxX) * 0.5; final yMid = m * midX + c;
      final prox = 1.0 / (1.0 + (yMid - (maxY - 1.0)).abs()); // encourage near bottom
      final horiz = 1.0 / (1.0 + m.abs());
      final support = log(1.0 + pts);
      // Prefer methods that provided left/right hints (likely true contacts)
      final hasHints = (b['left'] != null && b['right'] != null) ? 1.0 : 0.0;
      return 2.0 * horiz + 2.5 * prox + 1.0 * support + 0.8 * hasHints;
    }
    if (candidates.isEmpty) {
      final fb = _detectBaselineSimpleFallback(contour, width, height);
      fb['method'] = 'simple_fallback';
      return fb;
    }
    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.first;
  }
  
  // Smart baseline detection focused on actual droplet contact points with surface
  static Map<String, dynamic> _detectBaselineFromContactPoints(List<Offset> contour, List<int> mask, int width, int height) {
    if (contour.isEmpty) return {'m': 0.0, 'c': height * 0.95, 'pts': <Offset>[]};
    
    // Find the bottom-most points of the droplet contour
    final sortedByY = List<Offset>.from(contour)..sort((a, b) => b.dy.compareTo(a.dy));
    final bottomPoints = sortedByY.take(min(20, sortedByY.length)).toList();
    
    // Group bottom points by x-coordinate to find left and right contact regions
    bottomPoints.sort((a, b) => a.dx.compareTo(b.dx));
    
    // Find left and right contact regions (clusters of bottom points)
    final leftContactRegion = <Offset>[];
    final rightContactRegion = <Offset>[];
    
    final leftThreshold = bottomPoints.first.dx + (bottomPoints.last.dx - bottomPoints.first.dx) * 0.3;
    final rightThreshold = bottomPoints.first.dx + (bottomPoints.last.dx - bottomPoints.first.dx) * 0.7;
    
    for (final point in bottomPoints) {
      if (point.dx <= leftThreshold) {
        leftContactRegion.add(point);
      } else if (point.dx >= rightThreshold) {
        rightContactRegion.add(point);
      }
    }
    
    // If we have enough points in both regions, use them for baseline
    if (leftContactRegion.length >= 3 && rightContactRegion.length >= 3) {
      final allContactPoints = [...leftContactRegion, ...rightContactRegion];
      
      // Fit a horizontal line through these contact points
      final fit = AngleUtils.fitLineRANSACRefined(
        allContactPoints,
        iterations: 500,
        inlierThresh: 0.5, // Very tight threshold for precision
        slopePrior: 0.0,   // Force horizontal line
        slopePriorWeight: 50.0, // Very strong horizontal prior
      );
      
      return {
        'm': fit['m']!,
        'c': fit['c']!,
        'pts': allContactPoints,
        'left': leftContactRegion,
        'right': rightContactRegion,
      };
    }
    
    // Fallback: use all bottom points with horizontal constraint
    final fit = AngleUtils.fitLineRANSACRefined(
      bottomPoints,
      iterations: 300,
      inlierThresh: 1.0,
      slopePrior: 0.0,
      slopePriorWeight: 25.0,
    );
    
    return {
      'm': fit['m']!,
      'c': fit['c']!,
      'pts': bottomPoints,
      'left': bottomPoints.take(bottomPoints.length ~/ 2).toList(),
      'right': bottomPoints.skip(bottomPoints.length ~/ 2).toList(),
    };
  }
  
  // Simple fallback baseline detection
  static Map<String, dynamic> _detectBaselineSimpleFallback(List<Offset> contour, int width, int height) {
    if (contour.isEmpty) return {'m': 0.0, 'c': height * 0.95, 'pts': <Offset>[]};
    
    // Find the bottom-most Y coordinate of the droplet
    double maxY = -double.infinity;
    for (final p in contour) {
      if (p.dy > maxY) maxY = p.dy;
    }
    
    // Create a perfectly horizontal line at the droplet bottom
    final baselineY = maxY + 2.0; // Slightly below the droplet
    
    // Create points along the width for visualization
    final points = <Offset>[];
    for (int x = 0; x < width; x += 5) {
      points.add(Offset(x.toDouble(), baselineY));
    }
    
    return {
      'm': 0.0, // Perfectly horizontal
      'c': baselineY,
      'pts': points,
      'left': [Offset(0.0, baselineY)],
      'right': [Offset(width.toDouble(), baselineY)],
    };
  }
  
  // Automatically analyze contour characteristics for optimal drawing
  static Map<String, dynamic> _analyzeContour(List<Offset> contour) {
    if (contour.length < 3) return {'complexity': 'simple', 'smoothness': 1.0, 'density': 1.0};
    
    // Calculate contour complexity (number of significant direction changes)
    int directionChanges = 0;
    double totalLength = 0.0;
    List<double> segmentLengths = [];
    
    for (int i = 0; i < contour.length; i++) {
      final current = contour[i];
      final next = contour[(i + 1) % contour.length];
      final segmentLength = (next - current).distance;
      totalLength += segmentLength;
      segmentLengths.add(segmentLength);
      
      if (i > 0) {
        final prev = contour[i - 1];
        final v1 = current - prev;
        final v2 = next - current;
        final angle = (atan2(v2.dy, v2.dx) - atan2(v1.dy, v1.dx)).abs();
        if (angle > 0.3) directionChanges++; // Significant direction change
      }
    }
    
    // Calculate smoothness and density metrics
    final avgSegmentLength = totalLength / contour.length;
    final segmentVariance = segmentLengths.map((l) => pow(l - avgSegmentLength, 2)).reduce((a, b) => a + b) / segmentLengths.length;
    final smoothness = 1.0 / (1.0 + sqrt(segmentVariance) / avgSegmentLength);
    final density = contour.length / totalLength;
    
    // Determine complexity level
    String complexity;
    if (directionChanges < contour.length * 0.1) complexity = 'simple';
    else if (directionChanges < contour.length * 0.25) complexity = 'moderate';
    else complexity = 'complex';
    
    return {
      'complexity': complexity,
      'smoothness': smoothness,
      'density': density,
      'directionChanges': directionChanges,
      'totalLength': totalLength,
      'segmentCount': contour.length,
    };
  }
  
  // Automatically calculate optimal padding based on contour size and scale
  static double _calculateOptimalPadding(double dimension, double scale) {
    final basePadding = max(5.0, dimension * 0.02); // Minimum 5px or 2% of dimension
    return basePadding * (1.0 + (scale - 1.0) * 0.5); // Scale-aware padding
  }
  
  // Automatically calculate optimal background height based on aspect ratio
  static double _calculateOptimalBackgroundHeight(double aspectRatio, double contourHeight) {
    if (aspectRatio > 2.0) return 0.3;      // Wide contours: smaller background
    if (aspectRatio > 1.5) return 0.35;     // Medium-wide contours: medium background
    if (aspectRatio > 1.0) return 0.4;      // Square-ish contours: standard background
    return 0.5;                              // Tall contours: larger background
  }
  
  // Automatically calculate optimal drawing parameters
  static Map<String, dynamic> _calculateOptimalDrawingParams(Map<String, dynamic> contourAnalysis, double scale) {
    final complexity = contourAnalysis['complexity'] as String;
    final smoothness = contourAnalysis['smoothness'] as double;
    
    // Adaptive dash parameters based on contour characteristics
    double baseDashLength, baseGapLength;
    switch (complexity) {
      case 'simple':
        baseDashLength = 8.0;
        baseGapLength = 4.0;
        break;
      case 'moderate':
        baseDashLength = 6.0;
        baseGapLength = 3.0;
        break;
      case 'complex':
        baseDashLength = 4.0;
        baseGapLength = 2.0;
        break;
      default:
        baseDashLength = 6.0;
        baseGapLength = 3.0;
    }
    
    // Adjust for smoothness (smoother contours get longer dashes)
    final smoothnessFactor = 0.5 + smoothness * 0.5;
    baseDashLength *= smoothnessFactor;
    baseGapLength *= smoothnessFactor;
    
    // Scale-aware adjustments
    final scaleFactor = 1.0 + (scale - 1.0) * 0.3;
    baseDashLength *= scaleFactor;
    baseGapLength *= scaleFactor;
    
    return {
      'dashLength': baseDashLength,
      'gapLength': baseGapLength,
      'strokeWidth': max(1.0, 2.0 * scaleFactor),
      'complexity': complexity,
      'smoothness': smoothness,
    };
  }

  // ------------------- low-level helpers -------------------

  static int _computeDownscale(int w, int h, int maxDim) {
    final maxSide = max(w, h);
    if (maxSide <= maxDim) return 1;
    return (maxSide / maxDim).ceil();
  }

  static Future<Uint8List> _imageToRGBA(ui.Image img) async {
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bd!.buffer.asUint8List();
  }

  static Uint8List _resizeRGBA(Uint8List src, int sw, int sh, int dw, int dh) {
    // simple bilinear downscale for speed
    final out = Uint8List(dw * dh * 4);
    for (int y = 0; y < dh; y++) {
      for (int x = 0; x < dw; x++) {
        final fx = x * (sw - 1) / (dw - 1);
        final fy = y * (sh - 1) / (dh - 1);
        final x0 = fx.floor(), y0 = fy.floor();
        final x1 = min(x0 + 1, sw - 1), y1 = min(y0 + 1, sh - 1);
        final dx = fx - x0, dy = fy - y0;
        for (int c = 0; c < 4; c++) {
          final v00 = src[(y0 * sw + x0) * 4 + c].toDouble();
          final v10 = src[(y0 * sw + x1) * 4 + c].toDouble();
          final v01 = src[(y1 * sw + x0) * 4 + c].toDouble();
          final v11 = src[(y1 * sw + x1) * 4 + c].toDouble();
          final v = (1 - dx) * (1 - dy) * v00 + dx * (1 - dy) * v10 + (1 - dx) * dy * v01 + dx * dy * v11;
          out[(y * dw + x) * 4 + c] = v.round().clamp(0, 255);
        }
      }
    }
    return out;
  }

  static List<int> _rgbaToGray(Uint8List rgba, int w, int h) {
    final out = List<int>.filled(w * h, 0);
    for (int i = 0; i < w * h; i++) {
      final idx = i * 4;
      final r = rgba[idx], g = rgba[idx + 1], b = rgba[idx + 2];
      out[i] = (0.299 * r + 0.587 * g + 0.114 * b).round();
    }
    return out;
  }

  static List<int> _claheApprox(List<int> gray, int w, int h, {int tileSize = 64}) {
    // approximate CLAHE: local histogram stretch per tile, then blend
    final out = List<int>.filled(w * h, 0);
    for (int ty = 0; ty < h; ty += tileSize) {
      for (int tx = 0; tx < w; tx += tileSize) {
        final bw = min(tileSize, w - tx);
        final bh = min(tileSize, h - ty);
        final list = <int>[];
        for (int yy = 0; yy < bh; yy++) {
          for (int xx = 0; xx < bw; xx++) {
            list.add(gray[(ty + yy) * w + (tx + xx)]);
          }
        }
        list.sort();
        final low = list[(list.length * 0.02).floor()];
        final high = list[(list.length * 0.98).floor()];
        final denom = (high - low).abs() > 0 ? (high - low) : 1;
        for (int yy = 0; yy < bh; yy++) {
          for (int xx = 0; xx < bw; xx++) {
            final v = ((gray[(ty + yy) * w + (tx + xx)] - low) * 255) ~/ denom;
            out[(ty + yy) * w + (tx + xx)] = v.clamp(0, 255);
          }
        }
      }
    }
    return out;
  }

  static List<int> _medianBlur(List<int> img, int w, int h, {int radius = 1}) {
    final out = List<int>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final vals = <int>[];
        for (int dy = -radius; dy <= radius; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            vals.add(img[ny * w + nx]);
          }
        }
        vals.sort();
        out[y * w + x] = vals[vals.length ~/ 2];
      }
    }
    return out;
  }

  static List<int> _gaussianBlur(List<int> img, int w, int h) {
    const kernel = [1, 2, 1, 2, 4, 2, 1, 2, 1];
    final sumK = 16;
    final out = List<int>.filled(w * h, 0);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        int s = 0;
        for (int ky = -1; ky <= 1; ky++) {
          for (int kx = -1; kx <= 1; kx++) {
            s += img[(y + ky) * w + (x + kx)] * kernel[(ky + 1) * 3 + (kx + 1)];
          }
        }
        out[y * w + x] = (s ~/ sumK).clamp(0, 255);
      }
    }
    return out;
  }

  static List<int> _sobelMagnitude(List<int> img, int w, int h) {
    final out = List<int>.filled(w * h, 0);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final gx = -img[(y - 1) * w + (x - 1)] +
            img[(y - 1) * w + (x + 1)] +
            -2 * img[y * w + (x - 1)] +
            2 * img[y * w + (x + 1)] +
            -img[(y + 1) * w + (x - 1)] +
            img[(y + 1) * w + (x + 1)];
        final gy = -img[(y - 1) * w + (x - 1)] -
            2 * img[(y - 1) * w + x] -
            img[(y - 1) * w + (x + 1)] +
            img[(y + 1) * w + (x - 1)] +
            2 * img[(y + 1) * w + x] +
            img[(y + 1) * w + (x + 1)];
        out[y * w + x] = sqrt(gx * gx + gy * gy).round().clamp(0, 255);
      }
    }
    return out;
  }

  // Enhanced mask floor detection with better edge refinement
  static Map<String, dynamic> _detectBaselineFromMaskFloorEnhanced(List<int> mask, int w, int h) {
    final floorPts = <Offset>[];

    // Restrict search horizontally to the droplet's bounding box ±15%
    int minX = w - 1, maxX = 0, minYMask = h - 1, maxYMask = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (mask[y * w + x] > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minYMask) minYMask = y;
          if (y > maxYMask) maxYMask = y;
        }
      }
    }
    if (minX > maxX) { minX = (w * 0.25).round(); maxX = (w * 0.75).round(); }
    final expand = ((maxX - minX) * 0.15).round();
    final winL = max(0, minX - expand);
    final winR = min(w - 1, maxX + expand);

    // For each x, find the transition from mask to background near the bottom only within window
    for (int x = winL; x <= winR; x++) {
      int last = 0;
      int yEdge = -1;
      
      // Scan from bottom to top to find the first transition from background to mask
      for (int y = h - 1; y >= 0; y--) {
        final v = mask[y * w + x] > 0 ? 1 : 0;
        if (last == 0 && v == 1) {
          // Found transition from background (0) to mask (1) - this is the surface contact
          yEdge = y;
          break;
        }
        last = v;
      }
      
      if (yEdge >= 0) {
        // Additional validation: check if this is a strong edge
        bool strongEdge = false;
        if (yEdge > 0 && yEdge < h - 1) {
          final above = mask[(yEdge - 1) * w + x];
          final below = mask[(yEdge + 1) * w + x];
          // Should have mask above and background below
          if (above > 0 && below == 0) {
            strongEdge = true;
          }
        }
        
        if (strongEdge) {
          floorPts.add(Offset(x.toDouble(), yEdge.toDouble()));
        }
      }
    }
    
    if (floorPts.isEmpty) {
      // Fallback: use bottom portion of image
      return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    }
    
    // Keep central portion to avoid edge artifacts
    final xs = floorPts.map((p) => p.dx).toList()..sort();
    final l = xs[(xs.length * 0.15).floor()];
    final r = xs[(xs.length * 0.85).floor()];
    final trimmed = floorPts.where((p) => p.dx >= l && p.dx <= r).toList();
    
    if (trimmed.length < max(15, (w * 0.05).round())) {
      return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    }
    
    // Fit a near-horizontal line with strong prior toward horizontal
    final fit = AngleUtils.fitLineRANSACRefined(
      trimmed, 
      iterations: 1000, 
      inlierThresh: 1.2, // Tighter threshold
      slopePrior: 0.0, 
      slopePriorWeight: 15.0 // Stronger horizontal prior
    );
    
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': trimmed};
  }

  // Build baseline from the lowest mask boundary (floor contact) across columns
  static Map<String, dynamic> _detectBaselineFromMaskFloor(List<int> mask, int w, int h) {
    final floorPts = <Offset>[];
    
    // For each x, find the transition from mask to background near the bottom
    for (int x = 0; x < w; x++) {
      int last = 0;
      int yEdge = -1;
      
      // Scan from bottom to top to find the first transition from background to mask
      for (int y = h - 1; y >= 0; y--) {
        final v = mask[y * w + x] > 0 ? 1 : 0;
        if (last == 0 && v == 1) {
          // Found transition from background (0) to mask (1) - this is the surface contact
          yEdge = y;
          break;
        }
        last = v;
      }
      
      if (yEdge >= 0) {
        floorPts.add(Offset(x.toDouble(), yEdge.toDouble()));
      }
    }
    
    if (floorPts.isEmpty) {
      // Fallback: use bottom portion of image
      return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    }
    
    // Keep central portion to avoid edge artifacts
    final xs = floorPts.map((p) => p.dx).toList()..sort();
    final l = xs[(xs.length * 0.15).floor()];
    final r = xs[(xs.length * 0.85).floor()];
    final trimmed = floorPts.where((p) => p.dx >= l && p.dx <= r).toList();
    
    if (trimmed.length < max(12, (w * 0.04).round())) {
      return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    }
    
    // Fit a near-horizontal line with strong prior toward horizontal
    final fit = AngleUtils.fitLineRANSACRefined(
      trimmed, 
      iterations: 800, 
      inlierThresh: 1.5, 
      slopePrior: 0.0, 
      slopePriorWeight: 10.0
    );
    
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': trimmed};
  }

  // Estimate baseline by finding left/right contact candidates where contour meets its lowest band
  // Returns {'m','c','pts', 'left','right'} or null if insufficient support
  static Map<String, dynamic>? _baselineFromContourContacts(List<Offset> contour, int w, int h) {
    if (contour.length < 20) return null;
    // Find bottom band around global max y
    double maxY = -1e9;
    for (final p in contour) if (p.dy > maxY) maxY = p.dy;
    final bandMin = maxY - 10.0;
    final bandPts = contour.where((p) => p.dy >= bandMin).toList();
    if (bandPts.length < max(12, (w * 0.02).round())) return null;
    // Find extreme left/right within the band, but require local upward curvature (to avoid floor noise)
    bandPts.sort((a, b) => a.dx.compareTo(b.dx));
    final leftCand = bandPts.first;
    final rightCand = bandPts.last;
    // Build a slightly thicker strip to fit line robustly
    final bandMin2 = maxY - 18.0;
    final fitPts = contour.where((p) => p.dy >= bandMin2 && p.dy <= maxY + 2.0).toList();
    if (fitPts.length < max(20, (w * 0.04).round())) return null;
    final fit = AngleUtils.fitLineRANSACRefined(fitPts, iterations: 900, inlierThresh: 2.2, slopePrior: 0.0, slopePriorWeight: 5.0);
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': fitPts, 'left': leftCand, 'right': rightCand};
  }

  // Use contour geometry to estimate baseline: collect points near the lowest y across the droplet
  static Map<String, dynamic> _detectBaselineFromContour(List<Offset> contour, int w, int h) {
    if (contour.isEmpty) return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    
    // 1) Find bottom slice of the contour - look for the lowest points
    double maxY = -1e9;
    for (final p in contour) { 
      if (p.dy > maxY) maxY = p.dy; 
    }
    
    // Use a very thin band at the very bottom of the droplet
    final bandMin = maxY - 3.0; // much smaller band for precision
    final bandPts = contour.where((p) => p.dy >= bandMin).toList();
    
    if (bandPts.length < 8) {
      // widen band slightly if needed
      final bandMin2 = maxY - 6.0;
      final more = contour.where((p) => p.dy >= bandMin2).toList();
      if (more.length > bandPts.length) {
        bandPts.clear();
        bandPts.addAll(more);
      }
    }
    
    if (bandPts.isEmpty) return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    
    // 2) Fit near-horizontal line with very strong slope prior toward 0
    final fit = AngleUtils.fitLineRANSACRefined(
      bandPts, 
      iterations: 1000, 
      inlierThresh: 1.0, 
      slopePrior: 0.0, 
      slopePriorWeight: 15.0
    );
    
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': bandPts};
  }

  // Enhanced contour-based baseline detection: find points near the lowest y across the droplet
  static Map<String, dynamic> _detectBaselineFromContourEnhanced(List<Offset> contour, int w, int h) {
    if (contour.isEmpty) return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    
    // 1) Find bottom slice of the contour - look for the lowest points
    double maxY = -1e9;
    for (final p in contour) { 
      if (p.dy > maxY) maxY = p.dy; 
    }
    
    // Use a very thin band at the very bottom of the droplet
    final bandMin = maxY - 3.0; // much smaller band for precision
    final bandPts = contour.where((p) => p.dy >= bandMin).toList();
    
    if (bandPts.length < 8) {
      // widen band slightly if needed
      final bandMin2 = maxY - 6.0;
      final more = contour.where((p) => p.dy >= bandMin2).toList();
      if (more.length > bandPts.length) {
        bandPts.clear();
        bandPts.addAll(more);
      }
    }
    
    if (bandPts.isEmpty) return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    
    // 2) Fit near-horizontal line with very strong slope prior toward 0
    final fit = AngleUtils.fitLineRANSACRefined(
      bandPts, 
      iterations: 1000, 
      inlierThresh: 1.0, 
      slopePrior: 0.0, 
      slopePriorWeight: 15.0
    );
    
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': bandPts};
  }

  // Detect baseline robustly: near-horizontal line located at the lowest strong vertical gradient row
  // Returns {'m': m, 'c': c, 'pts': List<Offset> candidates}
  static Map<String, dynamic> _detectBaselineStable({
    required List<int> gray,
    required int w,
    required int h,
    required List<int> mask,
  }) {
    // 1) Compute vertical gradient magnitude Gy only (edge at baseline is mostly horizontal intensity change)
    final gy = List<int>.filled(w * h, 0);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final g = -gray[(y - 1) * w + (x - 1)] - 2 * gray[(y - 1) * w + x] - gray[(y - 1) * w + (x + 1)]
            + gray[(y + 1) * w + (x - 1)] + 2 * gray[(y + 1) * w + x] + gray[(y + 1) * w + (x + 1)];
        gy[y * w + x] = g.abs();
      }
    }
    
    // 2) Restrict to bottom band and rows just below droplet bounding box
    // droplet bounding box from mask
    int minX = w - 1, maxX = 0, minYMask = h - 1, maxYMask = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (mask[y * w + x] > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minYMask) minYMask = y;
          if (y > maxYMask) maxYMask = y;
        }
      }
    }
    
    if (minX > maxX) { // no mask; fallback later
      minX = (w * 0.2).round();
      maxX = (w * 0.8).round();
      minYMask = h - (h * 0.25).round(); // Move closer to bottom
      maxYMask = h - 1;
    }
    
    // search band centered around bottom of droplet - use thinner band
    int minY = max(0, maxYMask - 5);  // Reduced from 10
    int maxY = min(h - 1, maxYMask + 8); // Reduced from 14
    
    // horizontal window slightly wider than droplet
    final expand = ((maxX - minX) * 0.25).round();
    final winL = max(0, minX - expand);
    final winR = min(w - 1, maxX + expand);
    
    // 3) For each row in band, compute robust column-wise peak count of gy surpassing percentile
    final rowScores = List<double>.filled(h, -1);
    final rowPeaks = List<List<int>>.generate(h, (_) => <int>[]);
    
    for (int y = minY; y <= maxY; y++) {
      final line = List<int>.generate(w, (x) => gy[y * w + x]);
      final sorted = List<int>.from(line)..sort();
      final p95 = sorted[sorted.length * 19 ~/ 20]; // Increased from p90 to p95
      final peaks = <int>[];
      
      for (int x = max(1, winL + 1); x < min(w - 1, winR - 1); x++) {
        // ignore points clearly inside droplet mask to avoid inner shadow edges
        if (mask[y * w + x] > 0) continue;
        
        if (line[x] >= p95 && line[x] >= line[x - 1] && line[x] >= line[x + 1]) {
          // Additional check: ensure this is a true surface edge
          final above = gray[(y - 1) * w + x];
          final below = gray[(y + 1) * w + x];
          final intensityStep = below - above;
          
          if (intensityStep < -5) { // Darker below, brighter above
            peaks.add(x);
          }
        }
      }
      
      // require spatial support: spread peaks across width
      final span = (winR - winL + 1).clamp(1, w);
      if (peaks.length >= span * 0.15) { // Increased from 0.12
        rowScores[y] = peaks.length.toDouble();
        rowPeaks[y] = peaks;
      }
    }
    
    // 4) pick best row: maximum score but with preference to lower rows (closer to bottom)
    int bestY = maxY;
    double bestScore = -1.0;
    for (int y = minY; y <= maxY; y++) {
      final sc = rowScores[y];
      if (sc < 0) continue;
      
      // Stronger bias toward lower rows
      final bias = 1.0 + 2.0 * (y - minY) / max(1.0, (maxY - minY).toDouble());
      final total = sc * bias;
      if (total > bestScore) { 
        bestScore = total; 
        bestY = y; 
      }
    }
    
    // 5) Build candidate points from best row and a small ±1 neighborhood for precision
    final candidates = <Offset>[];
    for (int dy = -1; dy <= 1; dy++) { // Reduced from ±2 to ±1
      final y = (bestY + dy).clamp(0, h - 1);
      final peaks = rowPeaks[y];
      if (peaks.isEmpty) continue;
      for (final x in peaks) {
        candidates.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    
    if (candidates.isEmpty) {
      // fallback to original heuristic
      final fallback = _collectBaselineCandidatesFromRGBA(
          Uint8List.fromList(gray.expand((v) => [v, v, v, 255]).toList()), w, h, mask);
      final lc = AngleUtils.fitLineRANSACRefined(
        fallback, 
        iterations: 800, 
        inlierThresh: 2.0, 
        slopePrior: 0.0, 
        slopePriorWeight: 8.0
      );
      return {'m': lc['m']!, 'c': lc['c']!, 'pts': fallback};
    }
    
    // 6) Fit near-horizontal line with very strong slope prior toward zero
    final fit = AngleUtils.fitLineRANSACRefined(
      candidates, 
      iterations: 1000, 
      inlierThresh: 1.5, 
      slopePrior: 0.0, 
      slopePriorWeight: 15.0
    );
    
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': candidates};
  }

  // Enhanced global stable baseline detection: find points near the lowest strong vertical gradient row
  static Map<String, dynamic> _detectBaselineStableEnhanced({
    required List<int> gray,
    required int w,
    required int h,
    required List<int> mask,
  }) {
    // 1) Compute vertical gradient magnitude Gy only (edge at baseline is mostly horizontal intensity change)
    final gy = List<int>.filled(w * h, 0);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final g = -gray[(y - 1) * w + (x - 1)] - 2 * gray[(y - 1) * w + x] - gray[(y - 1) * w + (x + 1)]
            + gray[(y + 1) * w + (x - 1)] + 2 * gray[(y + 1) * w + x] + gray[(y + 1) * w + (x + 1)];
        gy[y * w + x] = g.abs();
      }
    }
    
    // 2) Restrict to bottom band and rows just below droplet bounding box
    // droplet bounding box from mask
    int minX = w - 1, maxX = 0, minYMask = h - 1, maxYMask = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (mask[y * w + x] > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minYMask) minYMask = y;
          if (y > maxYMask) maxYMask = y;
        }
      }
    }
    
    if (minX > maxX) { // no mask; fallback later
      minX = (w * 0.2).round();
      maxX = (w * 0.8).round();
      minYMask = h - (h * 0.25).round(); // Move closer to bottom
      maxYMask = h - 1;
    }
    
    // search band centered around bottom of droplet - use thinner band
    int minY = max(0, maxYMask - 5);  // Reduced from 10
    int maxY = min(h - 1, maxYMask + 8); // Reduced from 14
    
    // horizontal window slightly wider than droplet
    final expand = ((maxX - minX) * 0.25).round();
    final winL = max(0, minX - expand);
    final winR = min(w - 1, maxX + expand);
    
    // 3) For each row in band, compute robust column-wise peak count of gy surpassing percentile
    final rowScores = List<double>.filled(h, -1);
    final rowPeaks = List<List<int>>.generate(h, (_) => <int>[]);
    
    for (int y = minY; y <= maxY; y++) {
      final line = List<int>.generate(w, (x) => gy[y * w + x]);
      final sorted = List<int>.from(line)..sort();
      final p95 = sorted[sorted.length * 19 ~/ 20]; // Increased from p90 to p95
      final peaks = <int>[];
      
      for (int x = max(1, winL + 1); x < min(w - 1, winR - 1); x++) {
        // ignore points clearly inside droplet mask to avoid inner shadow edges
        if (mask[y * w + x] > 0) continue;
        
        if (line[x] >= p95 && line[x] >= line[x - 1] && line[x] >= line[x + 1]) {
          // Additional check: ensure this is a true surface edge
          final above = gray[(y - 1) * w + x];
          final below = gray[(y + 1) * w + x];
          final intensityStep = below - above;
          
          if (intensityStep < -5) { // Darker below, brighter above
            peaks.add(x);
          }
        }
      }
      
      // require spatial support: spread peaks across width
      final span = (winR - winL + 1).clamp(1, w);
      if (peaks.length >= span * 0.15) { // Increased from 0.12
        rowScores[y] = peaks.length.toDouble();
        rowPeaks[y] = peaks;
      }
    }
    
    // 4) pick best row: maximum score but with preference to lower rows (closer to bottom)
    int bestY = maxY;
    double bestScore = -1.0;
    for (int y = minY; y <= maxY; y++) {
      final sc = rowScores[y];
      if (sc < 0) continue;
      
      // Stronger bias toward lower rows
      final bias = 1.0 + 2.0 * (y - minY) / max(1.0, (maxY - minY).toDouble());
      final total = sc * bias;
      if (total > bestScore) { 
        bestScore = total; 
        bestY = y; 
      }
    }
    
    // 5) Build candidate points from best row and a small ±1 neighborhood for precision
    final candidates = <Offset>[];
    for (int dy = -1; dy <= 1; dy++) { // Reduced from ±2 to ±1
      final y = (bestY + dy).clamp(0, h - 1);
      final peaks = rowPeaks[y];
      if (peaks.isEmpty) continue;
      for (final x in peaks) {
        candidates.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    
    if (candidates.isEmpty) {
      // fallback to original heuristic
      final fallback = _collectBaselineCandidatesFromRGBA(
          Uint8List.fromList(gray.expand((v) => [v, v, v, 255]).toList()), w, h, mask);
      final lc = AngleUtils.fitLineRANSACRefined(
        fallback, 
        iterations: 800, 
        inlierThresh: 2.0, 
        slopePrior: 0.0, 
        slopePriorWeight: 8.0
      );
      return {'m': lc['m']!, 'c': lc['c']!, 'pts': fallback};
    }
    
    // 6) Fit near-horizontal line with very strong slope prior toward zero
    final fit = AngleUtils.fitLineRANSACRefined(
      candidates, 
      iterations: 1000, 
      inlierThresh: 1.5, 
      slopePrior: 0.0, 
      slopePriorWeight: 15.0
    );
    
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': candidates};
  }

  // Gradient band detector anchored to droplet bottom: restrict to a thin horizontal strip
  static Map<String, dynamic>? _detectBaselineNearDropletBand({
    required List<int> gray,
    required int w,
    required int h,
    required List<int> mask,
    required List<Offset> contour,
  }) {
    if (contour.isEmpty) return null;
    
    double maxY = -1e9; 
    double minX = w.toDouble(), maxX = 0;
    for (final p in contour) { 
      if (p.dy > maxY) maxY = p.dy; 
      if (p.dx < minX) minX = p.dx; 
      if (p.dx > maxX) maxX = p.dx; 
    }
    
    final centerBandY = maxY; // bottom of droplet
    // Use a much thinner band for precision
    final y0 = max(1, centerBandY.floor() - 2);
    final y1 = min(h - 2, centerBandY.floor() + 3);
    final winL = max(1, (minX - (maxX - minX) * 0.15).floor());
    final winR = min(w - 2, (maxX + (maxX - minX) * 0.15).ceil());
    
    // compute vertical gradient
    int gyAt(int x, int y) {
      final g = -gray[(y - 1) * w + (x - 1)] - 2 * gray[(y - 1) * w + x] - gray[(y - 1) * w + (x + 1)]
          + gray[(y + 1) * w + (x - 1)] + 2 * gray[(y + 1) * w + x] + gray[(y + 1) * w + (x + 1)];
      return g.abs();
    }
    
    // aggregate peaks across rows in the band
    final candidates = <Offset>[];
    for (int y = y0; y <= y1; y++) {
      final line = <int>[];
      for (int x = winL; x <= winR; x++) line.add(gyAt(x, y));
      
      final sorted = List<int>.from(line)..sort();
      final idx90 = ((sorted.length * 0.90).floor()).clamp(0, sorted.length - 1);
      final p90 = sorted[idx90];
      
      for (int x = winL + 1; x < winR - 1; x++) {
        if (mask[y * w + x] > 0) continue; // avoid inside droplet
        
        final v = gyAt(x, y);
        // intensity should step from brighter above to darker below at baseline → dv = below - above < 0
        final above = gray[(y - 1) * w + x];
        final below = gray[(y + 1) * w + x];
        final dv = below - above;
        
        // More strict criteria for baseline detection
        if (v >= p90 && dv < -8) {
          candidates.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    
    if (candidates.length < max(20, (w * 0.05).round())) return null;
    
    // Fit with very strong horizontal prior
    final fit = AngleUtils.fitLineRANSACRefined(
      candidates, 
      iterations: 1000, 
      inlierThresh: 1.5, 
      slopePrior: 0.0, 
      slopePriorWeight: 12.0
    );
    
    // Find rough left/right contacts as intersections between fitted line and contour
    final m = fit['m']!, c = fit['c']!;
    Offset? leftI, rightI;
    for (int i = 0; i < contour.length; i++) {
      final p1 = contour[i]; 
      final p2 = contour[(i + 1) % contour.length];
      final ip = AngleUtils.intersectSegmentWithBaseline(p1, p2, m, c);
      if (ip != null) {
        if (leftI == null || ip.dx < leftI.dx) leftI = ip;
        if (rightI == null || ip.dx > rightI.dx) rightI = ip;
      }
    }
    
    return {'m': m, 'c': c, 'pts': candidates, 'left': leftI, 'right': rightI};
  }

  // Enhanced gradient band detector anchored to droplet bottom: restrict to a thin horizontal strip
  static Map<String, dynamic>? _detectBaselineNearDropletBandEnhanced({
    required List<int> gray,
    required int w,
    required int h,
    required List<int> mask,
    required List<Offset> contour,
  }) {
    if (contour.isEmpty) return null;
    
    double maxY = -1e9; 
    double minX = w.toDouble(), maxX = 0;
    for (final p in contour) { 
      if (p.dy > maxY) maxY = p.dy; 
      if (p.dx < minX) minX = p.dx; 
      if (p.dx > maxX) maxX = p.dx; 
    }
    
    final centerBandY = maxY; // bottom of droplet
    // Use a much thinner band for precision
    final y0 = max(1, centerBandY.floor() - 2);
    final y1 = min(h - 2, centerBandY.floor() + 3);
    final winL = max(1, (minX - (maxX - minX) * 0.15).floor());
    final winR = min(w - 2, (maxX + (maxX - minX) * 0.15).ceil());
    
    // compute vertical gradient
    int gyAt(int x, int y) {
      final g = -gray[(y - 1) * w + (x - 1)] - 2 * gray[(y - 1) * w + x] - gray[(y - 1) * w + (x + 1)]
          + gray[(y + 1) * w + (x - 1)] + 2 * gray[(y + 1) * w + x] + gray[(y + 1) * w + (x + 1)];
      return g.abs();
    }
    
    // aggregate peaks across rows in the band
    final candidates = <Offset>[];
    for (int y = y0; y <= y1; y++) {
      final line = <int>[];
      for (int x = winL; x <= winR; x++) line.add(gyAt(x, y));
      
      final sorted = List<int>.from(line)..sort();
      final idx90 = ((sorted.length * 0.90).floor()).clamp(0, sorted.length - 1);
      final p90 = sorted[idx90];
      
      for (int x = winL + 1; x < winR - 1; x++) {
        if (mask[y * w + x] > 0) continue; // avoid inside droplet
        
        final v = gyAt(x, y);
        // intensity should step from brighter above to darker below at baseline → dv = below - above < 0
        final above = gray[(y - 1) * w + x];
        final below = gray[(y + 1) * w + x];
        final dv = below - above;
        
        // More strict criteria for baseline detection
        if (v >= p90 && dv < -8) {
          candidates.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    
    if (candidates.length < max(20, (w * 0.05).round())) return null;
    
    // Fit with very strong horizontal prior
    final fit = AngleUtils.fitLineRANSACRefined(
      candidates, 
      iterations: 1000, 
      inlierThresh: 1.5, 
      slopePrior: 0.0, 
      slopePriorWeight: 12.0
    );
    
    // Find rough left/right contacts as intersections between fitted line and contour
    final m = fit['m']!, c = fit['c']!;
    Offset? leftI, rightI;
    for (int i = 0; i < contour.length; i++) {
      final p1 = contour[i]; 
      final p2 = contour[(i + 1) % contour.length];
      final ip = AngleUtils.intersectSegmentWithBaseline(p1, p2, m, c);
      if (ip != null) {
        if (leftI == null || ip.dx < leftI.dx) leftI = ip;
        if (rightI == null || ip.dx > rightI.dx) rightI = ip;
      }
    }
    
    return {'m': m, 'c': c, 'pts': candidates, 'left': leftI, 'right': rightI};
  }

  // New enhanced method: analyze intensity profile to find true surface boundary
  static Map<String, dynamic> _detectBaselineFromIntensityProfileEnhanced({
    required List<int> gray,
    required int w,
    required int h,
    required List<int> mask,
    required List<Offset> contour,
  }) {
    if (contour.isEmpty) return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    
    // Find droplet bounding box
    double minX = w.toDouble(), maxX = 0, minY = h.toDouble(), maxY = 0;
    for (final p in contour) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    
    // Look for the surface boundary below the droplet with enhanced criteria
    final candidates = <Offset>[];
    final searchStartY = min(h - 1, maxY.floor() + 2);
    final searchEndY = min(h - 1, maxY.floor() + 20); // Increased search range
    
    for (int y = searchStartY; y <= searchEndY; y++) {
      for (int x = max(1, minX.floor() - 10); x <= min(w - 2, maxX.ceil() + 10); x++) {
        // Skip if inside droplet mask
        if (mask[y * w + x] > 0) continue;
        
        // Check for strong vertical intensity gradient (surface edge)
        final above = gray[(y - 1) * w + x];
        final below = gray[(y + 1) * w + x];
        final current = gray[y * w + x];
        
        // Enhanced surface detection criteria
        final gradient = (above - below).abs();
        final intensityStep = below - above;
        
        // More sophisticated edge detection
        if (gradient > 25 && intensityStep < -12) {
          // Additional check: look for horizontal consistency and edge strength
          int consistentCount = 0;
          double totalEdgeStrength = 0.0;
          
          for (int dx = -3; dx <= 3; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            if (nx != x && mask[y * w + nx] == 0) {
              final nAbove = gray[(y - 1) * w + nx];
              final nBelow = gray[(y + 1) * w + nx];
              final nGradient = (nAbove - nBelow).abs();
              if (nGradient > 20) {
                consistentCount++;
                totalEdgeStrength += nGradient;
              }
            }
          }
          
          // Require spatial consistency and strong edge
          if (consistentCount >= 3 && totalEdgeStrength > 100) {
            // Additional validation: check if this is a true surface boundary
            final leftCheck = x > 0 ? gray[y * w + (x - 1)] : 0;
            final rightCheck = x < w - 1 ? gray[y * w + (x + 1)] : 0;
            
            // Surface should have consistent intensity along the edge
            if ((leftCheck - current).abs() < 15 && (rightCheck - current).abs() < 15) {
              candidates.add(Offset(x.toDouble(), y.toDouble()));
            }
          }
        }
      }
    }
    
    if (candidates.length < max(15, (w * 0.04).round())) {
      return {'m': 0.0, 'c': h * 0.95, 'pts': <Offset>[]};
    }
    
    // Fit horizontal line with very strong prior and outlier rejection
    final fit = AngleUtils.fitLineRANSACRefined(
      candidates,
      iterations: 1500,
      inlierThresh: 0.8, // Tighter threshold
      slopePrior: 0.0,
      slopePriorWeight: 25.0, // Stronger horizontal prior
    );
    
    return {'m': fit['m']!, 'c': fit['c']!, 'pts': candidates, 'method': 'intensity_profile_enhanced'};
  }

  static List<int> _autoThreshold(List<int> mag, int w, int h) {
    final s = List<int>.from(mag)..sort();
    final med = s[s.length ~/ 2];
    final thr = max(12, (med * 0.9).round());
    final out = List<int>.filled(w * h, 0);
    for (int i = 0; i < mag.length; i++) out[i] = mag[i] >= thr ? 255 : 0;
    return out;
  }

  static List<int> _morphology(List<int> mask, int w, int h, {int closeR = 2, int openR = 1}) {
    var tmp = _dilate(mask, w, h, radius: closeR);
    tmp = _erode(tmp, w, h, radius: closeR);
    tmp = _erode(tmp, w, h, radius: openR);
    tmp = _dilate(tmp, w, h, radius: openR);
    return tmp;
  }

  static List<int> _erode(List<int> mask, int w, int h, {int radius = 1}) {
    final out = List<int>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool all = true;
        for (int dy = -radius; dy <= radius && all; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            if (mask[ny * w + nx] == 0) {
              all = false;
              break;
            }
          }
        }
        out[y * w + x] = all ? 255 : 0;
      }
    }
    return out;
  }

  static List<int> _dilate(List<int> mask, int w, int h, {int radius = 1}) {
    final out = List<int>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool any = false;
        for (int dy = -radius; dy <= radius && !any; dy++) {
          for (int dx = -radius; dx <= radius; dx++) {
            final nx = (x + dx).clamp(0, w - 1);
            final ny = (y + dy).clamp(0, h - 1);
            if (mask[ny * w + nx] > 0) {
              any = true;
              break;
            }
          }
        }
        out[y * w + x] = any ? 255 : 0;
      }
    }
    return out;
  }

  static List<int> _largestComponent(List<int> mask, int w, int h) {
    final visited = List<bool>.filled(w * h, false);
    final out = List<int>.filled(w * h, 0);
    int bestSize = 0;
    List<int> bestComp = [];
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        if (!visited[idx] && mask[idx] > 0) {
          final comp = _flood(mask, visited, w, h, x, y);
          if (comp.length > bestSize) {
            bestSize = comp.length;
            bestComp = comp;
          }
        }
      }
    }
    for (final i in bestComp) out[i] = 255;
    return out;
  }

  static List<int> _flood(List<int> mask, List<bool> visited, int w, int h, int sx, int sy) {
    final comp = <int>[];
    final stack = <Point<int>>[Point(sx, sy)];
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      final x = p.x, y = p.y;
      if (x < 0 || x >= w || y < 0 || y >= h) continue;
      final idx = y * w + x;
      if (visited[idx] || mask[idx] == 0) continue;
      visited[idx] = true;
      comp.add(idx);
      for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) if (!(dx == 0 && dy == 0)) stack.add(Point(x + dx, y + dy));
    }
    return comp;
  }

  static List<Offset> _maskToContour(List<int> mask, int w, int h) {
    final pts = <Offset>[];
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final idx = y * w + x;
        if (mask[idx] > 0 &&
            (mask[(y - 1) * w + x] == 0 ||
                mask[(y + 1) * w + x] == 0 ||
                mask[y * w + (x - 1)] == 0 ||
                mask[y * w + (x + 1)] == 0)) {
          pts.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    if (pts.isEmpty) return pts;
    final center = pts.fold(Offset.zero, (s, p) => s + p) / pts.length.toDouble();
    pts.sort((a, b) => atan2(a.dy - center.dy, a.dx - center.dx).compareTo(atan2(b.dy - center.dy, b.dx - center.dx)));
    return pts;
  }

  static List<Offset> _smoothContour(List<Offset> c, {int window = 5}) {
    if (c.length < 3) return c;
    final n = c.length;
    final out = List<Offset>.filled(n, Offset.zero);
    for (int i = 0; i < n; i++) {
      double sx = 0, sy = 0;
      int cnt = 0;
      for (int k = -window; k <= window; k++) {
        final idx = (i + k).clamp(0, n - 1);
        sx += c[idx].dx;
        sy += c[idx].dy;
        cnt++;
      }
      out[i] = Offset(sx / cnt, sy / cnt);
    }
    return out;
  }

  static List<Offset> _collectLocalNeighbors(List<Offset> contour, Offset pt, {int k = 8}) {
    // gather k neighbors around nearest index
    int idx = 0;
    double minD = double.infinity;
    for (int i = 0; i < contour.length; i++) {
      final d = (contour[i] - pt).distance;
      if (d < minD) {
        minD = d;
        idx = i;
      }
    }
    final start = (idx - k).clamp(0, contour.length - 1);
    final end = (idx + k).clamp(0, contour.length - 1);
    final out = <Offset>[];
    for (int i = start; i <= end; i++) out.add(contour[i]);
    return out;
  }

  static Offset _normalizeSafe(Offset v) {
    final d = v.distance;
    if (d < 1e-9) return const Offset(1.0, 0.0);
    return Offset(v.dx / d, v.dy / d);
  }

  static List<Offset> _collectBaselineCandidatesFromRGBA(Uint8List rgba, int w, int h, List<int> mask) {
    final candidates = <Offset>[];
    final bottomH = (h * 0.35).round();
    final startY = max(0, h - bottomH);
    for (int y = startY; y < h - 1; y++) {
      int run = 0;
      for (int x = 1; x < w - 1; x++) {
        final cur = _rgbaGray(rgba, x, y, w);
        final nxt = _rgbaGray(rgba, x + 1, y, w);
        if ((cur - nxt).abs() > 18) run++;
      }
      if (run > (w * 0.4).round()) {
        for (int x = 0; x < w; x++) candidates.add(Offset(x.toDouble(), y.toDouble()));
      }
    }
    // also include bottom-most mask points
    for (int x = 0; x < w; x++) {
      for (int y = h - 1; y >= 0; y--) {
        if (mask[y * w + x] > 0) {
          candidates.add(Offset(x.toDouble(), y.toDouble()));
          break;
        }
      }
    }
    if (candidates.isEmpty) {
      for (int x = 0; x < w; x++) candidates.add(Offset(x.toDouble(), (h * 0.9).toDouble()));
    }
    return candidates;
  }

  static int _rgbaGray(Uint8List rgba, int x, int y, int w) {
    final idx = (y * w + x) * 4;
    if (idx < 0 || idx + 2 >= rgba.length) return 0;
    return (0.299 * rgba[idx] + 0.587 * rgba[idx + 1] + 0.114 * rgba[idx + 2]).round();
  }

  static double _localEdgeStrength(Uint8List rgba, int w, int h, Offset center, {int radius = 7}) {
    final cx = center.dx.round();
    final cy = center.dy.round();
    double sum = 0.0; int count = 0;
    for (int y = max(1, cy - radius); y < min(h - 1, cy + radius); y++) {
      for (int x = max(1, cx - radius); x < min(w - 1, cx + radius); x++) {
        final gx = -_rgbaGray(rgba, x - 1, y - 1, w) + _rgbaGray(rgba, x + 1, y - 1, w)
            - 2 * _rgbaGray(rgba, x - 1, y, w) + 2 * _rgbaGray(rgba, x + 1, y, w)
            - _rgbaGray(rgba, x - 1, y + 1, w) + _rgbaGray(rgba, x + 1, y + 1, w);
        final gy = -_rgbaGray(rgba, x - 1, y - 1, w) - 2 * _rgbaGray(rgba, x, y - 1, w)
            - _rgbaGray(rgba, x + 1, y - 1, w) + _rgbaGray(rgba, x - 1, y + 1, w)
            + 2 * _rgbaGray(rgba, x, y + 1, w) + _rgbaGray(rgba, x + 1, y + 1, w);
        sum += sqrt(gx * gx + gy * gy);
        count++;
      }
    }
    if (count == 0) return 0.0;
    return sum / count;
  }
}

// Data holders
class ProcessedImageData {
  final List<Offset> boundary; // in original (unscaled) pixels
  final BaselineData baseline;
  final Offset leftContact;
  final Offset rightContact;
  final double leftAngle;
  final double rightAngle;
  final double avgAngle;
  final double bestAngle;
  final String bestSide; // 'left' | 'right'
  final Map<String, dynamic>? debug;
  final Map<String, dynamic>? enhancedBoundary; // Added for enhanced boundary

  ProcessedImageData({
    required this.boundary,
    required this.baseline,
    required this.leftContact,
    required this.rightContact,
    required this.leftAngle,
    required this.rightAngle,
    required this.avgAngle,
    required this.bestAngle,
    required this.bestSide,
    this.debug,
    this.enhancedBoundary, // Added for enhanced boundary
  });
}

class BaselineData {
  final Offset startPoint;
  final Offset endPoint;
  final double m;
  final double c;
  BaselineData({required this.startPoint, required this.endPoint, required this.m, required this.c});
}