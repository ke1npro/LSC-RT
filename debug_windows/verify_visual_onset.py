# -*- coding: utf-8 -*-
"""
verify_visual_onset.py
Genera una comparativa visual side-by-side del fotograma inicial (t=0 y t=6)
y del fotograma del ápex para verificar la eliminación de artefactos en el inicio.
"""

import os
import json
import cv2
import numpy as np

BANK_PATH = os.path.join(os.path.dirname(__file__), 'output', 'avatar', 'lsc_motion_bank.json')
BRAIN_DIR = r"C:\Users\Lenovo\.gemini\antigravity\brain\68f77ea0-10a8-41b2-b9e5-e6e8a1a09fbf"

HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),
    (0, 5), (5, 6), (6, 7), (7, 8),
    (9, 10), (10, 11), (11, 12),
    (13, 14), (14, 15), (15, 16),
    (0, 17), (17, 18), (18, 19), (19, 20),
    (5, 9), (9, 13), (13, 17)
]

with open(BANK_PATH, 'r', encoding='utf-8') as f:
    bank = json.load(f)

width, height = 480, 540

def render_frame_to_img(frame_data, title, phase_label):
    canvas = np.zeros((height, width, 3), dtype=np.uint8)
    for y in range(height):
        c = int(18 + (y / height) * 12)
        canvas[y, :] = (c, c, c + 4)

    torso = frame_data['torso']
    t_pts = {}
    for k, v in torso.items():
        t_pts[k] = (int(np.clip(v[0] * width, 0, width - 1)), int(np.clip(v[1] * height, 0, height - 1)))

    # Cabeza
    if 'nose' in t_pts:
        nx, ny = t_pts['nose']
        cv2.ellipse(canvas, (nx, ny - 24), (28, 36), 0, 0, 360, (50, 50, 65), -1, cv2.LINE_AA)
        cv2.ellipse(canvas, (nx, ny - 24), (28, 36), 0, 0, 360, (100, 100, 130), 2, cv2.LINE_AA)
        cv2.circle(canvas, (nx - 8, ny - 30), 2, (180, 200, 255), -1, cv2.LINE_AA)
        cv2.circle(canvas, (nx + 8, ny - 30), 2, (180, 200, 255), -1, cv2.LINE_AA)

    # Torso y Brazos
    if 'left_shoulder' in t_pts and 'right_shoulder' in t_pts:
        ls = t_pts['left_shoulder']
        rs = t_pts['right_shoulder']
        cv2.line(canvas, ls, rs, (0, 180, 255), 3, cv2.LINE_AA)

        if 'left_elbow' in t_pts and 'left_wrist' in t_pts:
            le = t_pts['left_elbow']
            lw = t_pts['left_wrist']
            cv2.line(canvas, ls, le, (0, 170, 240), 2, cv2.LINE_AA)
            cv2.line(canvas, le, lw, (0, 170, 240), 2, cv2.LINE_AA)
            cv2.circle(canvas, le, 5, (0, 210, 255), -1, cv2.LINE_AA)
            cv2.circle(canvas, lw, 5, (255, 200, 0), -1, cv2.LINE_AA) # Muñeca izq

        if 'right_elbow' in t_pts and 'right_wrist' in t_pts:
            re_p = t_pts['right_elbow']
            rw = t_pts['right_wrist']
            cv2.line(canvas, rs, re_p, (0, 170, 240), 2, cv2.LINE_AA)
            cv2.line(canvas, re_p, rw, (0, 170, 240), 2, cv2.LINE_AA)
            cv2.circle(canvas, re_p, 5, (0, 210, 255), -1, cv2.LINE_AA)
            cv2.circle(canvas, rw, 5, (0, 255, 120), -1, cv2.LINE_AA) # Muñeca der

    # Manos
    for hand_key, col_b, col_j in [('left_hand', (255, 220, 0), (255, 240, 120)), ('right_hand', (0, 255, 120), (100, 255, 180))]:
        pts = frame_data[hand_key]
        if len(pts) == 21:
            p_px = [(int(p[0] * width), int(p[1] * height)) for p in pts]
            for p1, p2 in HAND_CONNECTIONS:
                cv2.line(canvas, p_px[p1], p_px[p2], (0, 0, 0), 3, cv2.LINE_AA)
                cv2.line(canvas, p_px[p1], p_px[p2], col_b, 1, cv2.LINE_AA)
            for idx_p, pt in enumerate(p_px):
                cv2.circle(canvas, pt, 2, col_j, -1, cv2.LINE_AA)

    # Header
    cv2.putText(canvas, title, (15, 30), cv2.FONT_HERSHEY_DUPLEX, 0.55, (255, 255, 255), 1, cv2.LINE_AA)
    cv2.putText(canvas, phase_label, (15, 55), cv2.FONT_HERSHEY_DUPLEX, 0.45, (0, 240, 255), 1, cv2.LINE_AA)
    return canvas

# Generar triptico para "GRACIAS"
g_frames = bank['gracias']['frames']
apex_f = bank['gracias']['phases']['apex_frame']

img_start = render_frame_to_img(g_frames[0], "GRACIAS", "Fotograma 0: Reposo Natural")
img_mid = render_frame_to_img(g_frames[12], "GRACIAS", "Fotograma 12: Inicio Gesto Real")
img_apex = render_frame_to_img(g_frames[apex_f], "GRACIAS", f"Fotograma {apex_f}: Apex Consenso")

triptico = np.hstack([img_start, img_mid, img_apex])
out_triptico = os.path.join(BRAIN_DIR, 'onset_fix_validation_gracias.png')
cv2.imwrite(out_triptico, triptico)
print(f"Validación guardada en: {out_triptico}")
