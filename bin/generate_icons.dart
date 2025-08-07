#!/usr/bin/env dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../lib/custom_logo.dart';

void main() async {
  print('Generating Contact Angle Measurement App Icons...');
  
  // Create output directory
  final outputDir = Directory('assets/app_icons');
  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }
  
  // Define icon sizes for different platforms
  final iconSizes = {
    'android': [48, 72, 96, 144, 192],
    'ios': [20, 29, 40, 60, 76, 83.5, 1024],
    'web': [192, 512],
  };
  
  for (final platform in iconSizes.keys) {
    print('\nGenerating $platform icons...');
    final platformDir = Directory('${outputDir.path}/$platform');
    if (!await platformDir.exists()) {
      await platformDir.create(recursive: true);
    }
    
    for (final size in iconSizes[platform]!) {
      await generateIcon(size.toDouble(), '${platformDir.path}/icon_${size}.png');
      print('  Generated icon_${size}.png');
    }
  }
  
  print('\n✅ All app icons generated successfully!');
  print('📁 Icons are saved in: ${outputDir.absolute.path}');
  print('\nTo use these icons:');
  print('1. Copy the Android icons to: android/app/src/main/res/mipmap-*');
  print('2. Copy the iOS icons to: ios/Runner/Assets.xcassets/AppIcon.appiconset/');
  print('3. Copy the web icons to: web/icons/');
}

Future<void> generateIcon(double size, String outputPath) async {
  // Create a widget tree with the custom logo
  final logo = CustomLogo(
    size: size,
    primaryColor: Colors.blue,
    secondaryColor: Colors.white,
  );
  
  // For now, we'll create a simple placeholder
  // In a real implementation, you'd need to render the widget to an image
  final bytes = await _createPlaceholderIcon(size);
  
  final file = File(outputPath);
  await file.writeAsBytes(bytes);
}

Future<Uint8List> _createPlaceholderIcon(double size) async {
  // This is a placeholder implementation
  // In a real scenario, you'd use Flutter's rendering pipeline
  // For now, we'll create a simple colored square as a placeholder
  
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = Colors.blue;
  
  // Draw background
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), paint);
  
  // Draw a simple droplet shape
  final dropletPath = Path();
  final center = Offset(size / 2, size / 2);
  final radius = size * 0.3;
  
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
  
  final dropletPaint = Paint()..color = Colors.white;
  canvas.drawPath(dropletPath, dropletPaint);
  
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  
  return byteData!.buffer.asUint8List();
} 