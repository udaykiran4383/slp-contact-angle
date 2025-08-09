// lib/widgets/image_annotator_improved.dart
// Fully automatic UI: loads image, runs pipeline automatically, displays annotated overlays.
// Minimal user interaction: a "Process" button or auto-run on example load.

import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import '../image_processor.dart';
import '../processing/angle_utils.dart';

class ImageAnnotatorScreen extends StatefulWidget {
  const ImageAnnotatorScreen({super.key});
  @override
  State<ImageAnnotatorScreen> createState() => _ImageAnnotatorScreenState();
}

class _ImageAnnotatorScreenState extends State<ImageAnnotatorScreen> {
  ui.Image? _image;
  ProcessedImageData? _processed;
  bool _loading = false;
  bool _debug = false;

  @override
  void initState() {
    super.initState();
    // Optionally auto-load an example asset here if you have one.
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
        title: const Text('Automatic Contact Angle'),
        actions: [
          IconButton(
            icon: Icon(_debug ? Icons.bug_report : Icons.bug_report_outlined),
            onPressed: () => setState(() => _debug = !_debug),
            tooltip: 'Toggle debug info',
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : (_image == null)
                ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                  'Avg: ${_processed!.avgAngle.toStringAsFixed(2)}°',
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
}

class _OverlayPainter extends CustomPainter {
  final ProcessedImageData processed;
  final bool showDebug;
  _OverlayPainter({required this.processed, required this.showDebug});

  @override
  void paint(Canvas canvas, Size size) {
    final baselinePaint = Paint()..color = Colors.greenAccent..strokeWidth = 2.5;
    final contourPaint = Paint()..color = Colors.white24..style = PaintingStyle.stroke..strokeWidth = 1.2;
    final ptPaint = Paint()..color = Colors.orange..style = PaintingStyle.fill;
    final tanPaint = Paint()..color = Colors.redAccent..strokeWidth = 2.0;

    // draw baseline
    canvas.drawLine(processed.baseline.startPoint, processed.baseline.endPoint, baselinePaint);

    // contour path
    final c = processed.boundary;
    if (c.isNotEmpty) {
      final path = Path()..moveTo(c.first.dx, c.first.dy);
      for (int i = 1; i < c.length; i++) path.lineTo(c[i].dx, c[i].dy);
      path.close();
      canvas.drawPath(path, contourPaint);
    }

    // contact points
    canvas.drawCircle(processed.leftContact, 5.0, ptPaint);
    canvas.drawCircle(processed.rightContact, 5.0, ptPaint);

    // tangents: compute small segment around each point using local derivative approach
    final leftSlope = AngleUtils.localQuadraticDerivative(
        _collectNeighborsForPaint(c, processed.leftContact, k: 12), processed.leftContact.dx);
    final rightSlope = AngleUtils.localQuadraticDerivative(
        _collectNeighborsForPaint(c, processed.rightContact, k: 12), processed.rightContact.dx);
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

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}