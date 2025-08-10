// lib/widgets/image_annotator_improved.dart
// Fully automatic UI: loads image, runs pipeline automatically, displays annotated overlays.
// Minimal user interaction: a "Process" button or auto-run on example load.

import 'dart:ui' as ui;
import 'dart:io' as io;
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import '../image_processor.dart';
import '../processing/angle_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_svg/flutter_svg.dart';

class ImageAnnotatorScreen extends StatefulWidget {
  const ImageAnnotatorScreen({super.key});
  @override
  State<ImageAnnotatorScreen> createState() => _ImageAnnotatorScreenState();
}

class _ImageAnnotatorScreenState extends State<ImageAnnotatorScreen> with SingleTickerProviderStateMixin {
  ui.Image? _image;
  ProcessedImageData? _processed;
  bool _loading = false;
  bool _debug = false; // keep flag but default to no debug noise
  final ImagePicker _picker = ImagePicker();
  late final AnimationController _logoController;

  @override
  void initState() {
    super.initState();
    // Optionally auto-load an example asset here if you have one.
    _logoController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  }

  @override
  void dispose() {
    _logoController.dispose();
    super.dispose();
  }

  Future<void> _processImage(ui.Image img) async {
    setState(() => _loading = true);
    final res = await ImageProcessor.processDropletImageAuto(img, debug: _debug);
    setState(() {
      _image = img;
      _processed = res;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/contact_angle_icon.svg',
              width: 22,
              height: 22,
            ),
            const SizedBox(width: 8),
            const Text('Automatic Contact Angle'),
          ],
        ),
        actions: [
          if (_image != null && _processed != null)
            IconButton(
              icon: const Icon(Icons.save_alt),
              tooltip: 'Save annotated PNG',
              onPressed: _saveAnnotated,
            ),
        ],
      ),
      body: Center(
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RotationTransition(
                    turns: _logoController,
                    child: SvgPicture.asset(
                      'assets/contact_angle_icon.svg',
                      width: 96,
                      height: 96,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Processing...', style: TextStyle(color: Colors.white70)),
                ],
              )
            : (_image == null)
                ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      ElevatedButton.icon(
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Pick image & Auto-process'),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadExampleImage,
                        child: const Text('Load example image & Auto-process'),
                      ),
                      const SizedBox(height: 12),
                      const Text('Or programmatically call processImage with an image'),
                    ],
                  )
                : InteractiveViewer(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: _image!.width.toDouble(),
                        height: _image!.height.toDouble(),
                        child: Stack(children: [
                          RawImage(image: _image),
                          if (_processed != null)
                            CustomPaint(
                              size: Size(_image!.width.toDouble(), _image!.height.toDouble()),
                              painter: _OverlayPainter(processed: _processed!, showDebug: _debug),
                            ),
                          if (_processed != null)
                            Positioned(
                              left: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                color: Colors.black54,
                                child: Text(
                                  'L: ${_processed!.leftAngle.toStringAsFixed(2)}°  '
                                  'R: ${_processed!.rightAngle.toStringAsFixed(2)}°  '
                                  'Avg: ${_processed!.avgAngle.toStringAsFixed(2)}°  '
                                  'Best(${_processed!.bestSide[0].toUpperCase()}): ${_processed!.bestAngle.toStringAsFixed(2)}°',
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                        ]),
                      ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadExampleImage() async {
    // Try to load asset 'assets/example.jpg' (you can replace with your path)
    try {
      final data = await DefaultAssetBundle.of(context).load('assets/example.jpg');
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      await _processImage(frame.image);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No example asset found.')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final XFile? file = await _picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      await _processImage(frame.image);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick/process image: $e')),
        );
      }
    }
  }

  Future<void> _saveAnnotated() async {
    if (_image == null || _processed == null) return;
    try {
      final pngBytes = await _renderAnnotatedPng(_image!, _processed!, _debug);
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final path = '${dir.path}/contact_angle_annotated_$ts.png';
      final file = io.File(path);
      await file.writeAsBytes(pngBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved: $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
  }

  Future<Uint8List> _renderAnnotatedPng(ui.Image image, ProcessedImageData processed, bool showDebug) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    // draw background image
    canvas.drawImage(image, Offset.zero, Paint());
    // draw overlay via painter
    final painter = _OverlayPainter(processed: processed, showDebug: showDebug);
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final img = await picture.toImage(image.width, image.height);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}

class _OverlayPainter extends CustomPainter {
  final ProcessedImageData processed;
  final bool showDebug;
  _OverlayPainter({required this.processed, required this.showDebug});

  @override
  void paint(Canvas canvas, Size size) {
    final baselinePaint = Paint()..color = Colors.greenAccent..strokeWidth = 2.5;
    final contourPaint = Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1.2;
    final sphericalPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.6;
    final ptPaint = Paint()..color = Colors.orange..style = PaintingStyle.fill;
    final tanPaint = Paint()..color = Colors.redAccent..strokeWidth = 2.0;
    final dbgPaint = Paint()..color = Colors.cyanAccent.withValues(alpha: 0.9)..strokeWidth = 2.0;
    final dbgDim = Paint()..color = Colors.cyanAccent.withValues(alpha: 0.45)..strokeWidth = 1.5;

    // draw baseline with method-specific color
    final method = processed.debug?['baseline_method'] ?? 'unknown';
    switch (method) {
      case 'contact_points':
        baselinePaint.color = Colors.cyan; // Bright cyan for contact points method
        break;
      case 'mask_floor':
        baselinePaint.color = Colors.greenAccent;
        break;
      case 'contour_bottom':
        baselinePaint.color = Colors.blueAccent;
        break;
      case 'gradient_band':
        baselinePaint.color = Colors.purpleAccent;
        break;
      case 'global_stable':
        baselinePaint.color = Colors.orangeAccent;
        break;
      case 'intensity_profile_enhanced':
        baselinePaint.color = Colors.redAccent;
        break;
      case 'simple_fallback':
        baselinePaint.color = Colors.yellow; // Yellow for simple fallback
        break;
      default:
        baselinePaint.color = Colors.greenAccent;
    }
    
    // Draw baseline as dashed polyline across the frame
    final poly = processed.debug?['baseline_polyline'] as List<Offset>?;
    if (poly != null && poly.isNotEmpty) {
      final path = Path()..moveTo(poly.first.dx, poly.first.dy);
      for (int i = 1; i < poly.length; i++) path.lineTo(poly[i].dx, poly[i].dy);
      _drawDashedPath(canvas, path, baselinePaint, dashLength: 10, gapLength: 6);
    } else {
      canvas.drawLine(processed.baseline.startPoint, processed.baseline.endPoint, baselinePaint);
    }

    // Fill region above baseline lightly to mimic reference
    if (poly != null && poly.length >= 2) {
      final fillPath = Path();
      fillPath.moveTo(poly.first.dx, poly.first.dy);
      for (int i = 1; i < poly.length; i++) fillPath.lineTo(poly[i].dx, poly[i].dy);
      fillPath.lineTo(poly.last.dx, 0);
      fillPath.lineTo(poly.first.dx, 0);
      fillPath.close();
      final fillPaint = Paint()..color = Colors.redAccent.withValues(alpha: 0.18)..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);
    }

    // Draw only the clean droplet contour; remove noisy dashed overlays
    final c = processed.boundary;
    if (c.isNotEmpty) {
      final path = Path()..moveTo(c.first.dx, c.first.dy);
      for (int i = 1; i < c.length; i++) path.lineTo(c[i].dx, c[i].dy);
      path.close();
      canvas.drawPath(path, contourPaint);
    }

    // If available, draw spherical arc approximation as a dashed curve to emphasize circular boundary
    final enhanced = processed.enhancedBoundary;
    final arc = enhanced?['sphericalArc'] as List<Offset>?;
    if (arc != null && arc.length >= 2) {
      final arcPath = Path()..moveTo(arc.first.dx, arc.first.dy);
      for (int i = 1; i < arc.length; i++) arcPath.lineTo(arc[i].dx, arc[i].dy);
      _drawDashedPath(canvas, arcPath, sphericalPaint, dashLength: 8, gapLength: 5);
    }

    // contact points
    canvas.drawCircle(processed.leftContact, 5.0, ptPaint);
    canvas.drawCircle(processed.rightContact, 5.0, ptPaint);

    // tangents: compute small segment around each point using local derivative approach
    final leftSlope = AngleUtils.localQuadraticDerivative(
        _collectNeighborsForPaint(processed.boundary, processed.leftContact, k: 12), processed.leftContact.dx);
    final rightSlope = AngleUtils.localQuadraticDerivative(
        _collectNeighborsForPaint(processed.boundary, processed.rightContact, k: 12), processed.rightContact.dx);
    _drawTangent(canvas, processed.leftContact, leftSlope, tanPaint);
    _drawTangent(canvas, processed.rightContact, rightSlope, tanPaint);

    // angle labels near points
    final tp = TextPainter(
      text: TextSpan(
        text: '${processed.leftAngle.toStringAsFixed(1)}°',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, processed.leftContact + const Offset(8, -20));

    final tp2 = TextPainter(
      text: TextSpan(
        text: '${processed.rightAngle.toStringAsFixed(1)}°',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, processed.rightContact + const Offset(8, -20));

    // Suppress all debug overlays to remove visual noise
  }

  static List<Offset> _collectNeighborsForPaint(List<Offset> contour, Offset pt, {int k = 8}) {
    if (contour.isEmpty) return [pt];
    int idx = 0;
    double md = double.infinity;
    for (int i = 0; i < contour.length; i++) {
      final d = (contour[i] - pt).distance;
      if (d < md) {
        md = d;
        idx = i;
      }
    }
    final start = (idx - k).clamp(0, contour.length - 1);
    final end = (idx + k).clamp(0, contour.length - 1);
    final list = <Offset>[];
    for (int i = start; i <= end; i++) list.add(contour[i]);
    return list;
  }

  void _drawTangent(Canvas c, Offset pt, double slope, Paint p) {
    final vx = 1.0;
    final vy = -slope; // flip y
    final len = 60.0;
    final mag = sqrt(vx * vx + vy * vy);
    final v = Offset(vx / mag * len, vy / mag * len);
    c.drawLine(pt - v, pt + v, p);
  }

  // Intelligent automatic dashed path drawing with adaptive parameters
  void _drawDashedPath(Canvas canvas, Path path, Paint paint, {double? dashLength, double? gapLength}) {
    final pathMetrics = path.computeMetrics();
    
    for (final metric in pathMetrics) {
      // Automatically calculate optimal dash and gap lengths based on path characteristics
      final totalLength = metric.length;
      final autoDashLength = dashLength ?? _calculateOptimalDashLength(totalLength);
      final autoGapLength = gapLength ?? _calculateOptimalGapLength(totalLength, autoDashLength);
      
      // Adaptive drawing with intelligent segment handling
      double distance = 0.0;
      bool draw = true;
      int segmentCount = 0;
      
      while (distance < metric.length) {
        if (draw) {
          final start = metric.getTangentForOffset(distance)?.position;
          final end = metric.getTangentForOffset(min(distance + autoDashLength, metric.length))?.position;
          
          if (start != null && end != null) {
            // Automatically adjust paint properties for better visibility
            final adaptivePaint = _createAdaptivePaint(paint, segmentCount, totalLength);
            canvas.drawLine(start, end, adaptivePaint);
          }
        }
        
        distance += autoDashLength + autoGapLength;
        draw = !draw;
        segmentCount++;
      }
    }
  }
  
  // Automatically calculate optimal dash length based on path length
  double _calculateOptimalDashLength(double pathLength) {
    if (pathLength < 50) return 3.0;      // Short paths: small dashes
    if (pathLength < 200) return 6.0;     // Medium paths: medium dashes
    if (pathLength < 500) return 8.0;     // Long paths: larger dashes
    return 12.0;                          // Very long paths: large dashes
  }
  
  // Automatically calculate optimal gap length based on path and dash length
  double _calculateOptimalGapLength(double pathLength, double dashLength) {
    final ratio = dashLength / pathLength;
    if (ratio > 0.1) return dashLength * 0.5;      // High ratio: small gaps
    if (ratio > 0.05) return dashLength * 0.8;     // Medium ratio: medium gaps
    return dashLength * 1.2;                        // Low ratio: larger gaps
  }
  
  // Create adaptive paint with automatic adjustments
  Paint _createAdaptivePaint(Paint originalPaint, int segmentIndex, double totalLength) {
    final adaptivePaint = Paint()
      ..color = originalPaint.color
      ..style = originalPaint.style
      ..strokeWidth = originalPaint.strokeWidth;
    
    // Automatically adjust stroke width for better visibility
    if (totalLength < 100) {
      adaptivePaint.strokeWidth = max(1.0, originalPaint.strokeWidth * 0.8);
    } else if (totalLength > 300) {
      adaptivePaint.strokeWidth = min(4.0, originalPaint.strokeWidth * 1.2);
    }
    
    // Automatically adjust color opacity for better contrast
    if (originalPaint.color.a < 0.7) {
      adaptivePaint.color = originalPaint.color.withValues(alpha: min(1.0, originalPaint.color.a * 1.3));
    }
    
    return adaptivePaint;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}