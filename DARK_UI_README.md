# Dark UI + Image Annotator for Contact Angle App

## 🎨 New Features

### Dark Theme
- **Pure black background** for professional lab UI
- **Neon accent colors**: teal, cyan, amber for visibility
- **Modern Material Design** with dark theme integration

### Image Annotator Screen
- **Interactive overlay system** with toggle visibility
- **Draggable contact points** (red handles) for precise positioning
- **Draggable baseline endpoints** (blue handles) for baseline adjustment
- **Real-time angle calculation** with live updates
- **Visual feedback** with contour, tangent lines, and angle labels

### Export Capabilities
- **PNG export** with high-resolution (3x pixel ratio)
- **JSON export** with structured data including coordinates and angles
- **CSV export** for spreadsheet compatibility
- **Share integration** for easy file sharing

## 🚀 Usage

### Running the App
```bash
flutter pub get
flutter run
```

### Key Interactions
1. **Toggle Overlays**: Use the eye icon in the app bar
2. **Drag Contact Points**: Touch and drag the red circular handles
3. **Adjust Baseline**: Touch and drag the blue circular handles
4. **Export Images**: Use the save icon or bottom bar button
5. **Export Data**: Use the menu (3 dots) in the app bar

### Integration Points

#### Replacing Mock Contour
Replace the mock contour generation in `_initMockContour()` with your actual contour data:

```dart
// Replace this mock generation:
_contour = List.generate(120, (i) {
  final t = i / 120.0 * 2 * math.pi;
  final rx = 130.0 + 10.0 * (i % 6);
  final ry = 90.0 + 6.0 * ((i + 3) % 7);
  return center + Offset(rx * math.cos(t), ry * math.sin(t));
});

// With your actual contour data:
_contour = yourContourPoints.map((p) => Offset(p.x, p.y)).toList();
```

#### Adding Real Images
To display actual images instead of the black background:

```dart
// In ContactAnglePainter.paint():
// Add this before drawing overlays:
if (image != null) {
  canvas.drawImage(image, Offset.zero, Paint());
}
```

## 📁 File Structure

```
lib/
├── main.dart                    # Updated with dark theme
├── widgets/
│   └── image_annotator.dart     # New image annotator screen
└── ...
```

## 🎯 Key Components

### ImageAnnotatorScreen
- Main widget for the annotation interface
- Handles touch interactions and state management
- Manages export functionality

### ContactAnglePainter
- Custom painter for drawing overlays
- Renders contour, tangent lines, handles, and labels
- Supports real-time updates

## 🔧 Customization

### Colors
Modify the accent colors in `main.dart`:
```dart
colorScheme: dark.colorScheme.copyWith(
  primary: Colors.tealAccent,    // Change for different accent
  secondary: Colors.cyanAccent,  // Change for different accent
),
```

### Handle Sizes
Adjust handle sizes in `ContactAnglePainter`:
```dart
// Contact point handles (red)
canvas.drawCircle(p1!, 8, handle);  // Change 8 to adjust size

// Baseline handles (blue)  
canvas.drawCircle(baselineA!, 6, handle2);  // Change 6 to adjust size
```

## 📊 Data Export Format

### JSON Export
```json
{
  "contact_point_left": {"x": 123.45, "y": 67.89},
  "contact_point_right": {"x": 234.56, "y": 78.90},
  "baseline_a": {"x": 100.0, "y": 150.0},
  "baseline_b": {"x": 300.0, "y": 150.0},
  "measured_angle_deg": 45.67,
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

### CSV Export
```csv
label,x,y
contact_point_left,123.45,67.89
contact_point_right,234.56,78.90
baseline_a,100.0,150.0
baseline_b,300.0,150.0
measured_angle_deg,45.67,
```

## 🎨 UI/UX Features

- **Professional dark theme** suitable for laboratory environments
- **High contrast** neon accents for visibility
- **Intuitive touch interactions** for precise measurements
- **Real-time feedback** with live angle calculations
- **Export capabilities** for data analysis and sharing

## 🔄 Next Steps

1. **Integrate real image processing** to replace mock contour
2. **Add confidence indicators** for measurement accuracy
3. **Implement keyboard shortcuts** for desktop builds
4. **Add measurement history** with local storage
5. **Enhance tangent calculation** with subpixel precision
