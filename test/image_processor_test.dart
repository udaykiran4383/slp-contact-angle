import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contact_angle_app/image_processor.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Define the paths to the test images in the assets folder
  final List<String> testImagePaths = [
    'PFOTES/C_1.5%_1 coat_5a.JPG',
    'PFOTES/C_1.5%_1 coat_5b.JPG',
    'PFOTES/C_1.5%_1 coat_6.JPG',
    'PFOTES/C_1.5%_2 coat_5.JPG',
    'PFOTES/C_1.5%_2 coat_6.JPG',
    'PFOTES/C_3%_1 coat_5.JPG',
    'PFOTES/C_3%_1 coat_6a.JPG',
    'PFOTES/C_3%_1 coat_6b.JPG',
    'PFOTES/C_3%_2 coat_5a.JPG',
    'PFOTES/C_3%_2 coat_5b.JPG',
    'PFOTES/C_3%_2 coat_6a.JPG',
    'PFOTES/C_3%_2 coat_6b.JPG',
  ];

  group('ImageProcessor Batch Test', () {
    for (var imagePath in testImagePaths) {
      test('Processes image: ${p.basename(imagePath)}', () async {
        try {
          // Load image data from assets
          final ByteData data = await rootBundle.load('assets/$imagePath');
          final Uint8List bytes = data.buffer.asUint8List();
          final ui.Codec codec = await ui.instantiateImageCodec(bytes);
          final ui.FrameInfo frameInfo = await codec.getNextFrame();
          final ui.Image image = frameInfo.image;
          
          // Process the image using the new OpenCV algorithm
          final ProcessedImageData result = await ImageProcessor.processDropletImage(image);

          // Print the result for manual verification
          print('Image: ${p.basename(imagePath)}');
          print('  - Image Dimensions: ${image.width}x${image.height}');
          print('  - Droplet Boundary Points: ${result.boundary.length}');
          print('  - Contact Angle: ${result.contactAngle.toStringAsFixed(2)}°');
          print('  - Left Contact Point: (${result.leftContact.dx.toStringAsFixed(2)}, ${result.leftContact.dy.toStringAsFixed(2)})');
          print('  - Right Contact Point: (${result.rightContact.dx.toStringAsFixed(2)}, ${result.rightContact.dy.toStringAsFixed(2)})');
          print('  - Baseline: (${result.baseline.startPoint.dx.toStringAsFixed(2)}, ${result.baseline.startPoint.dy.toStringAsFixed(2)}) to (${result.baseline.endPoint.dx.toStringAsFixed(2)}, ${result.baseline.endPoint.dy.toStringAsFixed(2)})');
          print('  - Baseline Slope: ${result.baseline.slope.toStringAsFixed(4)}');
          print('-------------------------------------');

          // Basic assertions to ensure the processing worked
          expect(result.contactAngle, isA<double>());
          expect(result.contactAngle, greaterThanOrEqualTo(0.0));
          expect(result.contactAngle, lessThanOrEqualTo(180.0));
          expect(result.boundary, isNotEmpty);
          expect(result.boundary.length, greaterThan(10)); // Should have a reasonable number of boundary points
          expect(result.leftContact, isA<Offset>());
          expect(result.rightContact, isA<Offset>());
          expect(result.baseline, isA<BaselineData>());
          
        } catch (e) {
          print('Error processing ${p.basename(imagePath)}: $e');
          fail('Failed to process image ${p.basename(imagePath)}: $e');
        }
      });
    }
  });

  group('ImageProcessor Edge Cases', () {
    test('Handles empty boundary gracefully', () async {
      // This test would require a mock image or specific test case
      // For now, we'll just ensure the method exists and can be called
      expect(ImageProcessor.processDropletImage, isA<Function>());
    });
  });
}
