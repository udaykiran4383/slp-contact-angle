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

    // baseline detection: prefer fitting a near-horizontal line to bottom-of-contour candidates;
    // fall back to gray-gradient based detector when insufficient contour support is found.
    Map<String, dynamic> baselineResult;
    // 1) Primary: use mask-floor transition under the droplet (closest to true contact)
    final floorBased = _detectBaselineFromMaskFloor(mask, width, height);
    if ((floorBased['pts'] as List<Offset>).length >= max(24, (width * 0.06).round())) {
      baselineResult = floorBased;
    } else {
      // 2) Secondary: contour-bottom band
      final contourBased = _detectBaselineFromContour(smooth, width, height);
      if ((contourBased['pts'] as List<Offset>).length >= max(20, (width * 0.05).round())) {
        baselineResult = contourBased;
      } else {
        // 3) Tertiary: gradient band near droplet
        final nearBand = _detectBaselineNearDropletBand(gray: gauss, w: width, h: height, mask: mask, contour: smooth);
        if (nearBand != null && (nearBand['pts'] as List<Offset>).length >= max(20, (width * 0.05).round())) {
          baselineResult = nearBand;
        } else {
          // 4) Last resort: global stable
          baselineResult = _detectBaselineStable(
            gray: gauss,
            w: width,
            h: height,
            mask: mask,
          );
        }
      }
    }
    final m = baselineResult['m']!;
    final c = baselineResult['c']!;
    final baselineCandidates = (baselineResult['pts'] as List<Offset>);
    final Offset? contactLeftHint = baselineResult['left'] as Offset?;
    final Offset? contactRightHint = baselineResult['right'] as Offset?;

    // find intersections of contour segments with baseline (left & right)
    final intersections = <Offset>[];
    for (int i = 0; i < smooth.length; i++) {
      final p1 = smooth[i];
      final p2 = smooth[(i + 1) % smooth.length];
      final ip = AngleUtils.intersectSegmentWithBaseline(p1, p2, m, c);
      if (ip != null) intersections.add(ip);
    }

    // if none found or a better hint exists, use hinted contacts from baseline detector
    Offset leftApprox, rightApprox;
    if (contactLeftHint != null && contactRightHint != null) {
      leftApprox = contactLeftHint;
      rightApprox = contactRightHint;
    } else if (intersections.isEmpty) {
      final sortedByY = List<Offset>.from(smooth)..sort((a, b) => b.dy.compareTo(a.dy));
      final bottom = sortedByY.take(min(40, sortedByY.length)).toList();
      bottom.sort((a, b) => a.dx.compareTo(b.dx));
      leftApprox = bottom.first;
      rightApprox = bottom.last;
    } else {
      intersections.sort((a, b) => a.dx.compareTo(b.dx));
      leftApprox = intersections.first;
      rightApprox = intersections.length > 1 ? intersections.last : intersections.first;
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

    // Build baseline endpoints in original coordinates (use width of orig image)
    final cOrig = c * sx; // scale intercept to original pixel space
    final baselineStart = Offset(0, (m * 0 + cOrig));
    final baselineEnd = Offset(origW.toDouble(), (m * origW + cOrig));
    
    return ProcessedImageData(
      boundary: origContour,
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
        'left_neighborhood': leftLocalOrig,
        'right_neighborhood': rightLocalOrig,
        'approx_contacts': [leftApproxOrig, rightApproxOrig],
      } : null,
    );
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

  // Build baseline from the lowest mask boundary (floor contact) across columns
  static Map<String, dynamic> _detectBaselineFromMaskFloor(List<int> mask, int w, int h) {
    final floorPts = <Offset>[];
    // For each x, find the transition from mask to background near the bottom
    for (int x = 0; x < w; x++) {
      int last = 0;
      int yEdge = -1;
      for (int y = 0; y < h; y++) {
        final v = mask[y * w + x] > 0 ? 1 : 0;
        if (last == 1 && v == 0) {
          yEdge = y;
        }
        last = v;
      }
      if (yEdge >= 0) floorPts.add(Offset(x.toDouble(), yEdge.toDouble()));
    }
    if (floorPts.isEmpty) return {'m': 0.0, 'c': h * 0.92, 'pts': <Offset>[]};
    // Keep central portion to avoid edge artifacts
    final xs = floorPts.map((p) => p.dx).toList()..sort();
    final l = xs[(xs.length * 0.15).floor()];
    final r = xs[(xs.length * 0.85).floor()];
    final trimmed = floorPts.where((p) => p.dx >= l && p.dx <= r).toList();
    if (trimmed.length < max(12, (w * 0.04).round())) return {'m': 0.0, 'c': h * 0.92, 'pts': <Offset>[]};
    final fit = AngleUtils.fitLineRANSACRefined(trimmed, iterations: 800, inlierThresh: 2.0, slopePrior: 0.0, slopePriorWeight: 4.0);
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
    if (contour.isEmpty) return {'m': 0.0, 'c': h * 0.9, 'pts': <Offset>[]};
    // 1) Find bottom slice of the contour
    double maxY = -1e9;
    for (final p in contour) { if (p.dy > maxY) maxY = p.dy; }
    final bandMin = maxY - 8.0; // small vertical band near bottom of droplet
    final bandPts = contour.where((p) => p.dy >= bandMin).toList();
    if (bandPts.length < 8) {
      // widen band
      final bandMin2 = maxY - 16.0;
      final more = contour.where((p) => p.dy >= bandMin2).toList();
      if (more.length > bandPts.length) bandPts
        ..clear()
        ..addAll(more);
    }
    if (bandPts.isEmpty) return {'m': 0.0, 'c': h * 0.9, 'pts': <Offset>[]};
    // 2) Fit near-horizontal line with slope prior toward 0
    final fit = AngleUtils.fitLineRANSACRefined(bandPts, iterations: 800, inlierThresh: 2.0, slopePrior: 0.0, slopePriorWeight: 4.0);
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
      minYMask = h - (h * 0.35).round();
      maxYMask = h - 1;
    }
    // search band centered around bottom of droplet
    int minY = max(0, maxYMask - 10);
    int maxY = min(h - 1, maxYMask + 14);
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
      final p90 = sorted[sorted.length * 9 ~/ 10];
      final peaks = <int>[];
      for (int x = max(1, winL + 1); x < min(w - 1, winR - 1); x++) {
        // ignore points clearly inside droplet mask to avoid inner shadow edges
        if (mask[y * w + x] > 0) continue;
        if (line[x] >= p90 && line[x] >= line[x - 1] && line[x] >= line[x + 1]) peaks.add(x);
      }
      // require spatial support: spread peaks across width
      final span = (winR - winL + 1).clamp(1, w);
      if (peaks.length >= span * 0.12) {
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
      final bias = 1.0 + (y - minY) / max(1.0, (maxY - minY).toDouble());
      final total = sc * bias;
      if (total > bestScore) { bestScore = total; bestY = y; }
    }
    // 5) Build candidate points from best row and a small ±2 neighborhood for robustness
    final candidates = <Offset>[];
    for (int dy = -2; dy <= 2; dy++) {
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
      final lc = AngleUtils.fitLineRANSACRefined(fallback, iterations: 600, inlierThresh: 2.5, slopePrior: 0.0, slopePriorWeight: 2.0);
      return {'m': lc['m']!, 'c': lc['c']!, 'pts': fallback};
    }
    // 6) Fit near-horizontal line with slope prior toward zero
    final fit = AngleUtils.fitLineRANSACRefined(candidates, iterations: 800, inlierThresh: 2.0, slopePrior: 0.0, slopePriorWeight: 3.0);
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
    double maxY = -1e9; double minX = w.toDouble(), maxX = 0;
    for (final p in contour) { if (p.dy > maxY) maxY = p.dy; if (p.dx < minX) minX = p.dx; if (p.dx > maxX) maxX = p.dx; }
    final centerBandY = maxY; // bottom of droplet
    final y0 = max(1, centerBandY.floor() - 4);
    final y1 = min(h - 2, centerBandY.floor() + 6);
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
      final idx85 = ((sorted.length * 0.85).floor()).clamp(0, sorted.length - 1);
      final p85 = sorted[idx85];
      for (int x = winL + 1; x < winR - 1; x++) {
        if (mask[y * w + x] > 0) continue; // avoid inside droplet
        final v = gyAt(x, y);
        // intensity should step from brighter above to darker below at baseline → dv = below - above < 0
        final above = gray[(y - 2) * w + x];
        final below = gray[(y + 2) * w + x];
        final dv = below - above;
        if (v >= p85 && dv < -6) {
          candidates.add(Offset(x.toDouble(), y.toDouble()));
        }
      }
    }
    if (candidates.length < max(24, (w * 0.06).round())) return null;
    final fit = AngleUtils.fitLineRANSACRefined(candidates, iterations: 900, inlierThresh: 2.0, slopePrior: 0.0, slopePriorWeight: 6.0);
    // Find rough left/right contacts as intersections between fitted line and contour
    final m = fit['m']!, c = fit['c']!;
    Offset? leftI, rightI;
    for (int i = 0; i < contour.length; i++) {
      final p1 = contour[i]; final p2 = contour[(i + 1) % contour.length];
      final ip = AngleUtils.intersectSegmentWithBaseline(p1, p2, m, c);
      if (ip != null) {
        if (leftI == null || ip.dx < leftI.dx) leftI = ip;
        if (rightI == null || ip.dx > rightI.dx) rightI = ip;
      }
    }
    return {'m': m, 'c': c, 'pts': candidates, 'left': leftI, 'right': rightI};
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
  });
}

class BaselineData {
  final Offset startPoint;
  final Offset endPoint;
  final double m;
  final double c;
  BaselineData({required this.startPoint, required this.endPoint, required this.m, required this.c});
}