# 📐 Contact Angle Measurement App

A professional Flutter application for measuring water droplet contact angles using automatic computer vision detection and direct geometric calculation. This app provides objective, reproducible contact angle measurements without AI/ML complexity.

## 🎯 Key Features

### 🤖 **Automatic Detection Mode (Default)**
- **Zero Human Interaction Required** - Just capture image and get results
- **Automatic Droplet Boundary Detection** - Canny edge detection with connected component analysis
- **Automatic Baseline Detection** - Horizontal line detection using Hough transform
- **Automatic Contact Point Detection** - Precise contact location identification
- **Instant Results** - Contact angle calculated in 2-3 seconds

### 🎮 **Manual Adjustment Mode (Backup)**
- **Draggable Controls** - Fine-tune any detected points if needed
- **Haptic Feedback** - Physical feedback for better control
- **Real-time Updates** - Angle recalculated as you adjust
- **Professional Precision** - For critical measurements requiring manual verification

### 🔬 **Scientific Accuracy**
- **Direct Geometric Calculation** - No AI black box, pure mathematics
- **Tangent Vector Analysis** - Precise contact angle measurement
- **Reproducible Results** - Same image = same angle every time
- **No Human Bias** - Completely objective measurements

## 📱 How It Works

### **Simple 2-Step Process:**
1. **📷 Capture Image** → Take photo or select from gallery
2. **⚡ Get Results** → Automatic analysis provides contact angle instantly

### **Automatic Detection Pipeline:**
```
📷 Image Input → 🔍 Edge Detection → 🎯 Boundary Extraction → 📐 Angle Calculation
```

1. **Image Preprocessing** - Gaussian blur for noise reduction
2. **Edge Detection** - Canny algorithm finds all edges  
3. **Droplet Identification** - Connected component analysis finds largest droplet
4. **Baseline Detection** - Hough transform locates horizontal surface
5. **Contact Points** - Intersection of droplet and surface
6. **Angle Calculation** - Geometric tangent analysis

## 🎨 Professional Interface

### **Mode Toggle**
- **🟢 Auto Mode** - Green star icon (⭐) = Automatic detection ON
- **🟠 Manual Mode** - Orange touch icon (👆) = Manual adjustment mode

### **Visual Elements**
- **🟢 Green Contour** - Automatically detected droplet boundary
- **🔵 Blue Baseline** - Automatically detected surface line
- **🔴 Red Contact Points** - Precise contact locations (manual mode)
- **🟢 Green Contact Points** - Auto-detected locations (auto mode)
- **🟡 Yellow Tangent Lines** - Contact angle measurement lines

### **Real-Time Status**
- **Processing Updates** - "Detecting boundary...", "Calculating angle..."
- **Mode Indicator** - Always shows current operation mode
- **Results Display** - Large, prominent angle measurement
- **Quality Feedback** - Visual confirmation of detection quality

## 🔧 Technical Implementation

### **Computer Vision Algorithms**
- **Gaussian Blur** - 3×3 kernel for noise reduction
- **Canny Edge Detection** - Sobel operators with threshold
- **Connected Components** - Largest droplet identification
- **Hough Transform** - Horizontal line detection for baseline
- **Vector Geometry** - Tangent calculation at contact points

### **Performance Features**
- **Efficient Processing** - Optimized pixel operations
- **Smart Fallbacks** - Automatic recovery from detection failures
- **Memory Management** - Efficient image handling
- **Cross-Platform** - Works on Android, iOS, web, desktop

## 🚀 Getting Started

### **Installation**
   ```bash
# Clone the repository
git clone https://github.com/your-repo/contact_angle_app.git
cd contact_angle_app

# Install dependencies
   flutter pub get

# Run the app
   flutter run
   ```

### **Usage**
1. **Launch App** - Opens with automatic detection mode enabled
2. **Capture Image** - Tap camera icon, take photo or select from gallery
3. **Watch Analysis** - Automatic processing with real-time status updates
4. **Get Results** - Contact angle displayed instantly (e.g., "106.1°")
5. **Export Data** - Save PNG image and measurement data (JSON/CSV)

### **Manual Mode (Optional)**
1. **Toggle Mode** - Tap the star icon to switch to manual mode
2. **Adjust Points** - Drag red circles to fine-tune contact points
3. **Adjust Baseline** - Drag blue circles to adjust surface line
4. **Real-Time Update** - Angle recalculates as you drag

## 📊 Features & Benefits

### **For Students**
- **Zero Learning Curve** - Just take photo and get results
- **Instant Measurements** - No manual point placement required
- **Consistent Results** - Eliminates human error and bias
- **Professional Output** - Publication-quality measurements

### **For Researchers**
- **High Throughput** - Process many images quickly
- **Objective Analysis** - Removes subjective measurement bias
- **Reproducible Science** - Consistent methodology across measurements
- **Data Export** - Complete measurement data for analysis

### **For Educators**
- **Teaching Tool** - Shows how computer vision works
- **Simplified Workflow** - Students focus on science, not UI complexity
- **Reliable Results** - Consistent measurements for all students
- **Modern Technology** - Demonstrates current image analysis methods

## 📐 Scientific Methodology

### **Direct Geometric Approach**
- **No AI Complexity** - Pure mathematical calculation
- **Transparent Process** - Every step is visible and verifiable
- **Reproducible** - Same setup produces identical results
- **Setup Independent** - Works across different imaging conditions

### **Quality Assurance**
- **Multiple Validation** - Boundary, baseline, and angle validation
- **Error Detection** - Automatic detection of problematic measurements
- **Fallback Systems** - Manual mode available when needed
- **Visual Verification** - All detection results clearly displayed

## 📱 Export Capabilities

### **High-Resolution Images**
- **3× Quality PNG** - Publication-ready image export
- **Overlay Included** - Complete analysis visualization
- **Share Integration** - Direct sharing from the app

### **Structured Data**
- **JSON Format** - Complete measurement metadata
- **CSV Format** - Spreadsheet-compatible data
- **Coordinates** - All point locations included
- **Timestamp** - Measurement time and date

## 🎯 Perfect for Academic Use

### **Meets Scientific Standards**
- **Objective Measurement** - No human bias in detection
- **Reproducible Methods** - Consistent across all measurements  
- **Direct Calculation** - No black box AI algorithms
- **Fast Results** - Efficient for classroom use

### **Professor Approved**
- **Simple Methodology** - Direct geometric approach as requested
- **No AI Complexity** - Pure computer vision without machine learning
- **Consistent Results** - Reliable for research and education
- **Professional Interface** - Lab-ready application

## 📁 Project Structure

```
contact_angle_app/
├── lib/
│   ├── main.dart                           # App entry point
│   ├── image_processor.dart                # Automatic detection algorithms
│   ├── processing/angle_utils.dart         # Utility functions
│   └── widgets/image_annotator_improved.dart # Main UI with dual modes
├── assets/contact_angle_icon.svg           # Custom app icon
├── pubspec.yaml                            # Dependencies configuration
├── android/, ios/, web/, etc.              # Platform-specific files
└── PFOTES/                                 # Sample test images
```

## 🔬 Testing

The app includes sample droplet images in the `PFOTES/` directory for testing the automatic detection algorithms with various droplet shapes and contact angles.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please ensure any changes maintain the scientific accuracy and direct geometric approach of the measurement methodology.

## 📞 Support

For technical support or questions about the measurement methodology, please open an issue on GitHub.

---

**Contact Angle Measurement App** - Professional, automatic, and scientifically accurate contact angle analysis. 🎯