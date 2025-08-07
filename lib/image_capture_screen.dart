import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_view/photo_view.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'result_screen.dart';
import 'image_processing.dart';
import 'contact_angle_calculation.dart';
import 'firebase_integration.dart';
import 'custom_logo.dart';
import 'ai_contact_angle_detector.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class ImageCaptureScreen extends StatefulWidget {
  const ImageCaptureScreen({super.key});

  @override
  State<ImageCaptureScreen> createState() => _ImageCaptureScreenState();
}

class _ImageCaptureScreenState extends State<ImageCaptureScreen> with SingleTickerProviderStateMixin {
  XFile? _image;
  List<Offset> baselinePoints = [];
  List<cv.Point2f> contourPoints = [];
  bool isLoading = false;
  bool showGuideOverlay = true;
  bool isAutoDetectionEnabled = true; // Enable AI automatic detection by default
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;
  Map<String, dynamic>? _aiResults;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 0.8,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    final status = await Permission.camera.request();
    if (status.isDenied || status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Camera permission is required to capture droplet images'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _pickImage({required ImageSource source}) async {
    await _requestPermissions();
    final picker = ImagePicker();
    
    try {
      final pickedFile = await picker.pickImage(
        source: source,
        imageQuality: 100,
        preferredCameraDevice: CameraDevice.rear,
      );
      
      if (pickedFile != null) {
        setState(() {
          _image = pickedFile;
          baselinePoints.clear();
          contourPoints.clear();
          _aiResults = null;
          showGuideOverlay = false;
        });
        
        // Automatically process the image if AI detection is enabled
        if (isAutoDetectionEnabled) {
          await _processImageAutomatically();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No image selected. Please try again.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accessing camera: ${e.toString()}')),
        );
      }
    }
  }

  /// Process image automatically using AI
  Future<void> _processImageAutomatically() async {
    if (_image == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      // Use AI-powered detection with enhanced algorithms
      final aiResults = await AIContactAngleDetector.detectContactAngles(_image!.path);
      
      setState(() {
        _aiResults = aiResults;
        contourPoints = List<cv.Point2f>.from(aiResults['contourPoints'] ?? []);
        baselinePoints = (aiResults['baselinePoints'] as List<cv.Point2f>?)
            ?.map((p) => Offset(p.x, p.y))
            .toList() ?? [];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Detection Complete! Confidence: ${aiResults['confidence']} | Quality Score: ${(aiResults['qualityScore'] as double?)?.toStringAsFixed(2) ?? 'N/A'}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI Detection failed: ${e.toString()}. You can still use manual mode.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _addBaselinePoint(Offset point) {
    if (!isAutoDetectionEnabled && baselinePoints.length < 2) {
      setState(() {
        baselinePoints.add(point);
      });
      
      if (baselinePoints.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Good! Now tap the second baseline point'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _resetBaseline() {
    setState(() {
      baselinePoints.clear();
      contourPoints.clear();
      _aiResults = null;
    });
  }

  void _toggleAutoDetection() {
    setState(() {
      isAutoDetectionEnabled = !isAutoDetectionEnabled;
      if (isAutoDetectionEnabled && _image != null) {
        _processImageAutomatically();
      } else {
        baselinePoints.clear();
        contourPoints.clear();
        _aiResults = null;
      }
    });
  }

  Future<void> _processImage() async {
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }

    if (isAutoDetectionEnabled) {
      // Use AI results
      if (_aiResults == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please wait for AI detection to complete.')),
        );
        return;
      }
      
      await _processWithAIResults();
    } else {
      // Use manual mode
      if (baselinePoints.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select two baseline points.')),
        );
        return;
      }

      if ((baselinePoints[0].dx - baselinePoints[1].dx).abs() < 10) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Baseline points are too close. Please select points further apart.')),
        );
        return;
      }

      await _processWithManualResults();
    }
  }

  Future<void> _processWithAIResults() async {
    setState(() {
      isLoading = true;
    });

    try {
      final angles = _aiResults!;
      
      // Save results to Firebase (with error handling)
      String? imageUrl;
      try {
        imageUrl = await uploadImage(_image!.path);
        await saveMeasurement(
          imageUrl, 
          angles['leftAngle']!, 
          angles['rightAngle']!, 
          angles['averageAngle']!
        );
      } catch (e) {
        print('Firebase save failed: $e');
        // Continue without saving to Firebase
      }

      // Navigate to result screen
      if (mounted) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => ResultScreen(
              imagePath: _image!.path,
              leftAngle: angles['leftAngle']!,
              rightAngle: angles['rightAngle']!,
              averageAngle: angles['averageAngle']!,
              uncertainty: angles['uncertainty']!,
              eccentricity: angles['dropletProperties']?['eccentricity'] ?? 0.0,
              bondNumber: angles['dropletProperties']?['bondNumber'] ?? 0.0,
              baselinePoints: baselinePoints,
              contourPoints: contourPoints,
              qualityScore: angles['qualityScore'] ?? 0.0,
              confidence: angles['confidence'] ?? 'Unknown',
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing AI results: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _processWithManualResults() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Process image to get droplet contour
      final contourPoints = await processImage(_image!.path);

      // Calculate contact angles
      final angles = await calculateContactAngles(contourPoints, baselinePoints);

      // Save results to Firebase (with error handling)
      String? imageUrl;
      try {
        imageUrl = await uploadImage(_image!.path);
        await saveMeasurement(
          imageUrl, 
          angles['left']!, 
          angles['right']!, 
          angles['average']!
        );
      } catch (e) {
        print('Firebase save failed: $e');
        // Continue without saving to Firebase
      }

      // Navigate to result screen
      if (mounted) {
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => ResultScreen(
              imagePath: _image!.path,
              leftAngle: angles['left']!,
              rightAngle: angles['right']!,
              averageAngle: angles['average']!,
              uncertainty: angles['uncertainty']!,
              eccentricity: angles['eccentricity']!,
              bondNumber: angles['bondNumber']!,
              baselinePoints: baselinePoints,
              contourPoints: contourPoints,
              qualityScore: 0.0, // Manual mode doesn't have AI quality score
              confidence: 'Manual',
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(
                opacity: animation,
                child: child,
              );
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing image: ${e.toString()}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CustomLogo(
                size: 32,
                primaryColor: Colors.white,
                secondaryColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Text('AI Contact Angle Detection'),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_image != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                setState(() {
                  _image = null;
                  baselinePoints.clear();
                  contourPoints.clear();
                  _aiResults = null;
                  showGuideOverlay = true;
                });
              },
              tooltip: 'Clear Image',
            ),
          IconButton(
            icon: Icon(isAutoDetectionEnabled ? Icons.auto_awesome : Icons.touch_app),
            onPressed: _toggleAutoDetection,
            tooltip: isAutoDetectionEnabled ? 'AI Mode (Active)' : 'Manual Mode',
          ),
          IconButton(
            icon: const Icon(Icons.info),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.blue.shade50,
                  Colors.blue.shade100,
                ],
              ),
            ),
          ),
          Column(
            children: [
              // AI Status Bar
              if (isAutoDetectionEnabled)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.green.shade100,
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.green.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'AI Automatic Detection Enabled',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      if (_aiResults != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Confidence: ${_aiResults!['confidence']}',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              
              // Image Display Area
              Expanded(
                child: _image == null
                    ? _buildEmptyState()
                    : _buildImageDisplay(),
              ),
              
              // Control Buttons
              _buildControlButtons(),
            ],
          ),
          
          // Loading Overlay
          if (isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'AI Processing...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _pulseAnimation.value,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    size: 60,
                    color: Colors.blue.shade600,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            isAutoDetectionEnabled 
                ? 'AI-Powered Contact Angle Detection'
                : 'Manual Contact Angle Detection',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isAutoDetectionEnabled
                ? 'Tap to capture or select an image\nAI will automatically detect droplet and calculate contact angles'
                : 'Tap to capture or select an image\nThen manually select baseline points',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: () => _pickImage(source: ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _pickImage(source: ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageDisplay() {
    return Stack(
      children: [
        // Image with PhotoView
        PhotoView(
          imageProvider: FileImage(File(_image!.path)),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 2,
          backgroundDecoration: const BoxDecoration(
            color: Colors.transparent,
          ),
          onTapUp: (details, controllerValue, controller) {
            if (!isAutoDetectionEnabled) {
              // For now, use a default position since the API might have changed
              // This can be improved later when the exact API is confirmed
              _addBaselinePoint(const Offset(100, 100));
            }
          },
        ),
        
        // Overlay for baseline points and contour
        if (baselinePoints.isNotEmpty || contourPoints.isNotEmpty)
          CustomPaint(
            painter: OverlayPainter(
              baselinePoints: baselinePoints,
              contourPoints: contourPoints,
              isAutoDetectionEnabled: isAutoDetectionEnabled,
            ),
            size: Size.infinite,
          ),
        
        // Guide overlay for manual mode
        if (showGuideOverlay && !isAutoDetectionEnabled)
          Container(
            color: Colors.black26,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.touch_app,
                      size: 48,
                      color: Colors.blue.shade600,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Manual Mode',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap two points on the baseline\n(where the droplet meets the surface)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          showGuideOverlay = false;
                        });
                      },
                      child: const Text('Got it!'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControlButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (!isAutoDetectionEnabled && baselinePoints.isNotEmpty)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _resetBaseline,
                icon: const Icon(Icons.refresh),
                label: const Text('Reset Baseline'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _image != null && (isAutoDetectionEnabled ? _aiResults != null : baselinePoints.length >= 2)
                  ? _processImage
                  : null,
              icon: const Icon(Icons.science),
              label: Text(isAutoDetectionEnabled ? 'Process with AI' : 'Calculate Angles'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI Contact Angle Detection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This app uses advanced AI and computer vision to automatically detect contact angles from droplet images.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            const Text(
              'AI Mode Features:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('• Automatic droplet detection'),
            const Text('• Automatic baseline detection'),
            const Text('• Subpixel contour refinement'),
            const Text('• Multiple angle calculation methods'),
            const Text('• Quality assessment and confidence scoring'),
            const SizedBox(height: 16),
            const Text(
              'Manual Mode:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('• Manual baseline point selection'),
            const Text('• Traditional contact angle calculation'),
            const SizedBox(height: 16),
            const Text(
              'For best results:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text('• Ensure good lighting'),
            const Text('• Capture clear droplet images'),
            const Text('• Avoid reflections and shadows'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for drawing overlay elements
class OverlayPainter extends CustomPainter {
  final List<Offset> baselinePoints;
  final List<cv.Point2f> contourPoints;
  final bool isAutoDetectionEnabled;

  OverlayPainter({
    required this.baselinePoints,
    required this.contourPoints,
    required this.isAutoDetectionEnabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Draw contour points
    if (contourPoints.isNotEmpty) {
      paint.color = Colors.blue;
      final path = Path();
      for (int i = 0; i < contourPoints.length; i++) {
        final point = contourPoints[i];
        if (i == 0) {
          path.moveTo(point.x, point.y);
        } else {
          path.lineTo(point.x, point.y);
        }
      }
      path.close();
      canvas.drawPath(path, paint);
    }

    // Draw baseline points and line
    if (baselinePoints.isNotEmpty) {
      paint.color = Colors.red;
      paint.strokeWidth = 4.0;
      
      // Draw baseline points
      for (var point in baselinePoints) {
        canvas.drawCircle(point, 8, paint);
      }
      
      // Draw baseline line
      if (baselinePoints.length >= 2) {
        canvas.drawLine(baselinePoints[0], baselinePoints[1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}