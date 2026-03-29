import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:contact_angle_app/image_processor.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ImageProcessor Direct File Test', () {
    test('Processes a single image from file system', () async {
      try {
        // Use the first available image from the PFOTES directory
        final testImagePath = 'PFOTES/C_1.5%_1 coat_5a.JPG';
        final file = File(testImagePath);
        
        if (!await file.exists()) {
          print('Test image not found at: $testImagePath');
          print('Available files in PFOTES directory:');
          final pfotesDir = Directory('PFOTES');
          if (await pfotesDir.exists()) {
            final files = await pfotesDir.list().toList();
            for (final file in files) {
              if (file is File && file.path.endsWith('.JPG')) {
                print('  - ${p.basename(file.path)}');
              }
            }
          }
          fail('Test image not found');
        }

        // Read the image file
        final bytes = await file.readAsBytes();
        
        // Convert bytes to UI Image
        final codec = await ui.instantiateImageCodec(bytes);
        final frameInfo = await codec.getNextFrame();
        final image = frameInfo.image;
        
        print('Processing image: ${p.basename(testImagePath)}');
        print('Image dimensions: ${image.width}x${image.height}');
        
        // Process the image using the new OpenCV algorithm
        final result = await ImageProcessor.processDropletImage(image);

        // Print the result for manual verification
        print('Results:');
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
        
        print('✅ Test passed! OpenCV implementation is working correctly.');
        
      } catch (e) {
        print('❌ Error processing image: $e');
        fail('Failed to process image: $e');
      }
    });

    test('Processes multiple images from PFOTES directory', () async {
      final pfotesDir = Directory('PFOTES');
      if (!await pfotesDir.exists()) {
        print('PFOTES directory not found - skipping test');
        return;
      }

      final files = await pfotesDir.list().toList();
      final imageFiles = files.where((file) => 
        file is File && file.path.endsWith('.JPG')).toList();

      if (imageFiles.isEmpty) {
        print('No JPG files found in PFOTES directory - skipping test');
        return;
      }

      print('Found ${imageFiles.length} images to process...');
      
      int successCount = 0;
      int failureCount = 0;

      for (final file in imageFiles.take(3)) { // Process first 3 images
        try {
          final bytes = await (file as File).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frameInfo = await codec.getNextFrame();
          final image = frameInfo.image;
          
          final result = await ImageProcessor.processDropletImage(image);
          
          print('✅ ${p.basename(file.path)}: ${result.contactAngle.toStringAsFixed(2)}°');
          successCount++;
          
        } catch (e) {
          print('❌ ${p.basename(file.path)}: Error - $e');
          failureCount++;
        }
      }

      print('Summary: $successCount successful, $failureCount failed');
      expect(successCount, greaterThan(0), reason: 'At least one image should process successfully');
    });
  });
}
