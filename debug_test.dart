import 'dart:io';

void main() async {
  print('Current directory: ${Directory.current.path}');
  
  final pfotesDir = Directory('PFOTES');
  print('PFOTES directory path: ${pfotesDir.path}');
  print('PFOTES exists: ${await pfotesDir.exists()}');
  
  if (await pfotesDir.exists()) {
    print('Files in PFOTES:');
    final files = await pfotesDir.list().toList();
    for (final file in files) {
      if (file is File) {
        print('  ${file.path}');
      }
    }
  }
} 