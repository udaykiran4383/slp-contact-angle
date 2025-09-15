import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../image_processor.dart';
import 'package:image_picker/image_picker.dart';

// Example: batch image filenames for testing
final List<String> testImagePaths = [
  'PFOTES/C_1.5%_1 coat_6.JPG',
  'PFOTES/C_1.5%_2 coat_5.JPG',
  'PFOTES/C_3%_1 coat_5.JPG',
  'PFOTES/C_3%_1 coat_6a.JPG',
  'PFOTES/C_3%_2 coat_5a.JPG',
  'PFOTES/C_3%_2 coat_6a.JPG',
  // ...add more as needed
];

class ImageAnnotatorImproved extends StatefulWidget {
  const ImageAnnotatorImproved({Key? key}) : super(key: key);

  @override
  State<ImageAnnotatorImproved> createState() => _ImageAnnotatorImprovedState();
}

class _ImageAnnotatorImprovedState extends State<ImageAnnotatorImproved> {
  // --- STATE VARIABLES ---
  ui.Image? _image;
  List<Offset>? _contour;
  Offset? _leftContact, _rightContact, _baselineA, _baselineB;
  double? _measuredAngle, _qualityScore;
  bool _showOverlay = true;
  bool _isProcessing = false;
  String _processingStatus = '';
  final GlobalKey _repaintKey = GlobalKey();

  // --- MAIN PROCESSING FUNCTION CALL ---
  Future<void> _processImage(ui.Image image) async {
    setState(() {
      _isProcessing = true;
      _processingStatus = "Processing image...";
    });
    try {
      final result = await processDropletImage(image);
      setState(() {
        _contour = result?.boundary;
        _leftContact = result?.leftContact;
        _rightContact = result?.rightContact;
        _baselineA = result?.baseline.startPoint;
        _baselineB = result?.baseline.endPoint;
        _measuredAngle = result?.bestAngle ?? result?.avgAngle;
        _qualityScore = result?.qualityScore;
        _processingStatus = result == null ? "No result" : "Done";
        _isProcessing = false;
      });
    } catch (e) {
      setState(() {
        _processingStatus = "Processing failed: $e";
        _isProcessing = false;
      });
    }
  }

  // --- BUILD METHOD: INSERT YOUR UI LOGIC HERE ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contact Angle Annotator')),
      body: Center(
        child: _image == null
            ? const Text('No image loaded')
            : Stack(
                children: [
                  RepaintBoundary(
                    key: _repaintKey,
                    child: CustomPaint(
                      painter: _image != null
                          ? ContourPainter(
                              contour: _contour ?? [],
                              leftContact: _leftContact,
                              rightContact: _rightContact,
                              baselineA: _baselineA,
                              baselineB: _baselineB,
                            )
                          : null,
                    ),
                  ),
                  if (_isProcessing)
                    const Center(child: CircularProgressIndicator()),
                  if (_processingStatus.isNotEmpty)
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        color: Colors.black54,
                        child: Text(_processingStatus,
                            style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  if (!_isProcessing && _contour == null)
                    const Center(child: Text('No result available', style: TextStyle(fontSize: 18))),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          setState(() {
            _isProcessing = true;
            _processingStatus = "Selecting image...";
          });
          try {
            final picker = ImagePicker();
            final pickedFile = await picker.pickImage(source: ImageSource.gallery);
            if (pickedFile == null) {
              setState(() {
                _processingStatus = "No image selected.";
                _isProcessing = false;
              });
              return;
            }
            final imageBytes = await pickedFile.readAsBytes();
            final codec = await ui.instantiateImageCodec(imageBytes);
            final frame = await codec.getNextFrame();
            setState(() {
              _image = frame.image;
            });
            await _processImage(frame.image);
          } catch (e) {
            setState(() {
              _processingStatus = "Failed to load/process image: $e";
              _isProcessing = false;
            });
          }
        },
        child: const Icon(Icons.analytics),
      ),
    );
  }
}

// ------------ Supporting painter for overlays (demo only) -------------
class ContourPainter extends CustomPainter {
  final List<Offset> contour;
  final Offset? leftContact, rightContact, baselineA, baselineB;

  ContourPainter({
    required this.contour,
    this.leftContact,
    this.rightContact,
    this.baselineA,
    this.baselineB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    if (contour.isNotEmpty) {
      final path = Path()..moveTo(contour.first.dx, contour.first.dy);
      for (final pt in contour) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, paint);
    }
    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;
    if (leftContact != null) {
      canvas.drawCircle(leftContact!, 5, pointPaint);
    }
    if (rightContact != null) {
      canvas.drawCircle(rightContact!, 5, pointPaint);
    }
    if (baselineA != null && baselineB != null) {
      canvas.drawLine(baselineA!, baselineB!, Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.0);
    }
  }

  @override
  bool shouldRepaint(covariant ContourPainter oldDelegate) => true;
}
