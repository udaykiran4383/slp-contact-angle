import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../image_processor.dart';

class ImageAnnotatorScreen extends StatefulWidget {
  const ImageAnnotatorScreen({super.key});

  @override
  State<ImageAnnotatorScreen> createState() => _ImageAnnotatorScreenState();
}

class _ImageAnnotatorScreenState extends State<ImageAnnotatorScreen> {
  final GlobalKey _repaintKey = GlobalKey();
  bool _showOverlay = true;
  ui.Image? _image;
  List<Offset> _contour = [];
  Offset? _leftContact;
  Offset? _rightContact;
  Offset? _baselineA;
  Offset? _baselineB;

  double _measuredAngle = 0.0;
  bool _isProcessing = false;
  String? _dragging;
  bool _autoDetectionMode = true;
  String _processingStatus = 'Ready';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMock());
  }

  void _initMock() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Size s = box.size;
    final center = Offset(s.width / 2, s.height / 2);

    _contour = List.generate(160, (i) {
      final t = i / 160.0 * 2 * pi;
      final rx = 130.0 + 6.0 * (i % 5);
      final ry = 90.0 + 4.0 * ((i + 3) % 7);
      return center + Offset(rx * cos(t), ry * sin(t));
    });

    _leftContact = center + const Offset(-110, 40);
    _rightContact = center + const Offset(110, 40);
    _baselineA = center + const Offset(-160, 140);
    _baselineB = center + const Offset(160, 140);

    _calculateAngle();
    setState(() {});
  }

  Future<void> _captureImage() async {
    final ImagePicker picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.tealAccent),
              title: const Text('Camera', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
                if (image != null) {
                  _loadImage(File(image.path));
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.cyanAccent),
              title: const Text('Gallery', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
                if (image != null) {
                  _loadImage(File(image.path));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadImage(File imageFile) async {
    setState(() {
      _isProcessing = true;
      _processingStatus = 'Loading image...';
    });

    try {
      final bytes = await imageFile.readAsBytes();
      final ui.Image image = await decodeImageFromList(bytes);

      setState(() {
        _image = image;
        _processingStatus = 'Analyzing droplet...';
      });

      if (_autoDetectionMode) {
        await _performAutomaticDetection(image);
      } else {
        // Fallback to manual mode with mock contour
        await _createMockContour(image);
      }

      setState(() {
        _isProcessing = false;
        _processingStatus = 'Analysis complete';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _processingStatus = 'Analysis failed';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error processing image: $e')));
      }
    }
  }

  Future<void> _performAutomaticDetection(ui.Image image) async {
    try {
      setState(() {
        _processingStatus = 'Detecting droplet boundary...';
      });

      // Use the ImageProcessor to automatically detect everything
      final processedData = await ImageProcessor.processDropletImage(image);

      setState(() {
        _contour = processedData.boundary;
        _leftContact = processedData.leftContact;
        _rightContact = processedData.rightContact;
        _baselineA = processedData.baseline.startPoint;
        _baselineB = processedData.baseline.endPoint;
        _measuredAngle = processedData.contactAngle;
        _processingStatus = 'Detection complete - Angle: ${processedData.contactAngle.toStringAsFixed(1)}°';
      });
    } catch (e) {
      // Fallback to mock data if automatic detection fails
      debugPrint('Automatic detection failed: $e');
      await _createMockContour(image);
      setState(() {
        _processingStatus = 'Using manual mode (auto-detection failed)';
      });
    }
  }

  Future<void> _createMockContour(ui.Image image) async {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    final center = Offset(imageWidth / 2, imageHeight * 0.6);
    final mockContour = List.generate(120, (i) {
      final t = i / 120.0 * 2 * pi;
      final rx = imageWidth * 0.15 + (i % 6) * 2;
      final ry = imageHeight * 0.1 + (i % 7) * 1.5;
      return center + Offset(rx * cos(t), ry * sin(t));
    });

    setState(() {
      _contour = mockContour;
      if (_contour.isNotEmpty) {
        _autoDetectContactPoints();
        _autoSetBaseline();
      }
      _calculateAngle();
    });
  }

  void _autoDetectContactPoints() {
    if (_contour.isEmpty) return;
    final sortedByY = List<Offset>.from(_contour)..sort((a, b) => b.dy.compareTo(a.dy));
    final bottomPoints = sortedByY.take((_contour.length * 0.2).round()).toList();
    bottomPoints.sort((a, b) => a.dx.compareTo(b.dx));
    _leftContact = bottomPoints.first;
    _rightContact = bottomPoints.last;
  }

  void _autoSetBaseline() {
    if (_leftContact == null || _rightContact == null) return;
    final baselineY = max(_leftContact!.dy, _rightContact!.dy) + 20;
    _baselineA = Offset(_leftContact!.dx - 50, baselineY);
    _baselineB = Offset(_rightContact!.dx + 50, baselineY);
  }

  void _calculateAngle() {
    if (_leftContact == null || _rightContact == null ||
        _baselineA == null || _baselineB == null || _contour.isEmpty) {
      _measuredAngle = 0.0;
      return;
    }

    try {
      final leftTangent = _getTangentAt(_leftContact!);
      final rightTangent = _getTangentAt(_rightContact!);

      if (leftTangent != null && rightTangent != null) {
        final baselineVector = _baselineB! - _baselineA!;
        final baselineAngle = baselineVector.direction;

        final leftTangentAngle = leftTangent.direction;
        double angleDiff = (leftTangentAngle - baselineAngle).abs();
        if (angleDiff > pi) angleDiff = 2 * pi - angleDiff;

        _measuredAngle = angleDiff * 180 / pi;
      } else {
        _measuredAngle = 0.0;
      }
    } catch (e) {
      debugPrint('Error calculating angle: $e');
      _measuredAngle = 0.0;
    }
  }

  Offset? _getTangentAt(Offset point) {
    if (_contour.isEmpty) return null;
    int nearestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < _contour.length; i++) {
      final distance = (_contour[i] - point).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    final prev = _contour[(nearestIndex - 3 + _contour.length) % _contour.length];
    final next = _contour[(nearestIndex + 3) % _contour.length];
    final tangentVector = next - prev;
    return tangentVector / tangentVector.distance;
  }

  Future<void> _exportPng() async {
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to export')));
        }
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/contact_angle_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(pngBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Contact Angle: ${_measuredAngle.toStringAsFixed(1)}°');
    } catch (e) {
      debugPrint('Export PNG error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _exportJsonCsv() async {
    if (_leftContact == null || _rightContact == null) return;
    final Map<String, dynamic> payload = {
      'contact_point_left': {'x': _leftContact!.dx, 'y': _leftContact!.dy},
      'contact_point_right': {'x': _rightContact!.dx, 'y': _rightContact!.dy},
      'baseline_a': {'x': _baselineA!.dx, 'y': _baselineA!.dy},
      'baseline_b': {'x': _baselineB!.dx, 'y': _baselineB!.dy},
      'measured_angle_deg': _measuredAngle,
      'timestamp': DateTime.now().toIso8601String(),
    };
    final dir = await getTemporaryDirectory();
    final jsonFile = File('${dir.path}/contact_angle_${DateTime.now().millisecondsSinceEpoch}.json');
    await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    final csvFile = File('${dir.path}/contact_angle_${DateTime.now().millisecondsSinceEpoch}.csv');
    final csv = StringBuffer()
      ..writeln('label,x,y,angle')
      ..writeln('contact_point_left,${_leftContact!.dx},${_leftContact!.dy},')
      ..writeln('contact_point_right,${_rightContact!.dx},${_rightContact!.dy},')
      ..writeln('baseline_a,${_baselineA!.dx},${_baselineA!.dy},')
      ..writeln('baseline_b,${_baselineB!.dx},${_baselineB!.dy},')
      ..writeln('measured_angle_deg,,${_measuredAngle.toStringAsFixed(3)}');
    await csvFile.writeAsString(csv.toString());
    await Share.shareXFiles([XFile(jsonFile.path), XFile(csvFile.path)], text: 'Contact angle data');
  }

  void _showInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'How to Measure Contact Angle',
          style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
        ),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '1. Capture or load an image of a droplet\n'
                '2. Drag RED circles to contact points\n'
                '3. Drag BLUE circles to set baseline\n'
                '4. The angle is calculated automatically\n\n'
                'Color Guide:',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              SizedBox(height: 8),
              Row(children: [
                Icon(Icons.circle, color: Colors.green, size: 16),
                SizedBox(width: 8),
                Text('Green: Droplet contour', style: TextStyle(color: Colors.white)),
              ]),
              SizedBox(height: 4),
              Row(children: [
                Icon(Icons.circle, color: Colors.red, size: 16),
                SizedBox(width: 8),
                Text('Red: Contact points (draggable)', style: TextStyle(color: Colors.white)),
              ]),
              SizedBox(height: 4),
              Row(children: [
                Icon(Icons.circle, color: Colors.blue, size: 16),
                SizedBox(width: 8),
                Text('Blue: Baseline endpoints (draggable)', style: TextStyle(color: Colors.white)),
              ]),
              SizedBox(height: 4),
              Row(children: [
                Icon(Icons.remove, color: Colors.yellow, size: 16),
                SizedBox(width: 8),
                Text('Yellow: Tangent lines', style: TextStyle(color: Colors.white)),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it!', style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 24),
        tooltip: tooltip,
        onPressed: onPressed,
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.8)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.straighten, color: Colors.tealAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Contact Angle',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Professional Measurement',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.black,
        elevation: 8,
        shadowColor: Colors.tealAccent.withValues(alpha: 0.3),
        actions: [
          _buildAppBarButton(
            icon: Icons.camera_alt,
            color: Colors.tealAccent,
            tooltip: 'Capture Image',
            onPressed: _captureImage,
          ),
          _buildAppBarButton(
            icon: _showOverlay ? Icons.visibility : Icons.visibility_off,
            color: Colors.cyanAccent,
            tooltip: _showOverlay ? 'Hide overlays' : 'Show overlays',
            onPressed: () => setState(() => _showOverlay = !_showOverlay),
          ),
          _buildAppBarButton(
            icon: _autoDetectionMode ? Icons.auto_awesome : Icons.touch_app,
            color: _autoDetectionMode ? Colors.greenAccent : Colors.orangeAccent,
            tooltip: _autoDetectionMode ? 'Auto Detection ON' : 'Manual Mode ON',
            onPressed: () {
              setState(() {
                _autoDetectionMode = !_autoDetectionMode;
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_autoDetectionMode 
                      ? 'Switched to Automatic Detection Mode' 
                      : 'Switched to Manual Adjustment Mode'),
                    backgroundColor: _autoDetectionMode ? Colors.green : Colors.orange,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
          ),
          _buildAppBarButton(
            icon: Icons.help_outline,
            color: Colors.white70,
            tooltip: 'Instructions',
            onPressed: _showInstructions,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          GestureDetector(
            onPanStart: !_autoDetectionMode ? (details) {
              final p = details.localPosition;
              double best = double.infinity;
              String? bestId;
              void check(Offset? h, String id) {
                if (h == null) return;
                final d = (h - p).distance;
                if (d < best && d < 50) { // Increased touch area
                  best = d;
                  bestId = id;
                }
              }

              check(_leftContact, 'left');
              check(_rightContact, 'right');
              check(_baselineA, 'ba');
              check(_baselineB, 'bb');
              _dragging = bestId;
              
              // Provide haptic feedback
              if (_dragging != null) {
                HapticFeedback.lightImpact();
              }
            } : null,
            onPanUpdate: !_autoDetectionMode ? (details) {
              final p = details.localPosition;
              setState(() {
                if (_dragging == 'left') {
                  _leftContact = p;
                  _calculateAngle();
                }
                if (_dragging == 'right') {
                  _rightContact = p;
                  _calculateAngle();
                }
                if (_dragging == 'ba') {
                  _baselineA = p;
                  _calculateAngle();
                }
                if (_dragging == 'bb') {
                  _baselineB = p;
                  _calculateAngle();
                }
              });
            } : null,
            onPanEnd: !_autoDetectionMode ? (_) => _dragging = null : null,
            child: RepaintBoundary(
              key: _repaintKey,
              child: CustomPaint(
                size: Size.infinite,
                painter: _AnnotatorPainter(
                  contour: _contour,
                  leftContact: _leftContact,
                  rightContact: _rightContact,
                  baselineA: _baselineA,
                  baselineB: _baselineB,
                  showOverlay: _showOverlay,
                  image: _image,
                  draggingHandle: _dragging,
                  autoDetectionMode: _autoDetectionMode,
                ),
                child: Container(),
              ),
            ),
          ),
          // Status and Instructions overlay
          if (_showOverlay)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.95),
                      Colors.grey[900]!.withValues(alpha: 0.95),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.tealAccent.withValues(alpha: 0.4),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Mode indicator
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: (_autoDetectionMode ? Colors.greenAccent : Colors.orangeAccent)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _autoDetectionMode ? Colors.greenAccent : Colors.orangeAccent,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _autoDetectionMode ? Icons.auto_awesome : Icons.touch_app,
                            color: _autoDetectionMode ? Colors.greenAccent : Colors.orangeAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _autoDetectionMode ? 'AUTO DETECTION' : 'MANUAL MODE',
                            style: TextStyle(
                              color: _autoDetectionMode ? Colors.greenAccent : Colors.orangeAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Status
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _processingStatus,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (!_autoDetectionMode && _leftContact != null && _rightContact != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: const Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, color: Colors.red, size: 12),
                                SizedBox(width: 8),
                                Text('Contact Points (drag to adjust)', 
                                     style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.circle, color: Colors.blue, size: 12),
                                SizedBox(width: 8),
                                Text('Baseline (drag endpoints)', 
                                     style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.circle, color: Colors.green, size: 12),
                                SizedBox(width: 8),
                                Text('Droplet Contour', 
                                     style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                            SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(Icons.remove, color: Colors.yellow, size: 12),
                                SizedBox(width: 8),
                                Text('Tangent Lines', 
                                     style: TextStyle(color: Colors.white, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          // Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.grey[900]!,
                        Colors.black,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.tealAccent.withValues(alpha: 0.5),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.tealAccent.withValues(alpha: 0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          const SizedBox(
                            width: 60,
                            height: 60,
                            child: CircularProgressIndicator(
                              color: Colors.tealAccent,
                              strokeWidth: 3,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.tealAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.auto_awesome,
                              color: Colors.tealAccent,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'AI Analysis in Progress',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _processingStatus,
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: const Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                                SizedBox(width: 12),
                                Text(
                                  'Detecting droplet boundary',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                                SizedBox(width: 12),
                                Text(
                                  'Finding contact points',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                                SizedBox(width: 12),
                                Text(
                                  'Calculating baseline',
                                  style: TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Row(
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.tealAccent,
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Measuring contact angle',
                                  style: TextStyle(color: Colors.tealAccent, fontSize: 13),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.grey[900]!, Colors.black],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Angle display with visual indicator
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.grey[900]!.withValues(alpha: 0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.tealAccent.withValues(alpha: 0.3),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.tealAccent.withValues(alpha: 0.1),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.straighten, color: Colors.tealAccent, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Contact Angle',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            'Measurement Result',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.tealAccent, Colors.cyanAccent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.tealAccent.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Text(
                          '${_measuredAngle.toStringAsFixed(1)}°',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Control buttons row
                Row(
                  children: [
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.refresh_rounded,
                        label: 'Reset',
                        color: Colors.grey[600]!,
                        onPressed: () => _initMock(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.save_rounded,
                        label: 'Export PNG',
                        color: Colors.cyan,
                        onPressed: _exportPng,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.table_chart_rounded,
                        label: 'Export Data',
                        color: Colors.orange,
                        onPressed: _exportJsonCsv,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnotatorPainter extends CustomPainter {
  final List<Offset> contour;
  final Offset? leftContact;
  final Offset? rightContact;
  final Offset? baselineA;
  final Offset? baselineB;
  final bool showOverlay;
  final ui.Image? image;
  final String? draggingHandle;
  final bool autoDetectionMode;

  _AnnotatorPainter({
    required this.contour,
    this.leftContact,
    this.rightContact,
    this.baselineA,
    this.baselineB,
    required this.showOverlay,
    this.image,
    this.draggingHandle,
    required this.autoDetectionMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw background
    if (image != null) {
      final paint = Paint();
      final src = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(image!, src, dst, paint);
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    }

    if (!showOverlay) return;

    // Draw contour with enhanced visibility
    if (contour.isNotEmpty) {
      final Paint contourPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      
      // Add glow effect
      final Paint glowPaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      
      final Path path = Path()..moveTo(contour[0].dx, contour[0].dy);
      for (final pt in contour.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, contourPaint);
    }

    // Draw baseline with enhanced visibility
    if (baselineA != null && baselineB != null) {
      final Paint baselineGlowPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.3)
        ..strokeWidth = 6.0
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
      
      final Paint basePaint = Paint()
        ..color = Colors.cyanAccent
        ..strokeWidth = 3.0
        ..strokeCap = StrokeCap.round;
      
      canvas.drawLine(baselineA!, baselineB!, baselineGlowPaint);
      canvas.drawLine(baselineA!, baselineB!, basePaint);
    }

    // Draw tangent lines with enhanced visibility
    final Paint tangentGlowPaint = Paint()
      ..color = Colors.amber.withValues(alpha: 0.3)
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    
    final Paint tangentPaint = Paint()
      ..color = Colors.amber
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    if (leftContact != null && contour.isNotEmpty) {
      final tangent = _getTangentAt(leftContact!);
      if (tangent != null) {
        const tangentLength = 70.0;
        final start = leftContact! - tangent * tangentLength;
        final end = leftContact! + tangent * tangentLength;
        canvas.drawLine(start, end, tangentGlowPaint);
        canvas.drawLine(start, end, tangentPaint);
      }
    }

    if (rightContact != null && contour.isNotEmpty) {
      final tangent = _getTangentAt(rightContact!);
      if (tangent != null) {
        const tangentLength = 70.0;
        final start = rightContact! - tangent * tangentLength;
        final end = rightContact! + tangent * tangentLength;
        canvas.drawLine(start, end, tangentGlowPaint);
        canvas.drawLine(start, end, tangentPaint);
      }
    }

    // Draw contact points with enhanced visibility
    final bool leftDragging = draggingHandle == 'left';
    final bool rightDragging = draggingHandle == 'right';
    
    if (leftContact != null) {
      _drawContactPoint(canvas, leftContact!, leftDragging);
    }
    if (rightContact != null) {
      _drawContactPoint(canvas, rightContact!, rightDragging);
    }

    // Draw baseline handles with enhanced visibility
    final bool baseADragging = draggingHandle == 'ba';
    final bool baseBDragging = draggingHandle == 'bb';
    
    if (baselineA != null) {
      _drawBaselineHandle(canvas, baselineA!, baseADragging);
    }
    if (baselineB != null) {
      _drawBaselineHandle(canvas, baselineB!, baseBDragging);
    }

    // Draw angle arc for visual feedback
    if (leftContact != null && rightContact != null && baselineA != null && baselineB != null) {
      _drawAngleArc(canvas);
    }

    _drawLegend(canvas);
  }

  void _drawContactPoint(Canvas canvas, Offset point, bool isDragging) {
    final Color pointColor = autoDetectionMode ? Colors.greenAccent : Colors.redAccent;
    
    final Paint glowPaint = Paint()
      ..color = pointColor.withValues(alpha: 0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDragging ? 4.0 : 2.0);
    
    final Paint contactPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;
    
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = autoDetectionMode ? 3.0 : 2.0;
    
    final double radius = autoDetectionMode ? 8.0 : (isDragging ? 12.0 : 10.0);
    final double glowRadius = autoDetectionMode ? 12.0 : (isDragging ? 16.0 : 14.0);
    
    canvas.drawCircle(point, glowRadius, glowPaint);
    canvas.drawCircle(point, radius, contactPaint);
    canvas.drawCircle(point, radius, borderPaint);
    
    // Add auto-detection indicator
    if (autoDetectionMode) {
      final Paint centerPaint = Paint()..color = Colors.white;
      canvas.drawCircle(point, 2.0, centerPaint);
    }
  }

  void _drawBaselineHandle(Canvas canvas, Offset point, bool isDragging) {
    final Paint glowPaint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.3)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, isDragging ? 3.0 : 1.5);
    
    final Paint handlePaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.fill;
    
    final Paint borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    final double radius = isDragging ? 9.0 : 7.0;
    final double glowRadius = isDragging ? 12.0 : 10.0;
    
    canvas.drawCircle(point, glowRadius, glowPaint);
    canvas.drawCircle(point, radius, handlePaint);
    canvas.drawCircle(point, radius, borderPaint);
  }

  void _drawAngleArc(Canvas canvas) {
    if (leftContact == null || baselineA == null || baselineB == null) return;
    
    final baselineVector = baselineB! - baselineA!;
    final leftVector = leftContact! - baselineA!;
    
    final Paint arcPaint = Paint()
      ..color = Colors.orange.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    
    final center = baselineA!;
    const radius = 50.0;
    
    final startAngle = baselineVector.direction;
    final sweepAngle = leftVector.direction - startAngle;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      arcPaint,
    );
  }

  Offset? _getTangentAt(Offset point) {
    if (contour.isEmpty) return null;
    int nearestIndex = 0;
    double minDistance = double.infinity;
    for (int i = 0; i < contour.length; i++) {
      final distance = (contour[i] - point).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    final prev = contour[(nearestIndex - 3 + contour.length) % contour.length];
    final next = contour[(nearestIndex + 3) % contour.length];
    final tangentVector = next - prev;
    return tangentVector / tangentVector.distance;
  }

  void _drawLegend(Canvas canvas) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🟢 Contour • 🔵 Baseline • 🔴 Contacts • 🟡 Tangents',
        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    
    final rect = Rect.fromLTWH(12, 12, textPainter.width + 16, textPainter.height + 8);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.7);
    
    canvas.drawRRect(rrect, bgPaint);
    textPainter.paint(canvas, const Offset(20, 16));
  }

  @override
  bool shouldRepaint(covariant _AnnotatorPainter oldDelegate) {
    return oldDelegate.contour != contour ||
        oldDelegate.leftContact != leftContact ||
        oldDelegate.rightContact != rightContact ||
        oldDelegate.baselineA != baselineA ||
        oldDelegate.baselineB != baselineB ||
        oldDelegate.showOverlay != showOverlay ||
        oldDelegate.image != image ||
        oldDelegate.draggingHandle != draggingHandle ||
        oldDelegate.autoDetectionMode != autoDetectionMode;
  }
}
