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
    void main() {
      TestWidgetsFlutterBinding.ensureInitialized();

      group('Contact Angle - ImageProcessor', () {
        final pfotesDir = Directory('PFOTES');

        test('Single image (edge case)', () async {
          final testImagePath = 'PFOTES/C_1.5%_1 coat_5a.JPG';
          final file = File(testImagePath);
          if (!await file.exists()) fail('Test image not found at $testImagePath');
          final bytes = await file.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final image = frame.image;
          final result = await ImageProcessor.processDropletImage(image);

          print('Contact Angle: ${result.contactAngle.toStringAsFixed(2)}°');
          print('Boundary points: ${result.boundary.length}');
          print('Left: ${result.leftContact}, Right: ${result.rightContact}');
          print('Baseline: ${result.baseline.startPoint}, ${result.baseline.endPoint}');
          print('Quality: ${(result.qualityScore * 100).toStringAsFixed(0)}%');
          expect(result.contactAngle, inInclusiveRange(0.0, 180.0));
          expect(result.boundary, isNotEmpty);
          expect(result.qualityScore, greaterThan(0.2));
        });

        test('Batch test on PFOTES/', () async {
          if (!await pfotesDir.exists()) fail('PFOTES/ directory not found!');
          final imageFiles = pfotesDir
              .listSync()
              .where((f) => f is File && f.path.endsWith('.JPG'))
              .map((e) => e.path)
              .toList();
          if (imageFiles.isEmpty) fail('No test images in PFOTES/');
          int ok = 0, failC = 0;

          for (final path in imageFiles) {
            try {
              final bytes = await File(path).readAsBytes();
              final codec = await ui.instantiateImageCodec(bytes);
              final frame = await codec.getNextFrame();
              final image = frame.image;
              final result = await ImageProcessor.processDropletImage(image);
              print('${p.basename(path)}: ${result.contactAngle.toStringAsFixed(1)}° (${(result.qualityScore * 100).toStringAsFixed(0)}%)');
              expect(result.contactAngle, inInclusiveRange(0.0, 180.0));
              expect(result.boundary, isNotEmpty);
              if (result.qualityScore > 0.4) ok++;
              else failC++;
            } catch (e) {
              print('Failed on $path: $e');
              failC++;
            }
          }
          print('Batch summary: $ok succeeded, $failC failed/poor quality');
          expect(ok, greaterThan(0));
        });
      });
    }
}
