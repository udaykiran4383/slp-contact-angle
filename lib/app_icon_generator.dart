import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'custom_logo.dart';

class AppIconGenerator {
  static Future<void> generateAppIcon({
    required double size,
    required String outputPath,
    Color primaryColor = Colors.blue,
    Color secondaryColor = Colors.white,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    // Create the logo
    final logo = CustomLogo(
      size: size,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    );
    
    // Render the logo
    final renderObject = logo.createRenderObject(null);
    renderObject.layout(BoxConstraints.tight(Size(size, size)));
    renderObject.paint(canvas, Offset.zero);
    
    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();
    
    // Save the image
    final file = File(outputPath);
    await file.writeAsBytes(bytes);
  }
  
  static Future<void> generateAllAppIcons() async {
    final sizes = [
      {'size': 20.0, 'name': 'ic_launcher_20.png'},
      {'size': 29.0, 'name': 'ic_launcher_29.png'},
      {'size': 40.0, 'name': 'ic_launcher_40.png'},
      {'size': 60.0, 'name': 'ic_launcher_60.png'},
      {'size': 76.0, 'name': 'ic_launcher_76.png'},
      {'size': 83.5, 'name': 'ic_launcher_83.5.png'},
      {'size': 1024.0, 'name': 'ic_launcher_1024.png'},
    ];
    
    final directory = await getApplicationDocumentsDirectory();
    final outputDir = Directory('${directory.path}/app_icons');
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }
    
    for (final sizeInfo in sizes) {
      final outputPath = '${outputDir.path}/${sizeInfo['name']}';
      await generateAppIcon(
        size: sizeInfo['size']!,
        outputPath: outputPath,
      );
      print('Generated: $outputPath');
    }
  }
} 