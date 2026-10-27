# -*- coding: utf-8 -*-
"""
render_avatar_previews.py

Renderiza fotogramas de previsualización en alta definición del Avatar
en su fase clave de Ápex para las 4 señas maestras de LSC.
"""

import os
import json
import cv2
import numpy as np

BANK_PATH = os.path.join(os.path.dirname(__file__), 'output', 'avatar', 'lsc_motion_bank.json')
BRAIN_DIR = r"C:\Users\Lenovo\.gemini\antigravity\brain\68f77ea0-10a8-41b2-b9e5-e6e8a1a09fbf"
OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'avatar')

HAND_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 4),        # Pulgar
    (0, 5), (5, 6), (6, 7), (7, 8),        # Índice
    (9, 10), (10, 11), (11, 12),           # Medio
    (13, 14), (14, 15), (15, 16),          # Anular
    (0, 17), (17, 18), (18, 19), (19, 20), # Meñique
    (5, 9), (9, 13), (13, 17)              # Palma
]

with open(BANK_PATH, 'r', encoding='utf-8') as f:
    bank = json.load(f)

width, height = 960, 720

for sign_id, data in bank.items():
    apex_idx = data['phases']['apex_frame']
    frame_data = data['frames'][apex_idx]

    canvas = np.zeros((height, width, 3), dtype=np.uint8)

    # Fondo grafito
    for y in range(height):
        c_val = int(18 + (y / height) * 14)
        canvas[y, :] = (c_val, c_val, c_val + 4)

    # Cuadrícula base
    cv2.line(canvas, (0, int(height * 0.85)), (width, int(height * 0.85)), (40, 40, 50), 1)

    # Torso
    torso = frame_data['torso']
    torso_pts = {}
    for k, v in torso.items():
        px = int(np.clip(v[0] * width, 0, width - 1))
        py = int(np.clip(v[1] * height, 0, height - 1))
        torso_pts[k] = (px, py)

    if 'nose' in torso_pts:
        nose_p = torso_pts['nose']
        head_center = (nose_p[0], nose_p[1] - 30)
        cv2.ellipse(canvas, head_center, (38, 50), 0, 0, 360, (50, 50, 65), -1, cv2.LINE_AA)
        cv2.ellipse(canvas, head_center, (38, 50), 0, 0, 360, (100, 100, 130), 2, cv2.LINE_AA)
        cv2.circle(canvas, (head_center[0] - 12, head_center[1] - 8), 3, (180, 200, 255), -1, cv2.LINE_AA)
        cv2.circle(canvas, (head_center[0] + 12, head_center[1] - 8), 3, (180, 200, 255), -1, cv2.LINE_AA)

    if 'left_shoulder' in torso_pts and 'right_shoulder' in torso_pts:
        ls = torso_pts['left_shoulder']
        rs = torso_pts['right_shoulder']
        neck_center = (int((ls[0] + rs[0]) / 2), int((ls[1] + rs[1]) / 2))

        if 'nose' in torso_pts:
            cv2.line(canvas, neck_center, torso_pts['nose'], (70, 70, 90), 3, cv2.LINE_AA)

        cv2.line(canvas, ls, rs, (0, 180, 255), 4, cv2.LINE_AA)

        if 'left_elbow' in torso_pts and 'left_wrist' in torso_pts:
            le = torso_pts['left_elbow']
            lw = torso_pts['left_wrist']
            cv2.line(canvas, ls, le, (0, 170, 240), 3, cv2.LINE_AA)
            cv2.line(canvas, le, lw, (0, 170, 240), 3, cv2.LINE_AA)
            cv2.circle(canvas, le, 6, (0, 210, 255), -1, cv2.LINE_AA)

        if 'right_elbow' in torso_pts and 'right_wrist' in torso_pts:
            re_p = torso_pts['right_elbow']
            rw = torso_pts['right_wrist']
            cv2.line(canvas, rs, re_p, (0, 170, 240), 3, cv2.LINE_AA)
            cv2.line(canvas, re_p, rw, (0, 170, 240), 3, cv2.LINE_AA)
            cv2.circle(canvas, re_p, 6, (0, 210, 255), -1, cv2.LINE_AA)

        cv2.circle(canvas, ls, 8, (0, 220, 255), -1, cv2.LINE_AA)
        cv2.circle(canvas, rs, 8, (0, 220, 255), -1, cv2.LINE_AA)

    # Estela de trayectoria
    trail = []
    start_t = max(0, apex_idx - 16)
    for f_i in range(start_t, apex_idx + 1):
        f_pts = data['frames'][f_i]['right_hand']
        if len(f_pts) == 21:
            trail.append((int(f_pts[0][0] * width), int(f_pts[0][1] * height)))

    for t_i in range(1, len(trail)):
        intensity = t_i / float(len(trail))
        t_col = (int(0 * intensity), int(255 * intensity), int(200 * intensity))
        cv2.line(canvas, trail[t_i - 1], trail[t_i], t_col, max(1, int(4 * intensity)), cv2.LINE_AA)

    # Manos
    for hand_key, hand_pts_raw, color_bone, color_joint in [
        ('right', frame_data['right_hand'], (0, 255, 120), (100, 255, 180)),
        ('left', frame_data['left_hand'], (255, 220, 0), (255, 240, 120))
    ]:
        if len(hand_pts_raw) == 21:
            pts_px = [(int(p[0] * width), int(p[1] * height)) for p in hand_pts_raw]
            for p1, p2 in HAND_CONNECTIONS:
                cv2.line(canvas, pts_px[p1], pts_px[p2], (0, 0, 0), 4, cv2.LINE_AA)
                cv2.line(canvas, pts_px[p1], pts_px[p2], color_bone, 2, cv2.LINE_AA)

            for idx_pt, pt in enumerate(pts_px):
                radius = 5 if idx_pt in [4, 8, 12, 16, 20] else 3
                cv2.circle(canvas, pt, radius + 1, (0, 0, 0), -1, cv2.LINE_AA)
                cv2.circle(canvas, pt, radius, color_joint, -1, cv2.LINE_AA)

    # Pulso Ápex
    rh_pts = frame_data['right_hand']
    if len(rh_pts) == 21:
        wrist_px = (int(rh_pts[0][0] * width), int(rh_pts[0][1] * height))
        cv2.circle(canvas, wrist_px, 22, (0, 255, 255), 2, cv2.LINE_AA)
        cv2.circle(canvas, wrist_px, 14, (0, 255, 255), 1, cv2.LINE_AA)

    # HUD Superior
    cv2.rectangle(canvas, (0, 0), (width, 54), (18, 18, 22), -1)
    cv2.putText(canvas, "AVATAR MASTER LSC - CONSENSO MULTISENANTE", (25, 35), cv2.FONT_HERSHEY_DUPLEX, 0.7, (180, 180, 200), 1, cv2.LINE_AA)
    cv2.rectangle(canvas, (width - 270, 10), (width - 25, 44), (40, 140, 255), -1)
    cv2.putText(canvas, data['display_name'], (width - 255, 34), cv2.FONT_HERSHEY_DUPLEX, 0.65, (255, 255, 255), 2, cv2.LINE_AA)

    # HUD Inferior
    hud_bot_y = height - 90
    cv2.rectangle(canvas, (0, hud_bot_y), (width, height), (15, 15, 20), -1)
    cv2.line(canvas, (0, hud_bot_y), (width, hud_bot_y), (50, 50, 60), 1)

    cv2.putText(canvas, f"FASE: APEX (Fotograma {apex_idx}/{data['total_frames']}) - Presencia Manos: 100.0%", (25, hud_bot_y + 30), cv2.FONT_HERSHEY_DUPLEX, 0.62, (0, 255, 255), 2, cv2.LINE_AA)
    cv2.putText(canvas, data['pedagogical_metadata']['instructions'], (25, hud_bot_y + 62), cv2.FONT_HERSHEY_DUPLEX, 0.48, (200, 200, 210), 1, cv2.LINE_AA)

    out_name = f"avatar_{sign_id}_preview.png"
    out_path = os.path.join(OUT_DIR, out_name)
    cv2.imwrite(out_path, canvas)

    if os.path.exists(BRAIN_DIR):
        brain_path = os.path.join(BRAIN_DIR, out_name)
        cv2.imwrite(brain_path, canvas)

    print(f"Generated {out_name} (Apex frame: {apex_idx})")
