
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

// --- Robust RANSAC line fit with optional prior ---
Map<String, double> fitLineRANSACRefined(
  List<Offset> pts, {
  int iterations = 600,
  double inlierThresh = 2.5,
  double? slopePrior,
  double slopePriorWeight = 0.0,
}) {
  if (pts.length < 2) {
    return {
      'm': 0.0,
      'c': pts.isNotEmpty ? pts.first.dy : 0.0,
      'inliers': 0.0,
    };
  }
  final rnd = Random();
  double bestM = 0.0, bestC = 0.0;
  int bestInliers = -1;
  for (int it = 0; it < iterations; it++) {
    final a = pts[rnd.nextInt(pts.length)];
    final b = pts[rnd.nextInt(pts.length)];
    if ((a - b).distance < 1e-8 || (b.dx - a.dx).abs() < 1e-9) continue;
    double m = (b.dy - a.dy) / (b.dx - a.dx);
    double c = a.dy - m * a.dx;
    if (slopePrior != null && slopePriorWeight > 0.0) {
      m = (m + slopePriorWeight * slopePrior) / (1.0 + slopePriorWeight);
      c = a.dy - m * a.dx;
    }
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
  return {'m': bestM, 'c': bestC, 'inliers': bestInliers.toDouble()};
}

// --- Subpixel boundary refinement (gradient along normal) ---
Offset subpixelRefineFromRGBA({
  required Uint8List rgba,
  required int width,
  required int height,
  required Offset approx,
  required Offset normal,
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
  double dt = denom.abs() > 1e-8 ? ((y1 - y3) / denom).clamp(-1.0, 1.0) : 0.0;
  final tPeak = (imax - mid) * spacing + dt * spacing;
  return Offset(approx.dx + normal.dx * tPeak, approx.dy + normal.dy * tPeak);
}

double _bilinearSampleGray(Uint8List pixels, int width, int height, double x, double y) {
  x = x.clamp(0.0, width - 2.0);
  y = y.clamp(0.0, height - 2.0);
  final x0 = x.floor(), y0 = y.floor();
  final x1 = x0 + 1, y1 = y0 + 1;
  final dx = x - x0, dy = y - y0;
  int at(int xi, int yi, int ch) => pixels[(yi * width + xi) * 4 + ch];
  double gray(int xi, int yi) => 0.299 * at(xi, yi, 0) + 0.587 * at(xi, yi, 1) + 0.114 * at(xi, yi, 2);
  final c00 = gray(x0, y0);
  final c10 = gray(x1, y0);
  final c01 = gray(x0, y1);
  final c11 = gray(x1, y1);
  return (1 - dx) * (1 - dy) * c00 + dx * (1 - dy) * c10 + (1 - dx) * dy * c01 + dx * dy * c11;
}

// --- Algebraic Circle Fit (Kåsa) ---
Map<String, double>? fitCircleKasa(List<Offset> pts) {
  if (pts.length < 6) return null;
  double Sx = 0, Sy = 0, Sxx = 0, Syy = 0, Sxy = 0;
  for (final p in pts) {
    Sx += p.dx;
    Sy += p.dy;
    Sxx += p.dx * p.dx;
    Syy += p.dy * p.dy;
    Sxy += p.dx * p.dy;
  }
  final N = pts.length;
  final C = N * Sxx - Sx * Sx;
  final D = N * Sxy - Sx * Sy;
  final E = N * Syy - Sy * Sy;
  double G = 0, H = 0;
  for (final p in pts) {
    G += (p.dx * p.dx + p.dy * p.dy) * p.dx;
    H += (p.dx * p.dx + p.dy * p.dy) * p.dy;
  }
  G = 0.5 * (N * G - Sx * (Sxx + Syy));
  H = 0.5 * (N * H - Sy * (Sxx + Syy));
  final denom = (C * E - D * D);
  if (denom.abs() < 1e-12) return null;
  final xc = (G * E - D * H) / denom;
  final yc = (C * H - D * G) / denom;
  final distances = pts.map((p) => sqrt(pow(p.dx - xc, 2) + pow(p.dy - yc, 2))).toList();
  distances.sort();
  final keep = max(3, (distances.length * 0.6).floor());
  final r = distances.take(keep).reduce((a, b) => a + b) / keep;
  return {'xc': xc, 'yc': yc, 'r': r};
}

// --- Tangent slope from provided circle at point ---
double tangentSlopeFromCircleAtPoint(Map<String, double> circle, Offset pt) {
  final xc = circle['xc']!;
  final yc = circle['yc']!;
  final dx = pt.dx - xc;
  final dy = pt.dy - yc;
  if (dy.abs() < 1e-12) return dx < 0 ? double.infinity * -1.0 : double.infinity;
  return -dx / dy;
}

// --- Contact angle between two slopes, in degrees ---
double contactAngleDegreesFromSlopes(double tangentSlope, double baselineSlope) {
  final v1 = Offset(1.0, -tangentSlope);
  final v2 = Offset(1.0, -baselineSlope);
  final dot = v1.dx * v2.dx + v1.dy * v2.dy;
  final mag = (v1.distance * v2.distance) + 1e-12;
  double cosT = dot / mag;
  cosT = cosT.clamp(-1.0, 1.0);
  final acute = acos(cosT) * 180.0 / pi;
  return 180.0 - acute;
}

// --- Find intersection of contour segment with baseline ---
Offset? intersectSegmentWithBaseline(
    Offset p1, Offset p2, double m, double c,
    {double eps = 1e-5}) {
  final y1 = m * p1.dx + c;
  final y2 = m * p2.dx + c;
  if (((p1.dy - y1) * (p2.dy - y2)) > 0) return null; // must straddle
  double t = (y1 - p1.dy) / ((p2.dy - p1.dy) - (y2 - y1) + eps);
  t = t.clamp(0.0, 1.0);
  return Offset(
    p1.dx + t * (p2.dx - p1.dx),
    p1.dy + t * (p2.dy - p1.dy),
  );
}
