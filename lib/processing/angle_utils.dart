import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class AngleUtils {
  // Robust RANSAC line fit with optional prior/weight
  static Map fitLineRANSACRefined(
    List<Offset> pts, {
    int iterations = 600,
    double inlierThresh = 2.5,
    double? slopePrior, // e.g., 0 for horizontal
    double slopePriorWeight = 0.0,
  }) {
    if (pts.length < 2) return {'m': 0.0, 'c': pts.isNotEmpty ? pts.first.dy : 0.0};
    final rnd = Random();
    double bestM = 0.0, bestC = 0.0;
    int bestInliers = -1;
    for (int it = 0; it < iterations; it++) {
      final a = pts[rnd.nextInt(pts.length)];
      final b = pts[rnd.nextInt(pts.length)];
      if ((a - b).distance < 1e-6) continue;
      if ((b.dx - a.dx).abs() < 1e-9) continue;
      double m = (b.dy - a.dy) / (b.dx - a.dx);
      double c = a.dy - m * a.dx;
      if (slopePrior != null && slopePriorWeight > 0.0) {
        m = (m + slopePriorWeight * slopePrior) / (1.0 + slopePriorWeight);
        c = a.dy - m * a.dx;
      }
      int inliers = 0;
      final inlierIdx = <int>[];
      for (int i = 0; i < pts.length; i++) {
        final p = pts[i];
        final dist = (m * p.dx - p.dy + c).abs() / sqrt(m * m + 1);
        if (dist <= inlierThresh) {
          inliers++;
          inlierIdx.add(i);
        }
      }
      if (inliers > bestInliers) {
        bestInliers = inliers;
        final inlierPts = inlierIdx.map((i) => pts[i]).toList();
        final lc = _leastSquaresLine(inlierPts, slopePrior: slopePrior, slopePriorWeight: slopePriorWeight);
        bestM = lc['m']!;
        bestC = lc['c']!;
      }
    }
    return {'m': bestM, 'c': bestC};
  }

  // Ordinary least squares with L2 slope prior
  static Map _leastSquaresLine(List<Offset> pts, {double? slopePrior, double slopePriorWeight = 0.0}) {
    if (pts.length < 2) return {'m': 0.0, 'c': pts.isNotEmpty ? pts.first.dy : 0.0};
    double Sx = 0, Sy = 0, Sxx = 0, Sxy = 0;
    final n = pts.length.toDouble();
    for (final p in pts) {
      Sx += p.dx;
      Sy += p.dy;
      Sxx += p.dx * p.dx;
      Sxy += p.dx * p.dy;
    }
    final lambda = slopePrior != null ? slopePriorWeight : 0.0;
    final b = Sxy - (Sx * Sy) / n + (lambda * (slopePrior ?? 0.0));
    final a = Sxx - (Sx * Sx) / n + lambda;
    final m = a.abs() < 1e-12 ? 0.0 : (b / a);
    final c = (Sy - m * Sx) / n;
    return {'m': m, 'c': c};
  }

  // Subpixel refinement: sample normal, find gradient peak along normal
  static Offset subpixelRefineFromRGBA({
    required Uint8List rgba,
    required int width,
    required int height,
    required Offset approx,
    required Offset normal, // unit vector
    int samples = 25,
    double spacing = 0.6,
  }) {
    final mid = samples ~/ 2;
    final intens = List<double>.filled(samples, 0.0);
    for (int i = 0; i < samples; i++) {
      final t = (i - mid) * spacing;
      final sx = approx.dx + normal.dx * t;
      final sy = approx.dy + normal.dy * t;
      intens[i] = _bilinearSampleGray(rgba, width, height, sx, sy);
    }
    final grad = List<double>.filled(samples, 0.0);
    for (int i = 1; i < samples - 1; i++) grad[i] = (intens[i + 1] - intens[i - 1]) / 2.0;
    int imax = 1;
    double best = grad[1].abs();
    for (int i = 2; i < samples - 1; i++) {
      final d = grad[i].abs();
      if (d > best) {
        best = d;
        imax = i;
      }
    }
    if (imax <= 0 || imax >= samples - 1) return approx;
    final y1 = grad[imax - 1], y2 = grad[imax], y3 = grad[imax + 1];
    final denom = 2 * (y1 - 2 * y2 + y3);
    double dt = 0.0;
    if (denom.abs() > 1e-8) {
      dt = (y1 - y3) / denom;
      dt = dt.clamp(-1.0, 1.0);
    }
    final tPeak = (imax - mid) * spacing + dt * spacing;
    return Offset(approx.dx + normal.dx * tPeak, approx.dy + normal.dy * tPeak);
  }

  // Bilinear interpolate greyscale
  static double _bilinearSampleGray(Uint8List pixels, int width, int height, double x, double y) {
    if (x < 0 || y < 0 || x >= width - 1 || y >= height - 1) {
      final xi = x.clamp(0.0, width - 1.0).toInt();
      final yi = y.clamp(0.0, height - 1.0).toInt();
      final idx = (yi * width + xi) * 4;
      final r = pixels[idx], g = pixels[idx + 1], b = pixels[idx + 2];
      return 0.299 * r + 0.587 * g + 0.114 * b;
    }
    final x0 = x.floor(), y0 = y.floor();
    final x1 = x0 + 1, y1 = y0 + 1;
    final dx = x - x0, dy = y - y0;
    final idx00 = (y0 * width + x0) * 4;
    final idx10 = (y0 * width + x1) * 4;
    final idx01 = (y1 * width + x0) * 4;
    final idx11 = (y1 * width + x1) * 4;
    double r00 = pixels[idx00].toDouble(), g00 = pixels[idx00 + 1].toDouble(), b00 = pixels[idx00 + 2].toDouble();
    double r10 = pixels[idx10].toDouble(), g10 = pixels[idx10 + 1].toDouble(), b10 = pixels[idx10 + 2].toDouble();
    double r01 = pixels[idx01].toDouble(), g01 = pixels[idx01 + 1].toDouble(), b01 = pixels[idx01 + 2].toDouble();
    double r11 = pixels[idx11].toDouble(), g11 = pixels[idx11 + 1].toDouble(), b11 = pixels[idx11 + 2].toDouble();
    double r = (1 - dx) * (1 - dy) * r00 + dx * (1 - dy) * r10 + (1 - dx) * dy * r01 + dx * dy * r11;
    double g = (1 - dx) * (1 - dy) * g00 + dx * (1 - dy) * g10 + (1 - dx) * dy * g01 + dx * dy * g11;
    double b = (1 - dx) * (1 - dy) * b00 + dx * (1 - dy) * b10 + (1 - dx) * dy * b01 + dx * dy * b11;
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }

  // Algebraic circle fit (Kåsa/Pratt)
  static Map? fitCircleKasa(List<Offset> pts) {
    if (pts.length < 6) return null;
    double Sx = 0, Sy = 0, Sxx = 0, Syy = 0, Sxy = 0, Sxxx = 0, Sxxy = 0, Sxyy = 0, Syyy = 0;
    final n = pts.length.toDouble();
    for (final p in pts) {
      final x = p.dx;
      final y = p.dy;
      final x2 = x * x, y2 = y * y;
      Sx += x; Sy += y; Sxx += x2; Syy += y2; Sxy += x * y;
      Sxxx += x2 * x; Sxxy += x2 * y; Sxyy += x * y2; Syyy += y2 * y;
    }
    final C = n * Sxx - Sx * Sx;
    final D = n * Sxy - Sx * Sy;
    final E = n * Syy - Sy * Sy;
    final G = 0.5 * (n * (Sxxx + Sxyy) - Sx * (Sxx + Syy));
    final H = 0.5 * (n * (Sxxy + Syyy) - Sy * (Sxx + Syy));
    final denom = (C * E - D * D);
    if (denom.abs() < 1e-12) return null;
    final a = (G * E - D * H) / denom;
// ...existing code...
  // Intersect segment with baseline (y = mx + c)
  Offset? intersectSegmentWithBaseline(
    Offset p1,
    Offset p2,
    double m,
    double c,
    {double eps = 1e-6}
  ) {
    // Line segment: p1 to p2
    // Baseline: y = m*x + c
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    if (dx.abs() < eps) return null;
    // Parametric: x = p1.dx + t*dx, y = p1.dy + t*dy
    // Set y = m*x + c, solve for t
    final a = m * dx - dy;
    if (a.abs() < eps) return null;
    final t = (m * p1.dx + c - p1.dy) / a;
    if (t < 0 || t > 1) return null;
    return Offset(p1.dx + t * dx, p1.dy + t * dy);
  }

  // Contact angle from slopes
  double contactAngleDegreesFromSlopes(double tangentSlope, double baselineSlope) {
    final angleRad = atan((tangentSlope - baselineSlope) / (1 + tangentSlope * baselineSlope));
    return angleRad.abs() * 180 / pi;
  }

  // Tangent slope from circle at point
  double tangentSlopeFromCircleAtPoint(Map circle, Offset point) {
    final xc = circle['xc'], yc = circle['yc'];
    final dx = point.dx - xc, dy = point.dy - yc;
    if (dx.abs() < 1e-8) return double.infinity;
    return -dx / dy;
  }

  // Local quadratic derivative adaptive (stub)
  double localQuadraticDerivativeAdaptive(List<Offset> pts, Offset point) {
    // Simple finite difference as placeholder
    if (pts.length < 3) return 0.0;
    final idx = pts.indexWhere((p) => (p - point).distance < 1.0);
    if (idx < 1 || idx > pts.length - 2) return 0.0;
    final prev = pts[idx - 1], next = pts[idx + 1];
    return (next.dy - prev.dy) / (next.dx - prev.dx == 0 ? 1e-8 : next.dx - prev.dx);
  }

  // PCA tangent (stub)
  Map pcaTangent(List<Offset> pts) {
    // Simple linear regression as placeholder
    if (pts.length < 2) return {'slope': 0.0};
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final p in pts) {
      sumX += p.dx;
      sumY += p.dy;
      sumXY += p.dx * p.dy;
      sumX2 += p.dx * p.dx;
    }
    final n = pts.length;
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    return {'slope': slope};
  }

  // Robust local slope adaptive (stub)
  double robustLocalSlopeAdaptive(List<Offset> pts) {
    if (pts.length < 2) return 0.0;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final p in pts) {
      sumX += p.dx;
      sumY += p.dy;
      sumXY += p.dx * p.dy;
      sumX2 += p.dx * p.dx;
    }
    final n = pts.length;
    return (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
  }
}