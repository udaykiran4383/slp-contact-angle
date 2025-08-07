# Comprehensive Prompt for Gemini Pro: Contact Angle Detection Algorithm Improvement

## 🎯 **Objective**
Improve the accuracy and robustness of a contact angle detection algorithm for scientific droplet analysis. The current implementation achieves 99.93-100% accuracy for basic cases but needs enhancement for edge cases and real-world scenarios.

## 📊 **Current Performance**
- **Basic Cases**: 99.93-100% accuracy (45°, 60°, 120°, 135°)
- **Edge Cases**: 99.99% accuracy (30°, 150°)
- **Target Range**: 110-140° for hydrophobic surfaces
- **Current Uncertainty**: ±0.5° under optimal conditions

## 🔍 **Current Algorithm Analysis**

### **Core Implementation**
```dart
double _calculateDropletContactAngle(double tangentSlope, double baselineSlope) {
  // Handle vertical tangents
  if (tangentSlope.isInfinite) {
    double baselineAngle = atan(baselineSlope) * 180 / pi;
    return 90.0 - baselineAngle.abs();
  }
  
  // Handle horizontal baseline (most common case for droplets)
  if (baselineSlope.abs() < 1e-6) {
    double tangentAngle = atan(tangentSlope) * 180 / pi;
    
    double contactAngle;
    if (tangentSlope > 0) {
      contactAngle = tangentAngle;
    } else {
      contactAngle = 180 - tangentAngle.abs();
    }
    
    // Range correction
    if (contactAngle < 0) {
      contactAngle = 180 + contactAngle;
    } else if (contactAngle > 180) {
      contactAngle = 360 - contactAngle;
    }
    
    // Special handling for very small slopes
    if (tangentSlope.abs() < 1e-3) {
      if (tangentSlope > 0) {
        contactAngle = 0.0;
      } else {
        contactAngle = 180.0;
      }
    }
    
    return contactAngle;
  }
  
  // General case handling...
}
```

## 🚨 **Identified Challenges & Errors**

### **1. Edge Case Handling Issues**
- **Problem**: Very small slopes (< 1e-3) are hardcoded to 0° or 180°
- **Impact**: Loss of precision for near-horizontal tangents
- **Error**: Binary assignment instead of smooth interpolation

### **2. Numerical Stability Problems**
- **Problem**: Floating-point precision issues with very small angles
- **Impact**: Inconsistent results for angles near 0° or 180°
- **Error**: Rounding errors accumulate in trigonometric calculations

### **3. Geometric Assumptions**
- **Problem**: Assumes perfect ellipse fitting for all droplet shapes
- **Impact**: Poor accuracy for non-elliptical droplets (deformed, asymmetric)
- **Error**: Single model approach doesn't handle shape variations

### **4. Baseline Detection Issues**
- **Problem**: Assumes horizontal baseline (slope < 1e-6)
- **Impact**: Errors when surface is slightly tilted
- **Error**: Binary classification instead of continuous handling

### **5. Uncertainty Quantification**
- **Problem**: Simple empirical uncertainty estimation
- **Impact**: Unrealistic error bounds
- **Error**: Doesn't account for systematic errors

### **6. Multi-Model Fitting**
- **Problem**: Only uses ellipse fitting
- **Impact**: Poor performance for complex droplet shapes
- **Error**: No fallback or ensemble methods

## 🎯 **Areas for Improvement**

### **1. Enhanced Edge Case Handling**
```dart
// CURRENT (Problematic)
if (tangentSlope.abs() < 1e-3) {
  if (tangentSlope > 0) {
    contactAngle = 0.0;
  } else {
    contactAngle = 180.0;
  }
}

// NEEDED: Smooth interpolation
double _smoothEdgeCaseHandling(double tangentSlope) {
  const double threshold = 1e-3;
  const double transitionWidth = 1e-4;
  
  if (tangentSlope.abs() < threshold) {
    double t = tangentSlope.abs() / transitionWidth;
    double smoothFactor = _smoothStep(t);
    
    if (tangentSlope > 0) {
      return smoothFactor * 0.0 + (1 - smoothFactor) * atan(tangentSlope) * 180 / pi;
    } else {
      return smoothFactor * 180.0 + (1 - smoothFactor) * (180 - atan(tangentSlope.abs()) * 180 / pi);
    }
  }
  return _calculateStandardAngle(tangentSlope);
}
```

### **2. Numerical Stability Improvements**
```dart
// NEEDED: Robust trigonometric calculations
double _robustAtan2(double y, double x) {
  if (x.abs() < 1e-10 && y.abs() < 1e-10) {
    return 0.0; // Handle zero case
  }
  
  double result = atan2(y, x) * 180 / pi;
  
  // Ensure result is in [0, 360) range
  while (result < 0) result += 360;
  while (result >= 360) result -= 360;
  
  return result;
}
```

### **3. Multi-Model Fitting Approach**
```dart
// NEEDED: Ensemble of fitting methods
class MultiModelFitter {
  static Future<Map<String, double>> fitEnsemble(List<cv.Point2f> points) async {
    final results = <String, Map<String, double>>{};
    
    // Try multiple fitting approaches
    results['ellipse'] = await _fitEllipse(points);
    results['polynomial'] = await _fitPolynomial(points);
    results['spline'] = await _fitSpline(points);
    results['circle'] = await _fitCircle(points);
    
    // Weighted combination based on fit quality
    return _combineResults(results);
  }
}
```

### **4. Advanced Uncertainty Quantification**
```dart
// NEEDED: Comprehensive uncertainty analysis
class UncertaintyAnalyzer {
  static Map<String, double> analyzeUncertainty({
    required List<cv.Point2f> points,
    required Map<String, double> fitResults,
    required double angleDifference,
    required double eccentricity,
  }) {
    return {
      'systematic': _calculateSystematicUncertainty(points, fitResults),
      'random': _calculateRandomUncertainty(points),
      'geometric': _calculateGeometricUncertainty(eccentricity),
      'numerical': _calculateNumericalUncertainty(),
      'total': _combineUncertainties(...),
    };
  }
}
```

### **5. Adaptive Baseline Detection**
```dart
// NEEDED: Robust baseline detection
class AdaptiveBaselineDetector {
  static List<Offset> detectBaseline(List<cv.Point2f> contourPoints) {
    // Multiple baseline detection methods
    final methods = [
      _detectHorizontalBaseline,
      _detectRANSACBaseline,
      _detectHoughBaseline,
      _detectLeastSquaresBaseline,
    ];
    
    final results = methods.map((method) => method(contourPoints)).toList();
    
    // Select best baseline based on quality metrics
    return _selectBestBaseline(results);
  }
}
```

### **6. Quality Assessment Framework**
```dart
// NEEDED: Comprehensive quality metrics
class QualityAssessor {
  static Map<String, double> assessQuality({
    required List<cv.Point2f> points,
    required Map<String, double> angles,
    required Map<String, double> uncertainties,
  }) {
    return {
      'contour_smoothness': _calculateContourSmoothness(points),
      'fit_quality': _calculateFitQuality(points, angles),
      'angle_symmetry': _calculateAngleSymmetry(angles),
      'uncertainty_reliability': _assessUncertaintyReliability(uncertainties),
      'overall_confidence': _calculateOverallConfidence(...),
    };
  }
}
```

## 🔬 **Scientific Requirements**

### **1. Accuracy Standards**
- **Target Precision**: ±0.1° for research-grade measurements
- **Reproducibility**: <0.2° standard deviation
- **Validation**: Against known reference measurements

### **2. Robustness Requirements**
- **Shape Variations**: Handle elliptical, circular, deformed droplets
- **Image Quality**: Work with noisy, low-contrast images
- **Lighting Conditions**: Adapt to different illumination
- **Surface Types**: Hydrophobic (110-140°) and hydrophilic (0-90°) surfaces

### **3. Performance Requirements**
- **Processing Time**: <2 seconds per image
- **Memory Usage**: <500MB for batch processing
- **Scalability**: Handle 1000+ images efficiently

## 🎯 **Specific Improvement Requests**

### **1. Algorithm Enhancements**
- Implement smooth edge case handling with interpolation
- Add numerical stability improvements for small angles
- Develop multi-model fitting with ensemble methods
- Create adaptive baseline detection algorithms

### **2. Error Handling**
- Implement comprehensive error detection and recovery
- Add validation checks for input data quality
- Create fallback mechanisms for failed fits
- Develop confidence scoring for results

### **3. Performance Optimization**
- Optimize computational efficiency
- Implement parallel processing for batch operations
- Add caching mechanisms for repeated calculations
- Develop memory-efficient algorithms

### **4. Validation Framework**
- Create comprehensive test suite with edge cases
- Implement automated validation against reference data
- Develop performance benchmarking tools
- Add regression testing for algorithm changes

## 📋 **Expected Deliverables**

### **1. Enhanced Algorithm**
- Improved contact angle calculation with better edge case handling
- Multi-model fitting approach with ensemble methods
- Robust uncertainty quantification
- Adaptive baseline detection

### **2. Quality Assessment**
- Comprehensive quality metrics framework
- Confidence scoring system
- Error detection and recovery mechanisms
- Validation and testing framework

### **3. Documentation**
- Detailed algorithm documentation
- Performance analysis and benchmarks
- Usage guidelines and best practices
- Troubleshooting guide

### **4. Code Implementation**
- Clean, well-documented Dart/Flutter code
- Unit tests for all components
- Integration tests for full pipeline
- Performance optimization

## 🎯 **Success Criteria**

### **1. Accuracy Improvements**
- Achieve ±0.1° precision for standard cases
- Maintain <0.2° accuracy for edge cases
- Reduce uncertainty by 50% compared to current implementation

### **2. Robustness Improvements**
- Handle 95% of real-world droplet shapes
- Work with 90% of image quality variations
- Achieve 99% success rate for baseline detection

### **3. Performance Improvements**
- Reduce processing time by 30%
- Maintain memory usage under 500MB
- Support batch processing of 1000+ images

### **4. Usability Improvements**
- Provide clear error messages and recovery suggestions
- Implement comprehensive logging and debugging
- Create user-friendly configuration options

## 🔍 **Additional Context**

### **Current Test Results**
- Basic cases: 99.93-100% accuracy
- Edge cases: 99.99% accuracy
- Target range: 110-140° for hydrophobic surfaces
- Current uncertainty: ±0.5°

### **Real-World Challenges**
- Non-ideal droplet shapes (deformed, asymmetric)
- Image quality variations (noise, low contrast, lighting)
- Surface imperfections and contamination
- Environmental factors (temperature, humidity)

### **Scientific Applications**
- Surface wettability analysis
- Coating performance evaluation
- Material science research
- Quality control in manufacturing

Please provide a comprehensive solution that addresses all these challenges while maintaining or improving the current accuracy levels. 