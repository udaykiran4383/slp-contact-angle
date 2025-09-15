import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart' as path_provider;
import 'package:path/path.dart' as path;

/// Creates a temporary file from image bytes
Future<File> tempFileFromPixels(Uint8List imageData) async {
  final tempDir = await path_provider.getTemporaryDirectory();
  final tempPath = path.join(tempDir.path, 'temp_${DateTime.now().millisecondsSinceEpoch}.jpg');
  final file = File(tempPath);
  await file.writeAsBytes(imageData);
  return file;
}