# -*- coding: utf-8 -*-
"""
render_video_overlay.py

Reconstruye y superpone el esqueleto cinemático bimanual y de torso
estrictamente a partir de los datos registrados en el archivo CSV.

Genera:
1. Copia del video con overlay de esqueleto y HUD informativo.
2. Capturas de validación visual del fotograma inicial y final del segmento activo.
3. Composición Side-by-Side (inicio y fin juntos) en una sola imagen.
"""

import os
import sys
import json
import cv2
import numpy as np
import pandas as pd

# Conexiones estándar de mano (MediaPipe Hand)
HAND_CONNECTIONS = [
    # Pulgar
    (0, 1), (1, 2), (2, 3), (3, 4),
    # Índice
    (0, 5), (5, 6), (6, 7), (7, 8),
    # Medio
    (9, 10), (10, 11), (11, 12),
    # Anular
    (13, 14), (14, 15), (15, 16),
    # Meñique
    (0, 17), (17, 18), (18, 19), (19, 20),
    # Base de la palma
    (5, 9), (9, 13), (13, 17)
]

# Colores (en formato BGR de OpenCV)
COLOR_LEFT_HAND_BONE = (255, 230, 0)      # Cian brillante
COLOR_LEFT_HAND_JOINT = (255, 255, 100)
COLOR_RIGHT_HAND_BONE = (0, 255, 0)       # Verde neón
COLOR_RIGHT_HAND_JOINT = (100, 255, 100)
COLOR_TORSO_BONE = (0, 170, 255)          # Ámbar / Dorado
COLOR_TORSO_JOINT = (0, 215, 255)
COLOR_WHITE = (255, 255, 255)
COLOR_BLACK = (0, 0, 0)
COLOR_ACTIVE_BADGE = (40, 200, 40)        # Verde
COLOR_REST_BADGE = (120, 120, 120)        # Gris neutro


def draw_hud(frame, frame_idx, total_frames, t_ms, is_active, has_lh, has_rh, sign_name=""):
    """Dibuja barra HUD informativa en la parte superior del fotograma."""
    h, w = frame.shape[:2]
    overlay = frame.copy()

    # Barra superior oscura translúcida
    hud_h = 56
    cv2.rectangle(overlay, (0, 0), (w, hud_h), (20, 20, 20), -1)
    cv2.addWeighted(overlay, 0.75, frame, 0.25, 0, frame)

    # Texto de identificación de la seña
    sign_text = f"SEÑA: {sign_name}" if sign_name else "LSC50 DATASET"
    cv2.putText(frame, sign_text, (20, 36), cv2.FONT_HERSHEY_DUPLEX, 0.8, (0, 220, 255), 2, cv2.LINE_AA)

    # Frame y tiempo
    frame_text = f"Frame: {frame_idx:03d} / {total_frames:03d}  ({t_ms} ms)"
    cv2.putText(frame, frame_text, (380, 36), cv2.FONT_HERSHEY_DUPLEX, 0.65, COLOR_WHITE, 1, cv2.LINE_AA)

    # Insignia de estado ACTIVO / REPOSO
    status_text = "ACTIVO" if is_active else "REPOSO"
    badge_color = COLOR_ACTIVE_BADGE if is_active else COLOR_REST_BADGE
    badge_x = 760
    cv2.rectangle(frame, (badge_x, 12), (badge_x + 130, 44), badge_color, -1)
    cv2.rectangle(frame, (badge_x, 12), (badge_x + 130, 44), COLOR_WHITE, 1)
    cv2.putText(frame, status_text, (badge_x + 15, 35), cv2.FONT_HERSHEY_DUPLEX, 0.6, COLOR_WHITE, 2, cv2.LINE_AA)

    # Indicadores de detección de manos
    lh_col = COLOR_LEFT_HAND_BONE if has_lh else (100, 100, 100)
    rh_col = COLOR_RIGHT_HAND_BONE if has_rh else (100, 100, 100)
    lh_str = "IZQ: DETECTADA" if has_lh else "IZQ: --"
    rh_str = "DER: DETECTADA" if has_rh else "DER: --"

    cv2.putText(frame, lh_str, (w - 380, 36), cv2.FONT_HERSHEY_DUPLEX, 0.55, lh_col, 1, cv2.LINE_AA)
    cv2.putText(frame, rh_str, (w - 190, 36), cv2.FONT_HERSHEY_DUPLEX, 0.55, rh_col, 1, cv2.LINE_AA)


def draw_skeleton_from_row(frame, row):
    """
    Dibuja los puntos y líneas del esqueleto sobre el fotograma
    leyendo exclusivamente los valores de la fila del CSV.
    """
    h, w = frame.shape[:2]

    # 1. Torso y brazos
    has_pose = int(row['has_pose']) == 1
    if has_pose:
        # Puntos de torso: nose, left_shoulder, right_shoulder, left_elbow, right_elbow, left_wrist, right_wrist
        p_names = ['nose', 'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow', 'left_wrist', 'right_wrist']
        pts = {}
        for name in p_names:
            x_val = row[f'torso_{name}_x']
            y_val = row[f'torso_{name}_y']
            if not np.isnan(x_val) and not np.isnan(y_val):
                px = int(np.clip(x_val * w, 0, w - 1))
                py = int(np.clip(y_val * h, 0, h - 1))
                pts[name] = (px, py)

        # Conexiones de torso
        torso_lines = [
            ('left_shoulder', 'right_shoulder'),
            ('left_shoulder', 'left_elbow'),
            ('left_elbow', 'left_wrist'),
            ('right_shoulder', 'right_elbow'),
            ('right_elbow', 'right_wrist')
        ]
        for p1, p2 in torso_lines:
            if p1 in pts and p2 in pts:
                cv2.line(frame, pts[p1], pts[p2], (0, 0, 0), 5, cv2.LINE_AA)
                cv2.line(frame, pts[p1], pts[p2], COLOR_TORSO_BONE, 3, cv2.LINE_AA)

        # Conexión cuello/cabeza
        if 'left_shoulder' in pts and 'right_shoulder' in pts and 'nose' in pts:
            neck_x = int((pts['left_shoulder'][0] + pts['right_shoulder'][0]) / 2)
            neck_y = int((pts['left_shoulder'][1] + pts['right_shoulder'][1]) / 2)
            cv2.line(frame, pts['nose'], (neck_x, neck_y), (0, 0, 0), 4, cv2.LINE_AA)
            cv2.line(frame, pts['nose'], (neck_x, neck_y), COLOR_TORSO_BONE, 2, cv2.LINE_AA)

        # Puntos de articulación de torso
        for pt in pts.values():
            cv2.circle(frame, pt, 6, (0, 0, 0), -1, cv2.LINE_AA)
            cv2.circle(frame, pt, 4, COLOR_TORSO_JOINT, -1, cv2.LINE_AA)

    # 2. Mano Izquierda
    has_lh = int(row['has_lh']) == 1
    if has_lh:
        lh_pts = {}
        for k in range(21):
            x_val = row[f'lh_{k}_x']
            y_val = row[f'lh_{k}_y']
            if not np.isnan(x_val) and not np.isnan(y_val):
                px = int(np.clip(x_val * w, 0, w - 1))
                py = int(np.clip(y_val * h, 0, h - 1))
                lh_pts[k] = (px, py)

        for p1, p2 in HAND_CONNECTIONS:
            if p1 in lh_pts and p2 in lh_pts:
                cv2.line(frame, lh_pts[p1], lh_pts[p2], (0, 0, 0), 4, cv2.LINE_AA)
                cv2.line(frame, lh_pts[p1], lh_pts[p2], COLOR_LEFT_HAND_BONE, 2, cv2.LINE_AA)

        for pt in lh_pts.values():
            cv2.circle(frame, pt, 4, (0, 0, 0), -1, cv2.LINE_AA)
            cv2.circle(frame, pt, 3, COLOR_LEFT_HAND_JOINT, -1, cv2.LINE_AA)

    # 3. Mano Derecha
    has_rh = int(row['has_rh']) == 1
    if has_rh:
        rh_pts = {}
        for k in range(21):
            x_val = row[f'rh_{k}_x']
            y_val = row[f'rh_{k}_y']
            if not np.isnan(x_val) and not np.isnan(y_val):
                px = int(np.clip(x_val * w, 0, w - 1))
                py = int(np.clip(y_val * h, 0, h - 1))
                rh_pts[k] = (px, py)

        for p1, p2 in HAND_CONNECTIONS:
            if p1 in rh_pts and p2 in rh_pts:
                cv2.line(frame, rh_pts[p1], rh_pts[p2], (0, 0, 0), 4, cv2.LINE_AA)
                cv2.line(frame, rh_pts[p1], rh_pts[p2], COLOR_RIGHT_HAND_BONE, 2, cv2.LINE_AA)

        for pt in rh_pts.values():
            cv2.circle(frame, pt, 4, (0, 0, 0), -1, cv2.LINE_AA)
            cv2.circle(frame, pt, 3, COLOR_RIGHT_HAND_JOINT, -1, cv2.LINE_AA)


def build_side_by_side_image(start_frame_img, mid_frame_img, end_frame_img, start_idx, mid_idx, end_idx, sign_name=""):
    """
    Combina el fotograma inicial, intermedio y final en una sola imagen panorámica (Tríptico)
    con encabezados estilizados para cada postura clave del gesto.
    """
    target_h = 360
    aspect = start_frame_img.shape[1] / start_frame_img.shape[0]
    target_w = int(target_h * aspect)  # 640px para 16:9

    left_resized = cv2.resize(start_frame_img, (target_w, target_h), interpolation=cv2.INTER_AREA)
    mid_resized = cv2.resize(mid_frame_img, (target_w, target_h), interpolation=cv2.INTER_AREA)
    right_resized = cv2.resize(end_frame_img, (target_w, target_h), interpolation=cv2.INTER_AREA)

    banner_h = 46
    gap = 6
    total_w = target_w * 3 + gap * 2
    total_h = target_h + banner_h

    canvas = np.zeros((total_h, total_w, 3), dtype=np.uint8)
    canvas[:] = (24, 24, 24)  # Fondo grafito oscuro

    # Dibujar paneles
    x_left = 0
    x_mid = target_w + gap
    x_right = (target_w + gap) * 2

    canvas[banner_h:total_h, x_left:x_left + target_w] = left_resized
    canvas[banner_h:total_h, x_mid:x_mid + target_w] = mid_resized
    canvas[banner_h:total_h, x_right:x_right + target_w] = right_resized

    # Encabezado 1: Inicio
    label_start = f"INICIO ACTIVO - Frame {start_idx:03d}"
    cv2.rectangle(canvas, (x_left, 0), (x_left + target_w, banner_h), (35, 35, 35), -1)
    cv2.putText(canvas, label_start, (x_left + 15, 31), cv2.FONT_HERSHEY_DUPLEX, 0.65, (0, 255, 200), 2, cv2.LINE_AA)

    # Encabezado 2: Pose Intermedia
    label_mid = f"POSE INTERMEDIA - Frame {mid_idx:03d}"
    cv2.rectangle(canvas, (x_mid, 0), (x_mid + target_w, banner_h), (35, 35, 35), -1)
    cv2.putText(canvas, label_mid, (x_mid + 15, 31), cv2.FONT_HERSHEY_DUPLEX, 0.65, (0, 215, 255), 2, cv2.LINE_AA)

    # Encabezado 3: Culminación
    label_end = f"CULMINACION - Frame {end_idx:03d}"
    cv2.rectangle(canvas, (x_right, 0), (x_right + target_w, banner_h), (35, 35, 35), -1)
    cv2.putText(canvas, label_end, (x_right + 15, 31), cv2.FONT_HERSHEY_DUPLEX, 0.65, (50, 255, 120), 2, cv2.LINE_AA)

    # Título general en esquina superior derecha
    if sign_name:
        cv2.putText(canvas, sign_name, (total_w - 280, 31), cv2.FONT_HERSHEY_DUPLEX, 0.65, (255, 255, 255), 1, cv2.LINE_AA)

    return canvas


def render_overlay_and_screenshots(video_path, csv_path, output_dir, sign_label=""):
    """
    Genera el video con overlay superpuesto y las capturas de validación.
    """
    if not os.path.exists(video_path):
        raise FileNotFoundError(f"Video no encontrado: {video_path}")
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"CSV no encontrado: {csv_path}")

    base_name = os.path.splitext(os.path.basename(video_path))[0]
    df = pd.read_csv(csv_path)

    cap = cv2.VideoCapture(video_path)
    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 0:
        fps = 24.0

    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    # Carpetas de destino
    overlays_dir = os.path.join(output_dir, 'overlays')
    screenshots_dir = os.path.join(output_dir, 'screenshots')
    os.makedirs(overlays_dir, exist_ok=True)
    os.makedirs(screenshots_dir, exist_ok=True)

    out_video_path = os.path.join(overlays_dir, f'{base_name}_overlay.mp4')
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    writer = cv2.VideoWriter(out_video_path, fourcc, fps, (width, height))

    # Segmento activo del CSV
    active_mask = df['is_active'].values == 1
    active_indices = np.where(active_mask)[0]
    if len(active_indices) > 0:
        start_frame_idx = int(active_indices[0])
        end_frame_idx = int(active_indices[-1])
    else:
        start_frame_idx = 0
        end_frame_idx = max(0, total_frames - 1)

    mid_frame_idx = (start_frame_idx + end_frame_idx) // 2

    start_rendered_frame = None
    mid_rendered_frame = None
    end_rendered_frame = None

    fidx = 0
    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if fidx < len(df):
            row = df.iloc[fidx]
            # Superponer esqueleto
            draw_skeleton_from_row(frame, row)
            # Superponer HUD informativo
            draw_hud(
                frame,
                frame_idx=fidx,
                total_frames=total_frames,
                t_ms=int(row['timestamp_ms']),
                is_active=bool(row['is_active']),
                has_lh=bool(row['has_lh']),
                has_rh=bool(row['has_rh']),
                sign_name=sign_label
            )

        writer.write(frame)

        if fidx == start_frame_idx:
            start_rendered_frame = frame.copy()
        if fidx == mid_frame_idx:
            mid_rendered_frame = frame.copy()
        if fidx == end_frame_idx:
            end_rendered_frame = frame.copy()

        fidx += 1

    cap.release()
    writer.release()

    # Si por alguna razón no coincidieron exactamente los frames extremos
    if start_rendered_frame is None and fidx > 0:
        start_rendered_frame = frame.copy()
    if mid_rendered_frame is None and fidx > 0:
        mid_rendered_frame = start_rendered_frame.copy()
    if end_rendered_frame is None and fidx > 0:
        end_rendered_frame = frame.copy()

    # Guardar capturas individuales
    start_shot_path = os.path.join(screenshots_dir, f'{base_name}_start_active.png')
    mid_shot_path = os.path.join(screenshots_dir, f'{base_name}_mid_active.png')
    end_shot_path = os.path.join(screenshots_dir, f'{base_name}_end_active.png')
    if start_rendered_frame is not None:
        cv2.imwrite(start_shot_path, start_rendered_frame)
    if mid_rendered_frame is not None:
        cv2.imwrite(mid_shot_path, mid_rendered_frame)
    if end_rendered_frame is not None:
        cv2.imwrite(end_shot_path, end_rendered_frame)

    # Composición Side-by-Side (Tríptico con pose intermedia)
    side_by_side_path = os.path.join(screenshots_dir, f'{base_name}_side_by_side.png')
    if start_rendered_frame is not None and mid_rendered_frame is not None and end_rendered_frame is not None:
        sbs_img = build_side_by_side_image(
            start_rendered_frame,
            mid_rendered_frame,
            end_rendered_frame,
            start_frame_idx,
            mid_frame_idx,
            end_frame_idx,
            sign_name=sign_label
        )
        cv2.imwrite(side_by_side_path, sbs_img)

    return {
        'video_overlay': out_video_path,
        'start_shot': start_shot_path,
        'mid_shot': mid_shot_path,
        'end_shot': end_shot_path,
        'side_by_side': side_by_side_path,
        'start_frame': start_frame_idx,
        'mid_frame': mid_frame_idx,
        'end_frame': end_frame_idx
    }


if __name__ == '__main__':
    video_input = sys.argv[1] if len(sys.argv) > 1 else 'dataset/VIDEOS/COLOR_BODY/0000_0000_0000.avi'
    csv_input = sys.argv[2] if len(sys.argv) > 2 else 'debug_windows/output/csv/0000_0000_0000.csv'
    output_dir = sys.argv[3] if len(sys.argv) > 3 else 'debug_windows/output'
    label = sys.argv[4] if len(sys.argv) > 4 else 'GRACIAS'

    print(f"Renderizando overlay desde CSV: {csv_input} sobre video: {video_input}")
    res = render_overlay_and_screenshots(video_input, csv_input, output_dir, label)
    print(f"Renderizado completado exitosamente:")
    print(f" - Video con overlay: {res['video_overlay']}")
    print(f" - Captura Side-by-Side: {res['side_by_side']}")
