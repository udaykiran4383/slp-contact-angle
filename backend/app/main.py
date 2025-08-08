# backend/app/main.py
import io
import base64
import math
import random
from typing import Tuple, Dict, Any, List
from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from PIL import Image, ImageDraw
import numpy as np
import cv2

app = FastAPI(title="SLP Contact Angle Analyzer")

# ------------------------
# utilities
# ------------------------
def to_gray_cv(img_bgr: np.ndarray) -> np.ndarray:
    return cv2.cvtColor(img_bgr, cv2.COLOR_BGR2GRAY)

def preprocess(img_bgr: np.ndarray) -> np.ndarray:
    gray = to_gray_cv(img_bgr)
    g = cv2.GaussianBlur(gray, (5,5), 0)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
    g = clahe.apply(g)
    return g

def find_droplet_contour(gray: np.ndarray) -> np.ndarray:
    edges = cv2.Canny(gray, 60, 180)
    cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    if not cnts:
        return None
    cnts = sorted(cnts, key=cv2.contourArea, reverse=True)
    for c in cnts:
        if cv2.contourArea(c) > 500:
            return c
    return cnts[0]

def ransac_line_fit(points: np.ndarray, n_iters=400, thresh=3.5) -> Tuple[float,float]:
    # points: Nx2
    best = None
    best_inliers = -1
    n = points.shape[0]
    if n < 2:
        return 0.0, 0.0
    for _ in range(n_iters):
        i1, i2 = random.sample(range(n), 2)
        p1 = points[i1]
        p2 = points[i2]
        if np.allclose(p1, p2): 
            continue
        dx = p2[0] - p1[0]
        dy = p2[1] - p1[1]
        a = dy
        b = -dx
        c = -(a * p1[0] + b * p1[1])
        denom = math.hypot(a, b)
        if denom == 0: continue
        dists = np.abs(a * points[:,0] + b * points[:,1] + c) / denom
        inliers = (dists < thresh).sum()
        if inliers > best_inliers:
            best_inliers = inliers
            best = (a/denom, b/denom, c/denom)
    if best is None:
        # fallback to fitLine
        vx, vy, x0, y0 = cv2.fitLine(points.astype(np.float32), cv2.DIST_L2,0,0.01,0.01)
        vx = float(vx); vy = float(vy); x0 = float(x0); y0 = float(y0)
        if abs(vx) < 1e-9:
            return float('inf'), float(x0)
        m = vy / vx
        c = y0 - m * x0
        return float(m), float(c)
    a_n, b_n, c_n = best
    if abs(b_n) > 1e-6:
        m = -a_n / b_n
        c0 = -c_n / b_n
        return float(m), float(c0)
    else:
        return float('inf'), float(-c_n/a_n if a_n!=0 else 0.0)

def solve_ellipse_line_intersection(h, k, a, b, phi, m, cc) -> List[Tuple[float,float]]:
    # ellipse centered at (h,k), axes a,b, rotated phi
    c = math.cos(phi)
    s = math.sin(phi)
    # coefficients for quadratic in x: A x^2 + B x + C = 0
    A = ( (c + s*m)**2 ) / (a*a) + ( (-s + c*m)**2 ) / (b*b)
    B = ( 2*(c + s*m)*(c*(-h) + s*(cc - k)) ) / (a*a) + 2*((-s + c*m)*(-s*(-h) + c*(cc - k))) / (b*b)
    C = ( (c*(-h) + s*(cc-k))**2 )/(a*a) + ((-s*(-h) + c*(cc-k))**2)/(b*b) - 1.0
    if abs(A) < 1e-12:
        if abs(B) < 1e-12:
            return []
        x = -C / B
        y = m * x + cc
        return [(x,y)]
    disc = B*B - 4*A*C
    if disc < 0:
        return []
    xs = [(-B + math.sqrt(disc)) / (2*A), (-B - math.sqrt(disc)) / (2*A)]
    pts = [(x, m*x + cc) for x in xs]
    return pts

def analytic_tangent_slope_at_point(x0, y0, h, k, a, b, phi):
    dx = x0 - h
    dy = y0 - k
    c = math.cos(phi)
    s = math.sin(phi)
    xr = dx * c + dy * s
    yr = -dx * s + dy * c
    dFdxr = 2.0 * xr / (a*a)
    dFdyr = 2.0 * yr / (b*b)
    dFdx = dFdxr * c - dFdyr * s
    dFdy = dFdxr * s + dFdyr * c
    if abs(dFdy) < 1e-12:
        return float('inf')
    return -dFdx / dFdy

def bilinear_sample(img_gray: np.ndarray, x: float, y: float) -> float:
    h, w = img_gray.shape
    if x < 0 or x >= w-1 or y < 0 or y >= h-1:
        x = min(max(x,0), w-1)
        y = min(max(y,0), h-1)
        return float(img_gray[int(round(y)), int(round(x))])
    x0 = int(math.floor(x))
    y0 = int(math.floor(y))
    x1 = x0 + 1
    y1 = y0 + 1
    dx = x - x0
    dy = y - y0
    v00 = img_gray[y0, x0]
    v10 = img_gray[y0, x1]
    v01 = img_gray[y1, x0]
    v11 = img_gray[y1, x1]
    v0 = v00*(1-dx) + v10*dx
    v1 = v01*(1-dx) + v11*dx
    return float(v0*(1-dy) + v1*dy)

def sample_along_normal(img_gray: np.ndarray, px, py, nx, ny, length=31, spacing=0.7):
    half = length // 2
    intens = []
    ts = []
    for i in range(length):
        t = (i - half) * spacing
        sx = px + nx * t
        sy = py + ny * t
        intens.append(bilinear_sample(img_gray, sx, sy))
        ts.append(t)
    return np.array(ts, dtype=float), np.array(intens, dtype=float)

def subpixel_from_gradient(ts, intens):
    g = np.zeros_like(intens)
    g[1:-1] = (intens[2:] - intens[:-2]) / 2.0
    if len(g) < 3:
        return ts[0]
    imax = int(np.argmax(np.abs(g)))
    if imax <= 0 or imax >= len(g)-1:
        return ts[imax]
    y1, y2, y3 = g[imax-1], g[imax], g[imax+1]
    denom = 2.0 * (y1 - 2*y2 + y3)
    if abs(denom) < 1e-8:
        return ts[imax]
    dt = (y1 - y3) / denom
    dt = max(-1.0, min(1.0, dt))
    spacing = ts[1] - ts[0] if len(ts) > 1 else 1.0
    return ts[imax] + dt * spacing

# ------------------------
# API
# ------------------------
class AnalyzeResponse(BaseModel):
    left_angle_deg: float
    right_angle_deg: float
    mean_angle_deg: float
    left_contact: Dict[str,float]
    right_contact: Dict[str,float]
    ellipse: Dict[str,float]
    confidence: float
    overlay_png_b64: str

@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze(file: UploadFile = File(...)):
    data = await file.read()
    arr = np.asarray(bytearray(data), dtype=np.uint8)
    img_bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img_bgr is None:
        raise HTTPException(status_code=400, detail="Can't decode image")
    h_img, w_img = img_bgr.shape[:2]
    gray = preprocess(img_bgr)

    contour = find_droplet_contour(gray)
    if contour is None or len(contour) < 6:
        raise HTTPException(status_code=404, detail="No suitable droplet contour found")

    try:
        ellipse = cv2.fitEllipse(contour)
        (cx,cy),(d1,d2),angle_deg = ellipse
        a = d1/2.0
        b = d2/2.0
        phi = math.radians(angle_deg)
    except Exception:
        x,y,w,h = cv2.boundingRect(contour)
        cx = x + w/2.0
        cy = y + h/2.0
        a = w/2.0
        b = h/2.0
        phi = 0.0
        angle_deg = 0.0

    pts = contour.reshape(-1,2).astype(float)
    y_thresh = np.percentile(pts[:,1], 70)
    bottom_pts = pts[pts[:,1] >= y_thresh]
    if len(bottom_pts) < 6:
        bottom_pts = pts

    m, c = ransac_line_fit(bottom_pts, n_iters=400, thresh=3.5)

    inters = solve_ellipse_line_intersection(cx, cy, a, b, phi, m, c)
    candidates = []
    if len(inters) >= 1:
        for (xint, yint) in inters:
            if 0 <= xint < w_img and 0 <= yint < h_img:
                candidates.append((xint, yint))
    if len(candidates) < 2:
        dists = np.abs(m * pts[:,0] - pts[:,1] + c) / (math.hypot(m, -1) + 1e-12)
        idxs = np.argsort(dists)[:min(len(pts), 200)]
        close_pts = pts[idxs]
        if len(close_pts) >= 2:
            left = close_pts[np.argmin(close_pts[:,0])]
            right = close_pts[np.argmax(close_pts[:,0])]
            candidates = [(float(left[0]), float(left[1])), (float(right[0]), float(right[1]))]

    if len(candidates) == 1:
        candidates.append((candidates[0][0]+1.0, candidates[0][1]))

    candidates = sorted(candidates, key=lambda p: p[0])
    left_approx = candidates[0]
    right_approx = candidates[1]

    img_gray = gray.astype(np.float32)

    def refine_contact(approx):
        px, py = approx
        mt = analytic_tangent_slope_at_point(px, py, cx, cy, a, b, phi)
        if math.isinf(mt):
            tvec = (0.0, -1.0)
        else:
            tvec = (1.0, mt)
            norm = math.hypot(tvec[0], tvec[1])
            tvec = (tvec[0]/norm, tvec[1]/norm)
        nx, ny = -tvec[1], tvec[0]
        ts, intens = sample_along_normal(img_gray, px, py, nx, ny, length=31, spacing=0.7)
        dt = subpixel_from_gradient(ts, intens)
        refined_x = px + nx * dt
        refined_y = py + ny * dt
        return float(refined_x), float(refined_y)

    left_refined = refine_contact(left_approx)
    right_refined = refine_contact(right_approx)

    left_mt = analytic_tangent_slope_at_point(left_refined[0], left_refined[1], cx, cy, a, b, phi)
    right_mt = analytic_tangent_slope_at_point(right_refined[0], right_refined[1], cx, cy, a, b, phi)

    mb = m
    if not math.isfinite(mb):
        mb = 1e12

    left_angle = abs(math.atan(left_mt if math.isfinite(left_mt) else (1e12)) - math.atan(mb))
    if left_angle > math.pi: left_angle = 2*math.pi - left_angle
    left_deg = math.degrees(left_angle)

    right_angle = abs(math.atan(right_mt if math.isfinite(right_mt) else (1e12)) - math.atan(mb))
    if right_angle > math.pi: right_angle = 2*math.pi - right_angle
    right_deg = math.degrees(right_angle)
    mean_deg = 0.5 * (left_deg + right_deg)

    area = cv2.contourArea(contour)
    conf = min(1.0, max(0.0, (area / (w_img*h_img*0.02)) ))
    conf = min(1.0, conf)

    pil = Image.fromarray(cv2.cvtColor(img_bgr, cv2.COLOR_BGR2RGB))
    draw = ImageDraw.Draw(pil, 'RGBA')
    pts_list = [(float(x), float(y)) for x,y in pts]
    if len(pts_list) > 2:
        draw.line(pts_list + [pts_list[0]], fill=(0,255,120,180), width=2)
    try:
        ellipse_pts = cv2.ellipse2Poly((int(round(cx)), int(round(cy))), (int(round(a)), int(round(b))), int(round(math.degrees(phi))), 0, 360, 4)
        ellipse_pts = [(int(x),int(y)) for (x,y) in ellipse_pts]
        draw.line(ellipse_pts + [ellipse_pts[0]], fill=(255,200,0,200), width=2)
    except Exception:
        pass
    x1 = 0
    y1 = m*0 + c
    x2 = w_img
    y2 = m*w_img + c
    draw.line([(x1,y1),(x2,y2)], fill=(0,200,255,200), width=2)

    def draw_tangent(pt, m_t, color):
        px, py = pt
        if not math.isfinite(m_t):
            dx, dy = 0.0, -1.0
        else:
            dx, dy = 1.0, m_t
            norm = math.hypot(dx, dy)
            dx, dy = dx/norm, dy/norm
        L = max(w_img,h_img) * 0.25
        xA = px - dx * L
        yA = py - dy * L
        xB = px + dx * L
        yB = py + dy * L
        draw.line([(xA,yA),(xB,yB)], fill=color, width=2)

    draw.ellipse([(left_refined[0]-4, left_refined[1]-4),(left_refined[0]+4,left_refined[1]+4)], fill=(255,60,60,255))
    draw.ellipse([(right_refined[0]-4, right_refined[1]-4),(right_refined[0]+4,right_refined[1]+4)], fill=(255,60,60,255))
    draw_tangent(left_refined, left_mt, (255,200,0,200))
    draw_tangent(right_refined, right_mt, (255,200,0,200))

    buf = io.BytesIO()
    pil.save(buf, format='PNG')
    b64 = base64.b64encode(buf.getvalue()).decode('ascii')

    resp = {
        'left_angle_deg': float(left_deg),
        'right_angle_deg': float(right_deg),
        'mean_angle_deg': float(mean_deg),
        'left_contact': {'x': float(left_refined[0]), 'y': float(left_refined[1])},
        'right_contact': {'x': float(right_refined[0]), 'y': float(right_refined[1])},
        'ellipse': {'cx': float(cx), 'cy': float(cy), 'a': float(a), 'b': float(b), 'angle_deg': float(angle_deg)},
        'confidence': float(conf),
        'overlay_png_b64': b64
    }
    return JSONResponse(resp)
