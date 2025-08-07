# App Icon Generation

This document explains how to generate custom app icons for the Contact Angle Measurement app.

## Custom Logo

The app uses a custom logo designed specifically for contact angle measurement:

- **Primary Element**: A water droplet with contact angle lines
- **Design**: Modern, scientific, and professional
- **Colors**: Blue primary color with white secondary color
- **Style**: Clean, minimalist, and recognizable

## Generated Icons

The custom logo has been integrated into the app in the following places:

1. **Splash Screen**: Large custom logo with animation
2. **App Bar**: Small custom logo next to the title
3. **Empty State**: Custom logo when no image is selected
4. **Results Screen**: Custom logo in the header

## Icon Files

The app currently uses the custom logo rendered dynamically. To generate static icon files for different platforms:

### Android Icons

Required sizes for Android:
- `mipmap-mdpi`: 48x48 px
- `mipmap-hdpi`: 72x72 px
- `mipmap-xhdpi`: 96x96 px
- `mipmap-xxhdpi`: 144x144 px
- `mipmap-xxxhdpi`: 192x192 px

### iOS Icons

Required sizes for iOS:
- `Icon-App-20x20@1x.png`: 20x20 px
- `Icon-App-20x20@2x.png`: 40x40 px
- `Icon-App-20x20@3x.png`: 60x60 px
- `Icon-App-29x29@1x.png`: 29x29 px
- `Icon-App-29x29@2x.png`: 58x58 px
- `Icon-App-29x29@3x.png`: 87x87 px
- `Icon-App-40x40@1x.png`: 40x40 px
- `Icon-App-40x40@2x.png`: 80x80 px
- `Icon-App-40x40@3x.png`: 120x120 px
- `Icon-App-60x60@2x.png`: 120x120 px
- `Icon-App-60x60@3x.png`: 180x180 px
- `Icon-App-76x76@1x.png`: 76x76 px
- `Icon-App-76x76@2x.png`: 152x152 px
- `Icon-App-83.5x83.5@2x.png`: 167x167 px
- `Icon-App-1024x1024@1x.png`: 1024x1024 px

### Web Icons

Required sizes for web:
- `Icon-192.png`: 192x192 px
- `Icon-512.png`: 512x512 px

## Implementation

The custom logo is implemented using Flutter's `CustomPainter` class in `lib/custom_logo.dart`. The logo features:

1. **Droplet Shape**: Realistic water droplet using Bezier curves
2. **Contact Angle Lines**: Visual representation of contact angle measurement
3. **Baseline**: Horizontal line representing the surface
4. **Highlights**: Subtle lighting effects for depth
5. **Color Scheme**: Blue primary color with white accents

## Usage

To use the custom logo in your widgets:

```dart
import 'package:your_app/custom_logo.dart';

// Large logo for splash screen
CustomLogo(
  size: 120,
  primaryColor: Colors.blue,
  secondaryColor: Colors.white,
)

// Small logo for app bar
CustomLogo(
  size: 32,
  primaryColor: Colors.white,
  secondaryColor: Colors.white,
)
```

## Future Enhancements

1. **Static Icon Generation**: Create a tool to generate static icon files
2. **Multiple Themes**: Support for different color schemes
3. **Animation**: Add subtle animations to the logo
4. **Platform-Specific**: Optimize logo for different platforms

## Notes

- The logo is designed to be scalable and look good at all sizes
- The design emphasizes the scientific nature of contact angle measurement
- The color scheme matches the app's overall design language
- The logo is fully customizable through the `CustomLogo` widget parameters 