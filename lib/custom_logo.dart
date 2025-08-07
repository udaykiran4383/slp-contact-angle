import 'package:flutter/material.dart';

class CustomLogo extends StatelessWidget {
  final double size;
  final Color? primaryColor;
  final Color? secondaryColor;

  const CustomLogo({
    super.key,
    this.size = 120,
    this.primaryColor,
    this.secondaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final primary = primaryColor ?? Theme.of(context).primaryColor;
    final secondary = secondaryColor ?? Colors.white;

    return CustomPaint(
      size: Size(size, size),
      painter: ContactAngleLogoPainter(
        primaryColor: primary,
        secondaryColor: secondary,
      ),
    );
  }
}

class ContactAngleLogoPainter extends CustomPainter {
  final Color primaryColor;
  final Color secondaryColor;

  ContactAngleLogoPainter({
    required this.primaryColor,
    required this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.35;

    // Background circle
    final backgroundPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(center, radius + 10, backgroundPaint);

    // Main droplet shape
    final dropletPath = Path();
    final dropletCenter = Offset(center.dx, center.dy - radius * 0.2);
    
    // Create droplet shape using Bezier curves
    dropletPath.moveTo(dropletCenter.dx - radius * 0.6, dropletCenter.dy - radius * 0.3);
    dropletPath.quadraticBezierTo(
      dropletCenter.dx - radius * 0.8,
      dropletCenter.dy - radius * 0.8,
      dropletCenter.dx,
      dropletCenter.dy - radius * 1.2,
    );
    dropletPath.quadraticBezierTo(
      dropletCenter.dx + radius * 0.8,
      dropletCenter.dy - radius * 0.8,
      dropletCenter.dx + radius * 0.6,
      dropletCenter.dy - radius * 0.3,
    );
    dropletPath.quadraticBezierTo(
      dropletCenter.dx + radius * 0.4,
      dropletCenter.dy + radius * 0.2,
      dropletCenter.dx,
      dropletCenter.dy + radius * 0.4,
    );
    dropletPath.quadraticBezierTo(
      dropletCenter.dx - radius * 0.4,
      dropletCenter.dy + radius * 0.2,
      dropletCenter.dx - radius * 0.6,
      dropletCenter.dy - radius * 0.3,
    );

    // Droplet fill
    final dropletPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(dropletPath, dropletPaint);

    // Droplet outline
    final outlinePaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawPath(dropletPath, outlinePaint);

    // Contact angle lines
    final anglePaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    // Left contact angle line
    final leftStart = Offset(dropletCenter.dx - radius * 0.4, dropletCenter.dy + radius * 0.1);
    final leftEnd = Offset(dropletCenter.dx - radius * 0.8, dropletCenter.dy - radius * 0.2);
    canvas.drawLine(leftStart, leftEnd, anglePaint);

    // Right contact angle line
    final rightStart = Offset(dropletCenter.dx + radius * 0.4, dropletCenter.dy + radius * 0.1);
    final rightEnd = Offset(dropletCenter.dx + radius * 0.8, dropletCenter.dy - radius * 0.2);
    canvas.drawLine(rightStart, rightEnd, anglePaint);

    // Baseline
    final baselinePaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final baselineStart = Offset(dropletCenter.dx - radius * 0.8, dropletCenter.dy + radius * 0.3);
    final baselineEnd = Offset(dropletCenter.dx + radius * 0.8, dropletCenter.dy + radius * 0.3);
    canvas.drawLine(baselineStart, baselineEnd, baselinePaint);

    // Angle indicators
    final indicatorPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Left angle arc
    final leftArcRect = Rect.fromCenter(
      center: leftStart,
      width: radius * 0.3,
      height: radius * 0.3,
    );
    canvas.drawArc(leftArcRect, 0, -0.8, false, indicatorPaint);

    // Right angle arc
    final rightArcRect = Rect.fromCenter(
      center: rightStart,
      width: radius * 0.3,
      height: radius * 0.3,
    );
    canvas.drawArc(rightArcRect, 3.14, 0.8, false, indicatorPaint);

    // Add some highlights
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final highlightPath = Path();
    highlightPath.moveTo(dropletCenter.dx - radius * 0.3, dropletCenter.dy - radius * 0.6);
    highlightPath.quadraticBezierTo(
      dropletCenter.dx - radius * 0.1,
      dropletCenter.dy - radius * 0.8,
      dropletCenter.dx + radius * 0.1,
      dropletCenter.dy - radius * 0.6,
    );
    highlightPath.quadraticBezierTo(
      dropletCenter.dx,
      dropletCenter.dy - radius * 0.4,
      dropletCenter.dx - radius * 0.3,
      dropletCenter.dy - radius * 0.6,
    );

    canvas.drawPath(highlightPath, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Alternative simpler logo for smaller sizes
class SimpleContactAngleLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const SimpleContactAngleLogo({
    super.key,
    this.size = 48,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final logoColor = color ?? Theme.of(context).primaryColor;

    return CustomPaint(
      size: Size(size, size),
      painter: SimpleLogoPainter(color: logoColor),
    );
  }
}

class SimpleLogoPainter extends CustomPainter {
  final Color color;

  SimpleLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.3;

    // Simple droplet shape
    final dropletPath = Path();
    dropletPath.moveTo(center.dx - radius * 0.5, center.dy);
    dropletPath.quadraticBezierTo(
      center.dx - radius * 0.7,
      center.dy - radius * 0.7,
      center.dx,
      center.dy - radius * 1.1,
    );
    dropletPath.quadraticBezierTo(
      center.dx + radius * 0.7,
      center.dy - radius * 0.7,
      center.dx + radius * 0.5,
      center.dy,
    );
    dropletPath.quadraticBezierTo(
      center.dx + radius * 0.3,
      center.dy + radius * 0.3,
      center.dx,
      center.dy + radius * 0.5,
    );
    dropletPath.quadraticBezierTo(
      center.dx - radius * 0.3,
      center.dy + radius * 0.3,
      center.dx - radius * 0.5,
      center.dy,
    );

    // Fill droplet
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(dropletPath, fillPaint);

    // Add contact angle lines
    final linePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Left line
    canvas.drawLine(
      Offset(center.dx - radius * 0.3, center.dy + radius * 0.2),
      Offset(center.dx - radius * 0.6, center.dy - radius * 0.1),
      linePaint,
    );

    // Right line
    canvas.drawLine(
      Offset(center.dx + radius * 0.3, center.dy + radius * 0.2),
      Offset(center.dx + radius * 0.6, center.dy - radius * 0.1),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 