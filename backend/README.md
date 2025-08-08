# Contact Angle Analysis Backend

This is a FastAPI backend that provides advanced contact angle analysis using OpenCV and computer vision techniques.

## Features

- **Robust droplet detection** using Canny edge detection and contour analysis
- **Ellipse fitting** for accurate droplet shape modeling
- **Analytic tangent calculation** for precise contact angle measurement
- **Subpixel refinement** for improved accuracy
- **RANSAC line fitting** for robust baseline detection
- **JSON API** with base64 encoded overlay images

## Setup

### Option 1: Local Python Environment

1. Create a virtual environment:
```bash
cd backend
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

3. Run the server:
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

### Option 2: Docker

1. Build the Docker image:
```bash
cd backend
docker build -t slp-analyzer .
```

2. Run the container:
```bash
docker run -p 8000:8000 slp-analyzer
```

## API Usage

### Analyze Endpoint

**POST** `/analyze`

Upload an image file to get contact angle analysis.

**Request:**
- Content-Type: `multipart/form-data`
- Body: `file` - Image file (PNG, JPG, etc.)

**Response:**
```json
{
  "left_angle_deg": 45.2,
  "right_angle_deg": 47.8,
  "mean_angle_deg": 46.5,
  "left_contact": {"x": 123.4, "y": 456.7},
  "right_contact": {"x": 789.0, "y": 456.7},
  "ellipse": {
    "cx": 456.2,
    "cy": 234.5,
    "a": 100.0,
    "b": 80.0,
    "angle_deg": 15.2
  },
  "confidence": 0.85,
  "overlay_png_b64": "iVBORw0KGgoAAAANSUhEUgAA..."
}
```

## Testing

1. Open your browser to `http://localhost:8000/docs` for interactive API documentation
2. Use the `/analyze` endpoint to test with your own images
3. The response includes a base64-encoded PNG overlay showing the analysis results

## Configuration

Key parameters that can be tuned in `app/main.py`:

- **Canny thresholds** (lines 25-26): Adjust for different lighting conditions
- **RANSAC parameters** (line 45): `n_iters=400, thresh=3.5`
- **Subpixel sampling** (line 108): `length=31, spacing=0.7`
- **Contour area threshold** (line 32): Minimum area for droplet detection

## Integration with Flutter

The Flutter app can call this backend using the `http` package. See `lib/widgets/image_annotator.dart` for the integration code.

For Android emulator, use: `http://10.0.2.2:8000`
For iOS simulator, use: `http://localhost:8000`
For physical devices, use your computer's IP address.
