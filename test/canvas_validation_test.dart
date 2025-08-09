import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:contact_angle_app/image_processor.dart';

Future<ui.Image> _decode(String path) async {
  final bytes = await io.File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Only include files that exist in PFOTES snapshot
  final samples = <String, double>{
    // Provided Canvas results (degrees)
    'PFOTES/C_1.5%_1 coat_5a.JPG': 112.088,
    'PFOTES/C_3%_2 coat_6a.JPG': 126.337,
    'PFOTES/C_3%_2 coat_6b.JPG': 132.711,
  };

  const toleranceDeg = 3.0; // acceptable deviation

  samples.forEach((path, expectedAngle) {
    test('Validate $path vs Canvas=$expectedAngle°', () async {
      final file = io.File(path);
      if (!file.existsSync()) {
        fail('Missing test image: $path');
      }
      final img = await _decode(path);
      final result = await ImageProcessor.processDropletImageAuto(img, debug: false, maxDim: 1200);
      // Compare using the most reliable automatically-selected side
      final ours = result.bestAngle;
      final diff = (ours - expectedAngle).abs();
      // Print details for visibility
      // ignore: avoid_print
      print('File: $path  ours=${ours.toStringAsFixed(3)}  expected=${expectedAngle.toStringAsFixed(3)}  diff=${diff.toStringAsFixed(3)}');
      expect(diff, lessThanOrEqualTo(toleranceDeg));
    });
  });
}


