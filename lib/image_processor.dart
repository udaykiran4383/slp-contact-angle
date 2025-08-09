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

    // baseline candidates: bottom strip edges + bottom-of-mask points
    final baselineCandidates = _collectBaselineCandidatesFromRGBA(rgba, width, height, mask);

    // compute baseline via RANSAC and intersections
    final baselineFit = AngleUtils.fitLineRANSAC(baselineCandidates, iterations: 350, inlierThresh: 3.0);
    final m = baselineFit['m']!;
    final c = baselineFit['c']!;

    // find intersections of contour segments with baseline (left & right)
    final intersections = <Offset>[];
    for (int i = 0; i < smooth.length; i++) {
      final p1 = smooth[i];
      final p2 = smooth[(i + 1) % smooth.length];
      final ip = AngleUtils.intersectSegmentWithBaseline(p1, p2, m, c);
      if (ip != null) intersections.add(ip);
    }

    // if none found, fallback to bottom-most extremes of contour
    Offset leftApprox, rightApprox;
    if (intersections.isEmpty) {
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

    // Build baseline endpoints in original coordinates (use width of orig image)
    final baselineStart = Offset(0, (m * 0 + c));
    final baselineEnd = Offset(origW.toDouble(), (m * origW + c));
    
    return ProcessedImageData(
      boundary: origContour,
      baseline: BaselineData(startPoint: baselineStart, endPoint: baselineEnd, m: m, c: c),
      leftContact: leftRefined,
      rightContact: rightRefined,
      leftAngle: leftAngle,
      rightAngle: rightAngle,
      avgAngle: avgAngle,
      debug: debug ? {
        'downscale': scale,
        'width': width,
        'height': height,
        'baseline_m': m,
        'baseline_c': c,
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
  final Map<String, dynamic>? debug;

  ProcessedImageData({
    required this.boundary,
    required this.baseline,
    required this.leftContact,
    required this.rightContact,
    required this.leftAngle,
    required this.rightAngle,
    required this.avgAngle,
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