import 'package:flutter/material.dart';
import 'widgets/image_annotator_improved.dart';

void main() {
  runApp(const ContactAngleApp());
}

class ContactAngleApp extends StatelessWidget {
  const ContactAngleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contact Angle Measurement',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        primaryColor: Colors.blue[600],
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[900],
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[600],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.blue[400],
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
        cardTheme: CardThemeData(
          color: Colors.grey[850],
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Colors.grey[850],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.blue[400];
            }
            return Colors.grey[400];
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.blue[200]?.withValues(alpha: 0.5);
            }
            return Colors.grey[600];
          }),
        ),
        colorScheme: ColorScheme.dark(
          primary: Colors.blue[600]!,
          secondary: Colors.blue[400]!,
          surface: Colors.grey[850]!,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Colors.white,
        ),
      ),
      home: const ImageAnnotatorImproved(),
      debugShowCheckedModeBanner: false,
    );
  }
}