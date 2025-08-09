import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:contact_angle_app/image_processor.dart';

Future<ui.Image> _decodeImageFromFile(String path) async {
  final bytes = await io.File(path).readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Automatic processing on sample PFOTES images', () {
    Future<void> _runOn(String relativePath) async {
      final root = io.Directory.current.path;
      final path = io.Platform.isWindows
          ? '$root\\$relativePath'
          : '$root/$relativePath';
      final img = await _decodeImageFromFile(path);
      final res = await ImageProcessor.processDropletImageAuto(img, debug: false, maxDim: 1000);

      // Basic validity checks
      expect(res.boundary.length, greaterThan(50), reason: 'Boundary must have enough points');
      expect(res.leftAngle, inExclusiveRange(0.0, 180.0));
      expect(res.rightAngle, inExclusiveRange(0.0, 180.0));
      expect(res.avgAngle, inExclusiveRange(0.0, 180.0));

      // Contact points should lie inside the image bounds
      expect(res.leftContact.dx, inInclusiveRange(0.0, img.width.toDouble()));
      expect(res.leftContact.dy, inInclusiveRange(0.0, img.height.toDouble()));
      expect(res.rightContact.dx, inInclusiveRange(0.0, img.width.toDouble()));
      expect(res.rightContact.dy, inInclusiveRange(0.0, img.height.toDouble()));
    }

    test('PFOTES/C_1.5%_1 coat_5a.JPG', () async {
      await _runOn('PFOTES/C_1.5%_1 coat_5a.JPG');
    });

    test('PFOTES/C_3%_1 coat_6b.JPG', () async {
      await _runOn('PFOTES/C_3%_1 coat_6b.JPG');
    });

    test('PFOTES/C_3%_2 coat_6b.JPG', () async {
      await _runOn('PFOTES/C_3%_2 coat_6b.JPG');
    });
  });
}


