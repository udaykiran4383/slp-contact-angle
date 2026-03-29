// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:contact_angle_app/main.dart';

void main() {
  testWidgets('Contact Angle App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const SlpContactAngleApp());

    // Verify app loads and shows key UI elements
    expect(find.byType(MaterialApp), findsOneWidget);
    // App bar title contains Contact Angle
    expect(find.textContaining('Contact Angle'), findsWidgets);
    // Process button is present on initial screen
    expect(find.text('Load example image & Auto-process'), findsOneWidget);
  });
}
