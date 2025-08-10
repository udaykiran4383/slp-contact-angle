import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import '../image_processor.dart';

// Vector2D class for mathematical operations
class Vector2D {
  double x, y;
  
  Vector2D(this.x, this.y);
  
  Vector2D normalize() {
    final length = sqrt(x * x + y * y);
    if (length == 0) return Vector2D(0, 0);
    return Vector2D(x / length, y / length);
  }
  
  Vector2D operator +(Vector2D other) => Vector2D(x + other.x, y + other.y);
  Vector2D operator -(Vector2D other) => Vector2D(x - other.x, y - other.y);
  Vector2D operator *(double scalar) => Vector2D(x * scalar, y * scalar);
}

class ImageAnnotatorImproved extends StatefulWidget {
  const ImageAnnotatorImproved({super.key});

  @override
  State<ImageAnnotatorImproved> createState() => _ImageAnnotatorImprovedState();
}

class _ImageAnnotatorImprovedState extends State<ImageAnnotatorImproved> {
  ui.Image? _image;
  List<Offset> _contour = [];
  Offset? _leftContact;
  Offset? _rightContact;
  Offset? _baselineStart;
  Offset? _baselineEnd;
  double? _contactAngle;
  bool _isProcessing = false;
  String _processingStatus = '';
  bool _autoDetectionMode = true;

  @override
  void initState() {
    super.initState();
    _initMock();
  }

  void _initMock() {
    // Initialize with mock data for initial display
    setState(() {
      _contour = [
        const Offset(100, 200),
        const Offset(120, 180),
        const Offset(140, 160),
        const Offset(160, 150),
        const Offset(180, 160),
        const Offset(200, 180),
        const Offset(220, 200),
        const Offset(200, 220),
        const Offset(180, 240),
        const Offset(160, 250),
        const Offset(140, 240),
        const Offset(120, 220),
      ];
      _leftContact = const Offset(100, 200);
      _rightContact = const Offset(220, 200);
      _baselineStart = const Offset(80, 200);
      _baselineEnd = const Offset(240, 200);
      _contactAngle = 45.0;
    });
  }

  Future<void> _captureImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await showDialog<XFile>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: const Text('Choose how to capture the image'),
          actions: <Widget>[
            TextButton(
              child: const Text('Camera'),
              onPressed: () async {
                final XFile? photo = await picker.pickImage(source: ImageSource.camera);
                if (context.mounted) {
                  Navigator.of(context).pop(photo);
                }
              },
            ),
            TextButton(
              child: const Text('Gallery'),
              onPressed: () async {
                final XFile? photo = await picker.pickImage(source: ImageSource.gallery);
                if (context.mounted) {
                  Navigator.of(context).pop(photo);
                }
              },
            ),
          ],
        );
      },
    );

    if (image != null) {
      await _loadImage(image);
    }
  }

  Future<void> _loadImage(XFile imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    
    setState(() {
      _image = frame.image;
      _isProcessing = true;
      _processingStatus = 'Processing image...';
    });

    try {
      if (_autoDetectionMode) {
        await _performAutomaticDetection();
      } else {
        // Create mock contour for manual mode
        _createMockContour();
      }
    } catch (e) {
      setState(() {
        _processingStatus = 'Error: $e';
      });
      // Fallback to mock data
      _createMockContour();
    } finally {
      setState(() {
        _isProcessing = false;
        _processingStatus = '';
      });
    }
  }

  Future<void> _performAutomaticDetection() async {
    if (_image == null) return;

    try {
      setState(() {
        _processingStatus = 'Detecting droplet boundary...';
      });

      final result = await ImageProcessor.processDropletImage(_image!);
      
      setState(() {
        _contour = result.boundary;
        _leftContact = result.leftContact;
        _rightContact = result.rightContact;
        _baselineStart = result.baseline.startPoint;
        _baselineEnd = result.baseline.endPoint;
        _contactAngle = result.contactAngle;
        _processingStatus = 'Detection complete!';
      });
    } catch (e) {
      setState(() {
        _processingStatus = 'Auto-detection failed: $e';
      });
      // Fallback to mock data
      _createMockContour();
    }
  }

  void _createMockContour() {
    if (_image == null) return;
    
    final width = _image!.width.toDouble();
    final height = _image!.height.toDouble();
    
    // Create a more realistic mock contour
    final centerX = width / 2;
    final centerY = height * 0.6;
    final radiusX = width * 0.15;
    final radiusY = height * 0.2;
    
    final points = <Offset>[];
    for (int i = 0; i < 36; i++) {
      final angle = (i * 10) * pi / 180;
      final x = centerX + radiusX * cos(angle);
      final y = centerY + radiusY * sin(angle);
      points.add(Offset(x, y));
    }
    
    setState(() {
      _contour = points;
      _autoDetectContactPoints();
      _autoSetBaseline();
    });
  }

  void _autoDetectContactPoints() {
    if (_contour.isEmpty) return;
    
    final sortedPoints = List<Offset>.from(_contour)
      ..sort((a, b) => a.dy.compareTo(b.dy));
    
    final bottomY = sortedPoints.last.dy;
    final bottomPoints = _contour.where((p) => (p.dy - bottomY).abs() < 5).toList();
    
    if (bottomPoints.length >= 2) {
      bottomPoints.sort((a, b) => a.dx.compareTo(b.dx));
      setState(() {
        _leftContact = bottomPoints.first;
        _rightContact = bottomPoints.last;
      });
    }
  }

  void _autoSetBaseline() {
    if (_leftContact == null || _rightContact == null) return;
    
    final y = _leftContact!.dy;
    setState(() {
      _baselineStart = Offset(_leftContact!.dx - 20, y);
      _baselineEnd = Offset(_rightContact!.dx + 20, y);
    });
    
    _calculateAngle();
  }

  void _calculateAngle() {
    if (_leftContact == null || _rightContact == null || 
        _baselineStart == null || _baselineEnd == null) {
      return;
    }
    
    final tangentLeft = _getTangentAt(_leftContact!, true);
    final tangentRight = _getTangentAt(_rightContact!, false);
    
    if (tangentLeft != null && tangentRight != null) {
      final angleLeft = _calculateAngleFromTangent(tangentLeft, _baselineStart!, _baselineEnd!);
      final angleRight = _calculateAngleFromTangent(tangentRight, _baselineStart!, _baselineEnd!);
      
      setState(() {
        _contactAngle = (angleLeft + angleRight) / 2;
      });
    }
  }

  Vector2D? _getTangentAt(Offset point, bool isLeft) {
    if (_contour.isEmpty) return null;
    
    final index = _contour.indexWhere((p) => 
        (p - point).distance < 5);
    
    if (index == -1) {
      return null;
    }
    
    final prevIndex = (index - 1 + _contour.length) % _contour.length;
    final nextIndex = (index + 1) % _contour.length;
    
    final prev = _contour[prevIndex];
    final next = _contour[nextIndex];
    
    final tangent = Vector2D(
      next.dx - prev.dx,
      next.dy - prev.dy
    ).normalize();
    
    // Ensure tangent points outward from droplet
    if (isLeft && tangent.x > 0) {
      tangent.x = -tangent.x;
      tangent.y = -tangent.y;
    } else if (!isLeft && tangent.x < 0) {
      tangent.x = -tangent.x;
      tangent.y = -tangent.y;
    }
    
    return tangent;
  }

  double _calculateAngleFromTangent(Vector2D tangent, Offset baselineStart, Offset baselineEnd) {
    final baselineVector = Vector2D(
      baselineEnd.dx - baselineStart.dx,
      baselineEnd.dy - baselineStart.dy
    ).normalize();
    
    final dotProduct = tangent.x * baselineVector.x + tangent.y * baselineVector.y;
    final angle = acos(dotProduct.clamp(-1.0, 1.0)) * 180 / pi;
    
    return angle;
  }

  Future<void> _exportPng() async {
    if (_image == null) return;
    
    try {
      final boundary = GlobalKey();
      final RenderRepaintBoundary? renderObject = boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      
      if (renderObject != null) {
        final image = await renderObject.toImage(pixelRatio: 3.0);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        
        if (byteData != null) {
          await Share.shareXFiles(
            [XFile.fromData(byteData.buffer.asUint8List(), name: 'contact_angle_measurement.png')],
            text: 'Contact Angle Measurement Result',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _exportJsonCsv() async {
    if (_contactAngle == null) return;
    
    final data = {
      'contact_angle': _contactAngle,
      'left_contact': _leftContact != null ? {'x': _leftContact!.dx, 'y': _leftContact!.dy} : null,
      'right_contact': _rightContact != null ? {'x': _rightContact!.dx, 'y': _rightContact!.dy} : null,
      'baseline': _baselineStart != null && _baselineEnd != null ? {
        'start': {'x': _baselineStart!.dx, 'y': _baselineStart!.dy},
        'end': {'x': _baselineEnd!.dx, 'y': _baselineEnd!.dy},
      } : null,
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    final jsonString = jsonEncode(data);
    final csvString = 'Contact Angle,Left Contact X,Left Contact Y,Right Contact X,Right Contact Y,Baseline Start X,Baseline Start Y,Baseline End X,Baseline End Y\n'
        '$_contactAngle,${_leftContact?.dx ?? ""},${_leftContact?.dy ?? ""},${_rightContact?.dx ?? ""},${_rightContact?.dy ?? ""},${_baselineStart?.dx ?? ""},${_baselineStart?.dy ?? ""},${_baselineEnd?.dx ?? ""},${_baselineEnd?.dy ?? ""}';
    
    try {
      await Share.shareXFiles(
        [
          XFile.fromData(utf8.encode(jsonString), name: 'measurement_data.json'),
          XFile.fromData(utf8.encode(csvString), name: 'measurement_data.csv'),
        ],
        text: 'Contact Angle Measurement Data',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  void _showInstructions() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Instructions'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('• Drag the red points to adjust contact points'),
              const Text('• Drag the blue line to adjust the baseline'),
              const Text('• The contact angle is calculated automatically'),
              const SizedBox(height: 16),
              const Text('Color Guide:'),
              const Text('🔴 Red: Contact points'),
              const Text('🔵 Blue: Baseline'),
              const Text('🟢 Green: Droplet contour'),
              const Text('🟡 Yellow: Auto-detection mode indicator'),
            ],
          ),
          actions: [
            TextButton(
              child: const Text('OK'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Angle Measurement'),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: _showInstructions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Control Panel
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[850],
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _captureImage,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Capture Image'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Switch(
                  value: _autoDetectionMode,
                  onChanged: (value) {
                    setState(() {
                      _autoDetectionMode = value;
                    });
                  },
                ),
                Text(
                  _autoDetectionMode ? 'Auto Mode' : 'Manual Mode',
                  style: const TextStyle(color: Colors.white),
                ),
                const Spacer(),
                if (_contactAngle != null) ...[
                  ElevatedButton.icon(
                    onPressed: _exportPng,
                    icon: const Icon(Icons.image),
                    label: const Text('Export PNG'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _exportJsonCsv,
                    icon: const Icon(Icons.download),
                    label: const Text('Export Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange[600],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Processing Status
          if (_isProcessing || _processingStatus.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(8),
              color: _isProcessing ? Colors.blue[900] : Colors.grey[800],
              child: Row(
                children: [
                  if (_isProcessing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _processingStatus,
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          
          // Main Content
          Expanded(
            child: _image == null
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No image loaded',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Tap "Capture Image" to get started',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      // Image with annotations
                      RepaintBoundary(
                        key: GlobalKey(),
                        child: CustomPaint(
                          painter: _AnnotatorPainter(
                            image: _image!,
                            contour: _contour,
                            leftContact: _leftContact,
                            rightContact: _rightContact,
                            baselineStart: _baselineStart,
                            baselineEnd: _baselineEnd,
                            contactAngle: _contactAngle,
                            autoDetectionMode: _autoDetectionMode,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                      
                      // Draggable contact points
                      if (_leftContact != null)
                        Positioned(
                          left: _leftContact!.dx - 15,
                          top: _leftContact!.dy - 15,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _leftContact = Offset(
                                  _leftContact!.dx + details.delta.dx,
                                  _leftContact!.dy + details.delta.dy,
                                );
                              });
                              HapticFeedback.lightImpact();
                              _calculateAngle();
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.drag_indicator,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      
                      if (_rightContact != null)
                        Positioned(
                          left: _rightContact!.dx - 15,
                          top: _rightContact!.dy - 15,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _rightContact = Offset(
                                  _rightContact!.dx + details.delta.dx,
                                  _rightContact!.dy + details.delta.dy,
                                );
                              });
                              HapticFeedback.lightImpact();
                              _calculateAngle();
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.drag_indicator,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      
                      // Draggable baseline
                      if (_baselineStart != null && _baselineEnd != null)
                        Positioned(
                          left: _baselineStart!.dx - 15,
                          top: _baselineStart!.dy - 15,
                          child: GestureDetector(
                            onPanUpdate: (details) {
                              setState(() {
                                _baselineStart = Offset(
                                  _baselineStart!.dx + details.delta.dx,
                                  _baselineStart!.dy + details.delta.dy,
                                );
                                _baselineEnd = Offset(
                                  _baselineEnd!.dx + details.delta.dx,
                                  _baselineEnd!.dy + details.delta.dy,
                                );
                              });
                              HapticFeedback.lightImpact();
                              _calculateAngle();
                            },
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.8),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.drag_indicator,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          
          // Results Panel
          if (_contactAngle != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.grey[900],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contact Angle: ${_contactAngle!.toStringAsFixed(1)}°',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_leftContact != null && _rightContact != null)
                        Text(
                          'Contact Points: (${_leftContact!.dx.toStringAsFixed(1)}, ${_leftContact!.dy.toStringAsFixed(1)}) - (${_rightContact!.dx.toStringAsFixed(1)}, ${_rightContact!.dy.toStringAsFixed(1)})',
                          style: const TextStyle(color: Colors.grey),
                        ),
                    ],
                  ),
                  if (_autoDetectionMode)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.yellow[700],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                          SizedBox(width: 4),
                          Text(
                            'AUTO',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AnnotatorPainter extends CustomPainter {
  final ui.Image image;
  final List<Offset> contour;
  final Offset? leftContact;
  final Offset? rightContact;
  final Offset? baselineStart;
  final Offset? baselineEnd;
  final double? contactAngle;
  final bool autoDetectionMode;

  _AnnotatorPainter({
    required this.image,
    required this.contour,
    this.leftContact,
    this.rightContact,
    this.baselineStart,
    this.baselineEnd,
    this.contactAngle,
    required this.autoDetectionMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the image
    final paint = Paint();
    canvas.drawImage(image, Offset.zero, paint);
    
    // Draw contour with glow effect
    if (contour.isNotEmpty) {
      final contourPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      
      final path = Path();
      path.moveTo(contour.first.dx, contour.first.dy);
      for (int i = 1; i < contour.length; i++) {
        path.lineTo(contour[i].dx, contour[i].dy);
      }
      path.close();
      canvas.drawPath(path, contourPaint);
    }
    
    // Draw baseline
    if (baselineStart != null && baselineEnd != null) {
      final baselinePaint = Paint()
        ..color = Colors.blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.0);
      
      canvas.drawLine(baselineStart!, baselineEnd!, baselinePaint);
    }
    
    // Draw contact points
    if (leftContact != null) {
      final contactPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(leftContact!, 8, contactPaint);
      canvas.drawCircle(leftContact!, 8, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    
    if (rightContact != null) {
      final contactPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(rightContact!, 8, contactPaint);
      canvas.drawCircle(rightContact!, 8, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
    }
    
    // Draw contact angle if available
    if (contactAngle != null && leftContact != null && rightContact != null) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: '${contactAngle!.toStringAsFixed(1)}°',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(
                offset: Offset(1, 1),
                blurRadius: 2,
                color: Colors.black,
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      final center = Offset(
        (leftContact!.dx + rightContact!.dx) / 2,
        (leftContact!.dy + rightContact!.dy) / 2 - 30,
      );
      textPainter.paint(canvas, center - Offset(textPainter.width / 2, textPainter.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}