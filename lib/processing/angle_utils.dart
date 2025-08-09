// lib/processing/angle_utils.dart
// Robust geometry + subpixel helpers for fully-automatic contact angle measurement.

import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class AngleUtils {
  // RANSAC-like robust linear fit: y = m*x + c
  static Map<String, double> fitLineRANSAC(List<Offset> pts,
      {int iterations = 300, double inlierThresh = 3.0}) {
    if (pts.length < 2) return {'m': 0.0, 'c': pts.isNotEmpty ? pts.first.dy : 0.0};
    final rnd = Random();
    double bestM = 0.0, bestC = 0.0;
    int bestInliers = 0;
    for (int it = 0; it < iterations; it++) {
      final a = pts[rnd.nextInt(pts.length)];
      final b = pts[rnd.nextInt(pts.length)];
      if ((a - b).distance < 1e-6) continue;
      if ((b.dx - a.dx).abs() < 1e-9) continue;
      final m = (b.dy - a.dy) / (b.dx - a.dx);
      final c = a.dy - m * a.dx;
      int inliers = 0;
      for (final p in pts) {
        final dist = (m * p.dx - p.dy + c).abs() / sqrt(m * m + 1);
        if (dist <= inlierThresh) inliers++;
      }
      if (inliers > bestInliers) {
        bestInliers = inliers;
        bestM = m;
        bestC = c;
      }
    }
    return {'m': bestM, 'c': bestC};
  }

  // Refined robust fit: RANSAC with optional slope prior and final least-squares on inliers
  static Map<String, double> fitLineRANSACRefined(
    List<Offset> pts, {
    int iterations = 600,
    double inlierThresh = 2.5,
    double? slopePrior, // e.g., 0 for horizontal baseline
    double slopePriorWeight = 0.0, // set >0 to bias
  }) {
    if (pts.length < 2) return {'m': 0.0, 'c': pts.isNotEmpty ? pts.first.dy : 0.0};
    final rnd = Random(1337);
    double bestM = 0.0, bestC = 0.0;
    int bestInliers = -1;
    for (int it = 0; it < iterations; it++) {
      final a = pts[rnd.nextInt(pts.length)];
      final b = pts[rnd.nextInt(pts.length)];
      if ((a - b).distance < 1e-6) continue;
      // robust to near-vertical sample pairs by swapping role or skipping
      double m;
      if ((b.dx - a.dx).abs() < 1e-9) {
        // sample another pair
        continue;
      } else {
        m = (b.dy - a.dy) / (b.dx - a.dx);
      }
      double c = a.dy - m * a.dx;
      if (slopePrior != null && slopePriorWeight > 0.0) {
        // softly pull m toward prior
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
        // refine with least squares on inliers
        final inlierPts = inlierIdx.map((i) => pts[i]).toList();
        final lc = _leastSquaresLine(inlierPts, slopePrior: slopePrior, slopePriorWeight: slopePriorWeight);
        bestM = lc['m']!;
        bestC = lc['c']!;
      }
    }
    return {'m': bestM, 'c': bestC};
  }

  // Ordinary least squares fit for y = m*x + c, with optional L2 slope prior
  static Map<String, double> _leastSquaresLine(List<Offset> pts, {double? slopePrior, double slopePriorWeight = 0.0}) {
    if (pts.length < 2) return {'m': 0.0, 'c': pts.isNotEmpty ? pts.first.dy : 0.0};
    double Sx = 0, Sy = 0, Sxx = 0, Sxy = 0;
    final n = pts.length.toDouble();
    for (final p in pts) {
      Sx += p.dx;
      Sy += p.dy;
      Sxx += p.dx * p.dx;
      Sxy += p.dx * p.dy;
    }
    // With optional ridge on slope toward slopePrior
    final lambda = slopePrior != null ? slopePriorWeight : 0.0;
    final b = Sxy - (Sx * Sy) / n + (lambda * (slopePrior ?? 0.0));
    final a = Sxx - (Sx * Sx) / n + lambda;
    final m = a.abs() < 1e-12 ? 0.0 : (b / a);
    final c = (Sy - m * Sx) / n;
    return {'m': m, 'c': c};
  }

  // Intersection of line segment p1->p2 with baseline y = m*x + c (subpixel)
  // If there is no strict crossing but the segment lies within 'eps' distance
  // from the baseline, returns the closest point on the segment.
  static Offset? intersectSegmentWithBaseline(Offset p1, Offset p2, double m, double c, {double eps = 2.0}) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final denom = dy - m * dx;
    // signed distances of endpoints to line
    double distSigned(Offset p) => (m * p.dx - p.dy + c) / sqrt(m * m + 1);
    final d1 = distSigned(p1);
    final d2 = distSigned(p2);
    // true crossing
    if (denom.abs() >= 1e-12) {
      final t = (m * p1.dx + c - p1.dy) / denom;
      if (t >= 0.0 && t <= 1.0) return Offset(p1.dx + t * dx, p1.dy + t * dy);
    }
    // near-miss: return closest point on segment if within eps
    final denomLen2 = dx * dx + dy * dy;
    if (denomLen2 <= 1e-12) return null;
    // Closest point from infinite line to segment endpoints? Use projection of the
    // baseline's perpendicular foot onto the segment via t*.
    // We can find t* minimizing |(m x - y + c)| along the segment parameterized by t.
    // Approximate by checking endpoints and mid.
    final mid = Offset((p1.dx + p2.dx) * 0.5, (p1.dy + p2.dy) * 0.5);
    final dMid = distSigned(mid).abs();
    final best = <MapEntry<double, Offset>>[
      MapEntry(d1.abs(), p1),
      MapEntry(d2.abs(), p2),
      MapEntry(dMid, mid),
    ]..sort((a, b) => a.key.compareTo(b.key));
    if (best.first.key <= eps) return best.first.value;
    return null;
  }

  // Local quadratic least-squares fit and derivative at x0
  // returns dy/dx at x0
  static double localQuadraticDerivative(List<Offset> pts, double x0) {
    if (pts.length < 2) return 0.0;
    final p = List<Offset>.from(pts)..sort((a, b) => a.dx.compareTo(b.dx));
    final n = p.length;
    double Sx = 0, Sx2 = 0, Sx3 = 0, Sx4 = 0;
    double Sy = 0, Sxy = 0, Sx2y = 0;
    for (final o in p) {
      final x = o.dx;
      final y = o.dy;
      final x2 = x * x;
      final x3 = x2 * x;
      final x4 = x3 * x;
      Sx += x;
      Sx2 += x2;
      Sx3 += x3;
      Sx4 += x4;
      Sy += y;
      Sxy += x * y;
      Sx2y += x2 * y;
    }
    // normal eqns 3x3
    final m00 = Sx4, m01 = Sx3, m02 = Sx2;
    final m10 = Sx3, m11 = Sx2, m12 = Sx;
    final m20 = Sx2, m21 = Sx, m22 = n.toDouble();
    final det = m00 * (m11 * m22 - m12 * m21) -
        m01 * (m10 * m22 - m12 * m20) +
        m02 * (m10 * m21 - m11 * m20);
    if (det.abs() < 1e-12) {
      // fallback linear
      final first = p.first;
      final last = p.last;
      final dx = last.dx - first.dx;
      if (dx.abs() < 1e-12) return 0.0;
      return (last.dy - first.dy) / dx;
    }
    final b0 = Sx2y, b1 = Sxy, b2 = Sy;
    final detA = b0 * (m11 * m22 - m12 * m21) -
        m01 * (b1 * m22 - m12 * b2) +
        m02 * (b1 * m21 - m11 * b2);
    final detB = m00 * (b1 * m22 - m12 * b2) -
        b0 * (m10 * m22 - m12 * m20) +
        m02 * (m10 * b2 - b1 * m20);
    final a = detA / det;
    final b = detB / det;
    return 2.0 * a * x0 + b;
  }

  // Adaptive local quadratic derivative: fits y(x) or x(y) based on local orientation
  // Returns dy/dx at the neighborhood around 'at' point.
  static double localQuadraticDerivativeAdaptive(List<Offset> pts, Offset at) {
    if (pts.length < 3) {
      // fallback to simple two-point slope if possible
      if (pts.length >= 2) {
        final a = pts.first;
        final b = pts.last;
        final dx = b.dx - a.dx;
        if (dx.abs() < 1e-12) return double.infinity;
        return (b.dy - a.dy) / dx;
      }
      return 0.0;
    }
    double meanX = 0, meanY = 0;
    for (final p in pts) {
      meanX += p.dx;
      meanY += p.dy;
    }
    meanX /= pts.length;
    meanY /= pts.length;
    double varX = 0, varY = 0;
    for (final p in pts) {
      varX += (p.dx - meanX) * (p.dx - meanX);
      varY += (p.dy - meanY) * (p.dy - meanY);
    }
    // If horizontal spread dominates, fit y(x); else fit x(y) and invert
    if (varX >= varY) {
      return localQuadraticDerivative(pts, at.dx);
    } else {
      // Fit x as a quadratic function of y, then invert to dy/dx = 1 / (dx/dy)
      final p = List<Offset>.from(pts)..sort((a, b) => a.dy.compareTo(b.dy));
      final n = p.length;
      double Sy = 0, Sy2 = 0, Sy3 = 0, Sy4 = 0;
      double Sx = 0, Sxy = 0, Sy2x = 0;
      for (final o in p) {
        final y = o.dy;
        final x = o.dx;
        final y2 = y * y;
        final y3 = y2 * y;
        final y4 = y3 * y;
        Sy += y;
        Sy2 += y2;
        Sy3 += y3;
        Sy4 += y4;
        Sx += x;
        Sxy += x * y;
        Sy2x += y2 * x;
      }
      final m00 = Sy4, m01 = Sy3, m02 = Sy2;
      final m10 = Sy3, m11 = Sy2, m12 = Sy;
      final m20 = Sy2, m21 = Sy, m22 = n.toDouble();
      final det = m00 * (m11 * m22 - m12 * m21) -
          m01 * (m10 * m22 - m12 * m20) +
          m02 * (m10 * m21 - m11 * m20);
      if (det.abs() < 1e-12) {
        // linear fallback in y
        final first = p.first;
        final last = p.last;
        final dy = last.dy - first.dy;
        if (dy.abs() < 1e-12) return 0.0;
        final dxdy = (last.dx - first.dx) / dy;
        return dxdy.abs() < 1e-12 ? double.infinity : 1.0 / dxdy;
      }
      final b0 = Sy2x, b1 = Sxy, b2 = Sx;
      final detA = b0 * (m11 * m22 - m12 * m21) -
          m01 * (b1 * m22 - m12 * b2) +
          m02 * (b1 * m21 - m11 * b2);
      final detB = m00 * (b1 * m22 - m12 * b2) -
          b0 * (m10 * m22 - m12 * m20) +
          m02 * (m10 * b2 - b1 * m20);
      final a = detA / det; // x = a*y^2 + b*y + c => dx/dy = 2*a*y + b
      final b = detB / det;
      final dxdy = 2.0 * a * at.dy + b;
      if (dxdy.abs() < 1e-12) return double.infinity;
      return 1.0 / dxdy;
    }
  }

  // Algebraic circle fit (Kåsa method) for robust tangent estimation near contact
  // Returns {xc, yc, r, sse}
  static Map<String, double>? fitCircleKasa(List<Offset> pts) {
    if (pts.length < 6) return null;
    double Sx = 0, Sy = 0, Sxx = 0, Syy = 0, Sxy = 0, Sxxx = 0, Sxxy = 0, Sxyy = 0, Syyy = 0;
    final n = pts.length.toDouble();
    for (final p in pts) {
      final x = p.dx;
      final y = p.dy;
      final x2 = x * x, y2 = y * y;
      Sx += x;
      Sy += y;
      Sxx += x2;
      Syy += y2;
      Sxy += x * y;
      Sxxx += x2 * x;
      Sxxy += x2 * y;
      Sxyy += x * y2;
      Syyy += y2 * y;
    }
    final C = n * Sxx - Sx * Sx;
    final D = n * Sxy - Sx * Sy;
    final E = n * Syy - Sy * Sy;
    final G = 0.5 * (n * (Sxxx + Sxyy) - Sx * (Sxx + Syy));
    final H = 0.5 * (n * (Sxxy + Syyy) - Sy * (Sxx + Syy));
    final denom = (C * E - D * D);
    if (denom.abs() < 1e-12) return null;
    final a = (G * E - D * H) / denom;
    final b = (C * H - D * G) / denom;
    final xc = a;
    final yc = b;
    // robust trimming: compute distances, drop top 20% largest residuals, recompute r and sse
    final distances = <double>[];
    for (final p in pts) {
      final dx = p.dx - xc;
      final dy = p.dy - yc;
      distances.add(sqrt(dx * dx + dy * dy));
    }
    final sorted = List<double>.from(distances)..sort();
    final keep = max(3, (sorted.length * 0.6).floor());
    final r = sorted.take(keep).reduce((a, b) => a + b) / keep;
    double sse = 0.0;
    for (int i = 0; i < keep; i++) {
      final d = sorted[i];
      final e2 = (d - r) * (d - r);
      sse += e2;
    }
    final sseN = sse / keep;
    return {'xc': xc, 'yc': yc, 'r': r, 'sse': sse, 'sseN': sseN, 'count': keep.toDouble()};
  }

  // Pratt circle fit (approximate Taubin) for improved numerical stability
  static Map<String, double>? fitCirclePratt(List<Offset> pts) {
    if (pts.length < 6) return null;
    double meanX = 0, meanY = 0;
    for (final p in pts) { meanX += p.dx; meanY += p.dy; }
    meanX /= pts.length; meanY /= pts.length;
    // shift to mean
    final zx = <double>[]; final zy = <double>[]; final z2 = <double>[];
    for (final p in pts) { final x = p.dx - meanX; final y = p.dy - meanY; zx.add(x); zy.add(y); z2.add(x*x + y*y); }
    double Suu = 0, Suv = 0, Svv = 0, Suuu = 0, Svvv = 0, Suvv = 0, Svuu = 0;
    for (int i = 0; i < pts.length; i++) {
      final u = zx[i], v = zy[i], w = z2[i];
      Suu += u*u; Svv += v*v; Suv += u*v;
      Suuu += u*u*u; Svvv += v*v*v; Suvv += u*v*v; Svuu += v*u*u;
    }
    final A = [[Suu, Suv],[Suv, Svv]];
    final Bx = 0.5 * (Suuu + Suvv);
    final By = 0.5 * (Svvv + Svuu);
    final det = A[0][0]*A[1][1] - A[0][1]*A[1][0];
    if (det.abs() < 1e-12) return null;
    final uc = (Bx*A[1][1] - By*A[0][1]) / det;
    final vc = (By*A[0][0] - Bx*A[1][0]) / det;
    final xc = uc + meanX;
    final yc = vc + meanY;
    double r = 0.0; for (final p in pts) { final dx = p.dx - xc; final dy = p.dy - yc; r += sqrt(dx*dx + dy*dy); }
    r /= pts.length;
    // compute residual
    double sse = 0.0; for (final p in pts) { final dx = p.dx - xc; final dy = p.dy - yc; final d = sqrt(dx*dx + dy*dy); final e = d - r; sse += e*e; }
    final sseN = sse / pts.length;
    return {'xc': xc, 'yc': yc, 'r': r, 'sse': sse, 'sseN': sseN, 'count': pts.length.toDouble()};
  }

  // Tangent slope at point for fitted circle (screen coord, y-down): dy/dx = - (x - xc) / (y - yc)
  static double tangentSlopeFromCircleAtPoint(Map<String, double> circle, Offset pt) {
    final xc = circle['xc']!;
    final yc = circle['yc']!;
    final dx = pt.dx - xc;
    final dy = pt.dy - yc;
    if (dy.abs() < 1e-12) return double.infinity * (dx.isNegative ? -1.0 : 1.0);
    return -dx / dy;
  }

  // Robust local slope using Theil-Sen median across neighbors
  static double robustLocalSlopeAdaptive(List<Offset> pts) {
    if (pts.length < 3) {
      if (pts.length >= 2) {
        final a = pts.first;
        final b = pts.last;
        final dx = b.dx - a.dx;
        if (dx.abs() < 1e-12) return double.infinity;
        return (b.dy - a.dy) / dx;
      }
      return 0.0;
    }
    double meanX = 0, meanY = 0;
    for (final p in pts) { meanX += p.dx; meanY += p.dy; }
    meanX /= pts.length; meanY /= pts.length;
    double varX = 0, varY = 0;
    for (final p in pts) { varX += (p.dx - meanX)*(p.dx - meanX); varY += (p.dy - meanY)*(p.dy - meanY); }
    final isXDominant = varX >= varY;
    final slopes = <double>[];
    for (int i = 0; i < pts.length; i++) {
      for (int j = i + 1; j < pts.length; j++) {
        final a = pts[i];
        final b = pts[j];
        if (isXDominant) {
          final dx = b.dx - a.dx; if (dx.abs() < 1e-9) continue; slopes.add((b.dy - a.dy) / dx);
        } else {
          final dy = b.dy - a.dy; if (dy.abs() < 1e-9) continue; final dxdy = (b.dx - a.dx) / dy; slopes.add(1.0 / dxdy);
        }
      }
    }
    if (slopes.isEmpty) return 0.0;
    slopes.sort();
    return slopes[slopes.length ~/ 2];
  }

  // PCA-based tangent: returns {slope, varAlong, varAcross}
  static Map<String, double> pcaTangent(List<Offset> pts) {
    if (pts.length < 2) return {'slope': 0.0, 'varAlong': 0.0, 'varAcross': 0.0};
    double meanX = 0, meanY = 0;
    for (final p in pts) { meanX += p.dx; meanY += p.dy; }
    meanX /= pts.length; meanY /= pts.length;
    // covariance matrix
    double sxx = 0, syy = 0, sxy = 0;
    for (final p in pts) {
      final dx = p.dx - meanX; final dy = p.dy - meanY;
      sxx += dx * dx; syy += dy * dy; sxy += dx * dy;
    }
    sxx /= pts.length; syy /= pts.length; sxy /= pts.length;
    // eigen decomposition of [[sxx, sxy],[sxy, syy]]
    final trace = sxx + syy;
    final det = sxx * syy - sxy * sxy;
    final disc = (trace * trace - 4 * det).clamp(0.0, double.infinity);
    final root = sqrt(disc);
    final lambda1 = 0.5 * (trace + root); // max eigenvalue
    final lambda2 = 0.5 * (trace - root); // min eigenvalue
    // eigenvector for lambda1
    double vx, vy;
    if (sxy.abs() > 1e-12) {
      vx = lambda1 - syy; vy = sxy; // from (sxx - l)v_x + sxy v_y = 0 => pick v=(l-syy, sxy)
    } else {
      // diagonal matrix
      if (sxx >= syy) { vx = 1.0; vy = 0.0; } else { vx = 0.0; vy = 1.0; }
    }
    final norm = sqrt(vx * vx + vy * vy) + 1e-12;
    vx /= norm; vy /= norm;
    final slope = (vx.abs() < 1e-12) ? double.infinity : (vy / vx);
    return {'slope': slope, 'varAlong': lambda1, 'varAcross': lambda2};
  }

  // 2D rotation utilities
  static Offset rotatePoint(Offset p, double radians) {
    final c = cos(radians), s = sin(radians);
    return Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c);
  }

  static List<Offset> rotatePoints(List<Offset> pts, double radians) {
    if (pts.isEmpty) return pts;
    final c = cos(radians), s = sin(radians);
    return pts
        .map((p) => Offset(p.dx * c - p.dy * s, p.dx * s + p.dy * c))
        .toList();
  }

  // Theil–Sen robust slope in rotated coordinates (y' vs x')
  static double robustSlopeRotated(List<Offset> ptsRot) {
    if (ptsRot.length < 2) return 0.0;
    final slopes = <double>[];
    for (int i = 0; i < ptsRot.length; i++) {
      for (int j = i + 1; j < ptsRot.length; j++) {
        final a = ptsRot[i];
        final b = ptsRot[j];
        final dx = b.dx - a.dx;
        if (dx.abs() < 1e-9) continue;
        slopes.add((b.dy - a.dy) / dx);
      }
    }
    if (slopes.isEmpty) return 0.0;
    slopes.sort();
    return slopes[slopes.length ~/ 2];
  }

  // Compute angle between tangent slope and baseline slope (returns degrees in [0,180])
  static double contactAngleDegreesFromSlopes(double tangentSlope, double baselineSlope) {
    // convert slopes to vectors with y-up (screen y-down => flip sign)
    final v1 = Offset(1.0, -tangentSlope);
    final v2 = Offset(1.0, -baselineSlope);
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag = (v1.distance * v2.distance) + 1e-12;
    double cosT = dot / mag;
    cosT = cosT.clamp(-1.0, 1.0);
    final acute = acos(cosT) * 180.0 / pi; // [0,180]
    // Contact angle measured through the liquid phase (inside droplet)
    final inside = 180.0 - acute;
    return inside;
  }

  // Subpixel refinement by sampling grayscale along normal and finding gradient peak
  // pixels: raw rgba bytes, width,height
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

  // sample along normal, compute gradient, find peak: returns refined offset along normal
  static Offset subpixelRefineFromRGBA({
    required Uint8List rgba,
    required int width,
    required int height,
    required Offset approx,
    required Offset normal, // should be unit
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
}