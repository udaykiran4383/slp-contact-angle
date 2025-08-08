// lib/processing/angle_utils.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';

/// Compute tangent slope (dy/dx) at global point (x0,y0) on an ellipse.
/// ellipse parameters:
///  - center (h,k)
///  - a: semi-major axis
///  - b: semi-minor axis
///  - phi: rotation of ellipse in radians (counter-clockwise)
double ellipseTangentSlope({
  required double x0,
  required double y0,
  required double h,
  required double k,
  required double a,
  required double b,
  required double phi,
}) {
  final dx = x0 - h;
  final dy = y0 - k;
  final c = cos(phi);
  final s = sin(phi);

  final xr = dx * c + dy * s;
  final yr = -dx * s + dy * c;

  final dFdxr = 2.0 * xr / (a * a);
  final dFdyr = 2.0 * yr / (b * b);

  final dFdx = dFdxr * c - dFdyr * s;
  final dFdy = dFdxr * s + dFdyr * c;

  if (dFdy.abs() < 1e-12) return 1e12;
  return -dFdx / dFdy;
}

/// Angle between two slopes (m1,m2) in degrees in [0,180]
double contactAngleDegFromSlopes(double mT, double mB) {
  double a1 = atan(mT.isFinite ? mT : (mT > 0 ? 1e12 : -1e12));
  double a2 = atan(mB.isFinite ? mB : (mB > 0 ? 1e12 : -1e12));
  double diff = (a1 - a2).abs();
  if (diff > pi) diff = 2 * pi - diff;
  return diff * 180.0 / pi;
}

/// Bilinear sample helper: samples a grayscale intensity at subpixel (x,y).
double _bilinearSampleGray(Uint8List pixels, int width, int height, double x, double y) {
  if (x < 0 || x >= width - 1 || y < 0 || y >= height - 1) {
    final xi = x.clamp(0.0, width - 1.0);
    final yi = y.clamp(0.0, height - 1.0);
    final idx = (yi.toInt() * width + xi.toInt()) * 4;
    final r = pixels[idx];
    final g = pixels[idx + 1];
    final b = pixels[idx + 2];
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }
  final x0 = x.floor();
  final y0 = y.floor();
  final x1 = x0 + 1;
  final y1 = y0 + 1;
  final dx = x - x0;
  final dy = y - y0;

  final idx00 = (y0 * width + x0) * 4;
  final idx10 = (y0 * width + x1) * 4;
  final idx01 = (y1 * width + x0) * 4;
  final idx11 = (y1 * width + x1) * 4;

  final r00 = pixels[idx00 + 0];
  final g00 = pixels[idx00 + 1];
  final b00 = pixels[idx00 + 2];

  final r10 = pixels[idx10 + 0];
  final g10 = pixels[idx10 + 1];
  final b10 = pixels[idx10 + 2];

  final r01 = pixels[idx01 + 0];
  final g01 = pixels[idx01 + 1];
  final b01 = pixels[idx01 + 2];

  final r11 = pixels[idx11 + 0];
  final g11 = pixels[idx11 + 1];
  final b11 = pixels[idx11 + 2];

  double r = (1 - dx) * (1 - dy) * r00 +
      dx * (1 - dy) * r10 +
      (1 - dx) * dy * r01 +
      dx * dy * r11;
  double g = (1 - dx) * (1 - dy) * g00 +
      dx * (1 - dy) * g10 +
      (1 - dx) * dy * g01 +
      dx * dy * g11;
  double b = (1 - dx) * (1 - dy) * b00 +
      dx * (1 - dy) * b10 +
      (1 - dx) * dy * b01 +
      dx * dy * b11;

  return 0.299 * r + 0.587 * g + 0.114 * b;
}

/// Subpixel refinement: samples grayscale along the normal vector centered at approxPoint.
///
/// - [img]: ui.Image of the source image (must call `await img.toByteData(format: ui.ImageByteFormat.rawRgba)` inside)
/// - [approxPoint]: approximate contact point in image coordinates
/// - [normal]: normalized direction (unit-length) pointing outward along which to sample (normal to contour)
/// - [samples]: odd number of samples (default 21)
/// - [spacing]: pixel spacing between samples
Future<Offset> subpixelRefineContact({
  required ui.Image img,
  required Offset approxPoint,
  required Offset normal,
  int samples = 21,
  double spacing = 1.0,
}) async {
  assert(samples % 2 == 1);
  final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bd == null) return approxPoint;
  final Uint8List pixels = bd.buffer.asUint8List();
  final int width = img.width;
  final int height = img.height;

  final int mid = samples ~/ 2;
  final List<double> intens = List<double>.filled(samples, 0.0);

  for (int i = 0; i < samples; i++) {
    final t = (i - mid) * spacing;
    final sx = approxPoint.dx + normal.dx * t;
    final sy = approxPoint.dy + normal.dy * t;
    intens[i] = _bilinearSampleGray(pixels, width, height, sx, sy);
  }

  final List<double> grad = List<double>.filled(samples, 0.0);
  for (int i = 1; i < samples - 1; i++) {
    grad[i] = (intens[i + 1] - intens[i - 1]) / 2.0;
  }

  int imax = 1;
  double best = grad[1].abs();
  for (int i = 2; i < samples - 1; i++) {
    final d = grad[i].abs();
    if (d > best) {
      best = d;
      imax = i;
    }
  }

  if (imax <= 0 || imax >= samples - 1) return approxPoint;

  final double y1 = grad[imax - 1];
  final double y2 = grad[imax];
  final double y3 = grad[imax + 1];
  final double denom = 2.0 * (y1 - 2.0 * y2 + y3);
  double dt = 0.0;
  if (denom.abs() > 1e-8) {
    dt = (y1 - y3) / denom;
    dt = dt.clamp(-1.0, 1.0);
  }

  final double tPeak = (imax - mid) * spacing + dt * spacing;
  final Offset refined = approxPoint + Offset(normal.dx * tPeak, normal.dy * tPeak);
  return refined;
}
