# -*- coding: utf-8 -*-
"""
verify_visual_signs.py

Renderiza las etapas cinemáticas clave (Reposo Inicial, Inicio Activo, Ápex, Fin Activo, Reposo Final)
de varias señas directamente en imágenes PNG idénticas al Canvas HTML5, para validar biomecánicamente
que no existan manos deformadas, cruces horizontales o desprendimientos.
"""

import os
import json
import numpy as np
import cv2

BANK_PATH = os.path.join(os.path.dirname(__file__), 'output', 'avatar', 'lsc_motion_bank.json')
OUT_DIR = os.path.join(os.path.dirname(__file__), 'output', 'visual_qa')
os.makedirs(OUT_DIR, exist_ok=True)

HAND_CONNECTIONS = [
    [0, 1], [1, 2], [2, 3], [3, 4],       # Pulgar
    [0, 5], [5, 6], [6, 7], [7, 8],       # Índice
    [0, 9], [9, 10], [10, 11], [11, 12],   # Medio
    [0, 13], [13, 14], [14, 15], [15, 16], # Anular
    [0, 17], [17, 18], [18, 19], [19, 20]  # Meñique
]

def render_frame_to_image(frame_data, w=480, h=640, title=""):
    img = np.full((h, w, 3), (23, 17, 15), dtype=np.uint8) # Dark background #0f1117 (BGR: 23, 17, 15)

    # Floor line
    cv2.line(img, (0, int(h * 0.85)), (w, int(h * 0.85)), (44, 31, 26), 1)

    torso = frame_data['torso']
    t_pts = {k: (int(v[0] * w), int(v[1] * h)) for k, v in torso.items()}

    # Cabeza
    if 'nose' in t_pts:
        nx, ny = t_pts['nose']
        cv2.ellipse(img, (nx, ny - 30), (36, 48), 0, 0, 360, (69, 51, 45), -1)
        cv2.ellipse(img, (nx, ny - 30), (36, 48), 0, 0, 360, (122, 90, 78), 2)
        cv2.circle(img, (nx - 12, ny - 38), 3, (255, 183, 159), -1)
        cv2.circle(img, (nx + 12, ny - 38), 3, (255, 183, 159), -1)

    # Torso y Brazos
    if 'left_shoulder' in t_pts and 'right_shoulder' in t_pts:
        ls = t_pts['left_shoulder']
        rs = t_pts['right_shoulder']
        mid_neck = ((ls[0] + rs[0]) // 2, (ls[1] + rs[1]) // 2)

        if 'nose' in t_pts:
            cv2.line(img, mid_neck, t_pts['nose'], (94, 70, 62), 3)

        # Clavícula
        cv2.line(img, ls, rs, (254, 242, 0), 4) # cyan BGR

        # Brazo izquierdo (ls -> elbow -> wrist)
        if 'left_elbow' in t_pts and 'left_wrist' in t_pts:
            le = t_pts['left_elbow']
            lw = t_pts['left_wrist']
            cv2.line(img, ls, le, (255, 198, 0), 3)
            cv2.line(img, le, lw, (255, 198, 0), 3)
            cv2.circle(img, le, 5, (254, 172, 79), -1)

        # Brazo derecho (rs -> elbow -> wrist)
        if 'right_elbow' in t_pts and 'right_wrist' in t_pts:
            re = t_pts['right_elbow']
            rw = t_pts['right_wrist']
            cv2.line(img, rs, re, (255, 198, 0), 3)
            cv2.line(img, re, rw, (255, 198, 0), 3)
            cv2.circle(img, re, 5, (254, 172, 79), -1)

        cv2.circle(img, ls, 7, (254, 242, 0), -1)
        cv2.circle(img, rs, 7, (254, 242, 0), -1)

    # Manos
    # Mano izquierda (amarillo dorado: BGR 102, 209, 255)
    lh = frame_data.get('left_hand', [])
    if len(lh) == 21:
        lh_px = [(int(p[0] * w), int(p[1] * h)) for p in lh]
        for i1, i2 in HAND_CONNECTIONS:
            cv2.line(img, lh_px[i1], lh_px[i2], (102, 209, 255), 2)
        for p in lh_px:
            cv2.circle(img, p, 3, (154, 226, 255), -1)

    # Mano derecha (verde esmeralda: BGR 155, 245, 0)
    rh = frame_data.get('right_hand', [])
    if len(rh) == 21:
        rh_px = [(int(p[0] * w), int(p[1] * h)) for p in rh]
        for i1, i2 in HAND_CONNECTIONS:
            cv2.line(img, rh_px[i1], rh_px[i2], (155, 245, 0), 2)
        for p in rh_px:
            cv2.circle(img, p, 3, (204, 255, 112), -1)

    if title:
        cv2.putText(img, title, (20, 35), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (240, 242, 245), 2, cv2.LINE_AA)

    return img

def verify_and_save():
    with open(BANK_PATH, 'r', encoding='utf-8') as f:
        bank = json.load(f)

    test_keys = ['gracias', 'buenos_dias', 'buenas_tardes', 'buenas_noches', 'como_estas', 'hola', 'bien']
    
    for key in test_keys:
        if key not in bank:
            continue
        data = bank[key]
        frames = data['frames']
        apex = data.get('apex_frame', 42)
        n_tot = len(frames)

        key_indices = [
            (0, "Frame 0 (Reposo Inicial)"),
            (12, "Frame 12 (Inicio Activo)"),
            (apex, f"Frame {apex} (Apex Semantico)"),
            (n_tot - 13, f"Frame {n_tot - 13} (Fin Activo)"),
            (n_tot - 1, f"Frame {n_tot - 1} (Reposo Final)")
        ]

        panel_imgs = []
        for idx, lbl in key_indices:
            idx_clamped = max(0, min(n_tot - 1, idx))
            fr = frames[idx_clamped]
            im = render_frame_to_image(fr, w=300, h=420, title=lbl)
            panel_imgs.append(im)

        composite = np.hstack(panel_imgs)
        header = np.full((50, composite.shape[1], 3), (35, 25, 20), dtype=np.uint8)
        title_text = f"LSC: {data['display_name']} ({data['type'].upper()}) - Progresion Cinematica Bulletproof"
        cv2.putText(header, title_text, (20, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.75, (0, 242, 254), 2, cv2.LINE_AA)
        
        final_img = np.vstack([header, composite])
        out_file = os.path.join(OUT_DIR, f"qa_visual_{key}.png")
        cv2.imwrite(out_file, final_img)
        print(f"Generado: {out_file}")

if __name__ == '__main__':
    verify_and_save()
