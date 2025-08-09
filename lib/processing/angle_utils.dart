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

  // Intersection of line segment p1->p2 with baseline y = m*x + c (subpixel)
  static Offset? intersectSegmentWithBaseline(Offset p1, Offset p2, double m, double c) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final denom = dy - m * dx;
    if (denom.abs() < 1e-12) return null;
    final t = (m * p1.dx + c - p1.dy) / denom;
    if (t < 0.0 || t > 1.0) return null;
    return Offset(p1.dx + t * dx, p1.dy + t * dy);
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

  // Compute angle between tangent slope and baseline slope (returns degrees in [0,180])
  static double contactAngleDegreesFromSlopes(double tangentSlope, double baselineSlope) {
    // convert slopes to vectors with y-up (screen y-down => flip sign)
    final v1 = Offset(1.0, -tangentSlope);
    final v2 = Offset(1.0, -baselineSlope);
    final dot = v1.dx * v2.dx + v1.dy * v2.dy;
    final mag = (v1.distance * v2.distance) + 1e-12;
    double cosT = dot / mag;
    cosT = cosT.clamp(-1.0, 1.0);
    final angle = acos(cosT) * 180.0 / pi;
    return angle;
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