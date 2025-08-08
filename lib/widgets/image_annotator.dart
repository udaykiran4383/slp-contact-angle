// lib/widgets/image_annotator.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../processing/angle_utils.dart';

class ImageAnnotatorScreen extends StatefulWidget {
  const ImageAnnotatorScreen({super.key});

  @override
  State<ImageAnnotatorScreen> createState() => _ImageAnnotatorScreenState();
}

class _ImageAnnotatorScreenState extends State<ImageAnnotatorScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _showOverlay = true;
  ui.Image? _image; // loaded image (optional)
  List<Offset> _contour = [];
  Offset? _left;
  Offset? _right;
  Offset? _baselineA;
  Offset? _baselineB;

  // ellipse params from backend or local fit (cx, cy, a, b, phi radians)
  double? _cx, _cy, _a, _b, _phi;
  double _confidence = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMock());
  }

  void _initMock() {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Size s = box.size;
    final center = Offset(s.width / 2, s.height / 2);
    _contour = List.generate(160, (i) {
      final t = i / 160.0 * 2 * pi;
      final rx = 130.0 + 6.0 * (i % 5);
      final ry = 90.0 + 4.0 * ((i + 3) % 7);
      return center + Offset(rx * cos(t), ry * sin(t));
    });
    _left = center + const Offset(-110, 40);
    _right = center + const Offset(110, 40);
    _baselineA = center + const Offset(-160, 140);
    _baselineB = center + const Offset(160, 140);
    setState(() {});
  }

  Future<void> _exportPng() async {
    try {
      final boundary =
          _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/contact_angle_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles([XFile(file.path)], text: 'Contact Angle export');
    } catch (e) {
      debugPrint('Export PNG error: $e');
    }
  }

  Future<void> _exportJsonCsv() async {
    if (_left == null || _right == null || _baselineA == null || _baselineB == null) return;
    final Map<String, dynamic> payload = {
      'contact_point_left': {'x': _left!.dx, 'y': _left!.dy},
      'contact_point_right': {'x': _right!.dx, 'y': _right!.dy},
      'baseline_a': {'x': _baselineA!.dx, 'y': _baselineA!.dy},
      'baseline_b': {'x': _baselineB!.dx, 'y': _baselineB!.dy},
      'measured_angle_deg': _computeAngleLocal().toStringAsFixed(3),
      'timestamp': DateTime.now().toIso8601String(),
      'confidence': _confidence,
    };

    final dir = await getTemporaryDirectory();
    final jsonFile = File('${dir.path}/contact_angle_${DateTime.now().millisecondsSinceEpoch}.json');
    await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

    final csvFile = File('${dir.path}/contact_angle_${DateTime.now().millisecondsSinceEpoch}.csv');
    final csv = StringBuffer()
      ..writeln('label,x,y')
      ..writeln('contact_point_left,${_left!.dx},${_left!.dy}')
      ..writeln('contact_point_right,${_right!.dx},${_right!.dy}')
      ..writeln('baseline_a,${_baselineA!.dx},${_baselineA!.dy}')
      ..writeln('baseline_b,${_baselineB!.dx},${_baselineB!.dy}')
      ..writeln('measured_angle_deg,${_computeAngleLocal().toStringAsFixed(3)},');
    await csvFile.writeAsString(csv.toString());

    await Share.shareXFiles([XFile(jsonFile.path), XFile(csvFile.path)], text: 'Contact angle data');
  }

  // local computation using analytic tangent and optional subpixel refine (if image available)
  Future<double> _computeAngleLocalAsync({bool doSubpixel = true}) async {
    if (_left == null || _right == null || _baselineA == null || _baselineB == null) return 0.0;
    // baseline slope
    final baselineSlope = (_baselineB!.dy - _baselineA!.dy) / (_baselineB!.dx - _baselineA!.dx + 1e-12);
    // if ellipse params present, use analytic tangent + optional subpixel refine
    if (_cx != null && _cy != null && _a != null && _b != null && _phi != null) {
      double lx = _left!.dx;
      double ly = _left!.dy;
      if (doSubpixel && _image != null) {
        // compute tangent approx and normal
        final mt = ellipseTangentSlope(x0: lx, y0: ly, h: _cx!, k: _cy!, a: _a!, b: _b!, phi: _phi!);
        final tvec = mt.isFinite ? Offset(1, mt) : const Offset(0, -1);
        final tnorm = tvec / tvec.distance;
        final normal = Offset(-tnorm.dy, tnorm.dx);
        final refined = await subpixelRefineContact(img: _image!, approxPoint: Offset(lx, ly), normal: normal, samples: 31, spacing: 0.7);
        lx = refined.dx;
        ly = refined.dy;
      }
      final mtFinal = ellipseTangentSlope(x0: lx, y0: ly, h: _cx!, k: _cy!, a: _a!, b: _b!, phi: _phi!);
      final deg = contactAngleDegFromSlopes(mtFinal, baselineSlope);
      return deg;
    } else {
      // fallback approximate tangent using contour nearest neighbor
      return _computeAngleLocal();
    }
  }

  // fallback approximate angle from local contour neighbors (fast)
  double _computeAngleLocal() {
    if (_left == null || _baselineA == null || _baselineB == null || _contour.isEmpty) return 0.0;
    Offset tangentAt(Offset p) {
      int idx = 0;
      double best = double.infinity;
      for (int i = 0; i < _contour.length; i++) {
        final d = (_contour[i] - p).distanceSquared;
        if (d < best) {
          best = d;
          idx = i;
        }
      }
      final prev = _contour[(idx - 6 + _contour.length) % _contour.length];
      final next = _contour[(idx + 6) % _contour.length];
      return next - prev;
    }

    final v1 = tangentAt(_left!);
    final baselineVec = _baselineB! - _baselineA!;
    double a = v1.direction;
    double b = baselineVec.direction;
    double diff = (a - b).abs();
    if (diff > pi) diff = 2 * pi - diff;
    return diff * 180 / pi;
  }

  // call backend analyze endpoint
  Future<void> _callBackendAnalyze(File imageFile, String backendUrl) async {
    try {
      final uri = Uri.parse('$backendUrl/analyze');
      final request = http.MultipartRequest('POST', uri);
      final bytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'img.png'));
      final streamed = await request.send();
      final resp = await http.Response.fromStream(streamed);
      if (resp.statusCode != 200) {
        debugPrint('Backend error: ${resp.statusCode} ${resp.body}');
        return;
      }
      final Map<String, dynamic> j = jsonDecode(resp.body);
      setState(() {
        _left = Offset(j['left_contact']['x'].toDouble(), j['left_contact']['y'].toDouble());
        _right = Offset(j['right_contact']['x'].toDouble(), j['right_contact']['y'].toDouble());
        _cx = j['ellipse']['cx'].toDouble();
        _cy = j['ellipse']['cy'].toDouble();
        _a = j['ellipse']['a'].toDouble();
        _b = j['ellipse']['b'].toDouble();
        _phi = (j['ellipse']['angle_deg'] as num).toDouble() * pi / 180.0; // Convert to radians
        _confidence = (j['confidence'] as num).toDouble();
        // overlay PNG
        final overlayB64 = j['overlay_png_b64'] as String;
        final bytesImg = base64Decode(overlayB64);
        decodeImageFromList(bytesImg).then((ui.Image img) {
          setState(() {
            _image = img; // we can overlay this
          });
        });
      });
    } catch (e) {
      debugPrint('Error calling backend: $e');
    }
  }

  // UI and handlers
  String? _dragging; // 'left','right','ba','bb'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Angle — Improved'),
        backgroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showOverlay ? Icons.visibility : Icons.visibility_off),
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
          IconButton(
            icon: const Icon(Icons.save_alt),
            onPressed: _exportPng,
          ),
          PopupMenuButton<String>(
            onSelected: (s) {
              if (s == 'export_data') _exportJsonCsv();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'export_data', child: Text('Export JSON/CSV')),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        onPanStart: (details) {
          final p = details.localPosition;
          double best = double.infinity;
          String? bestId;
          void check(Offset? h, String id) {
            if (h == null) return;
            final d = (h - p).distance;
            if (d < best && d < 28) {
              best = d;
              bestId = id;
            }
          }

          check(_left, 'left');
          check(_right, 'right');
          check(_baselineA, 'ba');
          check(_baselineB, 'bb');
          _dragging = bestId;
        },
        onPanUpdate: (details) {
          final p = details.localPosition;
          setState(() {
            if (_dragging == 'left') _left = p;
            if (_dragging == 'right') _right = p;
            if (_dragging == 'ba') _baselineA = p;
            if (_dragging == 'bb') _baselineB = p;
          });
        },
        onPanEnd: (_) => _dragging = null,
        child: RepaintBoundary(
          key: _repaintKey,
          child: CustomPaint(
            size: Size.infinite,
            painter: _AnnotatorPainter(
              contour: _contour,
              left: _left,
              right: _right,
              baselineA: _baselineA,
              baselineB: _baselineB,
              showOverlay: _showOverlay,
              image: _image,
            ),
            child: Container(color: Colors.black),
          ),
        ),
      ),
      bottomNavigationBar: SizedBox(
        height: 76,
        child: Container(
          color: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Text('Angle:', style: TextStyle(color: Colors.white)),
              const SizedBox(width: 8),
              FutureBuilder<double>(
                future: _computeAngleLocalAsync(doSubpixel: true),
                builder: (context, snap) {
                  final text = snap.hasData ? '${snap.data!.toStringAsFixed(2)}°' : '--';
                  return Chip(label: Text(text, style: const TextStyle(color: Colors.black)), backgroundColor: Colors.tealAccent);
                },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.cloud_upload),
                label: const Text('Analyze (Backend)'),
                onPressed: () async {
                  // You can replace this with file picker.
                  // For demo, we create a mock image file by exporting current repaint boundary to png
                  try {
                    final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                    if (boundary == null) return;
                    final ui.Image img = await boundary.toImage(pixelRatio: 1.0);
                    final ByteData? bd = await img.toByteData(format: ui.ImageByteFormat.png);
                    final Uint8List bytes = bd!.buffer.asUint8List();
                    final dir = await getTemporaryDirectory();
                    final f = File('${dir.path}/tmp_export.png');
                    await f.writeAsBytes(bytes);
                    // set your backend host here (http://10.0.2.2:8000 for emulator)
                    const backend = 'http://10.0.2.2:8000';
                    await _callBackendAnalyze(f, backend);
                  } catch (e) {
                    debugPrint('Analyze error: $e');
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
              ),
              const Spacer(),
              ElevatedButton.icon(icon: const Icon(Icons.save), label: const Text('Export PNG'), onPressed: _exportPng, style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan)),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnotatorPainter extends CustomPainter {
  final List<Offset> contour;
  final Offset? left;
  final Offset? right;
  final Offset? baselineA;
  final Offset? baselineB;
  final bool showOverlay;
  final ui.Image? image;

  _AnnotatorPainter({required this.contour, this.left, this.right, this.baselineA, this.baselineB, required this.showOverlay, this.image});

  @override
  void paint(Canvas canvas, Size size) {
    // draw image if present
    if (image != null) {
      final paint = Paint();
      final src = Rect.fromLTWH(0,0,image!.width.toDouble(), image!.height.toDouble());
      final dst = Rect.fromLTWH(0,0,size.width, size.height);
      canvas.drawImageRect(image!, src, dst, paint);
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    }

    if (!showOverlay) return;

    if (contour.isNotEmpty) {
      final Paint contourPaint = Paint()..color = Colors.greenAccent..style = PaintingStyle.stroke..strokeWidth = 2.0;
      final Path p = Path()..moveTo(contour[0].dx, contour[0].dy);
      for (final pt in contour.skip(1)) {
        p.lineTo(pt.dx, pt.dy);
      }
      p.close();
      canvas.drawPath(p, contourPaint);
    }

    if (baselineA != null && baselineB != null) {
      final Paint basePaint = Paint()..color = Colors.cyanAccent..strokeWidth = 2.0;
      canvas.drawLine(baselineA!, baselineB!, basePaint);
    }

    if (left != null) canvas.drawCircle(left!, 8, Paint()..color = Colors.redAccent);
    if (right != null) canvas.drawCircle(right!, 8, Paint()..color = Colors.redAccent);
    if (baselineA != null) canvas.drawCircle(baselineA!, 6, Paint()..color = Colors.blueAccent);
    if (baselineB != null) canvas.drawCircle(baselineB!, 6, Paint()..color = Colors.blueAccent);
  }

  @override
  bool shouldRepaint(covariant _AnnotatorPainter oldDelegate) {
    return oldDelegate.contour != contour || oldDelegate.left != left || oldDelegate.right != right || oldDelegate.baselineA != baselineA || oldDelegate.baselineB != baselineB || oldDelegate.showOverlay != showOverlay || oldDelegate.image != image;
  }
}
