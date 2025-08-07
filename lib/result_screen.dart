import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'dart:math'; // Added for cos and sin

class ResultScreen extends StatefulWidget {
  final String imagePath;
  final double leftAngle;
  final double rightAngle;
  final double averageAngle;
  final double uncertainty;
  final double eccentricity;
  final double bondNumber;
  final List<Offset> baselinePoints;
  final List<cv.Point2f> contourPoints;
  final double qualityScore; // New AI quality score
  final String confidence; // New AI confidence level

  const ResultScreen({
    super.key,
    required this.imagePath,
    required this.leftAngle,
    required this.rightAngle,
    required this.averageAngle,
    required this.uncertainty,
    required this.eccentricity,
    required this.bondNumber,
    required this.baselinePoints,
    required this.contourPoints,
    this.qualityScore = 0.0,
    this.confidence = 'Unknown',
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Color _getQualityColor() {
    // Use AI quality score if available, otherwise fall back to uncertainty-based quality
    if (widget.qualityScore > 0.0) {
      if (widget.qualityScore > 0.8) {
        return Colors.green;
      } else if (widget.qualityScore > 0.6) {
        return Colors.orange;
      } else {
        return Colors.red;
      }
    } else {
      // Fallback to original logic
      if (widget.uncertainty < 1.0 && (widget.leftAngle - widget.rightAngle).abs() < 3.0) {
        return Colors.green;
      } else if (widget.uncertainty < 2.0 && (widget.leftAngle - widget.rightAngle).abs() < 5.0) {
        return Colors.orange;
      } else {
        return Colors.red;
      }
    }
  }

  String _getQualityText() {
    // Use AI quality score if available, otherwise fall back to uncertainty-based quality
    if (widget.qualityScore > 0.0) {
      if (widget.qualityScore > 0.8) {
        return 'Excellent (AI)';
      } else if (widget.qualityScore > 0.6) {
        return 'Good (AI)';
      } else {
        return 'Fair (AI)';
      }
    } else {
      // Fallback to original logic
      if (widget.uncertainty < 1.0 && (widget.leftAngle - widget.rightAngle).abs() < 3.0) {
        return 'Excellent';
      } else if (widget.uncertainty < 2.0 && (widget.leftAngle - widget.rightAngle).abs() < 5.0) {
        return 'Good';
      } else {
        return 'Fair';
      }
    }
  }

  Future<void> _shareResults() async {
    final String text = '''
Contact Angle Measurement Results
================================
Average Angle: ${widget.averageAngle.toStringAsFixed(1)}° ± ${widget.uncertainty.toStringAsFixed(1)}°
Left Angle: ${widget.leftAngle.toStringAsFixed(1)}°
Right Angle: ${widget.rightAngle.toStringAsFixed(1)}°
Quality: ${_getQualityText()}
${widget.qualityScore > 0.0 ? 'AI Quality Score: ${(widget.qualityScore * 100).toStringAsFixed(1)}%' : ''}
${widget.confidence != 'Unknown' ? 'AI Confidence: ${widget.confidence}' : ''}
Bond Number: ${widget.bondNumber.toStringAsFixed(3)}
Eccentricity: ${widget.eccentricity.toStringAsFixed(3)}
''';
    
    await Share.share(text, subject: 'Contact Angle Measurement Results');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Measurement Results'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showOverlay ? Icons.layers : Icons.layers_outlined),
            onPressed: () {
              setState(() {
                _showOverlay = !_showOverlay;
              });
            },
            tooltip: 'Toggle Overlay',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareResults,
            tooltip: 'Share Results',
          ),
        ],
      ),
      body: Column(
        children: [
          // Results Summary Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _getQualityColor().withValues(alpha: 0.8),
                  _getQualityColor(),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _getQualityColor().withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Contact Angle',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _getQualityText(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      widget.averageAngle.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      '°',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '± ${widget.uncertainty.toStringAsFixed(1)}°',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildAngleInfo('Left', widget.leftAngle),
                    Container(
                      width: 1,
                      height: 40,
                      color: Colors.white30,
                    ),
                    _buildAngleInfo('Right', widget.rightAngle),
                  ],
                ),
                // AI Information
                if (widget.qualityScore > 0.0 || widget.confidence != 'Unknown')
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        if (widget.qualityScore > 0.0)
                          _buildAIInfo('Quality Score', '${(widget.qualityScore * 100).toStringAsFixed(1)}%'),
                        if (widget.confidence != 'Unknown')
                          _buildAIInfo('Confidence', widget.confidence),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                color: Theme.of(context).primaryColor,
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey[600],
              tabs: const [
                Tab(text: 'Image'),
                Tab(text: 'Details'),
                Tab(text: 'Quality'),
              ],
            ),
          ),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildImageTab(),
                _buildDetailsTab(),
                _buildQualityTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAngleInfo(String label, double angle) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${angle.toStringAsFixed(1)}°',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildAIInfo(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildImageTab() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              File(widget.imagePath),
              fit: BoxFit.contain,
            ),
            if (_showOverlay)
              CustomPaint(
                painter: AnalysisOverlayPainter(
                  baselinePoints: widget.baselinePoints,
                  contourPoints: widget.contourPoints,
                  leftAngle: widget.leftAngle,
                  rightAngle: widget.rightAngle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildDetailCard(
            'Measurement Details',
            Icons.analytics,
            [
              _DetailRow('Left Angle', '${widget.leftAngle.toStringAsFixed(2)}°'),
              _DetailRow('Right Angle', '${widget.rightAngle.toStringAsFixed(2)}°'),
              _DetailRow('Average', '${widget.averageAngle.toStringAsFixed(2)}°'),
              _DetailRow('Uncertainty', '±${widget.uncertainty.toStringAsFixed(2)}°'),
              _DetailRow('Asymmetry', '${(widget.leftAngle - widget.rightAngle).abs().toStringAsFixed(2)}°'),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailCard(
            'Physical Parameters',
            Icons.science,
            [
              _DetailRow('Eccentricity', widget.eccentricity.toStringAsFixed(3)),
              _DetailRow('Bond Number', widget.bondNumber.toStringAsFixed(3)),
              _DetailRow('Contour Points', widget.contourPoints.length.toString()),
            ],
          ),
          const SizedBox(height: 16),
          if (widget.bondNumber > 0.1)
            _buildWarningCard(
              'Gravity Effects',
              'Bond number > 0.1 indicates significant gravity effects. Consider using smaller droplets.',
              Icons.warning,
              Colors.amber,
            ),
          if ((widget.leftAngle - widget.rightAngle).abs() > 5)
            _buildWarningCard(
              'Asymmetric Measurement',
              'Large angle difference detected. Check baseline alignment and surface uniformity.',
              Icons.info,
              Colors.orange,
            ),
        ],
      ),
    );
  }

  Widget _buildQualityTab() {
    final qualityScore = _calculateQualityScore();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: CustomPaint(
              painter: QualityGaugePainter(
                score: qualityScore,
                color: _getQualityColor(),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${(qualityScore * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: _getQualityColor(),
                      ),
                    ),
                    Text(
                      'Quality Score',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          
          // AI Information Section
          if (widget.qualityScore > 0.0 || widget.confidence != 'Unknown')
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      const Text(
                        'AI Analysis',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (widget.qualityScore > 0.0)
                    _buildQualityCheckItem(
                      'AI Quality Score',
                      widget.qualityScore > 0.8,
                      'Quality Score > 80%',
                      '${(widget.qualityScore * 100).toStringAsFixed(1)}%',
                      isAI: true,
                    ),
                  if (widget.confidence != 'Unknown')
                    _buildQualityCheckItem(
                      'AI Confidence',
                      widget.confidence == 'High',
                      'Confidence: High',
                      widget.confidence,
                      isAI: true,
                    ),
                ],
              ),
            ),
          
          _buildQualityCheckItem(
            'Uncertainty',
            widget.uncertainty < 1,
            'Uncertainty < 1°',
            widget.uncertainty.toStringAsFixed(1),
          ),
          _buildQualityCheckItem(
            'Symmetry',
            (widget.leftAngle - widget.rightAngle).abs() < 3,
            'Asymmetry < 3°',
            (widget.leftAngle - widget.rightAngle).abs().toStringAsFixed(1),
          ),
          _buildQualityCheckItem(
            'Bond Number',
            widget.bondNumber < 0.1,
            'Bond Number < 0.1',
            widget.bondNumber.toStringAsFixed(3),
          ),
          _buildQualityCheckItem(
            'Eccentricity',
            widget.eccentricity < 0.8,
            'Eccentricity < 0.8',
            widget.eccentricity.toStringAsFixed(3),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCard(String title, IconData icon, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildWarningCard(String title, String message, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityCheckItem(String label, bool passed, String criteria, String value, {bool isAI = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: passed 
            ? (isAI ? Colors.blue.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1))
            : Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: passed 
              ? (isAI ? Colors.blue : Colors.green)
              : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            color: passed 
                ? (isAI ? Colors.blue : Colors.green)
                : Colors.red,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  criteria,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: passed ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateQualityScore() {
    // Use AI quality score if available
    if (widget.qualityScore > 0.0) {
      return widget.qualityScore;
    }
    
    // Fallback to manual calculation
    double score = 1.0;
    
    // Uncertainty factor
    if (widget.uncertainty > 2) {
      score -= 0.3;
    } else if (widget.uncertainty > 1) {
      score -= 0.15;
    }
    
    // Asymmetry factor
    final asymmetry = (widget.leftAngle - widget.rightAngle).abs();
    if (asymmetry > 5) {
      score -= 0.3;
    } else if (asymmetry > 3) {
      score -= 0.15;
    }
    
    // Bond number factor
    if (widget.bondNumber > 0.15) {
      score -= 0.2;
    } else if (widget.bondNumber > 0.1) {
      score -= 0.1;
    }
    
    // Eccentricity factor
    if (widget.eccentricity > 0.9) {
      score -= 0.2;
    } else if (widget.eccentricity > 0.8) {
      score -= 0.1;
    }
    
    return score.clamp(0.0, 1.0);
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class AnalysisOverlayPainter extends CustomPainter {
  final List<Offset> baselinePoints;
  final List<cv.Point2f> contourPoints;
  final double leftAngle;
  final double rightAngle;

  AnalysisOverlayPainter({
    required this.baselinePoints,
    required this.contourPoints,
    required this.leftAngle,
    required this.rightAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw contour with green color (like in sample images)
    if (contourPoints.isNotEmpty) {
      final contourPaint = Paint()
        ..color = Colors.green
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      for (int i = 0; i < contourPoints.length; i++) {
        final point = Offset(contourPoints[i].x, contourPoints[i].y);
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, contourPaint);
    }

    // Draw baseline with green color
    final baselinePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (baselinePoints.length == 2) {
      canvas.drawLine(baselinePoints[0], baselinePoints[1], baselinePaint);
      
      // Draw baseline points with green color
      final pointPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.fill;
      
      for (var point in baselinePoints) {
        canvas.drawCircle(point, 6, pointPaint);
        canvas.drawCircle(
          point, 
          6, 
          Paint()
            ..color = Colors.white
            ..strokeWidth = 2
            ..style = PaintingStyle.stroke,
        );
      }

      // Draw tangent lines with green color (like in sample images)
      _drawTangentLines(canvas, baselinePoints, leftAngle, rightAngle);
      
      // Draw angle indicators
      _drawAngleIndicator(canvas, baselinePoints[0], leftAngle, true);
      _drawAngleIndicator(canvas, baselinePoints[1], rightAngle, false);
    }
  }

  void _drawTangentLines(Canvas canvas, List<Offset> baselinePoints, double leftAngle, double rightAngle) {
    if (baselinePoints.length < 2) return;

    final tangentPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Calculate tangent lines at contact points
    final leftPoint = baselinePoints[0];
    final rightPoint = baselinePoints[1];
    
    // Calculate tangent angles (convert to radians)
    final leftAngleRad = leftAngle * pi / 180;
    final rightAngleRad = rightAngle * pi / 180;
    
    // Calculate tangent line lengths
    final tangentLength = 50.0;
    
    // Draw left tangent line
    final leftTangentEnd = Offset(
      leftPoint.dx - tangentLength * cos(leftAngleRad),
      leftPoint.dy - tangentLength * sin(leftAngleRad),
    );
    canvas.drawLine(leftPoint, leftTangentEnd, tangentPaint);
    
    // Draw right tangent line
    final rightTangentEnd = Offset(
      rightPoint.dx + tangentLength * cos(rightAngleRad),
      rightPoint.dy - tangentLength * sin(rightAngleRad),
    );
    canvas.drawLine(rightPoint, rightTangentEnd, tangentPaint);
  }

  void _drawAngleIndicator(Canvas canvas, Offset center, double angle, bool isLeft) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '${angle.toStringAsFixed(1)}°',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    final offset = Offset(
      center.dx + (isLeft ? -textPainter.width - 15 : 15),
      center.dy - textPainter.height / 2,
    );
    
    // Draw background rectangle
    final backgroundPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    
    final backgroundRect = Rect.fromLTWH(
      offset.dx - 5,
      offset.dy - 2,
      textPainter.width + 10,
      textPainter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, const Radius.circular(4)),
      backgroundPaint,
    );
    
    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class QualityGaugePainter extends CustomPainter {
  final double score;
  final Color color;

  QualityGaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 20;

    // Background arc
    final backgroundPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -225 * 3.14159 / 180,
      270 * 3.14159 / 180,
      false,
      backgroundPaint,
    );

    // Score arc
    final scorePaint = Paint()
      ..color = color
      ..strokeWidth = 20
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -225 * 3.14159 / 180,
      270 * 3.14159 / 180 * score,
      false,
      scorePaint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}