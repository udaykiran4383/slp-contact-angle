import 'package:flutter/material.dart';
import 'widgets/image_annotator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SlpContactAngleApp());
}

class SlpContactAngleApp extends StatelessWidget {
  const SlpContactAngleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData dark = ThemeData.dark();
    return MaterialApp(
      title: 'SLP Contact Angle',
      theme: dark.copyWith(
        scaffoldBackgroundColor: Colors.black, // pure black background
        colorScheme: dark.colorScheme.copyWith(
          primary: Colors.tealAccent,
          secondary: Colors.cyanAccent,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
      ),
      home: const ImageAnnotatorScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}