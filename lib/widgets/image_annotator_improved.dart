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
import '../processing/angle_utils.dart'; // Import for tangent calculation

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
  double? _qualityScore;
  bool _isProcessing = false;
  String? _dragging;
  bool _autoDetectionMode = true;
  String _processingStatus = 'Ready';

  final List<String> _testImagePaths = [
    'PFOTES/C_1.5%_1 coat_5a.JPG',
    'PFOTES/C_1.5%_1 coat_5b.JPG',
    'PFOTES/C_1.5%_1 coat_6.JPG',
    'PFOTES/C_1.5%_2 coat_5.JPG',
    'PFOTES/C_1.5%_2 coat_6.JPG',
    'PFOTES/C_3%_1 coat_5.JPG',
    'PFOTES/C_3%_1 coat_5a.JPG',
    'PFOTES/C_3%_1 coat_6a.JPG',
    'PFOTES/C_3%_1 coat_6b.JPG',
    'PFOTES/C_3%_2 coat_5a.JPG',
    'PFOTES/C_3%_2 coat_5b.JPG',
    'PFOTES/C_3%_2 coat_6a.JPG',
    'PFOTES/C_3%_2 coat_6b.JPG',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initMock());
  }

  void _initMock() {
    setState(() {
      _image = null;
      _contour = [];
      _leftContact = null;
      _rightContact = null;
      _baselineA = null;
      _baselineB = null;
      _measuredAngle = 0.0;
      _isProcessing = false;
      _processingStatus = 'Ready';
    });
  }

  Future<void> _runTestBatch() async {
    setState(() {
      _isProcessing = true;
      _processingStatus = 'Running test batch...';
      _image = null;
      _contour = [];
      _leftContact = null;
      _rightContact = null;
      _baselineA = null;
      _baselineB = null;
    });

    final allResults = <ProcessedImageData>[];

    for (var path in _testImagePaths) {
      setState(() {
        _processingStatus = 'Processing $path...';
      });
      try {
        final ByteData bytes = await rootBundle.load('assets/$path');
        final ui.Image image = await decodeImageFromList(bytes.buffer.asUint8List());
        final processedData = await ImageProcessor.processDropletImage(image);
        allResults.add(processedData);
      } catch (e) {
        debugPrint('Error processing image $path: $e');
      }
    }

    if (mounted) {
      setState(() {
        _isProcessing = false;
        _processingStatus = 'Batch analysis complete';
      });
      _showBatchResults(allResults);
    }
  }

  void _showBatchResults(List<ProcessedImageData> results) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        title: const Text(
          'Batch Test Results',
          style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final result = results[index];
              final imagePath = _testImagePaths[index].split('/').last;
              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  title: Text(
                    imagePath,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Contact Angle: ${result.contactAngle.toStringAsFixed(2)}°',
                        style: const TextStyle(color: Colors.cyanAccent),
                      ),
                      Text(
                        'Quality Score: ${(result.qualityScore * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          color: result.qualityScore > 0.8 
                            ? Colors.green 
                            : result.qualityScore > 0.6 
                              ? Colors.orange 
                              : Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
    );
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
      await _performAutomaticDetection(image);
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
      final processedData = await ImageProcessor.processDropletImage(image);
      if (mounted) {
      setState(() {
          _contour = processedData.boundary;
          _leftContact = processedData.leftContact;
          _rightContact = processedData.rightContact;
          _baselineA = processedData.baseline.startPoint;
          _baselineB = processedData.baseline.endPoint;
          _measuredAngle = processedData.contactAngle;
          _qualityScore = processedData.qualityScore;
          _processingStatus = 'Detection complete - Angle: ${processedData.contactAngle.toStringAsFixed(1)}° (Quality: ${(processedData.qualityScore * 100).toStringAsFixed(0)}%)';
        });
      }
    } catch (e) {
      debugPrint('Automatic detection failed: $e');
      if (mounted) {
      setState(() {
          _processingStatus = 'Automatic detection failed.';
        });
      }
    }
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
      'quality_score': _qualityScore,
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
      ..writeln('measured_angle_deg,,${_measuredAngle.toStringAsFixed(3)}')
      ..writeln('quality_score,,${_qualityScore?.toStringAsFixed(3) ?? "N/A"}');
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
                      RepaintBoundary(
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
              ),
              child: Container(),
            ),
          ),
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
                // Quality Score Display
                if (_qualityScore != null)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _qualityScore! > 0.8 
                          ? Colors.green 
                          : _qualityScore! > 0.6 
                            ? Colors.orange 
                            : Colors.red,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _qualityScore! > 0.8 
                            ? Icons.check_circle 
                            : _qualityScore! > 0.6 
                              ? Icons.warning 
                              : Icons.error,
                          color: _qualityScore! > 0.8 
                            ? Colors.green 
                            : _qualityScore! > 0.6 
                              ? Colors.orange 
                              : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Detection Quality: ${(_qualityScore! * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _qualityScore! > 0.8 
                            ? 'Excellent' 
                            : _qualityScore! > 0.6 
                              ? 'Good' 
                              : 'Poor',
                          style: TextStyle(
                            color: _qualityScore! > 0.8 
                              ? Colors.green 
                              : _qualityScore! > 0.6 
                                ? Colors.orange 
                                : Colors.red,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.upload_file,
                        label: 'Load Image',
                        color: Colors.lightBlue,
                        onPressed: _captureImage,
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildControlButton(
                        icon: Icons.auto_awesome,
                        label: 'Run Test Batch',
                        color: Colors.green,
                        onPressed: _runTestBatch,
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

  _AnnotatorPainter({
    required this.contour,
    this.leftContact,
    this.rightContact,
    this.baselineA,
    this.baselineB,
    required this.showOverlay,
    this.image,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image != null) {
    final paint = Paint();
      final src = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(image!, src, dst, paint);
    } else {
      canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    }
    if (!showOverlay) return;
    if (contour.isNotEmpty) {
      final Paint contourPaint = Paint()
        ..color = Colors.greenAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
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
    if (leftContact != null && rightContact != null && baselineA != null && baselineB != null) {
      _drawAngleArc(canvas);
    }
    _drawLegend(canvas);
  }
  void _drawContactPoint(Canvas canvas, Offset point) {
    final Color pointColor = Colors.greenAccent;
    final Paint glowPaint = Paint()
      ..color = pointColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    final Paint contactPaint = Paint()
      ..color = pointColor
        ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    const double radius = 8.0;
    const double glowRadius = 12.0;
    canvas.drawCircle(point, glowRadius, glowPaint);
    canvas.drawCircle(point, radius, contactPaint);
    canvas.drawCircle(point, radius, borderPaint);
    final Paint centerPaint = Paint()..color = Colors.white;
    canvas.drawCircle(point, 2.0, centerPaint);
  }
  void _drawBaselineHandle(Canvas canvas, Offset point) {
    final Paint glowPaint = Paint()
      ..color = Colors.cyanAccent.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    final Paint handlePaint = Paint()
      ..color = Colors.cyanAccent
        ..style = PaintingStyle.fill;
    final Paint borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    const double radius = 7.0;
    const double glowRadius = 10.0;
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
        oldDelegate.image != image;
  }
}